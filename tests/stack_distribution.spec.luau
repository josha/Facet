--!strict
--[[
	THE STACK BRANCH GAINS THREE THINGS (docs/plans/swiftui-parity-round2.md §2.1,
	§2.4, §2.6). They are one coherent change to one branch, so they are one spec
	file. Two of the three live in ARRANGE only; the shrink pass has a MEASURE half
	as well, and which half a case is about is said case by case below.

	  §2.6 `distribute`   main-axis distribution of the leftover, on the CONTAINER.
	                      Until now the cursor was hard-anchored at the start of the
	                      axis (`local cursor = if isH then innerX else innerY`), so
	                      SpaceBetween / SpaceAround / SpaceEvenly could only be
	                      faked with hand-placed `Spacer`s — which a `UI.ForEach`
	                      list cannot do at all, because `row` returns exactly ONE
	                      blueprint. A tab bar whose tab count varies was
	                      inexpressible.
	  §2.4 the SHRINK pass  `layoutPriority` (the outer sort: tiers, lowest first)
	                      and `shrinkWeight` (the inner distribution: proportional
	                      to weight x basis, CSS's rule). Before this the solver had
	                      no shrink pass at all — `remaining = math.max(0, availMain)`
	                      clamped the deficit away and the content painted outside
	                      its box with only a diagnostic to say so. It is the one of
	                      the three that is NOT arrange-only: the measure branch runs
	                      the same negotiation at PASS 1.5 whenever the offer it was
	                      handed is already too small, which is what makes a squeezed
	                      label's extra wrapped lines RESERVED rather than painted
	                      outside the row (2026-08-12, "THE CLOSED SEAM" below).
	  §2.1 `lineAlign`    per-child cross-axis alignment, the leaf-level route to
	                      Roblox's `ItemLineAlignment`. It also disentangles `align`,
	                      which on a nested stack meant two different things at once
	                      (align MY children / align ME in my parent's line).

	DEFAULTS ARE INERT, DELIBERATELY. `distribute` defaults to `"start"` and
	`shrinkWeight` to `0` (Roblox's own `Enum.UIFlexMode.None`, "neither shrinks nor
	grows"), so every shipped screen is byte-identical. The first `describe` below
	pins that, because "additive and inert" is a claim like any other.

	EVERY MOUNTED FIXTURE HERE CALLS `controller.diagnostics()`
	(docs/lessons/the-solver-already-told-you.md §13): a fixture that does not ask
	is not evidence.
]]

local fs = require("@lune/fs")

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local solver = require("../src/layout/solver")
local UI = require("../src/blueprint")
local customFactory = require("../src/core/custom")
local environment = require("../src/env/environment")
local mountLib = require("../src/mount")
local rendererLib = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")

local function fixed(px: number)
	return { type = "fixed", px = px }
end
local function fill(weight: number?)
	return { type = "fill", weight = weight or 1 }
end

local function solve(root: any, w: number, h: number)
	return solver.solve(root, { w = w, h = h }, { rootPolicy = "edgeToEdge" })
end

-- x positions of the named children, in the order given
local function xs(result: any, ids: { string }): { number }
	local out = {}
	for _, id in ids do
		table.insert(out, result.rects[id].rect.x)
	end
	return out
end
local function ws(result: any, ids: { string }): { number }
	local out = {}
	for _, id in ids do
		table.insert(out, result.rects[id].rect.w)
	end
	return out
end

local function overflowIssue(result: any): string?
	for _, d in result.diagnostics do
		if string.find(d.issue, "content overflows", 1, true) ~= nil then
			return d.issue
		end
	end
	return nil
end

-- Three 100px boxes in a 500px row: the shape the §2.6 solver probe used.
--
-- `width = fill` is load-bearing, not decoration. A stack with no width dim HUGS,
-- and `solver.solve` sizes the root at `min(measured, contentRect)` — so a hugging
-- row is exactly as wide as its children and there is no leftover to distribute at
-- all. Every distribution case below therefore declares the box it is distributing
-- inside, which is also how a real screen writes it.
local function threeRow(extra: { [string]: any }?): any
	local node: any = {
		kind = "hstack",
		id = "R",
		width = fill(),
		children = {
			{ kind = "box", id = "a", width = fixed(100), height = fixed(20) },
			{ kind = "box", id = "b", width = fixed(100), height = fixed(20) },
			{ kind = "box", id = "c", width = fixed(100), height = fixed(20) },
		},
	}
	for k, v in extra or {} do
		node[k] = v
	end
	return node
end

-- ===========================================================================
-- §2.6 distribute
-- ===========================================================================

describe("§2.6 distribute — the default is today, byte for byte", function()
	it("an absent `distribute` packs from the start of the axis", function()
		expect(table.concat(xs(solve(threeRow(), 500, 100), { "a", "b", "c" }), ",")).toBe("0,100,200")
	end)

	it('an explicit `distribute = "start"` is the same arrangement', function()
		local r = solve(threeRow({ distribute = "start" }), 500, 100)
		expect(table.concat(xs(r, { "a", "b", "c" }), ",")).toBe("0,100,200")
	end)
end)

describe("§2.6 distribute — the three flex distributions", function()
	it("spaceBetween puts the leftover in the gaps only (0 / 200 / 400)", function()
		local r = solve(threeRow({ distribute = "spaceBetween" }), 500, 100)
		expect(table.concat(xs(r, { "a", "b", "c" }), ",")).toBe("0,200,400")
	end)

	it("spaceEvenly gives every gap AND both ends the same share (50 / 200 / 350)", function()
		local r = solve(threeRow({ distribute = "spaceEvenly" }), 500, 100)
		expect(table.concat(xs(r, { "a", "b", "c" }), ",")).toBe("50,200,350")
	end)

	it("spaceAround gives the ends a HALF share (33 / 199 / 366)", function()
		local r = solve(threeRow({ distribute = "spaceAround" }), 500, 100)
		expect(table.concat(xs(r, { "a", "b", "c" }), ",")).toBe("33,199,366")
	end)

	it("center and end move the whole group without changing the gaps", function()
		local c = solve(threeRow({ distribute = "center" }), 500, 100)
		expect(table.concat(xs(c, { "a", "b", "c" }), ",")).toBe("100,200,300")
		local e = solve(threeRow({ distribute = "end" }), 500, 100)
		expect(table.concat(xs(e, { "a", "b", "c" }), ",")).toBe("200,300,400")
	end)

	it("a declared `gap` is kept and the distribution rides on top of it", function()
		-- 500 - 300 - (2 x 10) = 180 leftover, 2 gaps -> +90 each
		local r = solve(threeRow({ distribute = "spaceBetween", gap = 10 }), 500, 100)
		expect(table.concat(xs(r, { "a", "b", "c" }), ",")).toBe("0,200,400")
	end)

	it("a single child: spaceBetween pins it at the start, spaceAround centres it", function()
		local function one(mode: string)
			return solve({
				kind = "hstack",
				id = "R",
				width = fill(),
				distribute = mode,
				children = { { kind = "box", id = "a", width = fixed(100), height = fixed(20) } },
			}, 500, 100).rects.a.rect.x
		end
		expect(one("spaceBetween")).toBe(0)
		expect(one("spaceAround")).toBe(200)
		expect(one("spaceEvenly")).toBe(200)
	end)

	it("a vertical stack distributes along Y, not X", function()
		local r = solve({
			kind = "vstack",
			id = "C",
			height = fill(),
			distribute = "spaceBetween",
			children = {
				{ kind = "box", id = "a", width = fixed(20), height = fixed(100) },
				{ kind = "box", id = "b", width = fixed(20), height = fixed(100) },
			},
		}, 100, 400)
		expect(r.rects.a.rect.y).toBe(0)
		expect(r.rects.b.rect.y).toBe(300)
		expect(r.rects.a.rect.x).toBe(0)
	end)

	it("no leftover means no movement: distribute cannot invent space", function()
		local r = solve(threeRow({ distribute = "spaceBetween" }), 300, 100)
		expect(table.concat(xs(r, { "a", "b", "c" }), ",")).toBe("0,100,200")
	end)
end)

describe("§2.6 distribute — the composition rule with `fill`", function()
	it("a fill child takes the whole leftover, so distribute has nothing left", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			width = fill(),
			distribute = "spaceBetween",
			children = {
				{ kind = "box", id = "a", width = fixed(100), height = fixed(20) },
				{ kind = "box", id = "s", width = fill(), height = fixed(20) },
				{ kind = "box", id = "c", width = fixed(100), height = fixed(20) },
			},
		}, 500, 100)
		expect(table.concat(xs(r, { "a", "s", "c" }), ",")).toBe("0,100,400")
		expect(r.rects.s.rect.w).toBe(300)
	end)

	it("...and says so: the conflict is a diagnostic, never a silent no-op", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			width = fill(),
			distribute = "spaceBetween",
			children = {
				{ kind = "box", id = "a", width = fixed(100), height = fixed(20) },
				{ kind = "box", id = "s", width = fill(), height = fixed(20) },
			},
		}, 500, 100)
		local found: string? = nil
		for _, d in r.diagnostics do
			if string.find(d.issue, "distribute", 1, true) ~= nil then
				found = d.issue
			end
		end
		expect(found ~= nil).toBe(true)
		expect(string.find(found :: string, "spaceBetween", 1, true) ~= nil).toBe(true)
		expect(string.find(found :: string, "fill", 1, true) ~= nil).toBe(true)
	end)

	it('a `fill` child under the default "start" is NOT a conflict and files nothing', function()
		local r = solve({
			kind = "hstack",
			id = "R",
			width = fill(),
			children = {
				{ kind = "box", id = "a", width = fixed(100), height = fixed(20) },
				{ kind = "box", id = "s", width = fill(), height = fixed(20) },
			},
		}, 500, 100)
		for _, d in r.diagnostics do
			expect(string.find(d.issue, "distribute", 1, true) == nil).toBe(true)
		end
	end)
end)

-- ===========================================================================
-- §2.4 the shrink pass
-- ===========================================================================

describe("§2.4 shrink — the default preserves today's geometry exactly", function()
	it("without `shrinkWeight` an overflowing row still paints outside its box", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			children = {
				{ kind = "box", id = "a", width = fixed(200), height = fixed(20) },
				{ kind = "box", id = "b", width = fixed(200), height = fixed(20) },
				{ kind = "box", id = "c", width = fixed(200), height = fixed(20) },
			},
		}, 500, 100)
		expect(table.concat(ws(r, { "a", "b", "c" }), ",")).toBe("200,200,200")
		expect(table.concat(xs(r, { "a", "b", "c" }), ",")).toBe("0,200,400")
	end)

	it("...and the overflow diagnostic keeps its exact historic wording", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			children = {
				{ kind = "box", id = "a", width = fixed(400), height = fixed(20) },
				{ kind = "box", id = "b", width = fixed(400), height = fixed(20) },
			},
		}, 500, 100)
		expect(overflowIssue(r)).toBe(
			"content overflows this hstack by 300px on the main axis; it will paint outside its box "
				.. "(wrap it in a ScrollView, or give it room)"
		)
	end)
end)

describe("§2.4 shrink — the inner distribution (`shrinkWeight`)", function()
	it("equal weights and equal bases split the deficit evenly", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			children = {
				{ kind = "box", id = "a", width = fixed(200), height = fixed(20), shrinkWeight = 1 },
				{ kind = "box", id = "b", width = fixed(200), height = fixed(20), shrinkWeight = 1 },
				{ kind = "box", id = "c", width = fixed(200), height = fixed(20), shrinkWeight = 1 },
			},
		}, 500, 100)
		-- deficit 100 over three equal bases: 34/33/33 taken, largest remainder first
		expect(table.concat(ws(r, { "a", "b", "c" }), ",")).toBe("166,167,167")
		expect(overflowIssue(r)).toBeNil()
	end)

	it("the weight is MULTIPLIED BY THE BASIS, so the small child is not collapsed first", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			children = {
				{ kind = "box", id = "big", width = fixed(400), height = fixed(20), shrinkWeight = 1 },
				{ kind = "box", id = "small", width = fixed(100), height = fixed(20), shrinkWeight = 1 },
			},
		}, 250, 100)
		-- deficit 250; basis-weighted -> 200 off the 400 and 50 off the 100.
		-- WITHOUT basis weighting both would give 125 and `small` would floor at 0.
		expect(table.concat(ws(r, { "big", "small" }), ",")).toBe("200,50")
	end)

	it("`shrinkWeight = 0` (the default) never shrinks, whatever its siblings do", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			children = {
				{ kind = "box", id = "elastic", width = fixed(300), height = fixed(20), shrinkWeight = 1 },
				{ kind = "box", id = "rigid", width = fixed(300), height = fixed(20) },
			},
		}, 500, 100)
		expect(table.concat(ws(r, { "elastic", "rigid" }), ",")).toBe("200,300")
	end)

	it("a bigger weight gives up proportionally more", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			children = {
				{ kind = "box", id = "soft", width = fixed(200), height = fixed(20), shrinkWeight = 3 },
				{ kind = "box", id = "firm", width = fixed(200), height = fixed(20), shrinkWeight = 1 },
			},
		}, 300, 100)
		-- deficit 100 split 3:1 -> 75 / 25
		expect(table.concat(ws(r, { "soft", "firm" }), ",")).toBe("125,175")
	end)
end)

describe("§2.4 shrink — the outer sort (`layoutPriority`)", function()
	it("the lowest tier absorbs the whole deficit before the next tier gives a pixel", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			children = {
				{ kind = "box", id = "lo1", width = fixed(200), height = fixed(20), shrinkWeight = 1 },
				{ kind = "box", id = "lo2", width = fixed(200), height = fixed(20), shrinkWeight = 1 },
				{
					kind = "box",
					id = "hi",
					width = fixed(200),
					height = fixed(20),
					shrinkWeight = 1,
					layoutPriority = 1,
				},
			},
		}, 500, 100)
		expect(table.concat(ws(r, { "lo1", "lo2", "hi" }), ",")).toBe("150,150,200")
	end)

	it("a tier that runs out of room passes the rest UP to the next tier", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			children = {
				{
					kind = "box",
					id = "lo",
					width = { type = "minMax", min = 150, preferred = 200 },
					height = fixed(20),
					shrinkWeight = 1,
				},
				{
					kind = "box",
					id = "hi",
					width = fixed(200),
					height = fixed(20),
					shrinkWeight = 1,
					layoutPriority = 1,
				},
			},
		}, 300, 100)
		-- deficit 100. Tier 0 can only give 50 (floor 150); tier 1 gives the other 50.
		expect(table.concat(ws(r, { "lo", "hi" }), ",")).toBe("150,150")
	end)

	it("a NEGATIVE priority is the first to give way", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			children = {
				{ kind = "box", id = "normal", width = fixed(200), height = fixed(20), shrinkWeight = 1 },
				{
					kind = "box",
					id = "cheap",
					width = fixed(200),
					height = fixed(20),
					shrinkWeight = 1,
					layoutPriority = -1,
				},
			},
		}, 300, 100)
		expect(table.concat(ws(r, { "normal", "cheap" }), ",")).toBe("200,100")
	end)
end)

-- THE FLOOR IS A CASCADE, NOT A SINGLE NUMBER (director ruling 1, 2026-08-13;
-- docs/handoff/2026-08-13-rulings-needed.md §1). An authored `minMax.min` is a
-- contract and binds at every rung; the floor the framework DERIVES from a text
-- descends when the rung above it cannot absorb the deficit: the longest word,
-- then the compact form's longest word, then one ellipsis — and whatever is left
-- after that is CLIPPED at the box rather than painted outside it.
describe("§2.4 shrink — the floor cascade: minMax.min, longest word, compact form, ellipsis, clip", function()
	it("`minMax.min` is a hard floor inside its own tier", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			children = {
				{
					kind = "box",
					id = "clamped",
					width = { type = "minMax", min = 120, preferred = 200 },
					height = fixed(20),
					shrinkWeight = 1,
				},
				{ kind = "box", id = "free", width = fixed(200), height = fixed(20), shrinkWeight = 1 },
			},
		}, 200, 100)
		-- deficit 200: `clamped` freezes at 120 (gives 80), `free` absorbs the rest
		expect(table.concat(ws(r, { "clamped", "free" }), ",")).toBe("120,80")
	end)

	it("a text node stops at the width of its longest word while that is enough", function()
		-- The deficit has to come from a SIBLING: a lone text child is measured
		-- against the row's own inner width and clamps itself to it, so it can never
		-- overflow on its own.
		local TEXT = "aa bb cc dd ee ff gg hh"
		local function row(rigid: number, weight: number?)
			return solve({
				kind = "hstack",
				id = "R",
				width = fill(),
				children = {
					{ kind = "box", id = "rigid", width = fixed(rigid), height = fixed(20) },
					{ kind = "text", id = "label", text = TEXT, shrinkWeight = weight },
				},
			}, 400, 400)
		end
		-- the longest word's width, measured on its own through the same seam
		local wordOnly = solve(
			{ kind = "hstack", id = "R", children = { { kind = "text", id = "w", text = "aa" } } },
			10000,
			200
		).rects.w.rect.w

		-- a deficit it CAN absorb: the label gives up exactly what is asked
		local partial = row(200, 1)
		expect(partial.rects.label.rect.w).toBe(200)
		expect(overflowIssue(partial)).toBeNil()

		-- ...and a deficit that lands EXACTLY on that floor: the rung holds, and the
		-- cascade below never has to open, so the label keeps its whole string
		local natural = row(380, nil).rects.label.rect.w
		local atFloor = row(380, 1)
		expect(natural > wordOnly).toBe(true)
		expect(atFloor.rects.label.rect.w).toBe(wordOnly)
		expect(overflowIssue(atFloor)).toBeNil()
	end)

	it("...and DESCENDS past it, to an ellipsis, when the longest word is not enough", function()
		-- RULING 1, the measured case. Before it, the pass absorbed at most
		-- `Sum(basis - floor)` and simply left the rest: the label froze at its
		-- longest word (20px), the row still overflowed, and — because a text
		-- squeezed under its min-content cannot wrap — it EXPLODED to eight lines
		-- and painted seven of them outside the row.
		--
		-- The cascade's second and third rungs close that. There is no compact form
		-- here, so the pass drops to the ellipsis floor, and the wrap rule (ruling 5)
		-- measures the label on ONE line at that width: the engine's
		-- TextTruncate.AtEnd draws `…` and the row fits.
		local TEXT = "aa bb cc dd ee ff gg hh"
		local r = solve({
			kind = "hstack",
			id = "R",
			width = fill(),
			children = {
				{ kind = "box", id = "rigid", width = fixed(390), height = fixed(20) },
				{ kind = "text", id = "label", text = TEXT, shrinkWeight = 1 },
			},
		}, 400, 400)
		-- it went BELOW the longest word (20px), which is the whole ruling
		expect(r.rects.label.rect.w < 20).toBe(true)
		-- ...the row fits, so nothing is left to paint outside and nothing is clipped
		expect(overflowIssue(r)).toBeNil()
		expect(r.rects.rigid.rect.w + r.rects.label.rect.w).toBe(400)
		-- ...and it is ONE line, not eight: the label tells the truth with an
		-- ellipsis instead of wrapping into a column no word of it fits
		local facts = r.rects.label.textFacts
		expect(`lines={facts.lines} truncated={facts.truncated} wraps={facts.wraps}`).toBe(
			"lines=1 truncated=true wraps=false"
		)
		expect(r.rects.R.rect.h).toBe(20)
	end)

	it("...and a declared COMPACT form is spent BEFORE any of the string is", function()
		-- rung 1 of the cascade, and the order the director asked for in as many
		-- words: "switch to compact and then truncate the text before clipping".
		-- The compact form's own longest word is the floor the pass may descend to
		-- once the full label's is not enough, and the re-measure at that reduced
		-- offer is what makes the compact ladder actually choose it — one mechanism,
		-- not two.
		local r = solve({
			kind = "hstack",
			id = "R",
			width = fill(),
			children = {
				{ kind = "box", id = "rigid", width = fixed(340), height = fixed(20) },
				{
					kind = "text",
					id = "label",
					text = "Configuration",
					compactText = "Cfg",
					shrinkWeight = 1,
				},
			},
		}, 400, 400)
		expect(overflowIssue(r)).toBeNil()
		-- the compact form won, and the label was NOT cut to get there
		expect(r.rects.label.compact).toBe(true)
		expect(r.rects.label.textFacts.truncated).toBe(false)
		-- ...and without the compact form the same row has to truncate instead
		local bare = solve({
			kind = "hstack",
			id = "R",
			width = fill(),
			children = {
				{ kind = "box", id = "rigid", width = fixed(340), height = fixed(20) },
				{ kind = "text", id = "label", text = "Configuration", shrinkWeight = 1 },
			},
		}, 400, 400)
		expect(bare.rects.label.textFacts.truncated).toBe(true)
	end)

	it("THE CLOSED SEAM: the row RESERVES the cross extent a squeezed text will need", function()
		-- THIS WAS A PIN ON A DEFECT UNTIL 2026-08-12, under the name "A NAMED SEAM";
		-- it is now the pin that keeps the defect closed, the same inversion
		-- `scroll_window_clip.spec.luau` got when its recorded defect was repaired.
		--
		-- What it recorded: the stack's own height was measured with the label on ONE
		-- line, because the measure pass sized children against the FULL offer while
		-- the shrink pass was an arrange-time negotiation only. Squeezed to its floor
		-- the label wrapped to eight lines and the row was still 20px tall, so the
		-- extra lines painted outside on the CROSS axis — the "painted at a size
		-- nobody measured" family (docs/lessons/measure-the-requirement-not-the-
		-- render.md), and exactly the seam a `fill` child had before the measure pass
		-- grew its own second pass for it (solver PASS 2).
		--
		-- The repair is PASS 1.5 in the solver's stack MEASURE branch: the same
		-- `shrinkStack` negotiation, run against the offer the measure pass was
		-- handed, with the shrunk children re-measured at their reduced offer so the
		-- reported cross extent is the wrapped one. So a `fill`-width row that will
		-- squeeze a label now RESERVES the wrap it is about to cause.
		--
		-- THE RIGID SIBLING SHRANK FROM 390 TO 300 (director ruling 1, 2026-08-13).
		-- At 390 the deficit is more than the longest-word floor can absorb, so the
		-- cascade now descends to the ellipsis rung and the label comes out ONE line
		-- — which is the ruling working, and which would leave this seam untested.
		-- At 300 the deficit stops inside the first rung, the label is squeezed to a
		-- width it CAN still wrap into, and the seam is exercised exactly as before.
		local r = solve({
			kind = "hstack",
			id = "R",
			width = fill(),
			children = {
				{ kind = "box", id = "rigid", width = fixed(300), height = fixed(20) },
				{ kind = "text", id = "label", text = "aa bb cc dd ee ff gg hh", shrinkWeight = 1 },
			},
		}, 400, 400)
		-- the label is squeezed to what the row had left…
		expect(r.rects.label.rect.w).toBe(100)
		-- …and it WRAPPED into that, and the row is as tall as the wrap it caused
		expect(r.rects.label.rect.h).toBe(58)
		expect(r.rects.R.rect.h).toBe(58)
		-- the oracle, so the wrap is not asserted into existence: the same string
		-- measured on its own at the width the label is actually painted at
		local oracle = solve({
			kind = "hstack",
			id = "O",
			width = fill(),
			children = { { kind = "text", id = "t", text = "aa bb cc dd ee ff gg hh", width = fixed(100) } },
		}, 400, 400)
		expect(r.rects.label.rect.h).toBe(oracle.rects.t.rect.h)
		expect(oracle.rects.t.rect.h > 20).toBe(true)
	end)

	it("...and the measure-side pass is INERT: the same row without a weight is unmoved", function()
		-- The other half of "additive and inert", on the measure path this time. The
		-- identical row that declared nothing still reports the ONE-LINE height it
		-- always did and still overflows its box — PASS 1.5 has no members, absorbs
		-- nothing, and reserves nothing.
		local r = solve({
			kind = "hstack",
			id = "R",
			width = fill(),
			children = {
				{ kind = "box", id = "rigid", width = fixed(390), height = fixed(20) },
				{ kind = "text", id = "label", text = "aa bb cc dd ee ff gg hh" },
			},
		}, 400, 400)
		expect(r.rects.label.rect.h).toBe(20)
		expect(r.rects.R.rect.h).toBe(20)
		expect(overflowIssue(r) ~= nil).toBe(true)
	end)

	it("...and the REPORT moves with the RESERVATION: a `content` row fits what it shrank into", function()
		-- The half of PASS 1.5 that is not about the cross axis, and it is what keeps
		-- the two passes from disagreeing a second time. A row that re-measured its
		-- squeezed child but still REPORTED its natural main extent would hand an
		-- uncapped (`content`) parent the pre-shrink width, be arranged at THAT width,
		-- find no deficit there, and paint a one-line label inside the two-line box
		-- this pass had just reserved for it. Reporting the shrunk extent is what
		-- makes measure a fixed point: offer the report back and the same arrangement
		-- comes out.
		--
		-- THE PARENT HAS TO BE AN HSTACK — the report has to be consumed as a MAIN
		-- extent to be observable at all. Under a `vstack` the row's width is the
		-- parent's CROSS axis, which clamps it to the parent's inner width either way
		-- and swallows the difference; a first version of this test did exactly that
		-- and the mutation survived it, the same trap the re-measure test above
		-- records for the cross axis.
		local r = solve({
			kind = "hstack",
			id = "Outer",
			width = fixed(400),
			children = {
				{
					kind = "hstack",
					id = "R",
					width = { type = "content" },
					children = {
						{ kind = "box", id = "rigid", width = fixed(200), height = fixed(20) },
						{ kind = "text", id = "label", text = "aa bb cc dd ee ff gg hh", shrinkWeight = 1 },
					},
				},
			},
		}, 600, 600)
		-- 200 + 229 natural = 429 against a 400 offer: the label gives up 29px, the
		-- row reports the 400 it shrank into rather than the 429 it started from…
		expect(r.rects.R.rect.w).toBe(400)
		expect(r.rects.label.rect.w).toBe(200)
		-- …the two-line box it reserved is the box it is painted in…
		expect(r.rects.label.rect.h).toBe(39)
		expect(r.rects.R.rect.h).toBe(39)
		-- …and nothing paints outside the parent: reporting 429 would have overflowed
		-- `Outer` by exactly 29px with a one-line label inside a two-line box
		expect(overflowIssue(r)).toBeNil()
	end)

	it("...and the shrunk text is RE-MEASURED at the reduced offer, so its box covers its wraps", function()
		-- THE CACHE-KEY OBLIGATION'S BITING CASE (round-2 plan §2.4). The plan's claim
		-- is that the shrink pass only ever varies the OFFER, so `maxW`/`maxH` already
		-- key it and the measure memo needs no new term. A claim is not a check: this
		-- is the case that FAILS when the pass reuses the natural measurement instead
		-- of re-measuring at the reduced offer.
		--
		-- The row declares a real cross extent on purpose. Squeezed against a row that
		-- hugs, the taller box is clamped straight back to the row's own height and the
		-- mutation survives — which is exactly what a first version of this test did.
		local function row(weight: number?)
			return solve({
				kind = "hstack",
				id = "R",
				width = fill(),
				height = fixed(200),
				children = {
					{ kind = "box", id = "rigid", width = fixed(200), height = fixed(20) },
					{ kind = "text", id = "label", text = "aa bb cc dd ee ff gg hh", shrinkWeight = weight },
				},
			}, 400, 400)
		end
		local natural = row(nil).rects.label.rect
		local shrunk = row(1).rects.label.rect
		expect(natural.w).toBe(229)
		expect(natural.h).toBe(20)
		-- one line at its natural width, two once it is squeezed — and the reserved
		-- box is the two-line box, not the one-line box it was first measured at
		expect(shrunk.w).toBe(200)
		expect(shrunk.h).toBe(39)
	end)

	it("the measure MEMO tells the two offers apart — the cache key already covers the pass", function()
		-- The other half of the cache-key obligation. The memo is gated on
		-- `ctx.hasScroll` (a tree with no scroll region never touches it), so the
		-- re-measure above runs UNCACHED and cannot prove the key is wide enough. Put
		-- the same row under a ScrollView and the memo is live: if the key did not
		-- carry the offer, the shrink pass's second measure would replay the natural
		-- one-line answer it cached at the full width.
		local r = solve({
			kind = "scroll",
			id = "Host",
			width = fill(),
			height = fill(),
			children = {
				{
					kind = "hstack",
					id = "R",
					width = fill(),
					height = fixed(200),
					children = {
						{ kind = "box", id = "rigid", width = fixed(200), height = fixed(20) },
						{
							kind = "text",
							id = "label",
							text = "aa bb cc dd ee ff gg hh",
							shrinkWeight = 1,
						},
					},
				},
			},
		}, 400, 400)
		expect(r.rects.label.rect.w).toBe(200)
		expect(r.rects.label.rect.h).toBe(39)
	end)

	it("...and the MEASURE-side pass is keyed by the memo too, at the same key", function()
		-- THE CACHE-KEY CLAIM RE-VERIFIED FOR PASS 1.5, which is a DIFFERENT claim
		-- from the arrange-side one above: §2.4 argued the shrink pass "only ever
		-- varies the OFFER", and the measure-side mirror re-measures a squeezed child
		-- from INSIDE `measure` itself, where the memo lives. Same trap as above and
		-- the same instrument: the memo is gated on `ctx.hasScroll`, so the closed-seam
		-- case up in the floor-stack block runs UNCACHED and cannot prove anything
		-- about the key. Under a ScrollView the memo is live, and if the key did not
		-- carry `maxW` the re-measure at the squeezed width would be served the
		-- one-line answer cached at the full width — the row would report 20px again
		-- and the seam would reopen with a green suite.
		local r = solve({
			kind = "scroll",
			id = "Host",
			width = fill(),
			height = fill(),
			children = {
				{
					kind = "hstack",
					id = "R",
					width = fill(),
					children = {
						-- 300, not 390, for the reason the closed-seam case above states:
						-- past the first rung the cascade reaches the ellipsis floor and
						-- the label stops wrapping, which is what this case must observe
						{ kind = "box", id = "rigid", width = fixed(300), height = fixed(20) },
						{
							kind = "text",
							id = "label",
							text = "aa bb cc dd ee ff gg hh",
							shrinkWeight = 1,
						},
					},
				},
			},
		}, 400, 400)
		expect(r.rects.label.rect.w).toBe(100)
		expect(r.rects.label.rect.h).toBe(58)
		expect(r.rects.R.rect.h).toBe(58)
	end)

	it("with no floor left the row fits exactly and nothing overflows", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			children = {
				{ kind = "box", id = "a", width = fixed(400), height = fixed(20), shrinkWeight = 1 },
				{ kind = "box", id = "b", width = fixed(400), height = fixed(20), shrinkWeight = 1 },
			},
		}, 100, 100)
		expect(table.concat(ws(r, { "a", "b" }), ",")).toBe("50,50")
		expect(overflowIssue(r)).toBeNil()
	end)
end)

describe("§2.4 shrink — when everything is at its floor the diagnostic still fires", function()
	it("the overflow diagnostic names the priority order the pass tried", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			children = {
				{
					kind = "box",
					id = "a",
					width = { type = "minMax", min = 180, preferred = 200 },
					height = fixed(20),
					shrinkWeight = 1,
				},
				{
					kind = "box",
					id = "b",
					width = { type = "minMax", min = 180, preferred = 200 },
					height = fixed(20),
					shrinkWeight = 1,
					layoutPriority = 2,
				},
			},
		}, 300, 100)
		local issue = overflowIssue(r)
		expect(issue ~= nil).toBe(true)
		-- 400 -> 360 is all the pass could take; 60px still overflows
		expect(string.find(issue :: string, "by 60px", 1, true) ~= nil).toBe(true)
		expect(string.find(issue :: string, "layoutPriority", 1, true) ~= nil).toBe(true)
		expect(string.find(issue :: string, "0, 2", 1, true) ~= nil).toBe(true)
		-- ...AND THE BOX CLIPPED THE REST (director ruling 1, 2026-08-13). An
		-- authored `minMax.min` is a contract, so the cascade may not descend below
		-- it and the 60px is genuinely unabsorbable — which is precisely where clip
		-- is the floor: `b` is placed where the flow put it (x = 180) and CROPPED at
		-- the box edge instead of painting 60px past it.
		expect(string.find(issue :: string, "CLIPPED the remaining 60px", 1, true) ~= nil).toBe(true)
		expect(table.concat(ws(r, { "a", "b" }), ",")).toBe("180,120")
		for _, id in { "a", "b" } do
			local rect = r.rects[id].rect
			expect(`{id} ends at {rect.x + rect.w}`).toBe(`{id} ends at {math.min(rect.x + rect.w, 300)}`)
		end
	end)

	it("a row that never opted in gets NO priority suffix (today's message, unchanged)", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			children = {
				{ kind = "box", id = "a", width = fixed(400), height = fixed(20) },
				{ kind = "box", id = "b", width = fixed(400), height = fixed(20) },
			},
		}, 500, 100)
		expect(string.find(overflowIssue(r) :: string, "layoutPriority", 1, true)).toBeNil()
	end)
end)

describe("§2.4 shrink — composition with the rest of the algebra", function()
	it("a CONTENT-sized nested stack shrinks like any other once it declares a weight", function()
		-- deliberately `content` and not `hug`: a `hug` child is already capped at
		-- the room its siblings left it (the second measure pass above), so it is
		-- structurally incapable of producing the deficit this pass exists for
		local r = solve({
			kind = "hstack",
			id = "R",
			width = fill(),
			children = {
				{
					kind = "hstack",
					id = "group",
					shrinkWeight = 1,
					children = { { kind = "box", id = "inner", width = fixed(300), height = fixed(20) } },
				},
				{ kind = "box", id = "b", width = fixed(300), height = fixed(20) },
			},
		}, 400, 100)
		expect(r.rects.group.rect.w).toBe(100)
	end)

	it("freed space goes to a `fill` sibling rather than becoming slack", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			children = {
				{ kind = "box", id = "rigid", width = fixed(600), height = fixed(20), shrinkWeight = 1 },
				{ kind = "box", id = "flex", width = fill(), height = fixed(20) },
			},
		}, 500, 100)
		-- the fill child measured 0 while the row overflowed; the shrink hands the
		-- row back to exactly its own width and the fill child stays at 0
		expect(r.rects.rigid.rect.w).toBe(500)
		expect(r.rects.flex.rect.w).toBe(0)
		expect(overflowIssue(r)).toBeNil()
	end)

	it("margins are not shrinkable: the deficit comes out of the child's own extent", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			children = {
				{
					kind = "box",
					id = "a",
					width = fixed(200),
					height = fixed(20),
					margin = 20,
					shrinkWeight = 1,
				},
				{ kind = "box", id = "b", width = fixed(200), height = fixed(20), shrinkWeight = 1 },
			},
		}, 340, 100)
		-- 200 + 40 margin + 200 = 440 against 340 -> deficit 100, split by basis 1:1
		expect(table.concat(ws(r, { "a", "b" }), ",")).toBe("150,150")
		expect(r.rects.a.rect.x).toBe(20)
	end)
end)

-- ===========================================================================
-- §2.1 lineAlign
-- ===========================================================================

describe("§2.1 lineAlign — per-child cross-axis alignment", function()
	local function row(childProps: { [string]: any }): any
		return {
			kind = "hstack",
			id = "R",
			children = {
				{ kind = "box", id = "tall", width = fixed(50), height = fixed(100) },
				(function()
					local c: any = { kind = "box", id = "short", width = fixed(50), height = fixed(20) }
					for k, v in childProps do
						c[k] = v
					end
					return c
				end)(),
			},
		}
	end

	it("without it a short child sits at the start of the line (today)", function()
		expect(solve(row({}), 300, 100).rects.short.rect.y).toBe(0)
	end)

	it("`center` centres just that child in the line", function()
		local r = solve(row({ lineAlign = "center" }), 300, 100)
		expect(r.rects.short.rect.y).toBe(40)
		expect(r.rects.tall.rect.y).toBe(0)
	end)

	it("`end` pins it to the far edge of the line", function()
		expect(solve(row({ lineAlign = "end" }), 300, 100).rects.short.rect.y).toBe(80)
	end)

	it("`stretch` fills the line, exactly as the container word does", function()
		local r = solve(row({ lineAlign = "stretch" }), 300, 100)
		expect(r.rects.short.rect.h).toBe(100)
	end)

	it("it beats the container's own `align`", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			align = "center",
			children = {
				{ kind = "box", id = "tall", width = fixed(50), height = fixed(100) },
				{ kind = "box", id = "short", width = fixed(50), height = fixed(20), lineAlign = "end" },
			},
		}, 300, 100)
		expect(r.rects.short.rect.y).toBe(80)
	end)

	it("it beats a nested stack's own `align`, which now means ONLY 'align my children'", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			children = {
				{ kind = "box", id = "tall", width = fixed(50), height = fixed(100) },
				{
					kind = "vstack",
					id = "nested",
					align = "center",
					lineAlign = "end",
					width = fixed(80),
					children = { { kind = "box", id = "pip", width = fixed(20), height = fixed(20) } },
				},
			},
		}, 300, 100)
		-- the nested stack sits at the BOTTOM of the row (lineAlign)…
		expect(r.rects.nested.rect.y).toBe(80)
		-- …while its own child is still CENTRED inside it (align)
		expect(r.rects.pip.rect.x).toBe(80)
	end)

	it("it works on a LEAF, which `align` never could — the ItemLineAlignment gap", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			children = {
				{ kind = "box", id = "tall", width = fixed(50), height = fixed(100) },
				{ kind = "text", id = "label", text = "hi", lineAlign = "center" },
			},
		}, 300, 100)
		local h = r.rects.label.rect.h
		expect(r.rects.label.rect.y).toBe(math.floor((100 - h) / 2))
	end)

	it("a VERTICAL stack aligns on X", function()
		local r = solve({
			kind = "vstack",
			id = "C",
			children = {
				{ kind = "box", id = "wide", width = fixed(100), height = fixed(20) },
				{ kind = "box", id = "narrow", width = fixed(20), height = fixed(20), lineAlign = "end" },
			},
		}, 100, 200)
		expect(r.rects.narrow.rect.x).toBe(80)
	end)
end)

-- ===========================================================================
-- the public surface: strict schema, real props, live diagnostics
-- ===========================================================================

local function render(screen: any, w: number, h: number): (any, any)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local root = mountLib.mount(core, screen)
	local adapter = fake_target.new()
	local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return adapter, controller
end

local function diagnosticsText(controller: any): string
	local parts = {}
	for _, d in controller.diagnostics() do
		table.insert(parts, `{d.node}: {d.issue}`)
	end
	return table.concat(parts, " | ")
end

describe("the props are public, strict, and reach the solver", function()
	it("`distribute` on a real HStack moves the real rects", function()
		local adapter, controller = render(
			UI.Screen({
				id = "S",
				children = {
					UI.HStack({
						id = "Bar",
						width = fill(),
						distribute = "spaceBetween",
						children = {
							UI.Box({ id = "l", width = fixed(100), height = fixed(20) }),
							UI.Box({ id = "r", width = fixed(100), height = fixed(20) }),
						},
					}),
				},
			}),
			600,
			200
		)
		expect(adapter.node("/S/Bar/l").rect.x).toBe(0)
		expect(adapter.node("/S/Bar/r").rect.x).toBe(500)
		expect(diagnosticsText(controller)).toBe("")
	end)

	it("`distribute` is accepted on Screen, VStack, HStack and AdaptiveStack — and nowhere else", function()
		for _, ctor in { "Screen", "VStack", "HStack", "AdaptiveStack" } do
			expect(pcall(function()
				(UI :: any)[ctor]({ id = "X", distribute = "center", children = {} })
			end)).toBe(true)
		end
		expect(pcall(function()
			UI.ZStack({ id = "X", distribute = "center", children = {} })
		end)).toBe(false)
		expect(pcall(function()
			UI.Grid({ id = "X", distribute = "center", children = {} })
		end)).toBe(false)
	end)

	it("a `distribute` outside the closed set is refused at construction", function()
		expect(pcall(function()
			UI.HStack({ id = "X", distribute = "spaceBetweeen", children = {} })
		end)).toBe(false)
	end)

	it("`shrinkWeight`, `layoutPriority` and `lineAlign` are shared box props", function()
		expect(pcall(function()
			UI.Text({ id = "T", text = "x", shrinkWeight = 1, layoutPriority = -1, lineAlign = "center" })
		end)).toBe(true)
		expect(pcall(function()
			UI.Box({ id = "B", shrinkWeight = 2 })
		end)).toBe(true)
		expect(pcall(function()
			UI.Box({ id = "B", shrinkWeight = "lots" })
		end)).toBe(false)
		expect(pcall(function()
			UI.Box({ id = "B", lineAlign = "middle" })
		end)).toBe(false)
	end)

	it("a real overflowing row shrinks and the solver stops complaining", function()
		local function bar(weight: number?)
			return UI.Screen({
				id = "S",
				children = {
					UI.HStack({
						id = "Row",
						children = {
							UI.Box({ id = "a", width = fixed(200), height = fixed(20), shrinkWeight = weight }),
							UI.Box({ id = "b", width = fixed(200), height = fixed(20), shrinkWeight = weight }),
						},
					}),
				},
			})
		end
		local _, before = render(bar(nil), 300, 200)
		expect(string.find(diagnosticsText(before), "content overflows", 1, true) ~= nil).toBe(true)

		local adapter, after = render(bar(1), 300, 200)
		expect(diagnosticsText(after)).toBe("")
		expect(adapter.node("/S/Row/a").rect.w).toBe(150)
		expect(adapter.node("/S/Row/b").rect.w).toBe(150)
	end)

	it("`lineAlign` on a real Text child aligns it in its row", function()
		local adapter, controller = render(
			UI.Screen({
				id = "S",
				children = {
					UI.HStack({
						id = "Row",
						children = {
							UI.Box({ id = "tall", width = fixed(50), height = fixed(100) }),
							UI.Text({ id = "cap", text = "hi", lineAlign = "end" }),
						},
					}),
				},
			}),
			400,
			200
		)
		local tall = adapter.node("/S/Row/tall").rect
		local cap = adapter.node("/S/Row/cap").rect
		expect(cap.y + cap.h).toBe(tall.y + tall.h)
		expect(diagnosticsText(controller)).toBe("")
	end)
end)

-- ===========================================================================
-- §2.4 the shrink pass's COST — the two Milestone-1 review findings (C5, C6)
-- ===========================================================================
--
-- Both are work eliminations on the solver's hot path, and neither changes a
-- single rect: that is exactly what makes them dangerous to check. A behavioural
-- assertion cannot tell the fixed code from the broken code, because the broken
-- code produced the right answer expensively — so the cases below are in two
-- deliberately different registers, and the file says which is which:
--
--   STRUCTURAL — the guard is read out of `src/layout/solver.luau` and pinned by
--   POSITION, the shape `tests/instance_park_corpse.spec.luau` established. It is
--   directional: reverting either finding reddens it. That is the only instrument
--   available for "this allocation no longer happens", because Lune's
--   `collectgarbage` rejects "collect"/"count" and a `gcinfo()` delta over this
--   workload measured -2191 KB to +624 KB run to run — noise an order of magnitude
--   larger than the thing being measured.
--
--   BEHAVIOURAL — the INVARIANCE the eliminations must preserve, which is where
--   the real risk lives: a guard that is too eager silently disables the shrink
--   pass, and no existing case here would notice for the stack shapes below.
local solverSource = fs.readFile("src/layout/solver.luau")

describe("§2.4 shrink — C5/C6: the pass costs nothing until it has a member", function()
	it("STRUCTURAL C5: arrange scans for a member BEFORE allocating `shrunk` and `basisMain`", function()
		local guardAt = string.find(solverSource, "\tif hasShrink then\n\t\tlocal absorbed\n\t\tshrunk = {}", 1, true)
		expect(`the arrange shrink block is entered on hasShrink: {guardAt ~= nil}`).toBe(
			"the arrange shrink block is entered on hasShrink: true"
		)
		-- ...and the scan that sets it is on the OVERFLOW path only, so a stack that
		-- fits pays nothing for the new test either
		local scanAt = string.find(
			solverSource,
			"\tlocal hasShrink = false\n\tif availMain < 0 then\n\t\tfor _, child in children do",
			1,
			true
		)
		expect(`the membership scan is gated on availMain: {scanAt ~= nil}`).toBe(
			"the membership scan is gated on availMain: true"
		)
		expect(`scan precedes guard: {scanAt ~= nil and guardAt ~= nil and (scanAt :: number) < (guardAt :: number)}`).toBe(
			"scan precedes guard: true"
		)
		-- DIRECTIONAL: the pre-fix line is `if availMain < 0 then` immediately in
		-- front of `shrunk = {}`, so restoring it reddens this case rather than
		-- passing it
		expect(string.find(solverSource, "\tif availMain < 0 then\n\t\tlocal absorbed", 1, true) == nil).toBe(true)
	end)

	it("STRUCTURAL C6: measure's PASS 1 allocates a basis only for a weight ABOVE zero", function()
		expect(
			string.find(solverSource, "if child.shrinkWeight ~= nil and child.shrinkWeight > 0 then", 1, true) ~= nil
		).toBe(true)
		-- DIRECTIONAL, same shape: the pre-fix gate was the bare nil test, and
		-- `shrinkWeight = 0` is a legal authored value meaning "never shrink"
		expect(string.find(solverSource, "if child.shrinkWeight ~= nil then", 1, true) == nil).toBe(true)
		-- and the same filter really is what the pass applies one level down
		expect(string.find(solverSource, "and weight > 0", 1, true) ~= nil).toBe(true)
	end)

	it("BEHAVIOURAL: an explicit `shrinkWeight = 0` is byte-identical to omitting it", function()
		local function row(withZero: boolean)
			return solve({
				kind = "hstack",
				id = "R",
				children = {
					{
						kind = "box",
						id = "a",
						width = fixed(300),
						height = fixed(20),
						shrinkWeight = if withZero then 0 else nil,
					},
					{
						kind = "box",
						id = "b",
						width = fixed(300),
						height = fixed(20),
						shrinkWeight = if withZero then 0 else nil,
					},
				},
			}, 500, 100)
		end
		local absent, zero = row(false), row(true)
		expect(table.concat(ws(zero, { "a", "b" }), ",")).toBe(table.concat(ws(absent, { "a", "b" }), ","))
		expect(table.concat(xs(zero, { "a", "b" }), ",")).toBe(table.concat(xs(absent, { "a", "b" }), ","))
		-- ...including the diagnostic, whose floor-order suffix is the one thing the
		-- shrink pass adds to it
		expect(tostring(overflowIssue(zero))).toBe(tostring(overflowIssue(absent)))
	end)

	it("BEHAVIOURAL: the hoisted guard does NOT disable the pass — a real member still shrinks", function()
		local r = solve({
			kind = "hstack",
			id = "R",
			children = {
				{ kind = "box", id = "a", width = fixed(300), height = fixed(20), shrinkWeight = 0 },
				{ kind = "box", id = "b", width = fixed(300), height = fixed(20), shrinkWeight = 2 },
			},
		}, 500, 100)
		-- the zero is a non-member and keeps every pixel; the weighted one absorbs
		-- the whole 100px deficit
		expect(table.concat(ws(r, { "a", "b" }), ",")).toBe("300,200")
		expect(overflowIssue(r)).toBeNil()
	end)

	it("BEHAVIOURAL: an overflow with no member still diagnoses, and WITHOUT the floor suffix", function()
		local none = solve({
			kind = "hstack",
			id = "R",
			children = {
				{ kind = "box", id = "a", width = fixed(400), height = fixed(20), shrinkWeight = 0 },
				{ kind = "box", id = "b", width = fixed(400), height = fixed(20) },
			},
		}, 500, 100)
		expect(overflowIssue(none)).toBe(
			"content overflows this hstack by 300px on the main axis; it will paint outside its box "
				.. "(wrap it in a ScrollView, or give it room)"
		)
		-- ...while a stack whose members are ALL at their floor still gets it, which
		-- is the half a too-eager guard would delete
		local floored = solve({
			kind = "hstack",
			id = "R",
			children = {
				{
					kind = "box",
					id = "a",
					width = { type = "minMax", min = 400, preferred = 400, max = 400 },
					height = fixed(20),
					shrinkWeight = 1,
				},
				{
					kind = "box",
					id = "b",
					width = { type = "minMax", min = 400, preferred = 400, max = 400 },
					height = fixed(20),
					shrinkWeight = 1,
				},
			},
		}, 500, 100)
		expect(string.find(tostring(overflowIssue(floored)), "already at its floor", 1, true) ~= nil).toBe(true)
	end)
end)
