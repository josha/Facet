--!strict
--[[ ONE SUGGESTER, FIVE POLICIES KEPT (ARCH-17 / reuse audit REUSE-5).

	`src/text_distance.luau` now owns the bounded-Levenshtein matrix and the
	sorted list renderer that `spec_guard`, `themes/package`, `blueprint_schema`,
	`motion/classes` and `motion/curves` each carried privately. The five copies
	were not the interesting part — the THRESHOLDS were, and they disagreed:

	  · `spec_guard` / `themes/package`: distance <= 2, case-SENSITIVE.
	  · `blueprint_schema` / `motion/classes` / `motion/curves`: both sides
	    lowercased, `d <= max(2, floor(#name / 3))`.

	So this file pins BOTH halves. The arithmetic is pinned directly, because a
	single owner means a single edit changes every error message in the framework.
	The policies are pinned THROUGH THE CALLERS, at the boundary an author reads,
	because "each caller keeps its current threshold explicitly" is the whole
	claim of the consolidation and a unit test of the helper cannot see it.

	THE MUTATION THAT MOTIVATED THE POLICY CASES: widening the comparison in
	`text_distance.nearest` from `d < bestD` to `d <= bestD` — a one-character
	slip that silently loosens every closed-key-set suggester in the framework —
	survived the entire fast tier before this file existed.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local textDistance = require("../src/text_distance")
local spec_guard = require("../src/spec_guard")
local curves = require("../src/motion/curves")

describe("text_distance: the matrix five modules wrote by hand", function()
	it("distance counts insertions, deletions and substitutions", function()
		expect(textDistance.distance("kitten", "sitting")).toBe(3)
		expect(textDistance.distance("same", "same")).toBe(0)
		expect(textDistance.distance("abc", "abd")).toBe(1) -- substitution
		expect(textDistance.distance("abc", "abcd")).toBe(1) -- insertion
		expect(textDistance.distance("abcd", "abc")).toBe(1) -- deletion
	end)

	--[[ NOT Damerau: a transposition costs TWO, not one. Every copy was
		transposition-free and the error text five modules print depends on it —
		`lable` is two from `label`, which is exactly at the case-sensitive
		callers' cutoff and would fall inside a Damerau one. ]]
	it("a transposition costs two, because this is not Damerau", function()
		expect(textDistance.distance("ab", "ba")).toBe(2)
		expect(textDistance.distance("lable", "label")).toBe(2)
	end)

	it("an empty side costs the other side's length", function()
		expect(textDistance.distance("", "")).toBe(0)
		expect(textDistance.distance("", "abcd")).toBe(4)
		expect(textDistance.distance("abcd", "")).toBe(4)
	end)

	it("it measures BYTES, which is what an identifier is", function()
		expect(textDistance.distance("Label", "label")).toBe(1) -- case IS a difference
	end)

	it("nearest refuses everything past the threshold the caller passed", function()
		local set = { label = true, layout = true, leading = true }
		expect(textDistance.nearest("labl", set, 2)).toBe("label") -- distance 1
		expect(textDistance.nearest("labl", set, 0)).toBeNil() -- ...and 1 > 0
		expect(textDistance.nearest("lable", set, 2)).toBe("label") -- distance 2, at the cutoff
		expect(textDistance.nearest("lable", set, 1)).toBeNil() -- ...and outside a tighter one
		expect(textDistance.nearest("completelyUnrelated", set, 2)).toBeNil()
	end)

	--[[ THE OFF-BY-ONE THIS FILE EXISTS FOR. `nearest` keeps a candidate only on
		a STRICT improvement, seeded one past the caller's maximum — so a distance
		exactly equal to `maxDistance` is accepted and one past it is not.
		Loosening `<` to `<=` changes no answer this assertion can see, so the
		boundary is asserted from both sides. ]]
	it("the threshold boundary is inclusive on the caller's number and nothing past it", function()
		local set = { alpha = true }
		expect(textDistance.nearest("alpht", set, 1)).toBe("alpha") -- d = 1 <= 1
		expect(textDistance.nearest("alphtx", set, 1)).toBeNil() -- d = 2 > 1
		expect(textDistance.nearest("alphtx", set, 2)).toBe("alpha")
	end)

	--[[ ENOUGH KEYS THAT HASH ORDER CANNOT PASS FOR SORTED ORDER. Three keys
		were not: dropping the `table.sort` left the three-key case still reading
		"apple, mango, zebra" by luck, so the mutation did not bite. A legal set
		printed in hash order is a different sentence on every run of a different
		build, which is exactly what an error message may not be. ]]
	it("listOf sorts, and the separator is the caller's sentence", function()
		local set = {
			zebra = true,
			apple = true,
			mango = true,
			kiwi = true,
			fig = true,
			cherry = true,
			banana = true,
			date = true,
		}
		expect(textDistance.listOf(set)).toBe("apple, banana, cherry, date, fig, kiwi, mango, zebra")
		expect(textDistance.listOf(set, " | ")).toBe("apple | banana | cherry | date | fig | kiwi | mango | zebra")
		expect(textDistance.listOf({})).toBe("")
	end)
end)

--[[ THE POLICIES, AT THE BOUNDARIES THAT OWN THEM. Two families, and the point
	of consolidating the arithmetic was to make the difference between them
	visible rather than to erase it. ]]
--[[ THE PUBLIC FACADE, WHICH IS A DIFFERENT THING FROM THE MODULE
	(ARCH-8; R5 review §4-4).

	`Facet.specGuard` is the wave's only new public export, and it shipped with
	no facade test at all — every case below this line requires
	`../src/spec_guard` directly, which exercises the MODULE and says nothing
	about the export. Measured by the review: replacing the export in
	`src/init.luau` with a frozen no-op stub left the suite at 6467 passed, the
	public-surface dump unchanged and both structural checkers at exit 0.

	That is the exact defect §4 existed to fix — the wave added four facade cases
	for four motion aliases in the same commit for this reason and did not apply
	the rule to itself. These four go through `Facet.specGuard`, the table an
	out-of-repo control author actually holds. ]]
describe("ARCH-8: the specGuard FACADE, not the module behind it", function()
	local Facet = require("../src") :: any

	it("the export is the module, and carries both members", function()
		expect(Facet.specGuard).toBe(spec_guard)
		expect(type(Facet.specGuard.keySet)).toBe("function")
		expect(type(Facet.specGuard.assertKnownKeys)).toBe("function")
	end)

	it("keySet through the facade builds a FROZEN set", function()
		local set = Facet.specGuard.keySet({ "id", "value", "onChange" })
		expect(set.id).toBe(true)
		expect(set.nope).toBeNil()
		--[[ FROZEN is load-bearing, not decoration: the documented shape is "build
			it once at module scope", and a shared mutable set would let one control's
			spec widen another's legal keys. ]]
		expect(table.isfrozen(set)).toBe(true)
	end)

	it("assertKnownKeys through the facade refuses, names the boundary, and suggests", function()
		local SPEC_KEYS = Facet.specGuard.keySet({ "id", "value", "onChange" })
		-- the documented example from api.md §specGuard, run
		local ok, err = pcall(function()
			Facet.specGuard.assertKnownKeys("newGauge", { id = "g", onChanged = function() end }, SPEC_KEYS, "spec")
		end)
		expect(ok).toBe(false)
		local text = tostring(err)
		-- the PUBLIC name the author typed, so the error is greppable from the call site
		expect(string.find(text, "Facet newGauge:", 1, true) ~= nil).toBe(true)
		expect(string.find(text, "unknown spec key 'onChanged'", 1, true) ~= nil).toBe(true)
		expect(string.find(text, "Did you mean 'onChange'%?") ~= nil).toBe(true)
		expect(string.find(text, "Known: id, onChange, value.", 1, true) ~= nil).toBe(true)
	end)

	it("a conforming spec passes, and `kind` is the sentence's own word", function()
		local OPTS_KEYS = Facet.specGuard.keySet({ "retry", "now" })
		Facet.specGuard.assertKnownKeys("newGauge", { retry = 1 }, OPTS_KEYS, "opts") -- no throw
		Facet.specGuard.assertKnownKeys("newGauge", nil, OPTS_KEYS, "opts") -- nil is not a spec
		local ok, err = pcall(function()
			Facet.specGuard.assertKnownKeys("newGauge", { nope = 1 }, OPTS_KEYS, "opts")
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "unknown opts key", 1, true) ~= nil).toBe(true)
	end)
end)

describe("ARCH-17: each caller kept its own threshold", function()
	local KNOWN = spec_guard.keySet({ "label", "onActivate", "focusVisual" })

	it("spec_guard suggests at distance 2 and stops there — case-SENSITIVELY", function()
		local ok, err = pcall(function()
			spec_guard.assertKnownKeys("newThing", { lable = 1 }, KNOWN, "spec")
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "Did you mean 'label'%?") ~= nil).toBe(true)

		-- three edits away: named as unknown, with the legal set, and NO guess
		local ok2, err2 = pcall(function()
			spec_guard.assertKnownKeys("newThing", { labelling = 1 }, KNOWN, "spec")
		end)
		expect(ok2).toBe(false)
		expect(string.find(tostring(err2), "Did you mean") == nil).toBe(true)
		expect(string.find(tostring(err2), "Known: focusVisual, label, onActivate%.") ~= nil).toBe(true)

		--[[ CASE-SENSITIVE, WRITTEN OUT: `LABEL` is five edits from `label` here
			and would be zero under the motion registries' folded policy. This is the
			difference ARCH-17 records rather than settles. ]]
		local ok3, err3 = pcall(function()
			spec_guard.assertKnownKeys("newThing", { LABEL = 1 }, KNOWN, "spec")
		end)
		expect(ok3).toBe(false)
		expect(string.find(tostring(err3), "Did you mean") == nil).toBe(true)
	end)

	it("motion/curves folds case and scales its threshold with the name's length", function()
		curves.reset()
		curves.registerCurve("bannerEntrance", { duration = 0.4, style = "quad", direction = "out" })

		-- FOLDED: an all-caps citation of a registered curve is still recognised
		local ok, err = pcall(function()
			curves.resolve("BANNERENTRANCE")
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "Did you mean 'bannerEntrance'%?") ~= nil).toBe(true)

		--[[ SCALED: `bannerEntrance` is 14 characters, so this caller accepts
			`max(2, floor(14 / 3))` = 4 edits — where `spec_guard` would have stopped
			at 2 and offered nothing. ]]
		local ok2, err2 = pcall(function()
			curves.resolve("bannerEntr")
		end)
		expect(ok2).toBe(false)
		expect(textDistance.distance("bannerEntr", "bannerEntrance")).toBe(4)
		expect(string.find(tostring(err2), "Did you mean 'bannerEntrance'%?") ~= nil).toBe(true)

		-- ...and past even the scaled cutoff there is still no guess
		local ok3, err3 = pcall(function()
			curves.resolve("somethingElseEntirely")
		end)
		expect(ok3).toBe(false)
		expect(string.find(tostring(err3), "Did you mean") == nil).toBe(true)
		curves.reset()
	end)
end)
