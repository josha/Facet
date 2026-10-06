import unittest

from verify_cutover import transform


class VerifyCodemodTests(unittest.TestCase):
    def convert(self, body):
        return transform('--!strict\nlocal t = require("./lib/testkit")\n' + body, "sample")

    def test_preserves_literals_and_changes_only_matcher_operators(self):
        source, counts = self.convert('t.describe("suite", function() t.it("case", function() local text = "t.it( and .toBe(" t.expect(text).toBe("t.it( and .toBe(") end) end)')
        self.assertIn('"t.it( and .toBe("', source)
        self.assertIn('Verify.expect(text):toBe(', source)
        self.assertIn('id = "sample::suite::case"', source)
        self.assertEqual(counts["matchers"], 1)
        self.assertEqual(counts["cases"], 1)

    def test_preserves_explicit_ids_and_adds_the_old_default_tolerance(self):
        source, counts = self.convert('t.describe("suite", function() t.it("case", function() t.expect(1).toBeCloseTo(1) t.expect(2).toBeCloseTo(2, 0.5) end, {id="stable"}) end)')
        self.assertIn('id = "stable"', source)
        self.assertIn(':toBeCloseTo(1, 1e-4)', source)
        self.assertIn(':toBeCloseTo(2, 0.5)', source)
        self.assertEqual(counts["explicit_tolerances"], 1)

    def test_release_deferral_and_negation_use_verify(self):
        source, counts = self.convert('t.describe("suite", function() t.it("case", function() t.expect(false).never().toBe(true) end, {tier="release"}) end)')
        self.assertIn('context:skip("tier:release")', source)
        self.assertIn('.never:toBe(true)', source)
        self.assertEqual(counts["tier_guards"], 1)

    def test_supports_registration_aliases_without_a_compatibility_surface(self):
        source, counts = self.convert('local it, expect = t.it, t.expect\nt.describe("suite", function() it("case", function() expect(true).toBe(true) end) end)')
        self.assertNotIn('t.it', source)
        self.assertIn('verifyHarness:case', source)
        self.assertEqual(counts["cases"], 1)

    def test_rejects_unrecognized_case_metadata(self):
        with self.assertRaisesRegex(ValueError, "unsupported case option"):
            self.convert('t.describe("suite", function() t.it("case", function() end, { retries=3 }) end)')

    def test_single_return_arguments_and_removed_harness_returns(self):
        source, counts = self.convert('t.describe("suite", function() t.it("case", function() t.expect(pcall(work)).toBe(true) end) end)\nreturn t')
        self.assertIn('Verify.expect((pcall(work))):toBe(true)', source)
        self.assertIn('return nil', source)
        self.assertEqual(counts['single_return_arguments'], 1)
        self.assertEqual(counts['removed_harness_returns'], 1)

    def test_single_expect_alias_keeps_one_actual_value(self):
        source, counts = self.convert('local expect = t.expect\nt.describe("suite", function() t.it("case", function() expect(pcall(work)).toBe(true) end) end)')
        self.assertIn('expect((pcall(work))):toBe(true)', source)

    def test_typeof_text_does_not_mask_code(self):
        source, counts = self.convert('t.describe("suite", function() t.it("case", function() t.expect(string.find(text, `{name}: typeof(`, 1, true) ~= nil).toBe(true) end) end)')
        self.assertIn(':toBe(true)', source)
        self.assertEqual(counts['matchers'], 1)


if __name__ == "__main__":
    unittest.main()
