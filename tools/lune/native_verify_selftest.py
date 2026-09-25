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

    def test_pending_live_risk_cannot_be_reported_as_complete_coverage(self):
        self.write("tools/lune/parity_blockers.json", json.dumps({"items": [], "pendingLiveRisks": ["compact largest-text input"]}))
        with self.historical([]):
            _, _, failures = verify.inventory()
        self.assertEqual(failures, ["pending live verification: compact largest-text input"])

    def test_full_generates_performance_before_checking_its_report(self):
        artifacts = self.root / "artifacts/verify/native"
        performance = self.root / "artifacts/phase-4/perf.json"
        commands = []

        def execute(command, **kwargs):
            commands.append(command)
            if command == ["lune", "run", "tools/lune/native_verify_suite", "full"]:
                (artifacts / "suite.json").write_text(json.dumps({"tier": "full", "cases": [{"id": "native_sample::sample", "spec": "native_sample", "status": "pass"}], "registeredSpecs": 1, "reportedSpecs": 1, "passed": 1, "failed": 0}))
            if command == ["bash", "tools/perf.sh"]:
                performance.parent.mkdir(parents=True, exist_ok=True)
                performance.write_text("{}")
            if command == ["python3", "tools/check_perf_budgets.py"]:
                self.assertTrue(performance.exists(), "budget validation needs this run's performance report")
            return type("Result", (), {"returncode": 0})()

        with patch.object(verify, "ARTIFACTS", artifacts), patch.object(verify, "inventory", return_value=([], ["native_sample"], [])), patch.object(verify, "architecture", return_value=[]), patch.object(verify.subprocess, "run", side_effect=execute), patch.object(verify.sys, "argv", ["native_verify.py", "full"]):
            self.assertEqual(verify.run(), 0)
        self.assertIn(["python3", "tools/check_perf_budgets.py"], commands)
        report = json.loads((artifacts / "report.json").read_text())
        self.assertTrue(report["completeTier"])
        self.assertTrue(report["ok"])
        self.assertEqual(report["historicalParity"], "not-established")
        for command in (
            ["lune", "run", "tools/lune/check_links_cli"],
            ["lune", "run", "tools/lune/check_links_cli", "--selftest"],
            ["python3", "tools/check_source_size.py"],
            ["python3", "tools/check_types.py", "--selftest"],
            ["python3", "tools/package.py", "--selftest"],
        ):
            self.assertIn(command, commands)

    def test_suite_census_rejects_missing_duplicate_failed_and_forged_results(self):
        case = {"id": "sample::one", "spec": "sample", "status": "pass"}
        clean = {"tier": "full", "cases": [case], "registeredSpecs": 1, "reportedSpecs": 1, "passed": 1, "failed": 0}
        self.assertEqual(verify.validate_suite(clean, ["sample"], "full"), [])
        for change in ({"tier": "fast"}, {"cases": []}, {"cases": [case, case], "passed": 2}, {"registeredSpecs": 0}, {"reportedSpecs": 0}, {"passed": 0}, {"failed": 1}, {"cases": [dict(case, status="fail")]}, {"cases": [dict(case, spec="other")]}):
            with self.subTest(change=change):
                self.assertTrue(verify.validate_suite(dict(clean, **change), ["sample"], "full"))

    def test_suite_accepts_a_tier_gated_case_only_below_its_tier(self):
        case = {"id": "sample::one", "spec": "sample", "status": "pass"}
        gated = {"id": "sample::ramp", "spec": "sample", "status": "skip", "tier": "full"}
        suite = {"cases": [case, gated], "registeredSpecs": 1, "reportedSpecs": 1, "passed": 1, "failed": 0, "skipped": 1}
        for tier in ("affected", "fast"):
            with self.subTest(tier=tier):
                self.assertEqual(verify.validate_suite(dict(suite, tier=tier), ["sample"], tier), [])
                self.assertEqual(verify.deferred_cases(dict(suite, tier=tier), tier), {"sample::ramp"})
        for tier in ("full", "release"):
            with self.subTest(tier=tier):
                self.assertTrue(verify.validate_suite(dict(suite, tier=tier), ["sample"], tier))
                self.assertEqual(verify.deferred_cases(dict(suite, tier=tier), tier), set())
        for change in ({"cases": [case, dict(gated, tier=None)]}, {"cases": [case, dict(gated, tier="fast")]}, {"cases": [case, dict(gated, tier="unknown")]}, {"skipped": 0}, {"passed": 2}):
            with self.subTest(change=change):
                self.assertTrue(verify.validate_suite(dict(suite, tier="fast", **change), ["sample"], "fast"))

    def test_architecture_rejects_example_imports_of_private_modules_and_extra_vendors(self):
        self.write("src/ui/private.luau", "return {}")
        self.write("examples/screen.luau", 'return require("../src/ui/private")')
        self.write("src/vendor/other/init.luau", "return {}")
        failures = verify.architecture()
        self.assertTrue(any("private Facet module" in issue for issue in failures))
        self.assertTrue(any("unapproved vendor" in issue for issue in failures))

    def test_architecture_rejects_both_old_api_and_abandoned_renderer(self):
        self.write("src/render/renderer.luau", "return {}")
        self.write("examples/screen.luau", "local app = Facet.new()")
        failures = verify.architecture()
        self.assertTrue(any("renderer.luau" in issue for issue in failures))
        self.assertTrue(any("removed Facet scaffolding API" in issue for issue in failures))

    def test_missing_live_evidence_is_reported_in_full_and_blocks_release(self):
        self.assertEqual(verify.producer_status(2, "studio"), "FAIL_ENVIRONMENT")
        self.assertEqual(verify.producer_status(2, "device"), "FAIL_ENVIRONMENT")
        self.assertEqual(verify.producer_status(2, "deterministic"), "FAIL")
        self.assertEqual(verify.producer_status(1, "studio"), "FAIL")
        self.assertEqual(verify.producer_status(2, "perf"), "FAIL_ENVIRONMENT")
        self.assertEqual(verify.producer_status(2, "perf", reference_host=True), "FAIL")
        self.assertEqual(verify.producer_status(1, "perf"), "FAIL")
        self.assertFalse(verify.status_blocks("FAIL_ENVIRONMENT", "full"))
        self.assertTrue(verify.status_blocks("FAIL_ENVIRONMENT", "release"))
        self.assertTrue(verify.status_blocks("FAIL", "full"))

    def test_release_selects_the_falsification_after_the_full_producers(self):
        full = [entry["id"] for entry in verify.producers_for("full")]
        release = [entry["id"] for entry in verify.producers_for("release")]
        self.assertNotIn("prove-perf-gate", full)
        self.assertEqual(release[: len(full)], full)
        self.assertEqual(release[len(full):], ["prove-perf-gate", "perf-gate-evidence-falsifiable"])
        fast = {entry["id"] for entry in verify.producers_for("fast")}
        self.assertNotIn("perf", fast)

    def test_release_run_writes_package_gate_evidence(self):
        artifacts = self.root / "artifacts/verify/native"

        def execute(command, **kwargs):
            if command[:2] == ["git", "rev-parse"]:
                return type("Result", (), {"returncode": 0, "stdout": "c" * 40})()
            if command[:2] == ["git", "status"]:
                return type("Result", (), {"returncode": 0, "stdout": ""})()
            if command[:3] == ["lune", "run", "tools/lune/native_verify_suite"]:
                (artifacts / "suite.json").write_text(json.dumps({"tier": command[3], "cases": [{"id": "native_sample::sample", "spec": "native_sample", "status": "pass"}], "registeredSpecs": 1, "reportedSpecs": 1, "passed": 1, "failed": 0}))
            code = 2 if command == ["python3", "tools/check_perf_gate_evidence.py", "studio"] else 0
            return type("Result", (), {"returncode": code, "stdout": ""})()

        for tier, expected in (("full", 0), ("release", 1)):
            with self.subTest(tier=tier), patch.object(verify, "ARTIFACTS", artifacts), patch.object(verify, "inventory", return_value=([], ["native_sample"], [])), patch.object(verify, "architecture", return_value=[]), patch.object(verify, "package_source_hash", return_value="s" * 64), patch.object(verify.subprocess, "run", side_effect=execute), patch.object(verify.sys, "argv", ["native_verify.py", tier]):
                self.assertEqual(verify.run(), expected)
                gate = json.loads((self.root / f"artifacts/verify/latest-{tier}.json").read_text())["gateEvidence"]
                self.assertEqual(gate["schema"], "facet-release-gate/1")
                self.assertEqual(gate["tier"], tier)
                self.assertEqual(gate["status"], "PASS" if expected == 0 else "FAIL")
                self.assertEqual(gate["commit"], "c" * 40)
                self.assertIs(gate["treeDirty"], False)
                self.assertEqual(gate["sourceHash"], "s" * 64)


if __name__ == "__main__":
    unittest.main()
