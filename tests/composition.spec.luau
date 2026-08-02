--!strict
-- DECLARED-CONTENT ADAPTIVE COMPOSITION (ADR-0023; ledger row OWN-D45).
--
-- The decision is PURE, so most of this file drives `composition.resolve` with a
-- synthetic measure table and asserts the whole matrix — arrangement choice per
-- rule, step-down order including rank ties, drop order, floor arithmetic,
-- reserved-at-rest, the one-scroll refusal, the Q9 column fallback. Nothing here
-- needs a mount, which is exactly the point: a device matrix that used to be a
-- screenshot review is a sweep.
--
-- The last two describes close the loop through the REAL path: a mounted
-- UI.Composition over FakeTarget, where the proof is rects, `hidden`, and the
-- re-solve counters (zero factory reruns, zero creates, zero removes across an
-- arrangement change) — the same proof AdaptiveStack's axis flip makes.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local composition = require("../src/layout/composition")
local themeSnapshot = require("../src/themes/snapshot")
local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")

-- ===== the fixture declaration =============================================
-- Shaped like the commissioning surface: a masthead that spans, a ceremony lane
-- that hugs, ONE field that fills and scrolls, and a trailing action lane.

local SIZES: { [string]: { { w: number, h: number } } } = {
	Ctas = { { w = 340, h = 52 }, { w = 170, h = 110 } },
	Field = { { w = 260, h = 400 } },
	Countdown = { { w = 160, h = 20 }, { w = 40, h = 20 } },
	Hero = { { w = 200, h = 96 }, { w = 140, h = 26 } },
	Slot = { { w = 200, h = 76 }, { w = 160, h = 44 } },
	FieldHead = { { w = 240, h = 40 }, { w = 200, h = 20 } },
	BankChip = { { w = 120, h = 24 }, { w = 80, h = 24 } },
	Sponsors = { { w = 180, h = 70 }, { w = 160, h = 20 } },
	Bogey = { { w = 180, h = 40 }, { w = 170, h = 20 } },
	Bait = { { w = 170, h = 40 }, { w = 170, h = 20 } },
	Tease = { { w = 170, h = 40 }, { w = 170, h = 20 } },
}

local function measureFrom(sizes: { [string]: { { w: number, h: number } } })
	return function(id: string, form: number, availW: number, _availH: number): (number, number)
		local forms = sizes[id]
		if forms == nil then
			return 0, 0
		end
		local entry = forms[math.min(form, #forms)]
		return math.min(entry.w, availW), entry.h
	end
end

local ARRANGEMENTS = {
	{ name = "threeLane", lanes = { { "head", "lead" }, { "main" }, { "trail" } } },
	{ name = "twoLane", lanes = { { "main" }, { "head", "lead", "trail" } } },
	{ name = "column", lanes = { { "head", "lead", "main", "trail" } } },
}

local function baseDecl(overrides: { [string]: any }?): any
	local decl = {
		id = "Results",
		laneGap = 12,
		groupGap = 8,
		arrangements = ARRANGEMENTS,
		groups = {
			{ id = "masthead", lane = "head", sizing = "hug", place = "start", gap = 4 },
			{ id = "ceremony", lane = "lead", sizing = "hug", place = "center", gap = 6 },
			{ id = "field", lane = "main", sizing = "fill", weight = 1, minWidth = 240, gap = 4 },
			{ id = "next", lane = "trail", sizing = "hug", place = 0.66, gap = 4 },
		},
		regions = {
			{ id = "Countdown", group = "masthead", rank = 2, forms = 2, floor = { lines = 1 } },
			{ id = "BankChip", group = "masthead", rank = 5, forms = 2, mayDrop = true },
			{ id = "Hero", group = "ceremony", rank = 3, forms = 2, floor = { lines = 1 } },
			{ id = "Slot", group = "ceremony", rank = 4, forms = 2, reserved = true, floor = { targets = 2 } },
			{ id = "Bogey", group = "ceremony", rank = 7, forms = 2, mayDrop = true },
			{ id = "FieldHead", group = "field", rank = 4, forms = 2, floor = { lines = 1 } },
			{
				id = "Field",
				group = "field",
				rank = 2,
				forms = 1,
				sizing = "fill",
				mayScroll = true,
				floor = { lines = 1 },
			},
			{ id = "Sponsors", group = "next", rank = 6, forms = 2, mayDrop = true },
			{ id = "Bait", group = "next", rank = 8, forms = 2, mayDrop = true },
			{ id = "Tease", group = "next", rank = 9, forms = 2, mayDrop = true },
			{ id = "Ctas", group = "next", rank = 1, forms = 2, floor = { targets = 2 } },
		},
	}
	for k, v in overrides or {} do
		decl[k] = v
	end
	return decl
end

local NEUTRAL = themeSnapshot.neutral()
local function ctx(sizes: { [string]: { { w: number, h: number } } }?)
	return {
		measure = measureFrom(sizes or SIZES),
		floorOf = function(r: any): number?
			return composition.floorPx(r.floor, NEUTRAL)
		end,
	}
end

local function resolve(w: number, h: number, decl: any?, sizes: any?)
	return composition.resolve(decl or baseDecl(), { w = w, h = h }, ctx(sizes))
end

local function formOf(res: any, id: string): number
	return res.regionById[id].form
end
local function mountedIds(res: any): { string }
	local out = {}
	for _, r in res.regions do
		if r.mounted then
			table.insert(out, r.id)
		end
	end
	return out
end
local function has(list: { string }, id: string): boolean
	return table.find(list, id) ~= nil
end

-- ===== arrangement choice ==================================================

describe("ADR-0023: the arrangement is chosen from the BOX, on both axes", function()
	it("a short wide offer resolves the richest arrangement (landscape phone)", function()
		local res = resolve(733, 313)
		expect(res.arrangement).toBe("threeLane")
		expect(res.legal).toBe(true)
		expect(res.fallback).toBe(false)
		expect(#res.rejected).toBe(0)
	end)

	it("a tall narrow offer falls to the column, and SAYS why the lanes lost", function()
		local res = resolve(360, 740)
		expect(res.arrangement).toBe("column")
		expect(res.legal).toBe(true)
		expect(#res.rejected).toBe(2)
		expect(res.rejected[1].arrangement).toBe("threeLane")
		expect(res.rejected[1].rule).toBe("laneWidth")
		-- the detail is the MEASUREMENT, not a category: it names the lane, what
		-- it got, and what it needed
		expect(string.find(res.rejected[1].detail, "240", 1, true) ~= nil).toBe(true)
		expect(res.rejected[2].arrangement).toBe("twoLane")
	end)

	it("a large offer stays on the richest arrangement (desktop)", function()
		expect(resolve(1400, 900).arrangement).toBe("threeLane")
	end)

	it("the choice follows the OFFER, not a viewport: the same width decides differently by height", function()
		-- 900 wide is one number; at 313 tall the lanes win, and shrinking the
		-- height alone can never change a width-only classifier's answer
		expect(resolve(900, 313).arrangement).toBe("threeLane")
		expect(resolve(900, 1200).arrangement).toBe("threeLane")
		-- ...while narrowing it does
		expect(resolve(420, 1200).arrangement).toBe("column")
	end)

	it("Q9: with twoLane withheld, an offer that fails threeLane falls to the column", function()
		local decl = baseDecl({ arrangements = { ARRANGEMENTS[1], ARRANGEMENTS[3] } })
		local res = resolve(360, 740, decl)
		expect(res.arrangement).toBe("column")
		expect(#res.rejected).toBe(1)
		expect(res.rejected[1].arrangement).toBe("threeLane")
	end)

	it("when NO candidate is legal the LAST one shows, flagged as the declared fallback", function()
		local res = resolve(300, 200)
		expect(res.arrangement).toBe("column")
		expect(res.legal).toBe(false)
		expect(res.fallback).toBe(true)
		expect(#res.rejected).toBe(3)
		-- a screen degrades; it never blanks
		expect(#mountedIds(res) > 0).toBe(true)
	end)
end)

-- ===== step-down before drop, both descending rank =========================

describe("ADR-0023: step down before dropping, both in descending rank", function()
	it("a lane that overflows steps its LEAST important region down first", function()
		-- one lane, tall enough for everything but the last few pixels
		local decl = baseDecl({ arrangements = { ARRANGEMENTS[3] } })
		local res = resolve(360, 570, decl)
		-- Tease is rank 9, the least important region on the surface
		expect(formOf(res, "Tease")).toBe(2)
		-- ...and nothing more important moved
		expect(formOf(res, "Ctas")).toBe(1)
		expect(formOf(res, "Hero")).toBe(1)
		expect(formOf(res, "Bait")).toBe(1)
	end)

	it("squeezing further walks UP the rank order, one region at a time", function()
		local decl = baseDecl({ arrangements = { ARRANGEMENTS[3] } })
		local looser = resolve(360, 570, decl)
		local tighter = resolve(360, 550, decl)
		local tightest = resolve(360, 500, decl)
		expect(formOf(looser, "Tease")).toBe(2)
		expect(formOf(looser, "Bait")).toBe(1)
		expect(formOf(tighter, "Bait")).toBe(2)
		expect(formOf(tighter, "Sponsors")).toBe(1)
		expect(formOf(tightest, "Sponsors")).toBe(2)
	end)

	it("NOTHING is dropped while any region in the failing lane can still step down", function()
		local decl = baseDecl({ arrangements = { ARRANGEMENTS[3] } })
		local res = resolve(360, 500, decl)
		for _, r in res.regions do
			expect(r.dropped).toBe(false)
		end
	end)

	it("only then are regions dropped, still in descending rank", function()
		local decl = baseDecl({ arrangements = { ARRANGEMENTS[3] } })
		-- one step past the last step-down: rank 9 goes, and NOTHING else does
		local first = resolve(360, 370, decl)
		local firstIds = mountedIds(first)
		expect(has(firstIds, "Tease")).toBe(false)
		expect(has(firstIds, "Bait")).toBe(true)
		-- tighter still: rank 8 follows it, and rank 7 and up survive
		local second = resolve(360, 340, decl)
		local secondIds = mountedIds(second)
		expect(has(secondIds, "Tease")).toBe(false)
		expect(has(secondIds, "Bait")).toBe(false)
		expect(has(secondIds, "Bogey")).toBe(true)
		expect(has(secondIds, "Sponsors")).toBe(true)
		expect(has(secondIds, "Ctas")).toBe(true)
		expect(has(secondIds, "Field")).toBe(true)
	end)

	it("a RANK TIE breaks by declaration order — the later-declared steps down first", function()
		local tie = baseDecl({
			arrangements = { ARRANGEMENTS[3] },
			regions = {
				{ id = "Ctas", group = "next", rank = 1, forms = 1, floor = { targets = 1 } },
				{ id = "Bait", group = "next", rank = 5, forms = 2 },
				{ id = "Tease", group = "next", rank = 5, forms = 2 },
			},
			groups = { { id = "next", lane = "trail", sizing = "hug", gap = 4 } },
		})
		local res = composition.resolve(tie, { w = 400, h = 130 }, ctx())
		expect(formOf(res, "Tease")).toBe(2)
		expect(formOf(res, "Bait")).toBe(1)
	end)

	it("a region with ONE form cannot step down, so rank 1 keeps its plate", function()
		local res = resolve(360, 370, baseDecl({ arrangements = { ARRANGEMENTS[3] } }))
		expect(res.regionById.Field.form).toBe(1)
		expect(res.regionById.Field.mounted).toBe(true)
	end)

	it("a step-down that cannot relieve the failure is not taken (it would only cheapen the screen)", function()
		-- the landscape offer fails on LANE WIDTH; only the regions that SET a hug
		-- lane's intrinsic width can narrow it, so the countdown and the bank chip
		-- (neither of which is the widest thing in its lane) keep their rich forms
		local res = resolve(733, 313)
		expect(formOf(res, "Ctas")).toBe(2) -- 340 -> 170: the trail lane's width
		expect(formOf(res, "Hero")).toBe(2) -- 200 -> 140: the lead lane's width
		expect(formOf(res, "Countdown")).toBe(1)
		expect(formOf(res, "BankChip")).toBe(1)
	end)

	it("a lane PINNED by a region that cannot narrow gives up nothing at all", function()
		-- The filter above asks "is this region AT the lane's intrinsic width",
		-- which is necessary and not sufficient. Here the lead lane's 200 px is
		-- set by a hero with ONE form that cannot be dropped, and the slot and the
		-- callout happen to measure the same 200: stepping or dropping either of
		-- them leaves the lane exactly as wide as it was, so the screen would be
		-- cheapened for nothing. The lane is pinned; only the trail lane (whose
		-- width the CTAs genuinely set) gives ground.
		local sizes = table.clone(SIZES)
		sizes.Hero = { { w = 200, h = 96 } } -- one form: the lane's own measure
		sizes.Bogey = { { w = 200, h = 40 }, { w = 200, h = 20 } } -- shorter, never narrower
		local decl = baseDecl()
		for _, r in decl.regions do
			if r.id == "Hero" then
				r.forms = 1
			end
		end
		local res = resolve(733, 313, decl, sizes)
		expect(res.arrangement).toBe("threeLane")
		expect(formOf(res, "Ctas")).toBe(2) -- the one region that CAN narrow its lane
		expect(formOf(res, "Slot")).toBe(1) -- pinned lane: the reserved slot keeps its full piece
		expect(formOf(res, "Bogey")).toBe(1)
		expect(has(mountedIds(res), "Bogey")).toBe(true) -- and is not dropped for nothing
	end)

	it("...but two regions that can BOTH give way still do, one at a time", function()
		-- the guard above must not cost the mechanism a real relief: when nothing
		-- immovable sits at the lane's width, tied regions still degrade in
		-- descending rank until the lane comes down
		local sizes = table.clone(SIZES)
		sizes.Hero = { { w = 200, h = 96 }, { w = 120, h = 26 } }
		sizes.Bogey = { { w = 200, h = 40 }, { w = 120, h = 20 } }
		sizes.Slot = { { w = 120, h = 76 }, { w = 120, h = 44 } }
		local res = resolve(620, 313, nil, sizes)
		expect(res.arrangement).toBe("threeLane")
		expect(formOf(res, "Bogey")).toBe(2) -- rank 7 gives way first...
		expect(formOf(res, "Hero")).toBe(2) -- ...then rank 3, and the lane comes down
	end)
end)

-- ===== floors ==============================================================

describe("ADR-0023: floors are content, and absolute", function()
	it("a `lines` floor resolves through the live theme's type role", function()
		local role = NEUTRAL.type.body
		expect(composition.floorPx({ lines = 1 }, NEUTRAL)).toBe(role.size * role.lineHeight)
		expect(composition.floorPx({ lines = 2 }, NEUTRAL)).toBe(2 * role.size * role.lineHeight)
	end)

	it("a `targets` floor resolves through the theme's minimum touch target", function()
		expect(composition.floorPx({ targets = 2 }, NEUTRAL)).toBe(2 * NEUTRAL.targetSizes.minimum)
	end)

	it("both stated takes the LARGER — a floor is a floor", function()
		local both = composition.floorPx({ lines = 1, targets = 2 }, NEUTRAL)
		expect(both).toBe(2 * NEUTRAL.targetSizes.minimum)
	end)

	it("a bigger type scale raises the floor by itself, with no author involvement", function()
		local big = themeSnapshot.resolve(themeSnapshot.neutralPackage(), nil, nil, { ["type.body.size"] = 28 })
		expect(composition.floorPx({ lines = 1 }, big) > composition.floorPx({ lines = 1 }, NEUTRAL)).toBe(true)
	end)

	it("no declared floor means the minimum-viable form's own measure", function()
		local decl = baseDecl({ arrangements = { ARRANGEMENTS[3] } })
		local res = resolve(360, 740, decl)
		-- Bogey declares no floor; its minimum form measures 20 tall
		expect(res.regionById.Bogey.floor).toBe(20)
	end)

	it("the FILL region never sinks below its floor — the lane is refused instead", function()
		-- a field floor of ten lines cannot fit a 200px column, and the field
		-- cannot be dropped, so every arrangement is illegal
		local decl = baseDecl({ arrangements = { ARRANGEMENTS[3] } })
		for _, r in decl.regions do
			if r.id == "Field" then
				r.floor = { lines = 10 }
			end
		end
		local res = composition.resolve(decl, { w = 360, h = 200 }, ctx())
		expect(res.fallback).toBe(true)
		expect(res.rejected[1].rule).toBe("overflow")
	end)
end)

-- ===== slack, reserved, empty ==============================================

describe("ADR-0023: slack flows to fill; reserved holds; empty is absent", function()
	it("every pixel left over goes to the fill region, on both axes", function()
		local res = resolve(1400, 900)
		local field = res.regionById.Field
		local lane = nil
		for _, l in res.lanes do
			if l.index == field.lane then
				lane = l
			end
		end
		-- the field lane took all the width the hug lanes did not
		local hug = 0
		for _, l in res.lanes do
			if l.index ~= field.lane then
				hug += l.rect.w
			end
		end
		expect((lane :: any).rect.w + hug + 2 * 12).toBe(1400)
		-- ...and the field itself took all the height its group did not need
		local head = res.regionById.FieldHead
		expect(field.rect.h + head.rect.h + 4).toBe(900)
	end)

	it("a reserved region holds its box when its content rests — neighbours do not move", function()
		local sizes = table.clone(SIZES)
		local resting = table.clone(SIZES)
		resting.Slot = { { w = 0, h = 0 }, { w = 0, h = 0 } } -- the transient finished
		local live = resolve(360, 740, baseDecl({ arrangements = { ARRANGEMENTS[3] } }), sizes)
		local rest = resolve(360, 740, baseDecl({ arrangements = { ARRANGEMENTS[3] } }), resting)
		-- the FLOOR is the reserved box: `targets = 2` (88px) covers the live
		-- piece (76px), so the box the transient occupied is the box that remains
		-- the slot is still mounted, still holding at least its floor
		expect(rest.regionById.Slot.mounted).toBe(true)
		expect(rest.regionById.Slot.rect.h >= rest.regionById.Slot.floor).toBe(true)
		-- and the region BELOW it in the same group has not moved up
		expect(rest.regionById.Bogey.rect.y).toBe(live.regionById.Bogey.rect.y)
	end)

	it("a reserved region is never dropped, however tight the offer", function()
		local res = resolve(300, 200)
		expect(res.regionById.Slot.dropped).toBe(false)
	end)

	it("a NON-reserved region whose content resolves to nothing is not mounted and costs no gap", function()
		local empty = table.clone(SIZES)
		empty.Bogey = { { w = 0, h = 0 }, { w = 0, h = 0 } }
		local decl = baseDecl({ arrangements = { ARRANGEMENTS[3] } })
		local withBogey = resolve(360, 900, decl, SIZES)
		local without = resolve(360, 900, decl, empty)
		expect(without.regionById.Bogey.mounted).toBe(false)
		-- the ceremony group shrank by the bogey line AND its gap, so the field
		-- (the one growing region) is exactly that much taller: no dead band
		expect(without.regionById.Field.rect.h - withBogey.regionById.Field.rect.h).toBe(40 + 6)
	end)

	it("maxMeasure caps both axes and centres the result", function()
		local decl = baseDecl({ maxMeasure = 900 })
		local res = composition.resolve(decl, { w = 1400, h = 900 }, ctx())
		expect(res.offer.w).toBe(900)
		expect(res.origin.x).toBe(250)
		expect(res.origin.y).toBe(0)
	end)
end)

-- ===== rule 9: empty-lane release (DV6-2) ==================================
-- A lane whose every region resolves to nothing paintable COLLAPSES: no width,
-- no lane gap, and what it would have held goes to the `fill` lanes. The
-- commissioning case is a quiet sponsor round — hero suppressed, callout absent,
-- celebration schedule finished — which spent 240 px of an 852-wide landscape
-- phone on an empty left column because the ONE reserved region in that lane was
-- pinned `reserved = true` and could therefore never be empty.

local RELEASE_SIZES: { [string]: { { w: number, h: number } } } = {
	Lead = { { w = 120, h = 40 } },
	Second = { { w = 90, h = 30 } },
	Main = { { w = 200, h = 40 } },
	Trail = { { w = 100, h = 40 } },
}
local EMPTY_FORM = { { w = 0, h = 0 } }

-- lead lane: `Lead` (optionally a reserved slot) + `Second`; main fills; trail hugs
local function releaseDecl(lead: any, second: any?): any
	local regions: { any } = {
		{ id = "Lead", group = "ceremony", rank = 3, forms = 1 },
		{ id = "Main", group = "field", rank = 1, forms = 1, sizing = "fill", floor = { lines = 1 } },
		{ id = "Trail", group = "next", rank = 2, forms = 1 },
	}
	for k, v in lead or {} do
		regions[1][k] = v
	end
	if second ~= nil then
		local r: any = { id = "Second", group = "ceremony", rank = 4, forms = 1 }
		for k, v in second do
			r[k] = v
		end
		table.insert(regions, 2, r)
	end
	return {
		id = "Release",
		laneGap = 10,
		groupGap = 8,
		arrangements = { { name = "threeLane", lanes = { { "lead" }, { "main" }, { "trail" } } } },
		groups = {
			{ id = "ceremony", lane = "lead", sizing = "hug", gap = 6 },
			{ id = "field", lane = "main", sizing = "fill", weight = 1, minWidth = 240 },
			{ id = "next", lane = "trail", sizing = "hug" },
		},
		regions = regions,
	}
end

local function laneAt(res: any, index: number): any
	for _, lane in res.lanes do
		if lane.index == index then
			return lane
		end
	end
	return nil
end
local function releaseSizes(overrides: { [string]: any }?): any
	local sizes = table.clone(RELEASE_SIZES)
	for id, forms in overrides or {} do
		sizes[id] = forms
	end
	return sizes
end

describe("ADR-0023 rule 9 (DV6-2): an all-empty lane COLLAPSES and gives up its width", function()
	--[[ THE MATRIX. A lane's regions can resolve to nothing in three ways, and the
		rule has to be indifferent to which: measured EMPTY, DROPPED by rule 3, or a
		reserved region whose schedule is over (`reserved` reading false). Anything
		still paintable — including a reserved region that is still ACTIVE — keeps
		the lane, byte for byte as before. ]]
	local CASES: { { name: string, lead: any, second: any?, sizes: any, collapsed: boolean } } = {
		{
			name = "measured empty",
			lead = {},
			sizes = releaseSizes({ Lead = EMPTY_FORM }),
			collapsed = true,
		},
		{
			name = "dropped by rule 3",
			lead = { mayDrop = true },
			sizes = releaseSizes(),
			collapsed = true,
		},
		{
			name = "reserved, schedule OVER (the quiet round)",
			lead = { reserved = false, floor = { targets = 1 } },
			sizes = releaseSizes({ Lead = EMPTY_FORM }),
			collapsed = true,
		},
		{
			name = "reserved, schedule RUNNING — unchanged",
			lead = { reserved = true, floor = { targets = 1 } },
			sizes = releaseSizes({ Lead = EMPTY_FORM }),
			collapsed = false,
		},
		{
			name = "one region still paintable beside an empty one",
			lead = {},
			second = {},
			sizes = releaseSizes({ Lead = EMPTY_FORM }),
			collapsed = false,
		},
		{
			name = "empty + dropped + released-reserve together",
			lead = { reserved = false, floor = { targets = 1 } },
			second = { mayDrop = true },
			sizes = releaseSizes({ Lead = EMPTY_FORM, Second = EMPTY_FORM }),
			collapsed = true,
		},
	}
	for _, case in CASES do
		it(`{case.name} -> collapsed={case.collapsed}`, function()
			-- 400 px: hugs 120 + 100 + two 10 px gaps leaves the fill lane 160, under
			-- its 240 minimum, so the `mayDrop` row is asked to give the lane up
			local res = composition.resolve(releaseDecl(case.lead, case.second), { w = 400, h = 300 }, ctx(case.sizes))
			local lane = laneAt(res, 1)
			expect(`{case.name}:reported={lane ~= nil}`).toBe(`{case.name}:reported=true`)
			expect(`{case.name}:collapsed={lane.collapsed}`).toBe(`{case.name}:collapsed={case.collapsed}`)
			expect(`{case.name}:groups={#lane.groups == 0}`).toBe(`{case.name}:groups={case.collapsed}`)
			-- a collapsed lane is not merely narrow: it is OUT OF THE FLOW, so the
			-- lane after it starts at 0 and pays no gap for it. A lane that is
			-- merely zero-wide (an active reserve holding only a floor HEIGHT) still
			-- costs its neighbour the lane gap, which is the difference the flag is
			-- for.
			expect(`{case.name}:mainX={laneAt(res, 2).rect.x}`).toBe(
				`{case.name}:mainX={if case.collapsed then 0 else laneAt(res, 1).rect.w + 10}`
			)
		end)
	end

	it("the released width AND its lane gap go to the fill lane, to the pixel", function()
		-- live: 400 − 120 (lead) − 100 (trail) − 2×10 (gaps) = 160 for the field
		local live = composition.resolve(releaseDecl({}), { w = 400, h = 300 }, ctx(releaseSizes()))
		expect(laneAt(live, 1).rect.w).toBe(120)
		expect(laneAt(live, 2).rect.w).toBe(160)
		-- quiet: the lead lane is gone, and so is ONE gap — 400 − 100 − 10 = 290
		local quiet = composition.resolve(
			releaseDecl({ reserved = false, floor = { targets = 1 } }),
			{ w = 400, h = 300 },
			ctx(releaseSizes({ Lead = EMPTY_FORM }))
		)
		expect(laneAt(quiet, 1).rect.w).toBe(0)
		expect(laneAt(quiet, 2).rect.w).toBe(290)
		expect(laneAt(quiet, 2).rect.w - laneAt(live, 2).rect.w).toBe(120 + 10)
		-- the trail lane did NOT move up: only `fill` takes the release (rule 6)
		expect(laneAt(quiet, 3).rect.w).toBe(100)
		-- ...and the collapsed lane is reported at the x it would have started at
		expect(laneAt(quiet, 1).rect.x).toBe(0)
		expect(laneAt(quiet, 2).rect.x).toBe(0)
	end)

	it("with NO fill lane the release is simply not spent — the composition measures narrower", function()
		local decl = releaseDecl({ reserved = false, floor = { targets = 1 } })
		decl.groups[2].sizing = "hug"
		decl.groups[2].minWidth = nil
		decl.regions[2].sizing = "hug"
		local quiet = composition.resolve(decl, { w = 400, h = 300 }, ctx(releaseSizes({ Lead = EMPTY_FORM })))
		expect(laneAt(quiet, 1).collapsed).toBe(true)
		expect(quiet.used.w).toBe(200 + 10 + 100)
	end)

	it("MID-SEQUENCE STABILITY survives the release: an ACTIVE reserve holds its box between pieces", function()
		--[[ Rule 7 is scoped, not withdrawn. While the schedule can still produce a
			piece the box is held at its floor even though the content measures
			nothing, so the region under it does not move when one piece ends and the
			next has not begun. ]]
		local live = composition.resolve(
			releaseDecl({ reserved = true, floor = { targets = 1 } }, {}),
			{ w = 700, h = 300 },
			ctx(releaseSizes())
		)
		local between = composition.resolve(
			releaseDecl({ reserved = true, floor = { targets = 1 } }, {}),
			{ w = 700, h = 300 },
			ctx(releaseSizes({ Lead = EMPTY_FORM }))
		)
		expect(between.regionById.Lead.mounted).toBe(true)
		expect(between.regionById.Lead.rect.h >= between.regionById.Lead.floor).toBe(true)
		expect(between.regionById.Second.rect.y).toBe(live.regionById.Second.rect.y)
		expect(laneAt(between, 1).collapsed).toBe(false)
		-- ...and once the schedule is OVER the same box is released with its lane
		local after = composition.resolve(
			releaseDecl({ reserved = false, floor = { targets = 1 } }),
			{ w = 700, h = 300 },
			ctx(releaseSizes({ Lead = EMPTY_FORM }))
		)
		expect(after.regionById.Lead.mounted).toBe(false)
		expect(laneAt(after, 1).collapsed).toBe(true)
	end)

	it("the dump carries `collapsed`, and every lane a reader already saw is unchanged", function()
		local quiet = composition.dump(
			composition.resolve(
				releaseDecl({ reserved = false, floor = { targets = 1 } }),
				{ w = 400, h = 300 },
				ctx(releaseSizes({ Lead = EMPTY_FORM }))
			)
		)
		expect(quiet.schema).toBe("luauui-composition-dump/1")
		local pinned = ""
		for _, lane in quiet.lanes do
			pinned ..= `{lane.index}|{lane.affinities}|{lane.groups}|{lane.rect.x},{lane.rect.w}|{tostring(
				lane.collapsed
			)}\n`
		end
		expect(pinned).toBe(table.concat({
			"1|lead||0,0|true",
			"2|main|field|0,290|false",
			"3|trail|next|300,100|false",
			"",
		}, "\n"))
		-- THE ADDITIVITY PIN: a declaration whose lanes all carry content dumps
		-- exactly what it dumped before rule 9 existed, `collapsed = false` apart
		local plain = composition.dump(resolve(733, 313))
		expect(#plain.lanes).toBe(3)
		for _, lane in plain.lanes do
			expect(`{lane.index}:{tostring(lane.collapsed)}`).toBe(`{lane.index}:false`)
		end
		expect(`{plain.lanes[1].rect.w}|{plain.lanes[2].rect.w}|{plain.lanes[3].rect.w}`).toBe("170|359|180")
	end)

	it("releasing the FLAG is not enough: a form that paints unconditionally is never empty", function()
		--[[ The other half of the same fact, and the game-side root cause the rule
			was commissioned for: RascalRally's celebration slot painted a fixed
			laneW x CELEB_H box whether or not any piece was up, so the lane held its
			width no matter what `reserved` said. The release is a property of what the
			region MEASURES; the flag only decides whether measuring nothing is allowed
			to mean nothing. ]]
		local paints = composition.resolve(
			releaseDecl({ reserved = false, floor = { targets = 1 } }),
			{ w = 400, h = 300 },
			ctx(releaseSizes()) -- the form still measures its 120x40 plate at rest
		)
		expect(laneAt(paints, 1).collapsed).toBe(false)
		expect(laneAt(paints, 1).rect.w).toBe(120)
	end)

	it("a `reserved` that is not a boolean is refused where it is written", function()
		local decl = releaseDecl({ reserved = { kind = "signal" }, floor = { targets = 1 } })
		local ok, err = pcall(function()
			composition.normalize(decl)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "reserved must be a boolean", 1, true) ~= nil).toBe(true)
	end)
end)

-- ===== spanning rows (DV5-1: the one contract gap ADR-0023 flagged) ========
-- A group declares `span = "above" | "below"` INSTEAD of a lane affinity, and is
-- its own full-width row in that position in EVERY arrangement. Everything else
-- about it is a group: its regions stack, they step down and drop by rank, and
-- an empty one costs nothing.

local SPAN_SIZES: { [string]: { { w: number, h: number } } } = (function()
	local sizes = table.clone(SIZES)
	sizes.Recap = { { w = 300, h = 40 }, { w = 300, h = 20 } }
	return sizes
end)()

local function spanDecl(overrides: { [string]: any }?): any
	local decl = baseDecl(overrides)
	local groups = table.clone(decl.groups)
	table.insert(groups, 1, { id = "caption", span = "above", gap = 4 })
	local regions = table.clone(decl.regions)
	table.insert(regions, { id = "Recap", group = "caption", rank = 5, forms = 2, floor = { lines = 1 } })
	decl.groups = groups
	decl.regions = regions
	return decl
end

describe("ADR-0023 (2026-07-31): a group may SPAN the composition as its own row", function()
	it("the spanning row is full width, above the lanes, in EVERY arrangement", function()
		for _, offer in
			{ { w = 733, h = 313, arrangement = "threeLane" }, { w = 360, h = 900, arrangement = "column" } }
		do
			local res = composition.resolve(spanDecl(), { w = offer.w, h = offer.h }, ctx(SPAN_SIZES))
			expect(`{offer.arrangement}:arrangement={res.arrangement}`).toBe(
				`{offer.arrangement}:arrangement={offer.arrangement}`
			)
			expect(#res.spans).toBe(1)
			local row = res.spans[1]
			expect(`{offer.arrangement}:side={row.side}`).toBe(`{offer.arrangement}:side=above`)
			expect(`{offer.arrangement}:full={row.rect.w == offer.w}`).toBe(`{offer.arrangement}:full=true`)
			expect(`{offer.arrangement}:top={row.rect.y}`).toBe(`{offer.arrangement}:top=0`)
			-- ...and every lane starts BELOW it, by the row plus the group gap
			for _, lane in res.lanes do
				expect(`{offer.arrangement}:laneY={lane.rect.y}`).toBe(
					`{offer.arrangement}:laneY={row.rect.h + (spanDecl().groupGap or 0)}`
				)
			end
			-- the region rides the row, not a lane
			local recap = res.regionById.Recap
			expect(`{offer.arrangement}:span={tostring(recap.span)}`).toBe(`{offer.arrangement}:span=above`)
			expect(`{offer.arrangement}:lane={tostring(recap.lane)}`).toBe(`{offer.arrangement}:lane=nil`)
			expect(`{offer.arrangement}:rectW={recap.rect.w}`).toBe(`{offer.arrangement}:rectW={offer.w}`)
		end
	end)

	it("a `below` row closes the flow, under the lane band", function()
		local decl = spanDecl()
		decl.groups[1] = { id = "caption", span = "below", gap = 4 }
		local res = composition.resolve(decl, { w = 733, h = 313 }, ctx(SPAN_SIZES))
		local row = res.spans[1]
		expect(row.side).toBe("below")
		for _, lane in res.lanes do
			expect(lane.rect.y).toBe(0)
			expect(lane.rect.y + lane.rect.h <= row.rect.y).toBe(true)
		end
		expect(row.rect.y + row.rect.h).toBe(313)
	end)

	it("the row takes its height from the LANES' budget — it is not a free band", function()
		local plain = resolve(733, 313)
		local spanned = composition.resolve(spanDecl(), { w = 733, h = 313 }, ctx(SPAN_SIZES))
		local rowH = spanned.spans[1].rect.h
		expect(rowH).toBe(40)
		-- the field is the one region that grows, so the whole cost lands there:
		-- the row plus one group gap, and not a pixel more
		expect(plain.regionById.Field.rect.h - spanned.regionById.Field.rect.h).toBe(rowH + 8)
		for _, lane in spanned.lanes do
			expect(lane.rect.y + lane.rect.h <= 313).toBe(true)
		end
	end)

	it("an EMPTY spanning row is absent, and the lanes get every pixel back", function()
		local empty = table.clone(SPAN_SIZES)
		empty.Recap = { { w = 0, h = 0 }, { w = 0, h = 0 } }
		local without = composition.resolve(spanDecl(), { w = 733, h = 313 }, ctx(empty))
		local plain = resolve(733, 313)
		expect(#without.spans).toBe(0)
		expect(without.regionById.Recap.mounted).toBe(false)
		expect(without.regionById.Field.rect.h).toBe(plain.regionById.Field.rect.h)
		for _, lane in without.lanes do
			expect(lane.rect.y).toBe(0)
		end
	end)

	it("a spanning region steps down and drops by RANK, like any other", function()
		-- 250px of height cannot hold the two-line caption plus the column's own
		-- content, and the caption is rank 5 — so it steps to its one-line form
		local decl = spanDecl({ arrangements = { ARRANGEMENTS[3] } })
		local res = composition.resolve(decl, { w = 360, h = 250 }, ctx(SPAN_SIZES))
		expect(res.regionById.Recap.form).toBe(2)
		expect(res.spans[1].rect.h).toBe(20)
		-- ...and the CTAs (rank 1) never moved to pay for it
		expect(res.regionById.Ctas.dropped).toBe(false)
		-- a droppable spanning region does leave when stepping down is not enough
		local droppable = spanDecl({ arrangements = { ARRANGEMENTS[3] } })
		droppable.regions[#droppable.regions].mayDrop = true
		droppable.regions[#droppable.regions].rank = 10
		local tight = composition.resolve(droppable, { w = 360, h = 180 }, ctx(SPAN_SIZES))
		expect(tight.regionById.Recap.dropped).toBe(true)
		expect(#tight.spans).toBe(0)
	end)

	it("a spanning row never narrows a lane, so a WIDTH failure never degrades it", function()
		-- 300px is too narrow for the three lanes; the caption is full-width by
		-- definition and cannot buy the hug lanes a pixel, so it keeps its richest
		-- form while the arrangement is rejected on the lane width
		local decl = spanDecl({ arrangements = { ARRANGEMENTS[1], ARRANGEMENTS[3] } })
		local res = composition.resolve(decl, { w = 300, h = 900 }, ctx(SPAN_SIZES))
		expect(res.arrangement).toBe("column")
		expect(res.rejected[1].rule).toBe("laneWidth")
		expect(res.regionById.Recap.form).toBe(1)
	end)

	it("a hug-width composition still MEASURES its content, not the offer it spans", function()
		-- the row PAINTS the full width; if it also REPORTED it, a composition
		-- inside an unbounded axis (a scroll canvas) would claim the whole box —
		-- the same lie the uniform Grid cell used to tell. So: no fill group, a
		-- huge offer, and `used.w` is still the widest thing anybody measured.
		local hug = {
			id = "H",
			laneGap = 12,
			groupGap = 8,
			arrangements = { { name = "one", lanes = { { "main" } } } },
			groups = { { id = "caption", span = "above", gap = 4 }, { id = "body", lane = "main", sizing = "hug" } },
			regions = {
				{ id = "Recap", group = "caption", rank = 5, forms = 2, floor = { lines = 1 } },
				{ id = "Bogey", group = "body", rank = 7, forms = 2 },
			},
		}
		local res = composition.resolve(hug, { w = 4000, h = 900 }, ctx(SPAN_SIZES))
		expect(res.spans[1].rect.w).toBe(4000) -- painted full width
		expect(res.used.w).toBe(300) -- ...measured at the caption's own 300
	end)

	it("the dump carries the row, and a declaration WITHOUT one is byte-unchanged", function()
		local spanned = composition.dump(composition.resolve(spanDecl(), { w = 733, h = 313 }, ctx(SPAN_SIZES)))
		expect(spanned.schema).toBe("luauui-composition-dump/1")
		expect(#spanned.spans).toBe(1)
		expect(spanned.spans[1].id).toBe("caption")
		expect(spanned.spans[1].side).toBe("above")
		for _, r in spanned.regions do
			if r.id == "Recap" then
				expect(r.span).toBe("above")
			else
				expect(r.span).toBe(nil)
			end
		end
		-- THE ADDITIVITY PIN: the pre-span declaration resolves to exactly the same
		-- arrangement, forms, rects and rejections it did before spans existed
		local plain = composition.dump(resolve(733, 313))
		expect(#plain.spans).toBe(0)
		expect(plain.arrangement).toBe("threeLane")
		local pinned = ""
		for _, r in plain.regions do
			pinned ..= `{r.id}|{r.form}|{tostring(r.mounted)}|{tostring(r.lane)}|{if r.rect ~= nil
				then `{r.rect.x},{r.rect.y},{r.rect.w},{r.rect.h}`
				else "-"}\n`
		end
		expect(pinned).toBe(table.concat({
			"Countdown|1|true|1|0,0,170,20",
			"BankChip|1|true|1|0,24,170,24",
			"Hero|2|true|1|0,130,170,26",
			"Slot|2|true|1|0,162,170,88",
			"Bogey|2|true|1|0,256,170,20",
			"FieldHead|1|true|2|182,0,359,40",
			"Field|1|true|2|182,44,359,269",
			"Sponsors|1|true|3|553,27,180,70",
			"Bait|1|true|3|553,101,180,40",
			"Tease|1|true|3|553,145,180,40",
			"Ctas|2|true|3|553,189,180,110",
			"",
		}, "\n"))
	end)

	it("a declaration that both rides a lane and spans is refused where it is written", function()
		local function refusesSpan(mutate: (any) -> (), fragment: string)
			local decl = spanDecl()
			mutate(decl)
			local ok, err = pcall(function()
				composition.normalize(decl)
			end)
			expect(ok).toBe(false)
			expect(`{fragment}:{string.find(tostring(err), fragment, 1, true) ~= nil}`).toBe(`{fragment}:true`)
		end
		refusesSpan(function(d)
			d.groups[1].lane = "lead"
		end, "declares BOTH lane")
		refusesSpan(function(d)
			d.groups[1].span = "middle"
		end, 'span must be "above" or "below"')
		refusesSpan(function(d)
			d.groups[1].minWidth = 200
		end, "'minWidth' means nothing to it")
		refusesSpan(function(d)
			d.groups[1].place = "center"
		end, "'place' means nothing to it")
		refusesSpan(function(d)
			d.groups[1].sizing = "fill"
		end, "'sizing' means nothing to it")
		refusesSpan(function(d)
			d.groups[1].span = nil
		end, "needs a lane affinity")
	end)

	it("a spanning group needs NO home in any arrangement — that is the point", function()
		-- the same declaration under three arrangements none of which names
		-- `caption`: it is not in the lane vocabulary at all, so it can never be
		-- the group that vanishes on one device
		local decl = spanDecl()
		local ok = pcall(function()
			composition.normalize(decl)
		end)
		expect(ok).toBe(true)
		for _, arr in ARRANGEMENTS do
			local res = composition.resolve(spanDecl({ arrangements = { arr } }), { w = 900, h = 700 }, ctx(SPAN_SIZES))
			expect(`{arr.name}:mounted={res.regionById.Recap.mounted}`).toBe(`{arr.name}:mounted=true`)
			expect(`{arr.name}:span={tostring(res.regionById.Recap.span)}`).toBe(`{arr.name}:span=above`)
		end
	end)
end)

-- ===== exactly one scroll ==================================================

describe("ADR-0023: exactly one scroll region", function()
	it("a second mayScroll region is refused at DECLARATION, not resolved around", function()
		local decl = baseDecl()
		table.insert(decl.regions, { id = "Second", group = "next", rank = 9, forms = 1, mayScroll = true })
		local ok, err = pcall(function()
			composition.normalize(decl)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "EXACTLY ONE", 1, true) ~= nil).toBe(true)
	end)

	it("the resolution names the one scroller when it is mounted", function()
		expect(resolve(733, 313).scroller).toBe("Field")
	end)

	it("a lane that overflows with no scroller in it makes the arrangement illegal", function()
		-- the trail lane holds no scrollable region: it must fit by stepping down
		-- and dropping, or the arrangement loses
		local decl = baseDecl({
			arrangements = { { name = "onlyTrail", lanes = { { "head", "lead", "main", "trail" } } } },
			groups = { { id = "next", lane = "trail", sizing = "hug", gap = 4 } },
			regions = {
				{ id = "Ctas", group = "next", rank = 1, forms = 1, floor = { targets = 2 } },
				{ id = "Sponsors", group = "next", rank = 6, forms = 1 },
			},
		})
		local res = composition.resolve(decl, { w = 400, h = 40 }, ctx())
		expect(res.fallback).toBe(true)
		expect(res.rejected[1].rule).toBe("overflow")
	end)
end)

-- ===== declaration refusals ================================================

describe("ADR-0023: a bad declaration is refused where it is written", function()
	local function refuses(mutate: (any) -> (), fragment: string)
		local decl = baseDecl()
		mutate(decl)
		local ok, err = pcall(function()
			composition.normalize(decl)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), fragment, 1, true) ~= nil).toBe(true)
	end

	it("an unknown region field", function()
		refuses(function(d)
			d.regions[1].mayShrink = true
		end, "does not accept 'mayShrink'")
	end)

	it("an unknown group field", function()
		refuses(function(d)
			d.groups[1].align = "center"
		end, "does not accept 'align'")
	end)

	it("an unknown floor key", function()
		refuses(function(d)
			d.regions[1].floor = { px = 30 }
		end, "does not accept 'px'")
	end)

	it("a floor that is a pixel count in disguise", function()
		refuses(function(d)
			d.regions[1].floor = {}
		end, "floor must state lines or targets")
	end)

	it("a region naming a group that does not exist", function()
		refuses(function(d)
			d.regions[1].group = "nowhere"
		end, "which is not declared")
	end)

	it("a duplicate region id", function()
		refuses(function(d)
			table.insert(d.regions, { id = "Ctas", group = "next", rank = 9, forms = 1 })
		end, "share the id")
	end)

	it("a non-integer rank", function()
		refuses(function(d)
			d.regions[1].rank = 1.5
		end, "integer rank")
	end)

	it("a region with no forms", function()
		refuses(function(d)
			d.regions[1].forms = 0
		end, "at least one form")
	end)

	it("reserved AND mayDrop together", function()
		refuses(function(d)
			d.regions[4].mayDrop = true
		end, "reserved")
	end)

	it("an unknown arrangement name", function()
		refuses(function(d)
			d.arrangements = { "fourLane" }
		end, "unknown arrangement 'fourLane'")
	end)

	it("a group with no home in some arrangement — the silent-disappearance case", function()
		refuses(function(d)
			d.arrangements = { { name = "partial", lanes = { { "lead" }, { "main" } } } }
		end, "has no lane for affinity")
	end)

	it("a custom arrangement with no lanes", function()
		refuses(function(d)
			d.arrangements = { { name = "empty", lanes = {} } }
		end, "at least one lane")
	end)
end)

-- ===== determinism + the dump ==============================================

describe("ADR-0023: the resolution is deterministic and dumpable", function()
	it("two resolutions of the same offer are byte-identical dumps", function()
		local a = composition.dump(resolve(733, 313))
		local b = composition.dump(resolve(733, 313))
		expect(a.arrangement).toBe(b.arrangement)
		expect(#a.regions).toBe(#b.regions)
		for i, r in a.regions do
			expect(r.id).toBe(b.regions[i].id)
			expect(r.form).toBe(b.regions[i].form)
			expect(r.rect.y).toBe(b.regions[i].rect.y)
		end
	end)

	it("the dump carries WHICH arrangement, WHICH form, and WHY each loser lost", function()
		local d = composition.dump(resolve(360, 570))
		expect(d.schema).toBe("luauui-composition-dump/1")
		expect(d.arrangement).toBe("column")
		expect(d.scroller).toBe("Field")
		expect(#d.rejected).toBe(2)
		expect(d.rejected[1].rule).toBe("laneWidth")
		expect(#d.rejected[1].detail > 0).toBe(true)
		local byId: { [string]: any } = {}
		for _, r in d.regions do
			byId[r.id] = r
		end
		expect(byId.Tease.form).toBe(2)
		expect(byId.Field.rect.h > 0).toBe(true)
	end)

	it("regions appear in DECLARATION order, whatever the arrangement", function()
		local wide = composition.dump(resolve(1400, 900))
		local tall = composition.dump(resolve(360, 740))
		for i, r in wide.regions do
			expect(r.id).toBe(tall.regions[i].id)
		end
	end)
end)

-- ===== mounted: rects, hidden, and re-solve identity =======================

local function screenWith(core: any, tallForm: boolean?)
	local function box(id: string, w: number, h: number)
		return UI.Box({ id = id, width = { type = "fixed", px = w }, height = { type = "fixed", px = h } })
	end
	return UI.Screen({
		id = "S",
		width = { type = "fill", weight = 1 },
		height = { type = "fill", weight = 1 },
		children = {
			UI.Composition({
				id = "C",
				arrangements = { "threeLane", "column" },
				laneGap = 12,
				groupGap = 8,
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				groups = {
					{ id = "ceremony", lane = "lead", sizing = "hug", place = "center" },
					{ id = "field", lane = "main", sizing = "fill", minWidth = 240 },
					{ id = "next", lane = "trail", sizing = "hug", place = "end" },
				},
				children = {
					UI.Region({
						id = "Hero",
						group = "ceremony",
						rank = 3,
						children = { box("HeroFull", 200, 96), box("HeroChip", 120, 26) },
					}),
					UI.Region({
						id = "Field",
						group = "field",
						rank = 2,
						sizing = "fill",
						mayScroll = true,
						floor = { lines = 1 },
						children = { box("FieldBody", 260, if tallForm then 900 else 300) },
					}),
					UI.Region({
						id = "Ctas",
						group = "next",
						rank = 1,
						floor = { targets = 2 },
						children = { box("CtaRow", 300, 52), box("CtaCol", 150, 110) },
					}),
					UI.Region({
						id = "Tease",
						group = "next",
						rank = 9,
						mayDrop = true,
						children = { box("TeaseLine", 150, 40) },
					}),
				},
			}),
		},
	})
end

local function mounted(w: number, h: number)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
	local root = mountLib.mount(core, screenWith(core))
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return core, env, root, adapter, controller
end

describe("ADR-0023: UI.Composition, mounted", function()
	it("places the lanes side by side on a short wide offer", function()
		local _, _, _, adapter = mounted(900, 320)
		local hero = adapter.node("/S/C/Hero/HeroFull").rect
		local field = adapter.node("/S/C/Field/FieldBody").rect
		local cta = adapter.node("/S/C/Ctas/CtaRow").rect
		expect(hero.x < field.x).toBe(true)
		expect(field.x < cta.x).toBe(true)
		-- three lanes across the width, one band of height
		expect(hero.y > 0).toBe(true)
	end)

	it("stacks them down a tall narrow offer, same tree", function()
		local _, _, _, adapter = mounted(360, 900)
		local hero = adapter.node("/S/C/Hero/HeroFull").rect
		local field = adapter.node("/S/C/Field/FieldBody").rect
		local cta = adapter.node("/S/C/Ctas/CtaRow").rect
		expect(hero.x).toBe(field.x)
		expect(hero.y < field.y).toBe(true)
		expect(field.y < cta.y).toBe(true)
	end)

	it("the losing form keeps its mount, gets a zero rect, and is marked hidden", function()
		local _, _, _, adapter, controller = mounted(360, 900)
		-- the rich CTA row fits a 360px column; its column candidate is the loser
		expect(adapter.node("/S/C/Ctas/CtaCol").rect.w).toBe(0)
		expect(controller.hiddenRoots()["/S/C/Ctas/CtaCol"]).toBe(true)
		expect(controller.hiddenRoots()["/S/C/Ctas/CtaRow"]).toBe(nil)
	end)

	it("a dropped region's whole subtree leaves the focus ring", function()
		-- 140px cannot hold the stepped-down hero + the field floor + CTAs + tease
		local _, _, _, adapter, controller = mounted(360, 140)
		expect(controller.hiddenRoots()["/S/C/Tease"]).toBe(true)
		expect(adapter.node("/S/C/Tease").rect.w).toBe(0)
	end)

	it("the resolution is readable from the controller, with the losing candidate's rule", function()
		local _, _, _, _, controller = mounted(360, 900)
		local d = controller.compositionAt("/S/C")
		expect(d.schema).toBe("luauui-composition-dump/1")
		expect(d.arrangement).toBe("column")
		expect(d.rejected[1].arrangement).toBe("threeLane")
		expect(d.rejected[1].rule).toBe("laneWidth")
		-- and the whole set is reachable without knowing the path
		expect(controller.compositionAt()["/S/C"].arrangement).toBe("column")
	end)

	it("an AXIS FLIP re-solves in place: zero factory reruns, zero creates, zero removes", function()
		local _, env, root, adapter, controller = mounted(900, 320)
		expect(controller.compositionAt("/S/C").arrangement).toBe("threeLane")
		local factoryRuns = root.counters().factoryRuns
		local mountedCount = root.counters().mounted
		local creates = controller.stats().creates

		env:set("viewportRect", { x = 0, y = 0, w = 320, h = 900 })
		controller.refresh()

		-- the arrangement actually changed...
		expect(controller.compositionAt("/S/C").arrangement).toBe("column")
		expect(adapter.node("/S/C/Hero/HeroFull").rect.x).toBe(adapter.node("/S/C/Field/FieldBody").rect.x)
		-- ...and nothing was rebuilt. This is the whole promise: a rotation keeps
		-- scroll offsets, focus and in-flight transitions because no node moved.
		expect(root.counters().factoryRuns).toBe(factoryRuns)
		expect(root.counters().mounted).toBe(mountedCount)
		expect(controller.stats().creates).toBe(creates)
		expect(controller.stats().removes).toBe(0)
	end)

	it("a region that dropped and comes back keeps its identity", function()
		local _, env, root, _, controller = mounted(360, 900)
		local creates = controller.stats().creates
		env:set("viewportRect", { x = 0, y = 0, w = 360, h = 140 })
		controller.refresh()
		expect(controller.hiddenRoots()["/S/C/Tease"]).toBe(true)
		env:set("viewportRect", { x = 0, y = 0, w = 360, h = 900 })
		controller.refresh()
		expect(controller.hiddenRoots()["/S/C/Tease"]).toBe(nil)
		expect(controller.stats().creates).toBe(creates)
		expect(controller.stats().removes).toBe(0)
		expect(root.counters().factoryRuns).toBe(root.counters().factoryRuns)
	end)

	it("DV6-2: a live `reserved` releases the whole lane, as a RE-SOLVE not a rebuild", function()
		--[[ The commissioning case, end to end: a ceremony lane holding one reserved
			slot whose form paints a fixed box while its schedule runs. While `active`
			reads true the box holds and the lane is a column; the moment the schedule
			is over the region is empty like any other, rule 9 collapses the lane, and
			the field gets the width — without one node being rebuilt. ]]
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 860, h = 400 })
		-- TWO facts, because the real surface has two: `piece` is whether anything
		-- occupies the slot RIGHT NOW, `active` is whether the schedule can still
		-- produce one. Between two pieces the first is false and the second is true,
		-- and that gap is exactly what rule 7 exists to hold still.
		local piece = core:signal(true)
		local active = core:signal(true)
		local function box(id: string, w: number, h: number)
			return UI.Box({ id = id, width = { type = "fixed", px = w }, height = { type = "fixed", px = h } })
		end
		local bp = UI.Screen({
			id = "S",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			children = {
				UI.Composition({
					id = "C",
					arrangements = { "threeLane" },
					laneGap = 12,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					groups = {
						{ id = "ceremony", lane = "lead", sizing = "hug" },
						{ id = "field", lane = "main", sizing = "fill", minWidth = 240 },
						{ id = "next", lane = "trail", sizing = "hug" },
					},
					children = {
						UI.Region({
							id = "Slot",
							group = "ceremony",
							rank = 3,
							reserved = active,
							floor = { targets = 1 },
							-- THE FORM ITSELF HAS TO BE ABLE TO MEASURE NOTHING. A fixed box
							-- painted unconditionally is never empty however the flag reads,
							-- so the reserve gates the BOX and the flag gates the reserve —
							-- the two halves of one fact (see the pure case above).
							children = {
								UI.When({
									id = "Piece",
									condition = piece,
									thenView = function()
										return UI.ZStack({
											id = "SlotBox",
											width = { type = "fixed", px = 200 },
											height = { type = "fixed", px = 76 },
											children = { box("PieceBox", 200, 76) },
										})
									end,
								}),
							},
						}),
						UI.Region({
							id = "Field",
							group = "field",
							rank = 1,
							sizing = "fill",
							mayScroll = true,
							floor = { lines = 1 },
							children = { box("FieldBody", 260, 300) },
						}),
						UI.Region({
							id = "Ctas",
							group = "next",
							rank = 2,
							floor = { targets = 2 },
							children = { box("CtaRow", 180, 52) },
						}),
					},
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()

		local live = controller.compositionAt("/S/C")
		expect(live.lanes[1].collapsed).toBe(false)
		expect(live.lanes[1].rect.w).toBe(200)
		local fieldLive = live.lanes[2].rect.w
		local ctaX = adapter.node("/S/C/Ctas/CtaRow").rect.x

		-- ONE: the piece ends, the schedule has not. Rule 7: the box is held at its
		-- floor and NOTHING beside it moves — no reflow under a thumb.
		piece:set(false)
		controller.refresh()
		local between = controller.compositionAt("/S/C")
		expect(between.lanes[1].collapsed).toBe(false)
		expect(between.regions[1].mounted).toBe(true)
		expect(between.regions[1].rect.h >= between.regions[1].floor).toBe(true)
		expect(adapter.node("/S/C/Ctas/CtaRow").rect.x).toBe(ctaX)

		-- TWO: the schedule is over. Nothing STRUCTURAL changes on this step — the
		-- piece is already gone — so the release is a pure re-solve, which is what
		-- the counters prove.
		local factoryRuns = root.counters().factoryRuns
		local creates = controller.stats().creates
		local removes = controller.stats().removes
		active:set(false)
		controller.refresh()

		local quiet = controller.compositionAt("/S/C")
		expect(quiet.lanes[1].collapsed).toBe(true)
		expect(quiet.lanes[1].rect.w).toBe(0)
		-- the released 200 px AND its 12 px lane gap went to the field
		expect(quiet.lanes[2].rect.w - fieldLive).toBe(212)
		expect(quiet.lanes[2].rect.x).toBe(0)
		expect(adapter.node("/S/C/Field/FieldBody").rect.x).toBe(0)
		expect(root.counters().factoryRuns).toBe(factoryRuns)
		expect(controller.stats().creates).toBe(creates)
		expect(controller.stats().removes).toBe(removes)
		expect(adapter.node("/S/C/Slot") ~= nil).toBe(true)

		-- ...and the next round claims its column back, from the same nodes
		active:set(true)
		controller.refresh()
		expect(controller.compositionAt("/S/C").lanes[1].collapsed).toBe(false)
		expect(controller.stats().creates).toBe(creates)
	end)

	it("a SPANNING row mounts as a full-width band above the lanes, and flips with them", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 900, h = 320 })
		local function box(id: string, w: number, h: number)
			return UI.Box({ id = id, width = { type = "fixed", px = w }, height = { type = "fixed", px = h } })
		end
		local bp = UI.Screen({
			id = "S",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			children = {
				UI.Composition({
					id = "C",
					arrangements = { "threeLane", "column" },
					laneGap = 12,
					groupGap = 8,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					groups = {
						{ id = "caption", span = "above" },
						{ id = "ceremony", lane = "lead", sizing = "hug", place = "center" },
						{ id = "field", lane = "main", sizing = "fill", minWidth = 240 },
						{ id = "next", lane = "trail", sizing = "hug", place = "end" },
					},
					children = {
						UI.Region({
							id = "Recap",
							group = "caption",
							rank = 5,
							children = { box("RecapLine", 300, 40) },
						}),
						UI.Region({
							id = "Hero",
							group = "ceremony",
							rank = 3,
							children = { box("HeroFull", 200, 96) },
						}),
						UI.Region({
							id = "Field",
							group = "field",
							rank = 2,
							sizing = "fill",
							mayScroll = true,
							floor = { lines = 1 },
							children = { box("FieldBody", 260, 300) },
						}),
						UI.Region({
							id = "Ctas",
							group = "next",
							rank = 1,
							floor = { targets = 2 },
							children = { box("CtaRow", 300, 52) },
						}),
					},
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local recap = adapter.node("/S/C/Recap").rect
		local hero = adapter.node("/S/C/Hero/HeroFull").rect
		local field = adapter.node("/S/C/Field/FieldBody").rect
		local cta = adapter.node("/S/C/Ctas/CtaRow").rect
		-- the band spans the composition and every lane starts under it
		expect(recap.w).toBe(900)
		expect(recap.y).toBe(0)
		expect(hero.y >= recap.y + recap.h).toBe(true)
		expect(field.y >= recap.y + recap.h).toBe(true)
		expect(hero.x < field.x and field.x < cta.x).toBe(true)
		-- the dump names the row from the controller, addressed by node path
		local d = controller.compositionAt("/S/C")
		expect(#d.spans).toBe(1)
		expect(d.spans[1].id).toBe("caption")
		-- ...and a rotation keeps the band exactly where it is: it does not travel
		local creates = controller.stats().creates
		env:set("viewportRect", { x = 0, y = 0, w = 320, h = 900 })
		controller.refresh()
		expect(controller.compositionAt("/S/C").arrangement).toBe("column")
		local flipped = adapter.node("/S/C/Recap").rect
		expect(flipped.y).toBe(0)
		expect(flipped.w).toBe(320)
		expect(adapter.node("/S/C/Hero/HeroFull").rect.y >= flipped.y + flipped.h).toBe(true)
		expect(controller.stats().creates).toBe(creates)
		expect(controller.stats().removes).toBe(0)
	end)

	it("a Composition child that is not a Region is refused at construction", function()
		local ok, err = pcall(function()
			UI.Composition({
				id = "Bad",
				arrangements = { "column" },
				groups = { { id = "g", lane = "main" } },
				children = { UI.Box({ id = "loose" }) },
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "not a UI.Region", 1, true) ~= nil).toBe(true)
	end)

	it("DV6-2: a LIVE `reserved` is still a reservation at construction", function()
		--[[ The flag says WHEN the box is held, never WHETHER this region is the kind
			that holds one — so both declaration errors must still fire at the call
			site with a Readable in the slot. Reading the signal here instead would
			make them depend on the value it happened to hold on the build frame. ]]
		local core = customFactory.new()
		local function region(props: any): any
			local spec: any = {
				id = "Slot",
				group = "g",
				rank = 1,
				children = { UI.Box({ id = "b", width = { type = "fixed", px = 10 } }) },
			}
			for k, v in props do
				spec[k] = v
			end
			return spec
		end
		local function build(props: any)
			return function()
				UI.Composition({
					id = "C",
					arrangements = { "column" },
					groups = { { id = "g", lane = "main" } },
					children = { UI.Region(region(props)) },
				})
			end
		end
		-- with a floor, a live reserve is legal
		expect(pcall(build({ reserved = core:signal(true), floor = { targets = 1 } }))).toBe(true)
		-- ...without one it reserves nothing, live or pinned
		local ok, err = pcall(build({ reserved = core:signal(true) }))
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "reserved but declares no floor", 1, true) ~= nil).toBe(true)
		-- ...and it is still mutually exclusive with mayDrop
		local ok2, err2 = pcall(build({ reserved = core:signal(false), floor = { targets = 1 }, mayDrop = true }))
		expect(ok2).toBe(false)
		expect(string.find(tostring(err2), "both reserved and mayDrop", 1, true) ~= nil).toBe(true)
	end)

	it("a Region without an explicit id is refused (the dump has to be stable)", function()
		local ok = pcall(function()
			UI.Region({ group = "g", rank = 1, children = { UI.Box({ id = "b" }) } })
		end)
		expect(ok).toBe(false)
	end)

	it("a group minWidth may be a theme METRIC NAME, resolved every solve", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 900, h = 320 })
		local bp = UI.Screen({
			id = "S",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			children = {
				UI.Composition({
					id = "C",
					arrangements = { "threeLane", "column" },
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					groups = {
						{ id = "lead", lane = "lead", sizing = "hug" },
						-- a metric name where a px count would have been
						{ id = "body", lane = "main", sizing = "fill", minWidth = "targetSizes.minimum" },
						{ id = "trail", lane = "trail", sizing = "hug" },
					},
					children = {
						UI.Region({
							id = "A",
							group = "lead",
							rank = 2,
							children = { UI.Box({ id = "a", width = { type = "fixed", px = 100 } }) },
						}),
						UI.Region({
							id = "B",
							group = "body",
							rank = 1,
							sizing = "fill",
							children = { UI.Box({ id = "b", width = { type = "fixed", px = 100 } }) },
						}),
						UI.Region({
							id = "C2",
							group = "trail",
							rank = 3,
							children = { UI.Box({ id = "c", width = { type = "fixed", px = 100 } }) },
						}),
					},
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect(controller.compositionAt("/S/C").arrangement).toBe("threeLane")
		-- an unresolvable metric name is refused where it is written
		local ok = pcall(function()
			UI.Composition({
				id = "Bad2",
				arrangements = { "column" },
				groups = { { id = "g", lane = "main", minWidth = "not.a.metric" } },
				children = { UI.Region({ id = "R", group = "g", rank = 1, children = { UI.Box({ id = "x" }) } }) },
			})
		end)
		expect(ok).toBe(false)
	end)

	it("a group's own GAP may be a spacing step, and it reaches the solver as pixels", function()
		-- the constructor accepts a step name here exactly as it does for
		-- `minWidth`; only `minWidth` used to be resolved, so `gap = "s"` arrived
		-- at the arithmetic as a string and read as NO gap — the regions in that
		-- group sat flush. Accepted-and-ignored, which this boundary exists to
		-- remove.
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		local bp = UI.Screen({
			id = "S",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			children = {
				UI.Composition({
					id = "C",
					arrangements = { "column" },
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					groups = { { id = "g", lane = "main", sizing = "hug", gap = "m" } },
					children = {
						UI.Region({
							id = "A",
							group = "g",
							rank = 1,
							children = {
								UI.Box({
									id = "a",
									width = { type = "fixed", px = 100 },
									height = { type = "fixed", px = 40 },
								}),
							},
						}),
						UI.Region({
							id = "B",
							group = "g",
							rank = 2,
							children = {
								UI.Box({
									id = "b",
									width = { type = "fixed", px = 100 },
									height = { type = "fixed", px = 40 },
								}),
							},
						}),
					},
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local a, b = adapter.node("/S/C/A/a").rect, adapter.node("/S/C/B/b").rect
		-- "m" is the neutral theme's 16 px step, between the two regions
		expect(b.y - (a.y + a.h)).toBe(16)
	end)
end)

-- ===========================================================================
-- THE GALLERY FIXTURE, HEADLESS HALF.
--
-- The Studio phase proves the pixels; this proves the fixture mounts, that every
-- step the driver invokes BY NAME exists and lands its declared state, and that
-- the five device offers plus the live axis flip produce the arrangement
-- switches, the form step-downs, the one scroll, the reserved rest and the state
-- survival the scenario exists to show.
-- ===========================================================================

local LuauUI = require("../src") :: any
local SCENARIO = require("../examples/gallery/scenarios/composition") :: any
local COMP_PATH = "/CompositionScreen/OfferFrame/Summary"

local function world(viewport: { x: number, y: number, w: number, h: number }?)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", viewport or { x = 0, y = 0, w = 1920, h = 1080 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	local built: any
	local ctx: any = {
		LuauUI = LuauUI,
		core = core,
		env = env,
		adapter = adapter,
		presenter = pres,
		actionSystem = system,
		record = function() end,
		composition = function(path: string?): any
			local handle = built and built.handle
			local controller = handle and handle.controller
			if controller == nil or controller.compositionAt == nil then
				return nil
			end
			return controller.compositionAt(path)
		end,
	}
	built = SCENARIO.build(ctx)
	built.handle = pres.present(built.screen, built.present)
	pres.refresh()
	local w: any = { core = core, env = env, adapter = adapter, pres = pres, built = built }
	function w.step(name: string): any
		local fn = built.steps[name]
		assert(fn ~= nil, `no step '{name}'`)
		local out = fn()
		pres.refresh()
		return out
	end
	function w.report(): any
		return built.report()
	end
	function w.resolution(): any
		return ctx.composition(COMP_PATH)
	end
	-- the solver addresses a region by its node PATH, exactly like every rect
	-- key and every hidden root; the declared id is its last segment
	local function leaf(id: string): string
		return string.match(id, "([^/]+)$") :: string
	end
	function w.formOf(id: string): number
		for _, r in w.resolution().regions do
			if leaf(r.id) == id then
				return r.form
			end
		end
		error(`no region '{id}'`)
	end
	function w.mountedRegion(id: string): boolean
		for _, r in w.resolution().regions do
			if leaf(r.id) == id then
				return r.mounted
			end
		end
		return false
	end
	function w.scroller(): string?
		local s = w.resolution().scroller
		return if s ~= nil then leaf(s) else nil
	end
	return w
end

describe("scenario 'composition': the fixture the device matrix drives", function()
	it("mounts headlessly and resolves an arrangement with no core error", function()
		local w = world()
		expect(w.core:counters().errors or 0).toBe(0)
		expect(w.resolution().schema).toBe("luauui-composition-dump/1")
	end)

	it("every step the driver names exists and lands its declared state", function()
		local w = world()
		local names = {
			"compactPortrait",
			"phoneLandscape",
			"tablet",
			"desktop",
			"tenFoot",
			"flipOffer",
			"restCelebration",
			"wakeCelebration",
			"emptyCallout",
			"fillCallout",
			"emptyRecap",
			"fillRecap",
			"bump",
		}
		for _, name in names do
			expect(w.built.steps[name] ~= nil).toBe(true)
		end
		expect(w.step("desktop")).toBe("desktop")
		expect(w.report().offer).toBe("desktop")
		expect(w.step("bump")).toBe(1)
		expect(w.step("restCelebration")).toBe(false)
		expect(w.report().celebrating).toBe(false)
	end)

	it("the five device offers resolve the arrangements the design intends", function()
		local w = world()
		w.step("compactPortrait")
		expect(w.resolution().arrangement).toBe("column")
		w.step("phoneLandscape")
		expect(w.resolution().arrangement).toBe("threeLane")
		w.step("tablet")
		expect(w.resolution().arrangement).toBe("threeLane")
		w.step("desktop")
		expect(w.resolution().arrangement).toBe("threeLane")
		w.step("tenFoot")
		expect(w.resolution().arrangement).toBe("threeLane")
	end)

	it("the short offer STEPS DOWN and the big one does not — same declaration", function()
		local w = world()
		w.step("desktop")
		local rich = w.resolution()
		w.step("phoneLandscape")
		local tight = w.resolution()
		local richForms, tightForms = 0, 0
		for _, r in rich.regions do
			richForms += r.form
		end
		for _, r in tight.regions do
			tightForms += r.form
		end
		expect(tightForms > richForms).toBe(true)
		-- ...and the rank-1 action band is never the first thing to give
		expect(w.formOf("Actions") <= 2).toBe(true)
	end)

	it("exactly one region scrolls, in every offer", function()
		local w = world()
		for _, offer in { "compactPortrait", "phoneLandscape", "tablet", "desktop", "tenFoot" } do
			w.step(offer)
			expect(w.scroller()).toBe("Field")
		end
	end)

	it("a rested transient does not move the region under it (reserved holds its box)", function()
		local w = world()
		w.step("compactPortrait")
		local before = w.adapter.node("/CompositionScreen/OfferFrame/Summary/Callout").rect
		w.step("restCelebration")
		local after = w.adapter.node("/CompositionScreen/OfferFrame/Summary/Callout").rect
		expect(after.y).toBe(before.y)
		w.step("wakeCelebration")
		expect(w.adapter.node("/CompositionScreen/OfferFrame/Summary/Callout").rect.y).toBe(before.y)
	end)

	it("an emptied region is ABSENT and its space goes to the field", function()
		local w = world()
		w.step("compactPortrait")
		local fieldBefore = w.adapter.node("/CompositionScreen/OfferFrame/Summary/Field").rect
		w.step("emptyCallout")
		expect(w.mountedRegion("Callout")).toBe(false)
		local fieldAfter = w.adapter.node("/CompositionScreen/OfferFrame/Summary/Field").rect
		expect(fieldAfter.h > fieldBefore.h).toBe(true)
	end)

	it("the SPANNING caption is a full-width band in every offer, and free when empty", function()
		local w = world()
		local root = "/CompositionScreen/OfferFrame/Summary"
		for _, offer in { "compactPortrait", "phoneLandscape", "tablet", "desktop", "tenFoot" } do
			w.step(offer)
			local frame = w.adapter.node("/CompositionScreen/OfferFrame").rect
			local band = w.adapter.node(`{root}/Recap`).rect
			local field = w.adapter.node(`{root}/Field`).rect
			expect(`{offer}:width={band.w == frame.w}`).toBe(`{offer}:width=true`)
			expect(`{offer}:top={band.y == frame.y}`).toBe(`{offer}:top=true`)
			expect(`{offer}:aboveField={band.y + band.h <= field.y}`).toBe(`{offer}:aboveField=true`)
		end
		-- an empty band is ABSENT: the lanes take every pixel of it back
		w.step("phoneLandscape")
		local fieldBefore = w.adapter.node(`{root}/Field`).rect
		w.step("emptyRecap")
		expect(w.mountedRegion("Recap")).toBe(false)
		local fieldAfter = w.adapter.node(`{root}/Field`).rect
		expect(fieldAfter.y < fieldBefore.y).toBe(true)
		expect(fieldAfter.h > fieldBefore.h).toBe(true)
		w.step("fillRecap")
		expect(w.adapter.node(`{root}/Field`).rect.y).toBe(fieldBefore.y)
	end)

	it("a live axis flip is a RE-SOLVE: state survives and nothing is rebuilt", function()
		local w = world()
		w.step("phoneLandscape")
		w.step("bump")
		w.step("bump")
		expect(w.resolution().arrangement).toBe("threeLane")
		local factoryRuns = w.built.handle.root.counters().factoryRuns
		local mountedCount = w.built.handle.root.counters().mounted
		local creates = w.built.handle.controller.stats().creates
		local removes = w.built.handle.controller.stats().removes

		w.step("flipOffer")

		expect(w.resolution().arrangement).toBe("column")
		expect(w.report().visits).toBe(2) -- owner state survived
		expect(w.built.handle.root.counters().factoryRuns).toBe(factoryRuns)
		expect(w.built.handle.root.counters().mounted).toBe(mountedCount)
		expect(w.built.handle.controller.stats().creates).toBe(creates)
		expect(w.built.handle.controller.stats().removes).toBe(removes)
	end)

	it("the report carries the resolution, so a device round can read the WHY", function()
		local w = world()
		w.step("compactPortrait")
		local report = w.report()
		expect(report.resolution.arrangement).toBe("column")
		expect(#report.resolution.rejected > 0).toBe(true)
		expect(report.resolution.rejected[1].rule).toBe("laneWidth")
		expect(#report.resolution.rejected[1].detail > 0).toBe(true)
	end)

	it("twenty offer changes leave the registry and the core exactly where they started", function()
		local w = world()
		local baseline = w.built.handle.controller.stats().creates
		for _ = 1, 10 do
			w.step("compactPortrait")
			w.step("desktop")
		end
		expect(w.built.handle.controller.stats().creates).toBe(baseline)
		expect(w.built.handle.controller.stats().removes).toBe(0)
	end)
end)

--[[ ================================================================ 2026-08-02
	ELIGIBILITY — a candidate gated on a fact geometry cannot show.

	Found live: a consumer wanted a one-column layout on a tablet or desktop and
	NOT on a landscape phone. Ordering `column` first could not express it,
	because the surface's list is a SCROLL region — every other region takes its
	space and the list scrolls in what is left, so `column` FITS every offer,
	including the phone where it costs the list its own lane. The author's rule
	was a SIZE CLASS, which rule 2 has no way to consult.
============================================================================ ]]
describe("composition — arrangement eligibility (2026-08-02)", function()
	local function gated(eligibleColumn: boolean): any
		return baseDecl({
			arrangements = {
				{ name = "column", lanes = { { "head", "lead", "main", "trail" } }, eligible = eligibleColumn },
				{ name = "threeLane", lanes = { { "head", "lead" }, { "main" }, { "trail" } } },
				{ name = "twoLane", lanes = { { "main" }, { "head", "lead", "trail" } } },
			},
		})
	end

	it("an ineligible candidate is SKIPPED even where it would have fitted", function()
		--[[ The whole point: `column` is first AND legal on this offer, so without
			the gate it would win. The gate is what lets an author say "not here". ]]
		local roomy = { w = 1200, h = 800 }
		local ungated = composition.resolve(gated(true), roomy, ctx())
		expect(`ungated={ungated.arrangement}`).toBe("ungated=column")
		local blocked = composition.resolve(gated(false), roomy, ctx())
		expect(`blocked={blocked.arrangement}`).toBe("blocked=threeLane")
	end)

	it("being skipped is NOT losing: the resolution stays legal and reports why", function()
		--[[ "This did not fit" and "this was not offered here" are different bugs,
			so the dump must not conflate them — and a skipped candidate must never
			mark the screen a fallback. ]]
		local r = composition.resolve(gated(false), { w = 1200, h = 800 }, ctx())
		expect(`legal={r.legal}`).toBe("legal=true")
		expect(`fallback={r.fallback}`).toBe("fallback=false")
		local rule = nil
		for _, rej in r.rejected do
			if rej.arrangement == "column" then
				rule = rej.rule
			end
		end
		expect(`rule={rule}`).toBe("rule=ineligible")
	end)

	it("the LAST candidate is never gated out — a screen always resolves", function()
		--[[ Rule 8 is not negotiable. An author who gates every candidate has made
			a mistake; blanking the screen would be a worse one. ]]
		local decl = baseDecl({
			arrangements = {
				{ name = "threeLane", lanes = { { "head", "lead" }, { "main" }, { "trail" } }, eligible = false },
				{ name = "column", lanes = { { "head", "lead", "main", "trail" } }, eligible = false },
			},
		})
		local r = composition.resolve(decl, { w = 1200, h = 800 }, ctx())
		expect(`arrangement={r.arrangement}`).toBe("arrangement=column")
		expect(`resolved={#r.regions > 0}`).toBe("resolved=true")
	end)

	it("absent `eligible` is the pre-existing behaviour, byte for byte", function()
		local before = composition.resolve(baseDecl(), { w = 1200, h = 800 }, ctx())
		local withNil = composition.resolve(
			baseDecl({
				arrangements = {
					{ name = "threeLane", lanes = { { "head", "lead" }, { "main" }, { "trail" } }, eligible = nil },
					{ name = "twoLane", lanes = { { "main" }, { "head", "lead", "trail" } } },
					{ name = "column", lanes = { { "head", "lead", "main", "trail" } } },
				},
			}),
			{ w = 1200, h = 800 },
			ctx()
		)
		expect(`same={withNil.arrangement}`).toBe(`same={before.arrangement}`)
	end)

	it("rejects a non-boolean gate at normalization, naming the arrangement", function()
		local ok, err = pcall(function()
			return composition.normalize(baseDecl({
				arrangements = {
					{ name = "column", lanes = { { "head", "lead", "main", "trail" } }, eligible = "roomy" },
				},
			}))
		end)
		expect(`rejected={not ok}`).toBe("rejected=true")
		expect(`named={string.find(tostring(err), "eligible", 1, true) ~= nil}`).toBe("named=true")
	end)
end)

--[[ ================================================================ 2026-08-02
	THE HUG-LANE OVERFLOW DIAGNOSTIC.

	Found live: a form inside a HUG group was authored `width = FILL`, so it
	measured the entire offer. Its lane's intrinsic width became the whole box,
	every lane arrangement failed rule 2, and the composition fell through to the
	column fallback — which from outside looks exactly like the region VANISHING.
	No error, no diagnostic, an hour to find. It is reported, not fatal, because a
	genuinely narrow offer can produce the same measure honestly.
============================================================================ ]]
describe("composition — hug-lane overflow is reported, not silent", function()
	it("names the region whose form filled the offer inside a hug lane", function()
		local sizes = table.clone(SIZES)
		-- `Hero` lives in the hug `ceremony` group; make its form measure the offer
		sizes.Hero = { { w = 100000, h = 40 }, { w = 100000, h = 40 } }
		local r = resolve(1200, 800, baseDecl(), sizes)
		expect(`named={table.concat(r.hugOverflow, ",")}`).toBe("named=Hero")
	end)

	it("a well-formed declaration reports NOTHING — the check is not noise", function()
		local r = resolve(1200, 800)
		expect(`clean={#r.hugOverflow}`).toBe("clean=0")
	end)

	it("it is a REPORT, never a failure: the screen still resolves", function()
		--[[ A narrow enough offer produces this measure honestly, so stopping would
			break a legitimate screen to catch an authoring mistake. The author is
			told; the player still gets a layout. ]]
		local sizes = table.clone(SIZES)
		sizes.Hero = { { w = 100000, h = 40 }, { w = 100000, h = 40 } }
		local r = resolve(1200, 800, baseDecl(), sizes)
		expect(`resolved={#r.regions > 0}`).toBe("resolved=true")
		expect(`arrangement={type(r.arrangement)}`).toBe("arrangement=string")
	end)

	it("a FILL group's region filling the offer is not a defect and is not reported", function()
		-- the field lane is `fill`; filling is its entire job
		local sizes = table.clone(SIZES)
		sizes.Field = { { w = 100000, h = 400 } }
		local r = resolve(1200, 800, baseDecl(), sizes)
		expect(`fieldQuiet={table.concat(r.hugOverflow, ",")}`).toBe("fieldQuiet=")
	end)
end)
