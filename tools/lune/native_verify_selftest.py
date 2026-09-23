#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("native_verify", Path(__file__).with_name("native_verify.py"))
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


class NativeVerificationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self.root_patch = patch.object(verify, "ROOT", self.root)
        self.root_patch.start()
        for directory in ("tests", "src/ui", "examples", "bench", "tools/lune"):
            (self.root / directory).mkdir(parents=True)
        verify.imports.cache_clear()

    def tearDown(self):
        self.root_patch.stop()
        self.temporary.cleanup()

    def write(self, path, text):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        return target

    def historical(self, names):
        result = type("Result", (), {"stdout": "\n".join(f"tests/{name}.spec.luau" for name in names)})()
        return patch.object(verify.subprocess, "run", return_value=result)

    def test_resolves_native_init_self_alias_and_rejects_missing_imports(self):
        path = self.write("src/init.luau", 'return require("@self/ui")')
        self.write("src/ui/init.luau", 'return require("@self/control")')
        self.write("src/ui/control.luau", "return {}")
        self.assertEqual(verify.missing_dependencies(path), [])
        self.write("src/ui/control.luau", 'return require("./gone")')
        verify.imports.cache_clear()
        self.assertTrue(any("./gone" in issue for issue in verify.missing_dependencies(path)))

    def test_deleted_historical_behavior_does_not_disappear(self):
        with self.historical(["removed_control"]) as git_inventory:
            records, selected, failures = verify.inventory()
        self.assertEqual(git_inventory.call_args.args[0], ["git", "ls-tree", "-r", "--name-only", "a8c8895673c0745506908b66dc89f8cead6b66f3", "tests"])
        self.assertEqual(selected, [])
        self.assertEqual(records[0]["classification"], "unmapped-behavior")
        self.assertTrue(any("removed_control" in issue for issue in failures))

    def test_dynamic_existing_data_prefix_is_executed_and_missing_prefix_fails(self):
        path = self.write("tests/data.spec.luau", 'return require("../examples/words/len" .. tostring(5))')
        self.write("examples/words/len5.luau", "return {}")
        self.assertEqual(verify.missing_dependencies(path), [])
        self.write("tests/data.spec.luau", 'return require("../examples/missing/len" .. tostring(5))')
        verify.imports.cache_clear()
        self.assertTrue(verify.missing_dependencies(path))

    def test_one_to_many_case_mappings_are_all_required(self):
        self.assertEqual(verify.mapped_cases({"cases": ["one"], "caseMappings": {"old": ["two", "three"]}}), ["one", "two", "three"])

    def test_require_examples_in_comments_and_literals_are_not_dependencies(self):
        path = self.write("tests/probe.spec.luau", '''-- require("./removed")
local example = 'require("./removed")'
local text = `example require("./removed"): {require("./actual")}`
return require("./actual")''')
        self.write("tests/actual.luau", "return {}")
        self.assertEqual(verify.missing_dependencies(path), [])
        self.assertEqual(verify.imports(path), ["./actual", "./actual"])

    def test_retirement_requires_explicit_mapping_and_uncovered_behavior_stays_red(self):
        self.write("tests/native_control.spec.luau", "return {}")
        self.write("tools/lune/coverage_test.json", json.dumps({
            "retiredMechanisms": ["solver"],
            "retirementReasons": {"solver": "The private layout solver was removed; engine layout owns geometry."},
            "replacements": {"control": {"specs": ["native_control"], "remaining": ["focus restoration"]}},
        }))
        with self.historical(["solver", "control"]):
            records, selected, failures = verify.inventory()
        self.assertEqual(selected, ["native_control"])
        self.assertEqual(len(failures), 1)
        self.assertIn("focus restoration", failures[0])
        self.assertEqual(next(row for row in records if row["spec"] == "solver")["classification"], "removed-mechanism")

    def test_retirement_without_reason_cannot_hide_behavior_mapping(self):
        self.write("tests/native_control.spec.luau", "return {}")
        self.write("tools/lune/coverage_test.json", json.dumps({
            "retiredMechanisms": ["control"],
            "replacements": {"control": {"specs": ["native_control"]}},
        }))
        with self.historical(["control"]):
            _, _, failures = verify.inventory()
        self.assertTrue(any("no explicit rationale" in issue for issue in failures))
        self.assertTrue(any("shadows behavioral" in issue for issue in failures))

    def test_passing_native_inventory_cannot_hide_known_product_parity_defects(self):
        self.write("tests/native_demo.spec.luau", "return {}")
        self.write("tools/lune/parity_blockers.json", json.dumps({"items": [{"id": "G01", "remaining": ["Reverse does not change visible row order"]}]}))
        with self.historical([]):
            _, selected, failures = verify.inventory()
        self.assertEqual(selected, ["native_demo"])
        self.assertEqual(failures, ["product parity G01: Reverse does not change visible row order"])

    def test_architecture_rejects_both_old_api_and_abandoned_renderer(self):
        self.write("src/render/renderer.luau", "return {}")
        self.write("examples/screen.luau", "local app = Facet.new()")
        failures = verify.architecture()
        self.assertTrue(any("renderer.luau" in issue for issue in failures))
        self.assertTrue(any("removed Facet scaffolding API" in issue for issue in failures))


if __name__ == "__main__":
    unittest.main()
