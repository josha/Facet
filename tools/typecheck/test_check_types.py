import contextlib
import importlib.util
import io
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("check_types", Path(__file__).resolve().parents[1] / "check_types.py")
checker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checker)


class TypeCoverageTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name).resolve()
        self.artifacts = self.root / "artifacts/verify/types"
        self.artifacts.mkdir(parents=True)
        self.files = ["src/a.luau", "src/vendor/dependency.luau", "tests/a.luau", "examples/a.luau", "bench/a.luau", "tools/designer/a.luau"]
        for name in self.files:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("--!strict\nreturn {}\n")
        self.lock = self.root / "game.lock.json"
        self.plugin = self.root / "plugin.lock.json"
        self.lune = self.root / "lune.lock.json"
        self.lock.write_text(json.dumps({"security": "None"}))
        self.plugin.write_text(json.dumps({"security": "PluginSecurity"}))
        self.lune.write_text("{}")
        for key, value in {"ROOT": self.root, "ARTIFACTS": self.artifacts, "LOCK": self.lock, "PLUGIN_LOCK": self.plugin, "LUNE_LOCK": self.lune}.items():
            active = patch.object(checker, key, value)
            active.start()
            self.addCleanup(active.stop)

    def check(self, diagnostics=(), files=None, source_only=False, solver="old"):
        args = SimpleNamespace(files=files, source_only=source_only, flag=[])
        groups = [(self.files, "all", [], self.lock, None)]
        with patch.object(checker, "repository_files", return_value=self.files), patch.object(checker, "project_runs", return_value=groups), patch.object(checker, "analyze", return_value=(list(diagnostics), "all.log")), patch.object(checker, "negative_probes", return_value={"count": 1, "missed": [], "unexpected": []}), contextlib.redirect_stdout(io.StringIO()):
            return checker.check(args, solver)

    def test_inventory_includes_each_repository_area_and_untracked_files(self):
        (self.root / "examples/new.luau").write_text("--!strict\nreturn {}\n")
        result = SimpleNamespace(stdout="\0".join([*self.files, "examples/new.luau", "src/deleted.luau", "src/a.luau", ""]))
        with patch.object(checker.subprocess, "run", return_value=result) as run:
            self.assertEqual(checker.repository_files(), sorted(set([*self.files, "examples/new.luau"])))
            self.assertIn("--others", run.call_args.args[0])
            self.assertIn("--cached", run.call_args.args[0])

    def test_complete_check_blocks_dependency_errors(self):
        error = {"file": "src/vendor/dependency.luau", "line": 2, "column": 1, "kind": "TypeError", "message": "wrong value"}
        self.assertFalse(self.check([error]))
        report = json.loads((self.artifacts / "repository.json").read_text())
        self.assertEqual(report["diagnostics"], [error])
        self.assertEqual(report["dependencyDiagnostics"], [])
        self.assertEqual(report["targets"], self.files)

    def test_analyzer_report_keeps_the_type_mismatch_details(self):
        output = "tests/a.luau(2,1): TypeError: Expected this to be\n\t'string'\nbut got\n\t'number'\ntests/a.luau(3,1): SyntaxError: missing end\n"
        result = SimpleNamespace(stdout=output, stderr="", returncode=1)
        with patch.object(checker, "definitions", return_value=self.lock), patch.object(checker.subprocess, "run", return_value=result):
            diagnostics, _ = checker.analyze(["tests/a.luau"], "details")
        self.assertEqual(len(diagnostics), 2)
        self.assertIn("but got\n\t'number'", diagnostics[0]["message"])
        self.assertEqual(diagnostics[1]["message"], "missing end")

    def test_focused_check_records_dependencies_separately(self):
        error = {"file": "src/vendor/dependency.luau", "line": 2, "column": 1, "kind": "TypeError", "message": "wrong value"}
        self.assertTrue(self.check([error], files=["src/a.luau"]))
        report = json.loads(next(self.artifacts.glob("focused-*.json")).read_text())
        self.assertEqual(report["dependencyDiagnostics"], [error])
        self.assertEqual(report["mode"], "focused")

    def test_strict_cannot_be_disabled_later_in_a_file(self):
        (self.root / "bench/a.luau").write_text("--!strict\n--!nocheck\nreturn {}\n")
        self.assertFalse(self.check())
        report = json.loads((self.artifacts / "repository.json").read_text())
        self.assertEqual(report["missingStrict"], ["bench/a.luau"])

    def test_new_solver_has_no_diagnostic_allowance(self):
        error = {"file": "tests/a.luau", "line": 2, "column": 1, "kind": "TypeError", "message": "wrong value"}
        self.assertFalse(self.check([error], solver="new"))

    def test_projects_cover_mapped_and_unmapped_files_in_both_security_contexts(self):
        def run(command, **kwargs):
            if command[0] == "git":
                return SimpleNamespace(stdout="default.project.json\0")
            path = Path(command[command.index("-o") + 1])
            path.write_text(json.dumps({"children": [{"filePaths": [str(self.root / name)]} for name in ["src/a.luau", "tools/designer/a.luau"]]}))
            return SimpleNamespace()

        with patch.object(checker.subprocess, "run", side_effect=run):
            runs = checker.project_runs(self.files)
        self.assertEqual(set().union(*(set(group) for group, *_ in runs)), set(self.files))
        contexts = {(project, lock) for _, _, _, lock, project in runs}
        self.assertEqual(contexts, {("default.project.json", self.lock), ("default.project.json", self.plugin), (None, self.lock)})


if __name__ == "__main__":
    unittest.main()
