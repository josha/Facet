--!strict
--[[ THE LINE BOX — `LuauUI.text.facts` / `LuauUI.text.lineBox`, and the three
	defects they fixed in `LuauUI.composition.floorPx` (ruled 2026-08-15,
	docs/plans/variable-item-extents.md).

	WHAT THIS FILE IS FOR. Declaring a correct `itemExtent`, a correct composition
	floor, or any "how tall is this text going to be" number used to mean
	hand-reproducing the solver's text arithmetic: the `max(typographyScale,
	typographyPaintScale)`, the ADDITIVE `preferredTextOffset`, and the live
	theme's line height for the role. A survey found SEVEN near-duplicates in this
	repo and exactly one correct — private to a gallery fixture — and the PUBLIC
	`composition.floorPx` was wrong three ways. When three independent `itemExtent`
	consumers make the same mistake, the API is wrong, not the consumers.

	THE PROOF IS DIFFERENTIAL, NOT ANECDOTAL. A helper that claims to equal the
	solver's answer cannot be trusted on three hand-picked cases: the whole defect
	class is "right on Studio Neutral at the default preference, wrong everywhere
	else". So §4 below generates a corpus — every shipped theme package x the four
	measured accessibility offsets x sub-1 through 3x preferences x both display
	classes x numeric and role-named sizes x 1..6 lines — MOUNTS each row through
	the real presenter, and compares `text.lineBox` to the rect the solver actually
	arranged and to the reserved size the solve recorded. Two independent equalities
	per row, several hundred rows, no tolerance.

	§1  text.facts — the two forms, and that they agree
	§2  text.lineBox — the arithmetic, the ceil-once property, the refusals
	§3  composition.floorPx — the three defects, one case each
	§4  the differential oracle against a real solve
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local UI = require("../src/blueprint")
local composition = require("../src/layout/composition")
local textFit = require("../src/layout/text_fit")
local textMetrics = require("../src/layout/text_metrics")
local snapshot = require("../src/themes/snapshot")
local prng = require("./lib/prng")
local lt = require("./lib/large_text")

local NEUTRAL = snapshot.neutral()
local NEUTRAL_PKG = snapshot.neutralPackage()

--[[ A THEME WHOSE ROLES DISAGREE ABOUT LINE HEIGHT. Every shipped package gives
	every role one factor (`out[role] = { …, lineHeight = 1.35 }`), so under all
	nine reference configurations "which role's line height did you take?" has no
	observable answer — a helper reading `control`'s factor for a `UI.Text` would
	pass the entire corpus. This snapshot is the one place the question is
	askable, and it is a corpus theme in §4 as well as a case in §2. ]]
local RAGGED = snapshot.resolve(NEUTRAL_PKG, nil, {}, {
	["type.body.lineHeight"] = 1.1,
	["type.control.lineHeight"] = 1.9,
	["type.title.lineHeight"] = 1.6,
	["type.caption.lineHeight"] = 1.45,
})

-- a reader that spends a Readable without registering a dependency. Spelled out
-- at every call site on purpose (see `text.facts`' own doc): a one-shot read is
-- legal here because a spec is not a reactive derivation, and writing it out is
-- what makes that a decision rather than an accident.
local function get(r: any): any
	return r:get()
end

-- ===== §1  text.facts ======================================================

describe("text.facts — the live text facts, read once for a whole extent pass", function()
	it("the { metrics } form derives the scales and the offset from the snapshot's own facts", function()
		local snap = snapshot.resolve(NEUTRAL_PKG, nil, {
			displaySize = "Large",
			preferredTextSize = 2,
			preferredTextOffset = 14,
		})
		local facts = LuauUI.text.facts({ metrics = snap })
		-- typographyScale = clamp(2) * the ten-foot 1.5 floor = 3; paint = 1.5;
		-- measure takes the larger, which is 3
		expect(`scale={facts.scale} offset={facts.offset}`).toBe("scale=3 offset=14")
	end)

	it("a SUB-1 preference reserves at the PAINT scale, never at the smaller one", function()
		--[[ THE RESERVATION FLOOR (preferred-text sweep, 2026-07-24). `typographyScale`
			legally goes down to 0.5 while the paint seam carries no preference factor at
			all, so a helper that used `typographyScale` alone would reserve HALF the box
			the engine draws into. Six of the seven hand copies did exactly that. ]]
		local snap = snapshot.resolve(NEUTRAL_PKG, nil, { preferredTextSize = 0.5 })
		expect(LuauUI.text.facts({ metrics = snap }).scale).toBe(1)
		local tenFoot = snapshot.resolve(NEUTRAL_PKG, nil, { displaySize = "Large", preferredTextSize = 0.5 })
		expect(LuauUI.text.facts({ metrics = tenFoot }).scale).toBe(1.5)
	end)

	it("the offset is clamped to the same legal domain the renderer's measure seam clamps it to", function()
		local wild = snapshot.resolve(NEUTRAL_PKG, nil, { preferredTextOffset = 4000 })
		expect(LuauUI.text.facts({ metrics = wild }).offset).toBe(32)
		local negative = snapshot.resolve(NEUTRAL_PKG, nil, { preferredTextOffset = -8 })
		expect(LuauUI.text.facts({ metrics = negative }).offset).toBe(0)
	end)

	it("the { env, use } form and the { metrics } form agree on every measured preference", function()
		--[[ THE TWO FORMS ARE ONE POLICY. `composition.floorPx` has only a snapshot;
			an `itemExtent` has a live env. If those two derivations could disagree, the
			framework would have exactly the parallel-copy defect this feature exists to
			end, one level up. Both call `themes/snapshot`'s text-scale policy. ]]
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		for _, display in { "Medium", "Large" } do
			for _, preference in { 0.5, 1, 1.5, 3 } do
				for _, offset in { 0, 4, 10, 14 } do
					local facts =
						{ displaySize = display, preferredTextSize = preference, preferredTextOffset = offset }
					env:set("displaySize", display)
					env:set("preferredTextSize", preference)
					env:set("preferredTextOffset", offset)
					local fromEnv = LuauUI.text.facts({ env = env, use = get })
					local fromSnap = LuauUI.text.facts({ metrics = snapshot.resolve(NEUTRAL_PKG, nil, facts) })
					expect(`{display}/{preference}/{offset}: {fromEnv.scale},{fromEnv.offset}`).toBe(
						`{display}/{preference}/{offset}: {fromSnap.scale},{fromSnap.offset}`
					)
				end
			end
		end
	end)

	it("{ env } WITHOUT `use` is refused — a fact read with :get() is right once and then stale", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		local ok, err = pcall(function()
			return LuauUI.text.facts({ env = env })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "use", 1, true) ~= nil).toBe(true)
	end)

	it("neither form, or both, is refused; an unknown key is refused", function()
		expect(pcall(function()
			return LuauUI.text.facts({})
		end)).toBe(false)
		expect(pcall(function()
			return LuauUI.text.facts({ env = {}, use = get, metrics = NEUTRAL })
		end)).toBe(false)
		expect(pcall(function()
			return (LuauUI.text.facts :: any)({ metrics = NEUTRAL, scale = 2 })
		end)).toBe(false)
	end)

	it("the extent function's contract: `use` is the memo's, so the facts re-derive when a fact moves", function()
		--[[ The reason `facts` takes `use` rather than reading the env itself: it has
			to register the dependency edges in the CALLER's derivation. Proved by
			driving the preference and watching a memo built on top of it recompute. ]]
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		local runs = 0
		local extent = core:memo(function(use)
			runs += 1
			local facts = LuauUI.text.facts({ env = env, use = use })
			return LuauUI.text.lineBox({ facts = facts, size = "body", lines = 2 })
		end)
		local first = extent:get()
		expect(runs).toBe(1)
		env:set("preferredTextOffset", 14)
		local second = extent:get()
		expect(`runs={runs} grew={second > first}`).toBe("runs=2 grew=true")
		env:set("displaySize", "Large")
		local third = extent:get()
		expect(`grewAgain={third > second}`).toBe("grewAgain=true")
	end)
end)

-- ===== §2  text.lineBox ====================================================

describe("text.lineBox — the one implementation of the line-box arithmetic", function()
	it("is the solver's own two seams, composed in the solver's order", function()
		local facts = LuauUI.text.facts({
			metrics = snapshot.resolve(NEUTRAL_PKG, nil, { preferredTextSize = 1.5, preferredTextOffset = 10 }),
		})
		local body = facts.metrics.type.body
		local expected = textMetrics.lineBoxPx(textMetrics.reservedSize(body.size, 1.5, 10), 3, body.lineHeight)
		expect(LuauUI.text.lineBox({ facts = facts, size = "body", lines = 3 })).toBe(expected)
	end)

	it("THE CEIL LANDS ONCE, on the whole product — not per line", function()
		--[[ THE RECORDED TRAP. Several of the hand copies ceiled one line and
			multiplied by the line count, which over-reserves by up to `lines - 1` px.
			Safe in direction, wrong as an answer, and enough to make the differential in
			§4 fail. This case is chosen so the two spellings differ: 13px at scale 1 and
			offset 0 under a 1.2 factor is 15.6 per line — `ceil(4 * 15.6) = 63` against
			`4 * ceil(15.6) = 64`. ]]
		local facts = LuauUI.text.facts({ metrics = NEUTRAL })
		local once = LuauUI.text.lineBox({ facts = facts, size = 13, lines = 4 })
		local perLine = 4 * LuauUI.text.lineBox({ facts = facts, size = 13, lines = 1 })
		expect(`once={once} perLine={perLine}`).toBe("once=63 perLine=64")
	end)

	it("the offset is ADDITIVE and lands AFTER the scale, never through it", function()
		--[[ The order is the engine's: it paints at `TextSize + offset` at draw time,
			so folding the preference into the scale is the double-application defect.
			`(size + offset) * scale` and `size * scale + offset` differ for every scale
			other than 1, and one of the seven copies had it the wrong way round. ]]
		local facts = LuauUI.text.facts({
			metrics = snapshot.resolve(NEUTRAL_PKG, nil, { displaySize = "Large", preferredTextOffset = 14 }),
		})
		-- scale 1.5, offset 14, body 16, factor 1.2 -> ceil((16*1.5 + 14) * 1.2) = 46.
		-- The wrong order would be ceil((16 + 14) * 1.5 * 1.2) = 54.
		expect(LuauUI.text.lineBox({ facts = facts, size = "body", lines = 1 })).toBe(46)
	end)

	it("a numeric size takes `body`'s line height — which is what the solver resolves it to", function()
		--[[ `snapshot.effectiveTypeRole` gives a literal px size on a `UI.Text` the
			class's INTRINSIC role, and that role is `body`. A helper that used the
			library's global 1.2 for numeric sizes would be right on Studio Neutral (whose
			body factor IS 1.2) and wrong under every package that authors its own.

			MEASURED AGAINST A RAGGED-FACTOR THEME, and that is not decoration: every one
			of the eight shipped packages gives EVERY role the same `lineHeight`, so
			"which role's factor did you take?" is unobservable under all of them. A
			mutation swapping `body` for `control` survived the whole file until this
			snapshot existed (mutation M9, artifacts/text-line-box/mutation-evidence.md).
			`RAGGED` is therefore a corpus theme too, not just a case here. ]]
		local parchment = lt.THEMES[2].metrics
		expect(parchment.type.body.lineHeight ~= textMetrics.LINE_HEIGHT_FACTOR).toBe(true)
		local facts = LuauUI.text.facts({ metrics = parchment })
		expect(LuauUI.text.lineBox({ facts = facts, size = 20, lines = 2 })).toBe(
			textMetrics.lineBoxPx(20, 2, parchment.type.body.lineHeight)
		)
		local ragged = LuauUI.text.facts({ metrics = RAGGED })
		expect(RAGGED.type.control.lineHeight ~= RAGGED.type.body.lineHeight).toBe(true)
		expect(LuauUI.text.lineBox({ facts = ragged, size = 20, lines = 2 })).toBe(
			textMetrics.lineBoxPx(20, 2, RAGGED.type.body.lineHeight)
		)
	end)

	it("the offset's marginal cost does NOT depend on the scale — the invariant behind `additive AFTER`", function()
		--[[ The `size * scale + offset` vs `(size + offset) * scale` question, asked as
			a PROPERTY rather than as one arithmetic snapshot. If the offset went through
			the scale, raising the display class would multiply what the offset costs;
			because it lands after, the extra pixels an offset buys are the same at every
			scale. Restating the formula here would just be an eighth copy of it. ]]
		local function boxAt(scale: number, offset: number): number
			local snap = snapshot.resolve(NEUTRAL_PKG, nil, {
				displaySize = if scale > 1 then "Large" else "Medium",
				preferredTextSize = 1,
				preferredTextOffset = offset,
			})
			return LuauUI.text.lineBox({ facts = LuauUI.text.facts({ metrics = snap }), size = 20, lines = 1 })
		end
		local nearCost = boxAt(1, 14) - boxAt(1, 0)
		local tenFootCost = boxAt(1.5, 14) - boxAt(1.5, 0)
		expect(`near={nearCost} tenFoot={tenFootCost}`).toBe(`near=17 tenFoot=17`)
	end)

	it("`role` overrides which line height applies, without moving the size", function()
		-- against `RAGGED` for the reason above: under every shipped package this
		-- assertion is vacuous, because title and body carry the same factor
		local facts = LuauUI.text.facts({ metrics = RAGGED })
		local asBody = LuauUI.text.lineBox({ facts = facts, size = 20, lines = 2 })
		local asTitle = LuauUI.text.lineBox({ facts = facts, size = 20, lines = 2, role = "title" })
		expect(asTitle).toBe(textMetrics.lineBoxPx(20, 2, RAGGED.type.title.lineHeight))
		expect(asBody).toBe(textMetrics.lineBoxPx(20, 2, RAGGED.type.body.lineHeight))
		expect(`overrideMoved={asTitle ~= asBody}`).toBe("overrideMoved=true")
		-- ...and a role-NAMED size takes that role's own factor, not body's
		expect(LuauUI.text.lineBox({ facts = facts, size = "control", lines = 2 })).toBe(
			textMetrics.lineBoxPx(RAGGED.type.control.size, 2, RAGGED.type.control.lineHeight)
		)
	end)

	it("refuses a role this theme does not carry, a bad size, a bad line count and an unknown key", function()
		local facts = LuauUI.text.facts({ metrics = NEUTRAL })
		local cases: { { name: string, run: () -> any, names: string } } = {
			{
				name = "unknown role in `size`",
				run = function()
					return LuauUI.text.lineBox({ facts = facts, size = "nonsense" })
				end,
				names = "nonsense",
			},
			{
				name = "unknown role in `role`",
				run = function()
					return LuauUI.text.lineBox({ facts = facts, size = 12, role = "nonsense" })
				end,
				names = "nonsense",
			},
			{
				name = "zero lines",
				run = function()
					return LuauUI.text.lineBox({ facts = facts, size = 12, lines = 0 })
				end,
				names = "lines",
			},
			{
				name = "negative size",
				run = function()
					return LuauUI.text.lineBox({ facts = facts, size = -3 })
				end,
				names = "size",
			},
			{
				name = "facts that did not come from text.facts",
				run = function()
					return LuauUI.text.lineBox({ facts = { scale = 1 } :: any, size = 12 })
				end,
				names = "text.facts",
			},
			{
				name = "an unknown spec key",
				run = function()
					return (LuauUI.text.lineBox :: any)({ facts = facts, size = 12, lineHeight = 1.4 })
				end,
				names = "lineHeight",
			},
		}
		for _, case in cases do
			local ok, err = pcall(case.run)
			expect(`{case.name}: refused={not ok}`).toBe(`{case.name}: refused=true`)
			expect(`{case.name}: names={string.find(tostring(err), case.names, 1, true) ~= nil}`).toBe(
				`{case.name}: names=true`
			)
		end
	end)
end)

-- ===== §3  composition.floorPx =============================================

describe("composition.floorPx — the three defects a public function carried", function()
	--[[ `floorPx` is PUBLIC and it was wrong, which is worse than absent: a caller
		trusts it. It computed `lines * role.size * role.lineHeight`. Each `it` below
		reddens on its own if exactly one of the three fixes is reverted — the ceil
		case never sees a scale or an offset, the scale case is at the default offset,
		and the offset case is on a near display at the default preference. ]]

	it("DEFECT 1 — no `ceil`: the floor could be smaller than any box the solver can draw", function()
		--[[ Neutral body is 16 at a 1.2 factor: one line is 19.2, and the solver's own
			box for it is `ceil(19.2) = 20`. A floor of 19.2 says a region can hold one
			line in 19.2px — the measure that follows disagrees by 0.8px, every line, and
			the region wins a step-down it is not entitled to. Two lines: 38.4 vs 39. ]]
		local role = NEUTRAL.type.body
		expect(role.size * role.lineHeight).toBe(19.2) -- the old answer, for the record
		expect(composition.floorPx({ lines = 1 }, NEUTRAL)).toBe(20)
		expect(composition.floorPx({ lines = 2 }, NEUTRAL)).toBe(39)
		-- the general property, so a case that stops differing does not stop testing
		for lines = 1, 6 do
			local px = composition.floorPx({ lines = lines }, NEUTRAL) :: number
			expect(`{lines}: integer={px == math.floor(px)}`).toBe(`{lines}: integer=true`)
			expect(`{lines}: >=exact={px >= lines * role.size * role.lineHeight}`).toBe(`{lines}: >=exact=true`)
		end
	end)

	it("DEFECT 2 — no SCALE: the player's text preference and the ten-foot floor moved nothing", function()
		--[[ The doc comment promised "a bigger type scale raises every floor by
			itself", and that only ever happened when the THEME's authored numbers moved.
			`role.size` is the AUTHORED size; the measure seam reserves at
			`max(typographyScale, typographyPaintScale)`. On a ten-foot display the whole
			ladder is x1.5, and at preference 2 it is x3 — so a one-line floor of 20 was
			being spent where the solver measures 58. At the DEFAULT offset, so nothing
			here can be attributed to defect 3. ]]
		local tenFoot = snapshot.resolve(NEUTRAL_PKG, nil, { displaySize = "Large" })
		local raised = snapshot.resolve(NEUTRAL_PKG, nil, { preferredTextSize = 2 })
		local both = snapshot.resolve(NEUTRAL_PKG, nil, { displaySize = "Large", preferredTextSize = 2 })
		-- the AUTHORED numbers are identical in all four snapshots; only the facts move
		expect(tenFoot.type.body.size).toBe(NEUTRAL.type.body.size)
		expect(composition.floorPx({ lines = 1 }, NEUTRAL)).toBe(20) -- 16 * 1.2
		expect(composition.floorPx({ lines = 1 }, tenFoot)).toBe(29) -- 16*1.5 * 1.2 = 28.8
		expect(composition.floorPx({ lines = 1 }, raised)).toBe(39) -- 16*2 * 1.2 = 38.4
		expect(composition.floorPx({ lines = 1 }, both)).toBe(58) -- 16*3 * 1.2 = 57.6
	end)

	it("DEFECT 3 — no TEXT OFFSET: the four preferences this project binds itself to were invisible", function()
		--[[ `preferredTextOffset` is ADDITIVE px the engine adds to every painted line,
			and the measured set is {0, 4, 10, 14}. On a near display at the default
			preference — so the scale is 1 and defect 2 cannot be in play — a one-line
			floor was short by `ceil(offset * 1.2)` at every one of them, and a four-line
			floor by four times that. ]]
		for _, offset in { 0, 4, 10, 14 } do
			local snap = snapshot.resolve(NEUTRAL_PKG, nil, { preferredTextOffset = offset })
			expect(LuauUI.text.facts({ metrics = snap }).scale).toBe(1) -- no scale in this row
			local one = composition.floorPx({ lines = 1 }, snap) :: number
			local four = composition.floorPx({ lines = 4 }, snap) :: number
			expect(`+{offset} one={one} four={four}`).toBe(
				`+{offset} one={math.ceil((16 + offset) * 1.2)} four={math.ceil(4 * (16 + offset) * 1.2)}`
			)
			expect(`+{offset} grew={one > 19.2}`).toBe(`+{offset} grew={offset > 0 or true}`)
		end
	end)

	it("the un-broken halves are untouched: `targets`, the max of both, nil, and the role fallback", function()
		expect(composition.floorPx(nil, NEUTRAL)).toBe(nil)
		expect(composition.floorPx({ targets = 2 }, NEUTRAL)).toBe(2 * NEUTRAL.targetSizes.minimum)
		local both = composition.floorPx({ lines = 1, targets = 2 }, NEUTRAL) :: number
		expect(both).toBe(math.max(20, 2 * NEUTRAL.targetSizes.minimum))
		-- a `role` this theme does not carry still falls back to `body`, exactly as it
		-- always has: tightening THAT is a separate decision from fixing the arithmetic
		expect(composition.floorPx({ lines = 1, role = "nonsense" }, NEUTRAL)).toBe(
			composition.floorPx({ lines = 1 }, NEUTRAL)
		)
		-- ...and a snapshot with no typography at all falls back to the neutral body
		-- size and the measurer's own factor rather than erroring inside a solve
		expect(composition.floorPx({ lines = 1 }, {})).toBe(math.ceil(14 * textMetrics.LINE_HEIGHT_FACTOR))
	end)

	it("a named role still wins, and it scales with the facts like every other floor", function()
		local snap = snapshot.resolve(NEUTRAL_PKG, nil, { preferredTextOffset = 14 })
		local title = snap.type.title
		expect(composition.floorPx({ lines = 2, role = "title" }, snap)).toBe(
			textMetrics.lineBoxPx(textMetrics.reservedSize(title.size, 1, 14), 2, title.lineHeight)
		)
	end)
end)

-- ===== §4  the differential oracle =========================================

--[[ EVERY SHIPPED THEME PACKAGE. Nine configurations is what every geometry
	claim in this repo is measured against, and the reason it matters here is
	`lineHeight`: the packages carry 1.2, 1.25, 1.3, 1.35 and 1.45, so a helper
	that used the library's global factor would be right on exactly one of them. ]]
local PACKAGE_NAMES = {
	"glossy_mobile",
	"glossy_touch",
	"pixel_quest",
	"fantasy_ornate",
	"scifi_hud",
	"compact_pointer",
	"classic_desktop",
	"fantasy_parchment",
}

local THEMES: { { id: string, pkg: any, overrides: any? } } = { { id = "studio-neutral", pkg = NEUTRAL_PKG } }
for _, name in PACKAGE_NAMES do
	local built = (require)(`../examples/themes/{name}`)
	local pkg = built.build(LuauUI.themes)
	table.insert(THEMES, { id = name, pkg = pkg })
end
-- ...and the ragged-factor theme, which is the ONLY configuration in this repo
-- where the role a size resolves to is observable at all (see `RAGGED` above)
table.insert(THEMES, {
	id = "ragged-line-heights",
	pkg = NEUTRAL_PKG,
	overrides = {
		["type.body.lineHeight"] = 1.1,
		["type.control.lineHeight"] = 1.9,
		["type.title.lineHeight"] = 1.6,
		["type.caption.lineHeight"] = 1.45,
	},
})

local DISPLAYS = { "Medium", "Large" }
local PREFERENCES = { 0.5, 0.75, 1, 1.25, 1.5, 2, 3 }
local OFFSETS = { 0, 4, 10, 14 }
local ROLES = { "caption", "body", "control", "title" }
-- one-character words, so the string wraps at every viewport this sweep uses even
-- when a 3x preference and a +14 offset put a line at ~140px: `singleLine` in the
-- solver latches on the widest WORD, and a corpus whose rows silently collapse to
-- one line would prove nothing about `lines`
local WRAPPY = string.rep("a b c d e f g h i j ", 40)
local BOX_W = 420

describe("text.lineBox equals what the solver arranges — differentially, over a generated corpus", function()
	it(
		"every row: the predicted line box IS the arranged rect, and the predicted reserved size IS the solve's",
		function()
			--[[ THE ORACLE. Each row mounts a real Screen through the real presenter with a
			real theme snapshot and real env facts, puts eight `UI.Text` nodes in it at
			assorted sizes and line caps, and asks two questions of each:

			  1. does `text.lineBox` equal the height the solver ARRANGED?
			  2. does `text_metrics.reservedSize(authored, facts.scale, facts.offset)`
			     equal the size the solve RECORDED measuring at?

			(2) is not implied by (1): a helper could get the reserved size wrong and the
			ceil could hide it. Both are exact — no tolerance, no "within a pixel".

			The corpus is seeded, so a failure is replayable from its seed alone. ]]
			local rng = prng.new(0x1EB0C)
			local rows = 0
			local comparisons = 0
			local sawTenFoot, sawSubOne, sawRoleName, sawMultiLine = false, false, false, false
			local failures: { string } = {}

			for _, theme in THEMES do
				for row = 1, 5 do
					local display = DISPLAYS[if row % 2 == 0 then 2 else 1]
					local preference = rng:pick(PREFERENCES)
					local offset = rng:pick(OFFSETS)
					local facts = {
						displaySize = display,
						preferredTextSize = preference,
						preferredTextOffset = offset,
					}
					local metrics = snapshot.resolve(theme.pkg, nil, facts, theme.overrides)
					local w = lt.world({
						viewport = { x = 0, y = 0, w = 900, h = 1400 },
						offset = offset,
						theme = { id = theme.id, metrics = metrics },
					})
					w.env:set("displaySize", display)
					w.env:set("preferredTextSize", preference)

					-- eight texts per mount: the mount is the expensive part, the comparisons
					-- are free, and one solve holding many sizes is also a harder test of the
					-- role ladder than eight solves holding one
					local children = {}
					local declared: { { id: string, size: any, lines: number } } = {}
					for i = 1, 8 do
						local useRole = rng:bool(0.5)
						local size: any = if useRole then rng:pick(ROLES) else rng:range(9, 34)
						local lines = rng:range(1, 6)
						if useRole then
							sawRoleName = true
						end
						if lines > 1 then
							sawMultiLine = true
						end
						local id = `T{i}`
						table.insert(declared, { id = id, size = size, lines = lines })
						table.insert(
							children,
							UI.Text({
								id = id,
								text = WRAPPY,
								textSize = size,
								lineLimit = lines,
								width = { type = "fixed", px = BOX_W },
							})
						)
					end
					w.present(UI.Screen({ id = "S", children = children }))

					local live = LuauUI.text.facts({ env = w.env, use = get })
					if live.scale > 1 and display == "Large" then
						sawTenFoot = true
					end
					if preference < 1 then
						sawSubOne = true
					end
					rows += 1

					for _, d in declared do
						local node = w.adapter.node(`/S/{d.id}`)
						local solved = w.controller.textAt(`/S/{d.id}`)
						local tag = `{theme.id}/{display}/pref{preference}/+{offset}/{tostring(d.size)}x{d.lines}`
						if node == nil or node.rect == nil or solved == nil then
							table.insert(failures, `{tag}: the node did not solve`)
							continue
						end
						-- the row is only a test of `lines` if the string really wrapped past
						-- the cap; a silently-collapsed row would pass vacuously
						if solved.naturalLines < d.lines then
							table.insert(failures, `{tag}: the corpus string did not reach {d.lines} lines`)
							continue
						end
						comparisons += 1
						local predicted = LuauUI.text.lineBox({ facts = live, size = d.size, lines = d.lines })
						if predicted ~= node.rect.h then
							table.insert(
								failures,
								`{tag}: predicted {predicted}px, the solver arranged {node.rect.h}px`
							)
						end
						local authored = if type(d.size) == "number" then d.size else metrics.type[d.size].size
						local reserved = textMetrics.reservedSize(authored, live.scale, live.offset)
						if reserved ~= solved.size then
							table.insert(
								failures,
								`{tag}: predicted a reserved size of {reserved}, the solve used {solved.size}`
							)
						end
					end
				end
			end

			-- the corpus must be broad enough to have been able to fail
			expect(`rows={rows >= 50} comparisons={comparisons >= 340}`).toBe("rows=true comparisons=true")
			expect(`tenFoot={sawTenFoot} subOne={sawSubOne} roleName={sawRoleName} multiLine={sawMultiLine}`).toBe(
				"tenFoot=true subOne=true roleName=true multiLine=true"
			)
			expect(`failures={#failures}: {table.concat(failures, " | ")}`).toBe("failures=0: ")
		end
	)
end)
