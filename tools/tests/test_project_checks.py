import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_architecture as architecture
import check_plan as plan


class ProjectCheckTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self.patches = [patch.object(architecture, "ROOT", self.root), patch.object(plan, "ROOT", self.root)]
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

    def test_resolves_native_init_self_alias_and_rejects_missing_imports(self):
        path = self.write("src/init.luau", 'return require("@self/ui")')
        self.write("src/ui/init.luau", 'return require("@self/control")')
        self.write("src/ui/control.luau", "return {}")
        self.assertEqual(architecture.missing_dependencies(path), [])
        self.write("src/ui/control.luau", 'return require("./gone")')
        architecture.imports.cache_clear()
        self.assertTrue(any("./gone" in issue for issue in architecture.missing_dependencies(path)))

    def test_dynamic_existing_data_prefix_is_executed_and_missing_prefix_fails(self):
        path = self.write("tests/data.spec.luau", 'return require("../examples/words/len" .. tostring(5))')
        self.write("examples/words/len5.luau", "return {}")
        self.assertEqual(architecture.missing_dependencies(path), [])
        self.write("tests/data.spec.luau", 'return require("../examples/missing/len" .. tostring(5))')
        architecture.imports.cache_clear()
        self.assertTrue(architecture.missing_dependencies(path))

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


    def declare(self, units):
        self.write("tests/plan.json", json.dumps({"units": units}))

    def test_plan_accepts_every_nested_spec_and_legacy_suffix_once(self):
        self.write("tests/native.spec.luau", "return {}")
        self.write("tests/nested/control_spec.luau", "return {}")
        self.write("tests/lib/helper.luau", "return {}")
        self.declare([{"id": "native", "locator": "tests/native.spec.luau"}, {"id": "nested/control", "locator": "tests/nested/control_spec.luau"}])
        self.assertEqual(plan.check_plan(), [])

    def test_plan_rejects_a_missing_source_and_an_undeclared_spec(self):
        self.write("tests/added.spec.luau", "return {}")
        self.declare([{"id": "removed", "locator": "tests/removed.spec.luau"}])
        self.assertEqual(plan.check_plan(), ["Verify plan spec is not on disk: removed", "spec is missing from the Verify plan: added"])

    def test_plan_rejects_duplicate_ids_and_locators(self):
        self.write("tests/native.spec.luau", "return {}")
        unit = {"id": "native", "locator": "tests/native.spec.luau"}
        self.declare([unit, unit])
        self.assertEqual(plan.check_plan(), ["duplicate Verify plan ID: native", "duplicate Verify plan locator: tests/native.spec.luau"])

    def test_plan_rejects_a_locator_that_does_not_match_its_source_id(self):
        self.write("tests/native.spec.luau", "return {}")
        self.declare([{"id": "native", "locator": "tests/other.spec.luau"}])
        self.assertEqual(plan.check_plan(), ["Verify plan locator for native must be tests/native.spec.luau"])

    def test_plan_rejects_unreadable_malformed_or_incomplete_plans(self):
        self.assertIn("cannot read tests/plan.json", plan.check_plan()[0])
        self.write("tests/plan.json", "{")
        self.assertIn("cannot read tests/plan.json", plan.check_plan()[0])
        self.write("tests/plan.json", "[]")
        self.assertEqual(plan.check_plan(), ["Verify plan must contain a units list"])
        self.declare([None, {"id": "native"}])
        self.assertEqual(plan.check_plan(), ["Verify plan unit 1 needs a nonempty ID", "Verify plan unit native needs a locator"])

    def test_plan_rejects_spec_files_with_colliding_ids(self):
        self.write("tests/native.spec.luau", "return {}")
        self.write("tests/native_spec.luau", "return {}")
        self.declare([{"id": "native", "locator": "tests/native_spec.luau"}])
        self.assertEqual(plan.check_plan(), ["spec files share the same ID: native"])


if __name__ == "__main__":
    unittest.main()
