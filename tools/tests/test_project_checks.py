import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_architecture as architecture
import check_coverage as coverage


class ProjectCheckTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self.patches = [patch.object(architecture, "ROOT", self.root), patch.object(coverage, "ROOT", self.root)]
        for item in self.patches:
            item.start()
        for directory in ("tests", "src/ui", "examples", "bench", "tools/lune"):
            (self.root / directory).mkdir(parents=True)
        architecture.imports.cache_clear()

    def tearDown(self):
        for item in self.patches:
            item.stop()
        self.temporary.cleanup()

    def write(self, path, text):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        return target

    def historical(self, names):
        result = type("Result", (), {"stdout": "\n".join(f"tests/{name}.spec.luau" for name in names)})()
        return patch.object(coverage.subprocess, "run", return_value=result)

    def test_resolves_native_init_self_alias_and_rejects_missing_imports(self):
        path = self.write("src/init.luau", 'return require("@self/ui")')
        self.write("src/ui/init.luau", 'return require("@self/control")')
        self.write("src/ui/control.luau", "return {}")
        self.assertEqual(architecture.missing_dependencies(path), [])
        self.write("src/ui/control.luau", 'return require("./gone")')
        architecture.imports.cache_clear()
        self.assertTrue(any("./gone" in issue for issue in architecture.missing_dependencies(path)))

    def test_deleted_historical_behavior_does_not_disappear(self):
        with self.historical(["removed_control"]) as git_inventory:
            records, selected, failures = coverage.inventory()
        self.assertEqual(git_inventory.call_args.args[0], ["git", "ls-tree", "-r", "--name-only", "a8c8895673c0745506908b66dc89f8cead6b66f3", "tests"])
        self.assertEqual(selected, [])
        self.assertEqual(records[0]["classification"], "unmapped-behavior")
        self.assertTrue(any("removed_control" in issue for issue in failures))

    def test_dynamic_existing_data_prefix_is_executed_and_missing_prefix_fails(self):
        path = self.write("tests/data.spec.luau", 'return require("../examples/words/len" .. tostring(5))')
        self.write("examples/words/len5.luau", "return {}")
        self.assertEqual(architecture.missing_dependencies(path), [])
        self.write("tests/data.spec.luau", 'return require("../examples/missing/len" .. tostring(5))')
        architecture.imports.cache_clear()
        self.assertTrue(architecture.missing_dependencies(path))

    def test_one_to_many_case_mappings_are_all_required(self):
        self.assertEqual(coverage.mapped_cases({"cases": ["one"], "caseMappings": {"old": ["two", "three"]}}), ["one", "two", "three"])

    def test_require_examples_in_comments_and_literals_are_not_dependencies(self):
        path = self.write("tests/probe.spec.luau", '''-- require("./removed")
local example = 'require("./removed")'
local text = `example require("./removed"): {require("./actual")}`
return require("./actual")''')
        self.write("tests/actual.luau", "return {}")
        self.assertEqual(architecture.missing_dependencies(path), [])
        self.assertEqual(architecture.imports(path), ["./actual", "./actual"])

    def test_typeof_imports_are_erased_but_runtime_imports_stay_checked(self):
        path = self.write("tests/probe.spec.luau", '\n'.join([
            'type Props = typeof(require("@repo/missing")("("))',
            'local value: typeof(require("./missing")) = nil :: any',
            'local text = "typeof(require(\\\"./missing\\\"))"',
            'local runtimeKind = typeof(require("./actual"))',
            'return typeof(require("./actual"))',
        ]))
        self.write("tests/actual.luau", "return {}")
        self.assertEqual(architecture.imports(path), ["./actual", "./actual"])
        self.assertEqual(architecture.missing_dependencies(path), [])
        self.write("tests/probe.spec.luau", 'return require("@repo/missing")')
        architecture.imports.cache_clear()
        self.assertTrue(architecture.missing_dependencies(path))

    def test_typed_require_alias_keeps_dynamic_dependency_checks(self):
        path = self.write("tests/probe.spec.luau", '\n'.join([
            'local requireDynamic = require :: (any) -> any',
            'return requireDynamic("../examples/words/len" .. tostring(5))',
        ]))
        self.write("examples/words/len5.luau", "return {}")
        self.assertEqual(architecture.imports(path), ["dynamic:../examples/words/len"])
        self.assertEqual(architecture.missing_dependencies(path), [])
        self.write("tests/probe.spec.luau", 'local load = require :: (any) -> any; return load("./missing")')
        architecture.imports.cache_clear()
        self.assertTrue(architecture.missing_dependencies(path))

    def test_retirement_requires_explicit_mapping_and_uncovered_behavior_stays_red(self):
        self.write("tests/native_control.spec.luau", "return {}")
        self.write("tools/lune/coverage_test.json", json.dumps({
            "retiredMechanisms": ["solver"],
            "retirementReasons": {"solver": "The private layout solver was removed; engine layout owns geometry."},
            "replacements": {"control": {"specs": ["native_control"], "remaining": ["focus restoration"]}},
        }))
        with self.historical(["solver", "control"]):
            records, selected, failures = coverage.inventory()
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
            _, _, failures = coverage.inventory()
        self.assertTrue(any("no explicit rationale" in issue for issue in failures))
        self.assertTrue(any("shadows behavioral" in issue for issue in failures))

    def test_passing_native_inventory_cannot_hide_known_product_parity_defects(self):
        self.write("tests/native_demo.spec.luau", "return {}")
        self.write("tools/lune/parity_blockers.json", json.dumps({"items": [{"id": "G01", "remaining": ["Reverse does not change visible row order"]}]}))
        with self.historical([]):
            _, selected, failures = coverage.inventory()
        self.assertEqual(selected, ["native_demo"])
        self.assertEqual(failures, ["product parity G01: Reverse does not change visible row order"])

    def test_pending_live_risk_cannot_be_reported_as_complete_coverage(self):
        self.write("tools/lune/parity_blockers.json", json.dumps({"items": [], "pendingLiveRisks": ["compact largest-text input"]}))
        with self.historical([]):
            _, _, failures = coverage.inventory()
        self.assertEqual(failures, ["pending live verification: compact largest-text input"])

    def test_architecture_rejects_example_imports_of_private_modules_and_extra_vendors(self):
        self.write("src/ui/private.luau", "return {}")
        self.write("examples/screen.luau", 'return require("../src/ui/private")')
        self.write("src/vendor/other/init.luau", "return {}")
        failures = architecture.architecture()
        self.assertTrue(any("private Facet module" in issue for issue in failures))
        self.assertTrue(any("unapproved vendor" in issue for issue in failures))

    def test_architecture_rejects_both_old_api_and_abandoned_renderer(self):
        self.write("src/render/renderer.luau", "return {}")
        self.write("examples/screen.luau", "local app = Facet.new()")
        failures = architecture.architecture()
        self.assertTrue(any("renderer.luau" in issue for issue in failures))
        self.assertTrue(any("removed Facet scaffolding API" in issue for issue in failures))

    def test_mapped_replacement_cases_must_be_in_the_suite_result_of_a_planned_source(self):
        def receipt(worker, source, ids):
            results = [{"id": case, "source": f"tests/{source}.spec.luau", "status": "passed"} for case in ids]
            self.write(f"artifacts/verify/native/gate/run-1/suite-worker-{worker}/suite-{worker}-result.json", json.dumps({"report": {"results": results}}))

        receipt(1, "sample", ["sample::one", "sample::two"])
        receipt(2, "other", ["other::one"])
        records = [{"spec": "old", "replacement": {"cases": ["sample::one"], "caseMappings": {"legacy": ["sample::two"]}}}]
        self.assertEqual(coverage.replacement_findings(records, ["sample"], "run-1"), [])
        self.assertEqual(len(coverage.replacement_findings(records, ["other"], "run-1")), 2)
        absent = [{"spec": "old", "replacement": {"cases": ["sample::three"]}}]
        self.assertEqual(len(coverage.replacement_findings(absent, ["sample"], "run-1")), 1)
        unplanned = [{"spec": "old", "replacement": {"cases": ["other::one"]}}]
        self.assertEqual(len(coverage.replacement_findings(unplanned, ["sample"], "run-1")), 1)
        self.assertEqual(coverage.replacement_findings(records, ["sample"], "run-2"), ["gate run run-2 has no suite result for a planned source"])


if __name__ == "__main__":
    unittest.main()
