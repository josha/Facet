--!strict
--[[
	FLOW-WRAP (docs/plans/swiftui-parity-round3.md, item A).

	`UI.HStack{ wrap = true }` / `UI.VStack{ wrap = true }` — Roblox's
	`UIListLayout.Wraps`, which Facet had no spelling for at all. One PROP, one
	new arrange branch, and NO new alignment vocabulary: the cross-axis rule was
	measured live in Studio on 2026-08-13 and it is `align` for the block of lines
	and `lineAlign` for an item inside its line — the two words Facet already
	ships. SwiftUI has no flow layout to be parity with ([SW-10]-shaped absence,
	verified 2026-08-13); the gap being closed is the NATIVE one.

	WHAT EACH BLOCK WOULD CATCH, because a table of rects proves nothing alone:

	  · "the partition is pure"        -> a partition that reads the tree, the ctx
	    or the clock, i.e. one a fuzz cannot drive and two passes can disagree on.
	  · "measure and arrange share it" -> the file's four-times-fixed defect class:
	    a container that measured one shape and arranged another.
	  · "the block sits where Roblox puts it" -> the numbers in these three cases
	    are the LIVE STUDIO PROBE's (300x400 box, six 100x40 items): Top 0/40,
	    Center 160/200, Bottom 320/360. A branch that invented its own cross-axis
	    rule reddens here rather than shipping a divergence.
	  · "a line is as tall as its tallest item" -> the ragged case, y = 90 not 40.
	  · "an over-wide item"            -> silently painting past the line, or
	    silently swallowing the fact.
	  · "the lines overflow the box"   -> the direction a wrapping stack can run
	    out of room is its CROSS axis, where no diagnostic looked before.
	  · "`stretch` is refused"         -> one word meaning both "a child fills its
	    line" and "the lines fill the container".
	  · "the audit learned the kind"   -> `auditPlacement` returns nil for an
	    unknown kind and polices NOTHING, so every placement prop on a wrapping
	    stack's children would be accepted-and-ignored (constitution §4).
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local solver = require("../src/layout/solver")
local UI = require("../src/blueprint")
local schema = require("../src/blueprint_schema")
local customFactory = require("../src/core/custom")
local environment = require("../src/env/environment")
local mountLib = require("../src/mount")
local rendererLib = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")
local Facet = require("../src") :: any

local function fixed(px: number): any
	return { type = "fixed", px = px }
end
local function fill(): any
	return { type = "fill", weight = 1 }
end

local function solve(root: any, w: number, h: number): any
	return solver.solve(root, { w = w, h = h }, { rootPolicy = "edgeToEdge" })
end

local function box(result: any, id: string): string
	local r = result.rects[id]
	if r == nil then
		return `{id}: MISSING`
	end
	return `{id}: {r.rect.x},{r.rect.y} {r.rect.w}x{r.rect.h}`
end

local function issues(result: any): string
	local parts = {}
	for _, d in result.diagnostics do
		table.insert(parts, `{d.node}: {d.issue}`)
	end
	return table.concat(parts, " | ")
end

local function cell(id: string, w: number, h: number, extra: { [string]: any }?): any
	local node: any = { kind = "box", id = id, width = fixed(w), height = fixed(h) }
	for k, v in extra or {} do
		node[k] = v
	end
	return node
end

-- six 100x40 plates — the live Studio probe's own fixture
local function sixPlates(extra: { [string]: any }?): any
	local node: any = { kind = "hwrap", id = "W", width = fixed(300), height = fixed(400), gap = 0, children = {} }
	for i = 1, 6 do
		table.insert(node.children, cell(`p{i}`, 100, 40))
	end
	for k, v in extra or {} do
		node[k] = v
	end
	return node
end

-- "first..last @main" per line, so a failure prints the whole partition
local function partitionOf(mains: { number }, innerMain: number, gap: number): string
	local parts = {}
	for _, line in solver.flowPartition(mains, innerMain, gap) do
		table.insert(parts, `{line.first}..{line.last}@{line.main}`)
	end
	return table.concat(parts, " ")
end

-- ===========================================================================
-- 1. THE PARTITION IS A PURE FUNCTION
-- ===========================================================================
describe("flow-wrap: the line partition is pure, and greedy", function()
	it("packs greedily against the offer, gaps counted only BETWEEN items", function()
		-- 100 + 10 + 100 + 10 + 100 = 320 <= 350; the fourth would need 430
		expect(partitionOf({ 100, 100, 100, 100 }, 350, 10)).toBe("1..3@320 4..4@100")
		-- with no gap the same offer takes three and no more (400 > 350)
		expect(partitionOf({ 100, 100, 100, 100 }, 350, 0)).toBe("1..3@300 4..4@100")
	end)

	it("an item WIDER than the line still gets a line — of its own", function()
		expect(partitionOf({ 50, 400, 50 }, 200, 0)).toBe("1..1@50 2..2@400 3..3@50")
	end)

	it("an UNBOUNDED offer is one line: a partition of infinity is not a wrap", function()
		expect(partitionOf({ 100, 100, 100 }, math.huge, 10)).toBe("1..3@320")
	end)

	it("no children is no lines", function()
		expect(partitionOf({}, 300, 8)).toBe("")
	end)

	it("fuzz: every child lands in exactly one line, in order, and only a lone item may overflow", function()
		-- a seeded LCG rather than `math.random`, so the case a failure names is
		-- reproducible from this file alone and cannot be moved by another spec
		local seed = 20260813
		local function nextInt(lo: number, hi: number): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return lo + seed % (hi - lo + 1)
		end
		for _ = 1, 400 do
			local mains: { number } = {}
			for _ = 1, nextInt(1, 12) do
				table.insert(mains, nextInt(1, 220))
			end
			local innerMain = nextInt(10, 300)
			local gap = nextInt(0, 16)
			local lines = solver.flowPartition(mains, innerMain, gap)
			local expected = 1
			for _, line in lines do
				if line.first ~= expected then
					error(`partition skipped or repeated an index at line {line.first} (expected {expected})`)
				end
				if line.last < line.first then
					error("partition produced an EMPTY line")
				end
				-- the recomputed extent must equal the reported one...
				local recomputed = 0
				for i = line.first, line.last do
					recomputed += mains[i] + (if i > line.first then gap else 0)
				end
				if recomputed ~= line.main then
					error(`line {line.first}..{line.last} reported {line.main}, is really {recomputed}`)
				end
				-- ...and only a SINGLE item is ever allowed past the offer
				if recomputed > innerMain and line.last > line.first then
					error(
						`line {line.first}..{line.last} overflows {innerMain} with {line.last - line.first + 1} items`
					)
				end
				expected = line.last + 1
			end
			if expected ~= #mains + 1 then
				error(`partition dropped children: stopped at {expected - 1} of {#mains}`)
			end
		end
	end)
end)

-- ===========================================================================
-- 2. MEASURE
-- ===========================================================================
describe("flow-wrap: what a wrapping stack REPORTS", function()
	it("content = (widest line) x (sum of line extents + a gap between lines)", function()
		-- hugging root: what it hugs to IS the measure's answer
		local r = solve({
			kind = "vstack",
			id = "Root",
			width = fill(),
			height = fill(),
			children = {
				{
					kind = "hwrap",
					id = "W",
					gap = 10,
					children = { cell("a", 90, 20), cell("b", 90, 30), cell("c", 90, 25) },
				},
			},
		}, 200, 400)
		-- 90 + 10 + 90 = 190 <= 200; c starts line 2. Widest line = 190; lines are
		-- 30 (max(20,30)) and 25, plus one 10px gap between them = 65
		expect(box(r, "W")).toBe("W: 0,0 190x65")
		expect(issues(r)).toBe("")
	end)

	it("a line's cross extent is its TALLEST item, not the first one's", function()
		local r = solve({
			kind = "vstack",
			id = "Root",
			width = fill(),
			height = fill(),
			children = {
				{
					kind = "hwrap",
					id = "W",
					gap = 0,
					children = { cell("a", 100, 40), cell("b", 100, 90), cell("c", 100, 40), cell("d", 100, 40) },
				},
			},
		}, 300, 400)
		-- three per line; line 1 is 90 tall (b), line 2 is 40 -> 130
		expect(box(r, "W")).toBe("W: 0,0 300x130")
	end)
end)

-- ===========================================================================
-- 3. ARRANGE — the live Studio probe, reproduced
-- ===========================================================================
describe("flow-wrap: the cross-axis rule Roblox actually has (probed 2026-08-13)", function()
	it("Top (the default): the block of lines packs at the start", function()
		local r = solve(sixPlates(), 300, 400)
		expect(box(r, "p1")).toBe("p1: 0,0 100x40")
		expect(box(r, "p3")).toBe("p3: 200,0 100x40")
		expect(box(r, "p4")).toBe("p4: 0,40 100x40")
		expect(box(r, "p6")).toBe("p6: 200,40 100x40")
		expect(issues(r)).toBe("")
	end)

	it("Center: the BLOCK is centred — (400-80)/2 = 160 exactly, not per line", function()
		local r = solve(sixPlates({ align = "center" }), 300, 400)
		expect(box(r, "p1")).toBe("p1: 0,160 100x40")
		expect(box(r, "p4")).toBe("p4: 0,200 100x40")
	end)

	it("End: the block sits at 400-80 = 320, again exactly", function()
		local r = solve(sixPlates({ align = "end" }), 300, 400)
		expect(box(r, "p1")).toBe("p1: 0,320 100x40")
		expect(box(r, "p4")).toBe("p4: 0,360 100x40")
	end)

	it("ragged: line 2 starts at the TALLEST item of line 1 (90), never at 40", function()
		local node = sixPlates()
		node.children[2] = cell("p2", 100, 90)
		local r = solve(node, 300, 400)
		expect(box(r, "p4")).toBe("p4: 0,90 100x40")
	end)

	it("a vertical wrap wraps into COLUMNS: same rule, axes swapped", function()
		local node: any = {
			kind = "vwrap",
			id = "W",
			width = fixed(400),
			height = fixed(300),
			gap = 0,
			children = {},
		}
		for i = 1, 6 do
			table.insert(node.children, cell(`p{i}`, 40, 100))
		end
		local r = solve(node, 400, 300)
		expect(box(r, "p3")).toBe("p3: 0,200 40x100")
		expect(box(r, "p4")).toBe("p4: 40,0 40x100")
	end)
end)

describe("flow-wrap: the vocabulary it INHERITS rather than invents", function()
	it("`lineAlign` places one item inside its own line (Roblox ItemLineAlignment)", function()
		local node = sixPlates()
		node.children[2] = cell("p2", 100, 90)
		node.children[1] = cell("p1", 100, 40, { lineAlign = "end" })
		local r = solve(node, 300, 400)
		-- line 1 is 90 tall; p1 is 40 and pinned to the line's end
		expect(box(r, "p1")).toBe("p1: 0,50 100x40")
		-- ...while its untouched neighbour keeps the line's start
		expect(box(r, "p3")).toBe("p3: 200,0 100x40")
	end)

	it("`lineAlign = 'stretch'` fills the LINE, and only the line", function()
		local node = sixPlates()
		node.children[2] = cell("p2", 100, 90)
		node.children[1] = cell("p1", 100, 40, { lineAlign = "stretch" })
		local r = solve(node, 300, 400)
		expect(box(r, "p1")).toBe("p1: 0,0 100x90")
	end)

	it("`distribute` spreads the leftover WITHIN each line, per line", function()
		-- 300px lines holding 2x100 = 100 of slack; the last line holds ONE item
		local node: any = {
			kind = "hwrap",
			id = "W",
			width = fixed(300),
			height = fixed(400),
			gap = 0,
			distribute = "spaceBetween",
			children = { cell("a", 100, 40), cell("b", 100, 40), cell("c", 100, 40), cell("d", 100, 40) },
		}
		local r = solve(node, 300, 400)
		-- line 1: three at 100 fills it exactly, nothing to spread
		expect(box(r, "a")).toBe("a: 0,0 100x40")
		expect(box(r, "c")).toBe("c: 200,0 100x40")
		-- line 2: one item, 200 of slack, spaceBetween pins it at the start (CSS)
		expect(box(r, "d")).toBe("d: 0,40 100x40")
	end)

	it("...and `distribute = 'center'` centres each line's own content", function()
		local node: any = {
			kind = "hwrap",
			id = "W",
			width = fixed(300),
			height = fixed(400),
			gap = 0,
			distribute = "center",
			children = { cell("a", 100, 40), cell("b", 100, 40), cell("c", 100, 40), cell("d", 100, 40) },
		}
		local r = solve(node, 300, 400)
		expect(box(r, "d")).toBe("d: 100,40 100x40")
	end)
end)

-- ===========================================================================
-- 4. MEASURE AND ARRANGE SHARE ONE PARTITION
-- ===========================================================================
describe("flow-wrap: measure and arrange cannot disagree about the lines", function()
	it("the hug parent's box is exactly the box the children were placed in", function()
		local r = solve({
			kind = "vstack",
			id = "Root",
			width = fill(),
			height = fill(),
			children = {
				{
					kind = "hwrap",
					id = "W",
					gap = 6,
					children = {
						cell("a", 80, 20),
						cell("b", 80, 44),
						cell("c", 80, 20),
						cell("d", 80, 20),
						cell("e", 80, 20),
					},
				},
			},
		}, 260, 400)
		-- 80+6+80+6+80 = 252 <= 260 -> three, then two. Lines 44 and 20 + 6 = 70
		expect(box(r, "W")).toBe("W: 0,0 252x70")
		-- and the LAST child sits inside that reported box rather than past it
		expect(box(r, "e")).toBe("e: 86,50 80x20")
		expect(issues(r)).toBe("")
	end)

	-- THE CASE THAT MAKES THE CACHE KEY LOAD-BEARING, and it took a mutation to
	-- find. Every other fixture in this file measures a wrapping stack at the box it
	-- is then arranged in, so dropping the box from `flowPlan`'s key changed nothing
	-- and "the plan is keyed by the box" was an assertion nothing tested.
	--
	-- A stack's SHRINK pass is the cheapest place the two genuinely differ: a
	-- wrapping stack that opts into `shrinkWeight` under a short parent is measured
	-- once at the full offer, squeezed, re-measured at the reduced one, and then
	-- arranged at the reduced one. Three questions, two different boxes, one node —
	-- so a plan cached without the box in its key answers the first question three
	-- times, reports one line, and paints four items side by side out of a box a
	-- quarter as wide.
	it("the plan is keyed by the BOX: a SHRUNK wrapping stack re-breaks its lines", function()
		local r = solve({
			kind = "hstack",
			id = "Root",
			width = fill(),
			height = fill(),
			children = {
				cell("rigid", 300, 20),
				{
					kind = "hwrap",
					id = "W",
					gap = 0,
					shrinkWeight = 1,
					children = { cell("a", 100, 40), cell("b", 100, 40), cell("c", 100, 40), cell("d", 100, 40) },
				},
			},
		}, 400, 400)
		-- 700 of content in 400: `W` gives up 300 and is left with 100, which is one
		-- tag per line, four lines
		expect(box(r, "W")).toBe("W: 300,0 100x160")
		expect(box(r, "a")).toBe("a: 300,0 100x40")
		expect(box(r, "d")).toBe("d: 300,120 100x40")
		expect(issues(r)).toBe("")
	end)
end)

-- ===========================================================================
-- 5. THE TWO SUB-RULES, AND THE CROSS-AXIS OVERFLOW
-- ===========================================================================
describe("flow-wrap: an item wider than its line", function()
	it("gets its own line, is CLAMPED to the line, and the solver says so", function()
		local r = solve({
			kind = "hwrap",
			id = "W",
			width = fixed(200),
			height = fixed(400),
			gap = 0,
			children = { cell("a", 50, 20), cell("wide", 400, 20), cell("b", 50, 20) },
		}, 200, 400)
		expect(box(r, "a")).toBe("a: 0,0 50x20")
		expect(box(r, "wide")).toBe("wide: 0,20 200x20")
		expect(box(r, "b")).toBe("b: 0,40 50x20")
		local text = issues(r)
		expect(string.find(text, "200px wider than this hwrap's line", 1, true) ~= nil).toBe(true)
		-- the always-on sweep greps for this phrase; a message without it is a
		-- finding no fixture will ever fail on
		expect(string.find(text, "on the main axis", 1, true) ~= nil).toBe(true)
	end)
end)

describe("flow-wrap: the lines can overflow the CROSS axis, and that is now visible", function()
	it("more lines than fit reports on the cross axis, with the pixel count", function()
		local node = sixPlates()
		node.height = fixed(60) -- two 40px lines in 60px
		local r = solve(node, 300, 400)
		local text = issues(r)
		expect(string.find(text, "overflow this hwrap by 20px on the cross axis", 1, true) ~= nil).toBe(true)
	end)

	it("...and a stack whose lines DO fit says nothing at all", function()
		expect(issues(solve(sixPlates(), 300, 400))).toBe("")
	end)
end)

describe("flow-wrap: `align = 'stretch'` is refused, not quietly reinterpreted", function()
	it("a LITERAL stretch on a wrapping stack is a construction error naming both readings", function()
		local ok, err = pcall(function()
			UI.HStack({ id = "W", wrap = true, align = "stretch" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "lineAlign", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "stretch", 1, true) ~= nil).toBe(true)
	end)

	it("...and a non-wrapping stack keeps it, exactly as it always had", function()
		local ok = pcall(function()
			UI.HStack({ id = "W", align = "stretch" })
		end)
		expect(ok).toBe(true)
	end)

	it("a stretch that only a SOLVE can see is refused there, and treated as start", function()
		local node = sixPlates({ align = "stretch" })
		local r = solve(node, 300, 400)
		expect(string.find(issues(r), 'align = "stretch" has two readings', 1, true) ~= nil).toBe(true)
		-- treated as `start`: the block packs at 0 and no child grew to the box
		expect(box(r, "p1")).toBe("p1: 0,0 100x40")
	end)
end)

describe("flow-wrap: a `fill` child on the main axis", function()
	it("takes a whole line to itself, and is named rather than ignored", function()
		local r = solve({
			kind = "hwrap",
			id = "W",
			width = fixed(300),
			height = fixed(400),
			gap = 0,
			children = { cell("a", 100, 20), { kind = "box", id = "f", width = fill(), height = fixed(20) } },
		}, 300, 400)
		expect(box(r, "f")).toBe("f: 0,20 300x20")
		expect(string.find(issues(r), "takes a whole line to itself", 1, true) ~= nil).toBe(true)
	end)
end)

-- ===========================================================================
-- 6. THE PLACEMENT AUDIT LEARNED THE KIND
-- ===========================================================================
describe("flow-wrap: the placement-prop audit polices a wrapping stack", function()
	-- WHICH PROPS WERE FLAGGED, not the prose. Every message OPENS with the
	-- offending prop in backticks and then goes on to name the ones that DO work
	-- there, so a substring search over the whole string finds `lineAlign` in the
	-- advice for `alignH` and calls it a flag. The opening token is the verdict.
	local function flagged(kind: string, child: any): string
		local found = solver.auditPlacement(kind, "W", { child })
		if found == nil then
			return "NOTHING POLICED"
		end
		local parts = {}
		for _, f in found do
			table.insert(parts, string.match(f.issue, "^`(%a+)`") or `UNPARSEABLE: {f.issue}`)
		end
		table.sort(parts)
		return table.concat(parts, ",")
	end
	local function auditOf(kind: string, child: any): string
		local found = solver.auditPlacement(kind, "W", { child })
		if found == nil then
			return "NOTHING POLICED"
		end
		local parts = {}
		for _, f in found do
			table.insert(parts, `{f.node}: {f.issue}`)
		end
		return table.concat(parts, " | ")
	end

	it("an unknown kind polices NOTHING — which is why the row has to exist", function()
		expect(auditOf("hwrapp", cell("c", 10, 10, { alignH = "end", placementProps = true }))).toBe("NOTHING POLICED")
	end)

	-- ONE CHILD CARRYING BOTH WORDS IS THE ONLY HONEST DISCRIMINATOR. A child
	-- carrying only `lineAlign` produces no findings under a wrapping stack AND no
	-- findings under a kind the table has never heard of — the two answers a nil
	-- return conflates, and the exact reason this row had to be added. Pairing the
	-- read word with an unread one asks both questions at once: the unread word
	-- MUST be flagged (so the kind is policed at all) and the read word must NOT be
	-- (so it is genuinely read).
	it("`lineAlign` IS read by a wrapping stack; `alignH` beside it is NOT", function()
		for _, kind in { "hwrap", "vwrap" } do
			local child = cell("c", 10, 10, { lineAlign = "end", alignH = "end", placementProps = true })
			expect(`{kind}: {flagged(kind, child)}`).toBe(`{kind}: alignH`)
			-- ...and the message carries the way out, not only the prohibition
			local advice = auditOf(kind, child)
			expect(`{kind} names the wrap: {string.find(advice, "wrapping", 1, true) ~= nil}`).toBe(
				`{kind} names the wrap: true`
			)
			expect(`{kind} names lineAlign: {string.find(advice, "lineAlign", 1, true) ~= nil}`).toBe(
				`{kind} names lineAlign: true`
			)
		end
	end)

	it("the SHRINK PAIR is refused: wrapping IS the answer to a main-axis deficit", function()
		for _, prop in { "layoutPriority", "shrinkWeight" } do
			local child = cell("c", 10, 10, { [prop] = 1, placementProps = true })
			expect(`vwrap: {flagged("vwrap", child)}`).toBe(`vwrap: {prop}`)
			expect(string.find(auditOf("vwrap", child), "wraps instead", 1, true) ~= nil).toBe(true)
		end
	end)

	it("...and a NON-wrapping stack still reads the shrink pair, unmoved", function()
		-- the pairing trick: `alignH` must still be flagged on an `hstack`, so the
		-- silence about `shrinkWeight` is a READ rather than an unpoliced kind
		local child = cell("c", 10, 10, { shrinkWeight = 1, alignH = "end", placementProps = true })
		expect(flagged("hstack", child)).toBe("alignH")
	end)
end)

-- ===========================================================================
-- 7. THE PUBLIC SURFACE
-- ===========================================================================
describe("flow-wrap: the prop, through the authoring surface", function()
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

	it("`wrap` is declared on VStack and HStack, reactive, and dirties measure", function()
		for _, class in { "VStack", "HStack" } do
			local spec = (schema.forClass(class) :: any).props.wrap
			expect(`{class}.wrap declared: {spec ~= nil}`).toBe(`{class}.wrap declared: true`)
			expect(spec.types[1]).toBe("boolean")
			expect(spec.reactive).toBe(true)
			expect(spec.dirty[1]).toBe("measure")
		end
	end)

	it("...and NOWHERE else: a `wrap` a solver branch would never read is refused", function()
		for _, class in { "ZStack", "Grid", "ScrollView", "Screen", "AdaptiveStack", "Anchor" } do
			expect(`{class}.wrap: {(schema.forClass(class) :: any).props.wrap ~= nil}`).toBe(`{class}.wrap: false`)
		end
		local ok = pcall(function()
			UI.ZStack({ id = "Z", wrap = true } :: any)
		end)
		expect(ok).toBe(false)
	end)

	it("a non-boolean `wrap` is a construction error", function()
		local ok = pcall(function()
			UI.HStack({ id = "W", wrap = "yes" } :: any)
		end)
		expect(ok).toBe(false)
	end)

	it("`UI.HStack{ wrap = true }` wraps for real, through mount + render", function()
		local adapter = render(
			UI.Screen({
				id = "S",
				width = fixed(300) :: any,
				children = {
					UI.HStack({
						id = "W",
						wrap = true,
						gap = 0,
						children = {
							UI.Box({ id = "a", width = fixed(100) :: any, height = fixed(40) :: any }),
							UI.Box({ id = "b", width = fixed(100) :: any, height = fixed(40) :: any }),
							UI.Box({ id = "c", width = fixed(100) :: any, height = fixed(40) :: any }),
							UI.Box({ id = "d", width = fixed(100) :: any, height = fixed(40) :: any }),
						},
					}),
				},
			}),
			300,
			400
		)
		local d = adapter.node("/S/W/d")
		expect(d ~= nil).toBe(true)
		expect(`{d.rect.x},{d.rect.y}`).toBe("0,40")
	end)

	it("...and the SAME stack without `wrap` still runs off its own box, unmoved", function()
		local adapter, controller = render(
			UI.Screen({
				id = "S",
				width = fixed(300) :: any,
				children = {
					UI.HStack({
						id = "W",
						gap = 0,
						children = {
							UI.Box({ id = "a", width = fixed(100) :: any, height = fixed(40) :: any }),
							UI.Box({ id = "b", width = fixed(100) :: any, height = fixed(40) :: any }),
							UI.Box({ id = "c", width = fixed(100) :: any, height = fixed(40) :: any }),
							UI.Box({ id = "d", width = fixed(100) :: any, height = fixed(40) :: any }),
						},
					}),
				},
			}),
			300,
			400
		)
		local d = adapter.node("/S/W/d")
		expect(`{d.rect.x},{d.rect.y}`).toBe("300,0")
		local text = {}
		for _, f in controller.diagnostics() do
			table.insert(text, f.issue)
		end
		expect(string.find(table.concat(text, " | "), "on the main axis", 1, true) ~= nil).toBe(true)
	end)

	it("a BOUND `wrap` flips in place: the same stack, re-solved, never remounted", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 300, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local wrapping = core:signal(false)
		local screen = UI.Screen({
			id = "S",
			width = fixed(300) :: any,
			children = {
				UI.HStack({
					id = "W",
					wrap = wrapping :: any,
					gap = 0,
					children = {
						UI.Box({ id = "a", width = fixed(100) :: any, height = fixed(40) :: any }),
						UI.Box({ id = "b", width = fixed(100) :: any, height = fixed(40) :: any }),
						UI.Box({ id = "c", width = fixed(100) :: any, height = fixed(40) :: any }),
						UI.Box({ id = "d", width = fixed(100) :: any, height = fixed(40) :: any }),
					},
				}),
			},
		})
		local root = mountLib.mount(core, screen)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local before = adapter.node("/S/W/d")
		local identity = tostring(before)
		expect(`{before.rect.x},{before.rect.y}`).toBe("300,0")
		wrapping:set(true)
		controller.refresh()
		local after = adapter.node("/S/W/d")
		expect(`{after.rect.x},{after.rect.y}`).toBe("0,40")
		-- the node is the same node: a flip is a re-solve, never a remount
		expect(tostring(after)).toBe(identity)
	end)
end)

-- ===========================================================================
-- 8. THE DELIBERATE NON-GOAL
-- ===========================================================================
describe("flow-wrap: it does NOT compose with newVirtualList, and that is refused", function()
	local function listSpec(extra: { [string]: any }?): (any, any)
		local core = customFactory.new()
		local spec: any = {
			id = "L",
			rows = core:signal({}),
			itemExtent = 40,
			viewportExtent = 200,
			key = function(row: any): string
				return tostring(row.id)
			end,
			cell = function()
				return UI.Box({ id = "c" })
			end,
		}
		for k, v in extra or {} do
			spec[k] = v
		end
		return core, spec
	end

	it("the same list WITHOUT `wrap` builds, so the refusal below is about the word", function()
		local core, spec = listSpec()
		local ok, err = pcall(function()
			Facet.newVirtualList(Facet, core, spec)
		end)
		expect(`built: {ok} {tostring(err)}`).toBe("built: true nil")
	end)

	it("`newVirtualList{ wrap = true }` is refused: the spec is CLOSED", function()
		local core, spec = listSpec({ wrap = true })
		local ok, err = pcall(function()
			Facet.newVirtualList(Facet, core, spec)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "wrap", 1, true) ~= nil).toBe(true)
	end)
end)

-- ===========================================================================
-- 9. THE SHOWCASE SURFACE, UNDER EVERY SHIPPED THEME
-- ===========================================================================
--
-- STUDIO NEUTRAL IS NOT EVIDENCE ON ITS OWN. It reserves no chrome, so a control
-- measured only there has slack no shipped package gives it — and Pixel Quest and
-- Parchment have each broken a layout Neutral survived. A wrapping row is exactly
-- the shape that class of defect lands on: a package with a wider control face
-- puts fewer tags on a line, more lines in the block, and a taller block in the
-- same box.
describe("flow-wrap: the gallery surface holds under every shipped package", function()
	-- the packages are BUILT through the PUBLIC facade (`Facet.themes`), which is
	-- what a reference package's `build` expects, and RESOLVED through the snapshot
	-- compiler — the same pair `tests/compact_label.spec.luau` uses
	local snapshot = require("../src/themes/snapshot") :: any
	local scenario = require("../examples/gallery/scenarios/flow_wrap") :: any

	-- the eight shipped reference packages plus the flat theme = the nine
	-- configurations every geometry claim in this repo is measured against
	local PACKAGES = {
		"glossy_mobile",
		"glossy_touch",
		"pixel_quest",
		"fantasy_ornate",
		"scifi_hud",
		"compact_pointer",
		"classic_desktop",
		"fantasy_parchment",
	}
	-- the narrowest supported viewport in both orientations plus a desktop: a
	-- wrapping row's failure mode is width, and landscape-only defects are how the
	-- 2026-08-12 round's B5 survived a portrait capture set
	local VIEWS = { { w = 320, h = 640 }, { w = 640, h = 320 }, { w = 1232, h = 1067 } }

	local function mountUnder(pkgName: string?, view: any): (any, any)
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		if pkgName ~= nil then
			env:set(
				"themeMetrics",
				snapshot.resolve((require)(`../examples/themes/{pkgName}`).build(Facet.themes), nil, {})
			)
		end
		local built = scenario.build({
			Facet = Facet,
			core = core,
			env = env,
			actionSystem = system,
			presenter = pres,
		})
		built.handle = pres.present(built.screen, built.present)
		for _ = 1, 3 do
			pres.refresh()
		end
		return { adapter = adapter, core = core }, built
	end

	local function report(built: any): string
		local parts = {}
		for _, f in built.handle.controller.diagnostics() do
			table.insert(parts, `{f.node}: {f.issue}`)
		end
		return table.concat(parts, " | ")
	end

	it("no diagnostic, in any package, at any of the three viewports", function()
		local problems: { string } = {}
		for _, pkgName in { false, table.unpack(PACKAGES) } do
			for _, view in VIEWS do
				local name = if pkgName == false then "flat" else tostring(pkgName)
				local w, built = mountUnder(if pkgName == false then nil else tostring(pkgName), view)
				local text = report(built)
				if text ~= "" then
					table.insert(problems, `  {name} at {view.w}x{view.h}: {text}`)
				end
				expect(w.core:lastError()).toBeNil()
				built.dispose()
			end
		end
		if #problems > 0 then
			error(
				`flow_wrap reports diagnostics under {#problems} package/viewport pair(s):\n`
					.. table.concat(problems, "\n"),
				0
			)
		end
	end)

	it("...and no two tags ever overlap, in any package, at any viewport", function()
		for _, pkgName in { false, table.unpack(PACKAGES) } do
			for _, view in VIEWS do
				local name = if pkgName == false then "flat" else tostring(pkgName)
				local w, built = mountUnder(if pkgName == false then nil else tostring(pkgName), view)
				local placed: { any } = {}
				for i = 1, scenario.tagCount do
					local node = w.adapter.node(`/FlowWrap/Page/Cloud/T{i}`)
					if node == nil or node.rect == nil then
						error(`{name} at {view.w}x{view.h}: tag {i} was never placed`, 0)
					end
					local r = node.rect
					for _, other in placed do
						if
							r.x < other.r.x + other.r.w
							and other.r.x < r.x + r.w
							and r.y < other.r.y + other.r.h
							and other.r.y < r.y + r.h
						then
							error(
								`{name} at {view.w}x{view.h}: tag {i} [{r.x},{r.y} {r.w}x{r.h}] overlaps `
									.. `tag {other.i} [{other.r.x},{other.r.y} {other.r.w}x{other.r.h}]`,
								0
							)
						end
					end
					table.insert(placed, { i = i, r = r })
				end
				built.dispose()
			end
		end
	end)

	it("a WIDER package really does re-break the lines — the sweep is not vacuous", function()
		-- the discriminator for the sweep above: if every package produced the same
		-- line count, the eight extra mounts would be proving nothing. Pixel Quest's
		-- control face is wider than the flat theme's, so at 320px it fits fewer
		-- tags per line.
		local function lineCount(pkgName: string?): number
			local w, built = mountUnder(pkgName, { w = 320, h = 640 })
			local seen: { [number]: boolean } = {}
			local n = 0
			for i = 1, scenario.tagCount do
				local y = w.adapter.node(`/FlowWrap/Page/Cloud/T{i}`).rect.y
				if seen[y] == nil then
					seen[y] = true
					n += 1
				end
			end
			built.dispose()
			return n
		end
		local flat = lineCount(nil)
		local pixel = lineCount("pixel_quest")
		expect(`flat {flat} < pixel_quest {pixel}: {flat < pixel}`).toBe(`flat {flat} < pixel_quest {pixel}: true`)
	end)
end)
