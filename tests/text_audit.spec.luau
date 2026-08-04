--!strict
-- LARGE-TEXT AUTHORING SAFETY (docs/plans/large-text-accessibility.md
-- "Diagnostics and authoring safety"; decision LTN-4). Two halves:
--
--   1. the SOLVE now reports what it truncated — per text node: the font
--      descriptor and px size it measured with, the natural and drawn line
--      counts, the truncation verdict, whether the author declared `disclose`,
--      and the resulting overflow policy — and the layout dump carries it;
--   2. src/layout/text_audit turns those facts (plus rects and viewports) into
--      ordered findings that name the node, the contract and the likely fix.
--
-- EVERY CHECK GETS A NEGATIVE CONTROL. A check that cannot be made to stop
-- firing is not evidence of anything: each violation below is constructed, seen
-- to fire, then DECLARED or FIXED and seen to go silent.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local environment = require("../src/env/environment")
local mountLib = require("../src/mount")
local renderer = require("../src/render/renderer")
local fake_target = require("../tests/lib/fake_target")
local solver = require("../src/layout/solver")
local dump = require("../src/layout/dump")
local audit = require("../src/layout/text_audit")

local LONG_NAME = "Bartholomewwwwwwwwwwwwwwwwww" -- one word, far wider than a 120px cell
local LONG_PHRASE = "a much longer phrase that will certainly wrap several times over"

local function render(children: { any })
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
	local root = mountLib.mount(core, UI.Screen({ id = "S", children = children }))
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {})
	controller.initialRender()
	return controller, core
end

local function cell(id: string, text: any, extra: any?): any
	local props: any = { id = id, text = text, textSize = 16 }
	for k, v in extra or {} do
		props[k] = v
	end
	return UI.VStack({
		id = id .. "Row",
		width = { type = "fixed", px = 120 },
		height = { type = "fixed", px = 44 },
		children = { UI.Text(props) },
	})
end

local function rect(x: number, y: number, w: number, h: number): any
	return { x = x, y = y, w = w, h = h }
end

describe("LTN-4 text facts: the solve reports what it truncated", function()
	it("a wrapped label capped by lineLimit reports truncated with its natural line count", function()
		local controller = render({ cell("Blurb", LONG_PHRASE, { lineLimit = 1 }) })
		local facts = controller.textAt("/S/BlurbRow/Blurb")
		expect(facts ~= nil).toBe(true)
		expect(facts.truncated).toBe(true)
		expect(facts.lines).toBe(1)
		expect(facts.naturalLines > 1).toBe(true)
		expect(facts.policy).toBe("truncate")
	end)

	it("a single-line label clamped narrower than its string reports truncated (the identity case)", function()
		-- ONE WORD has no legal break, so it is measured and drawn on one line and
		-- the box clamps it: `naturalLines == lines == 1` and the engine ellipsizes
		-- anyway. A `truncated` derived from line counts alone reports "fits" here,
		-- which is exactly the long-display-name case disclosure exists for.
		local controller = render({ cell("Name", LONG_NAME) })
		local facts = controller.textAt("/S/NameRow/Name")
		expect(facts.lines).toBe(1)
		expect(facts.naturalLines).toBe(1)
		expect(facts.truncated).toBe(true)
		expect(facts.policy).toBe("truncate")
	end)

	it("a label that fits reports policy wrap and truncated false", function()
		local controller = render({ cell("Short", "ok") })
		local facts = controller.textAt("/S/ShortRow/Short")
		expect(facts.truncated).toBe(false)
		expect(facts.policy).toBe("wrap")
		expect(facts.font).toBe("BuilderSans#Regular#Normal")
		expect(facts.size).toBe(16)
	end)

	it("the declared disclose permission rides the same channel as the truncation verdict", function()
		local controller = render({ cell("Name", LONG_NAME, { disclose = true }) })
		local facts = controller.textAt("/S/NameRow/Name")
		expect(facts.truncated).toBe(true)
		expect(facts.disclose).toBe(true)
		expect(facts.policy).toBe("truncate+disclose")
	end)

	it("the layout dump is luauui-dump/2 and carries textFacts per text node", function()
		local root: solver.Node = {
			kind = "vstack",
			id = "root",
			width = { type = "fixed", px = 120 },
			children = {
				{ kind = "text", id = "name", text = LONG_PHRASE, textSize = 16, lineLimit = 1, disclose = true },
				{
					kind = "box",
					id = "plate",
					width = { type = "fixed", px = 40 },
					height = { type = "fixed", px = 40 },
				},
			},
		}
		local d = dump.fromSolve(root, { w = 390, h = 844 })
		expect(d.schema).toBe("luauui-dump/2")
		local text = d.tree.children[1]
		expect(text.textFacts.truncated).toBe(true)
		expect(text.textFacts.disclose).toBe(true)
		expect(text.textFacts.policy).toBe("truncate+disclose")
		expect(text.textFacts.naturalLines > text.textFacts.lines).toBe(true)
		-- a node that is not text reports no truncation state at all
		expect(d.tree.children[2].textFacts).toBeNil()
	end)

	it("UI.Text refuses a bound disclose, naming the prop and the rebuild idiom", function()
		local core = customFactory.new()
		local ok, err = pcall(function()
			UI.Text({ id = "N", text = "x", disclose = core:signal(true) })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "disclose") ~= nil).toBe(true)
		expect(string.find(tostring(err), "UI.When", 1, true) ~= nil).toBe(true)
	end)

	it("UI.Text refuses a non-boolean disclose", function()
		local ok, err = pcall(function()
			UI.Text({ id = "N", text = "x", disclose = "yes" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "disclose") ~= nil).toBe(true)
	end)
end)

describe("LTN-4 audit: overlaps", function()
	local function siblings(kind: string?, overflow: string?): { [string]: any }
		return {
			["/S"] = { rect = rect(0, 0, 390, 844), kind = kind or "vstack", overflow = overflow },
			["/S/A"] = { rect = rect(0, 0, 200, 40), kind = "text" },
			["/S/B"] = { rect = rect(0, 20, 200, 40), kind = "text" },
		}
	end

	it("overlapping painted siblings are a finding naming both nodes and the fix", function()
		local found = audit.overlaps(siblings())
		expect(#found).toBe(1)
		expect(found[1].node).toBe("/S/A")
		expect(found[1].other).toBe("/S/B")
		expect(string.find(found[1].contract, "overlap", 1, true) ~= nil).toBe(true)
		expect(string.find(found[1].fix, "intentionalOverlap", 1, true) ~= nil).toBe(true)
		expect(string.find(found[1].detail :: string, "20px", 1, true) ~= nil).toBe(true)
	end)

	it("...and the finding is gone once the parent declares intentionalOverlap", function()
		expect(#audit.overlaps(siblings(nil, "intentionalOverlap"))).toBe(0)
	end)

	it("...or once the caller declares the pair in opts.declaredOverlays", function()
		expect(#audit.overlaps(siblings(), { declaredOverlays = { { a = "/S/A", b = "/S/B" } } })).toBe(0)
		-- either orientation, and a PREFIX rather than an exact path
		expect(#audit.overlaps(siblings(), { declaredOverlays = { { "/S/B", "/S/A" } } })).toBe(0)
		-- ...and a predicate is the same answer written as code
		expect(#audit.overlaps(siblings(), {
			declaredOverlays = function(a: string, b: string)
				return a == "/S/A" and b == "/S/B"
			end,
		})).toBe(0)
		-- a DIFFERENT declared pair does not silence this one
		expect(#audit.overlaps(siblings(), { declaredOverlays = { { a = "/S/A", b = "/S/C" } } })).toBe(1)
	end)

	it("a ZStack's children never fire the overlap check: layering is the job", function()
		expect(#audit.overlaps(siblings("zstack"))).toBe(0)
		expect(#audit.overlaps(siblings("anchor"))).toBe(0)
	end)

	it("a hidden subtree is audited by nobody: the losing candidate's rects are skipped", function()
		local rects = siblings()
		-- the solver marks the candidate ROOT only, so the skip must carry down
		rects["/S/Cand"] = { rect = rect(0, 0, 200, 40), kind = "vstack", hidden = true }
		rects["/S/Cand/Inner"] = { rect = rect(0, 0, 200, 40), kind = "text" }
		rects["/S/Cand/Inner2"] = { rect = rect(0, 10, 200, 40), kind = "text" }
		local found = audit.overlaps(rects)
		expect(#found).toBe(1) -- still only the visible A/B pair
		expect(found[1].node).toBe("/S/A")
	end)

	it("a one-pixel seam is not an overlap at the default epsilon", function()
		local rects = siblings()
		rects["/S/B"] = { rect = rect(0, 39, 200, 40), kind = "text" } -- 1px of shared edge
		expect(#audit.overlaps(rects)).toBe(0)
		expect(#audit.overlaps(rects, { epsilon = 0 })).toBe(1)
	end)

	it("text_audit.overlaps refuses an unknown opts key", function()
		local ok, err = pcall(function()
			audit.overlaps(siblings(), { epsilion = 4 })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "epsilion", 1, true) ~= nil).toBe(true)
	end)
end)

describe("LTN-4 audit: clippedEssential", function()
	local function cut(disclose: boolean): { [string]: any }
		return {
			["/S/Name"] = {
				rect = rect(0, 0, 120, 20),
				kind = "text",
				textFacts = {
					font = "BuilderSans#Regular#Normal",
					size = 16,
					lines = 1,
					naturalLines = 3,
					truncated = true,
					disclose = disclose,
					policy = if disclose then "truncate+disclose" else "truncate",
				},
			},
		}
	end

	it("truncated text with no disclose and no allowlist entry is a finding", function()
		local found = audit.clippedEssential(cut(false))
		expect(#found).toBe(1)
		expect(found[1].node).toBe("/S/Name")
		expect(string.find(found[1].fix, "disclose", 1, true) ~= nil).toBe(true)
		expect(string.find(found[1].detail :: string, "1 of 3 lines", 1, true) ~= nil).toBe(true)
	end)

	it("...gone the moment the node declares disclose", function()
		expect(#audit.clippedEssential(cut(true))).toBe(0)
	end)

	it("...gone when the caller declares it non-essential", function()
		expect(#audit.clippedEssential(cut(false), { nonEssential = { "/S/Name" } })).toBe(0)
		expect(#audit.clippedEssential(cut(false), { nonEssential = { "/S" } })).toBe(0)
		expect(#audit.clippedEssential(cut(false), {
			nonEssential = function(path: string)
				return path == "/S/Name"
			end,
		})).toBe(0)
		-- a neighbouring path is not this one: prefixes compare on the separator
		expect(#audit.clippedEssential(cut(false), { nonEssential = { "/S/Nam" } })).toBe(1)
	end)

	it("a real solve of a truncated undisclosed label produces exactly one clippedEssential finding", function()
		local controller = render({ cell("Name", LONG_NAME), cell("Short", "ok") })
		local rects: { [string]: any } = {}
		for path, facts in controller.textAt() do
			rects[path] = { rect = controller.rectOf(path), kind = "text", textFacts = facts }
		end
		local found = audit.clippedEssential(rects)
		expect(#found).toBe(1)
		expect(found[1].node).toBe("/S/NameRow/Name")
	end)
end)

describe("LTN-4 audit: hitFloor", function()
	local function control(w: number, h: number): { [string]: any }
		return {
			["/S/Go"] = { rect = rect(0, 0, w, h), kind = "box", hitFloor = 44 },
			["/S/Label"] = { rect = rect(0, 60, 20, 20), kind = "text" },
		}
	end

	it("an interactive node painted under its declared floor is a finding", function()
		local found = audit.hitFloor(control(44, 26))
		expect(#found).toBe(1)
		expect(found[1].node).toBe("/S/Go")
		expect(string.find(found[1].detail :: string, "44x26px", 1, true) ~= nil).toBe(true)
		expect(string.find(found[1].fix, "invisible activation surface", 1, true) ~= nil).toBe(true)
	end)

	it("...gone once the box reflows back to the floor", function()
		expect(#audit.hitFloor(control(44, 44))).toBe(0)
	end)

	it("a decorative rect the same size is never a hitFloor finding", function()
		-- /S/Label is 20x20 and carries no declared floor: it is not something the
		-- player is meant to hit, and reporting it would be the noise that makes a
		-- diagnostic ignorable
		local found = audit.hitFloor(control(44, 44), 44)
		expect(#found).toBe(0)
	end)

	it("an explicit floorPx audits every interactive node against one number", function()
		expect(#audit.hitFloor(control(44, 44), 48)).toBe(1)
	end)
end)

describe("LTN-4 audit: movingText", function()
	it("a second moving text surface is a finding at the default maximum of one", function()
		local found = audit.movingText(2)
		expect(#found).toBe(1)
		expect(string.find(found[1].detail :: string, "2 running", 1, true) ~= nil).toBe(true)
	end)

	it("one moving surface (or none) is not", function()
		expect(#audit.movingText(1)).toBe(0)
		expect(#audit.movingText(0)).toBe(0)
		expect(#audit.movingText(3, 3)).toBe(0)
	end)
end)

describe("LTN-4 audit: focusVisibility", function()
	local VIEWPORTS = { { path = "/S/List", rect = rect(0, 100, 300, 200) } }

	it("a focused rect fully outside its clipping viewport is a finding", function()
		local found = audit.focusVisibility({ path = "/S/List/Row9", rect = rect(0, 400, 300, 40) }, VIEWPORTS)
		expect(#found).toBe(1)
		expect(found[1].node).toBe("/S/List/Row9")
		expect(found[1].other).toBe("/S/List")
	end)

	it("...gone once the viewport scrolls it back into view", function()
		local found = audit.focusVisibility({ path = "/S/List/Row9", rect = rect(0, 260, 300, 40) }, VIEWPORTS)
		expect(#found).toBe(0)
	end)

	it("a viewport that does not contain the focused path is never consulted", function()
		-- a sibling scroller clipping nothing of ours is not evidence of anything
		local found = audit.focusVisibility({ path = "/S/Panel/Field", rect = rect(0, 400, 300, 40) }, VIEWPORTS)
		expect(#found).toBe(0)
	end)

	it("nothing focused is nothing to report", function()
		expect(#audit.focusVisibility(nil, VIEWPORTS)).toBe(0)
	end)
end)

describe("LTN-4 audit: findings are ordered and frozen", function()
	it("two runs over equal input produce equal, deterministically ordered findings", function()
		local rects: { [string]: any } = {
			["/S"] = { rect = rect(0, 0, 390, 844), kind = "vstack" },
			["/S/C"] = { rect = rect(0, 0, 200, 40), kind = "text" },
			["/S/A"] = { rect = rect(0, 20, 200, 40), kind = "text" },
			["/S/B"] = { rect = rect(0, 30, 200, 40), kind = "text" },
		}
		local first, second = audit.overlaps(rects), audit.overlaps(rects)
		expect(#first).toBe(3)
		local order = {}
		for i, f in first do
			table.insert(order, `{f.node}|{f.other}`)
			expect(second[i].node).toBe(f.node)
			expect(second[i].other).toBe(f.other)
		end
		expect(table.concat(order, " ")).toBe("/S/A|/S/B /S/A|/S/C /S/B|/S/C")
		expect(table.isfrozen(first)).toBe(true)
		expect(table.isfrozen(first[1])).toBe(true)
	end)
end)

describe("LTN-4 audit: outOfBounds (the declared-bounds check the matrix build found missing)", function()
	-- the live shape that motivated this: a content-sized HStack of two
	-- content-sized Buttons outgrew a 390px phone by ~195px, rendered off the
	-- right edge, and none of the other four checks fired
	local BOUNDS = { x = 0, y = 0, w = 390, h = 844 }

	local function overflowRects(): { [string]: any }
		return {
			["/S"] = { rect = rect(0, 0, 390, 844), kind = "vstack" },
			["/S/Band"] = { rect = rect(16, 100, 560, 48), kind = "hstack" },
			["/S/Band/A"] = { rect = rect(16, 100, 260, 48), kind = "button" },
			["/S/Band/B"] = { rect = rect(284, 100, 292, 48), kind = "button" },
		}
	end

	it("a painted node past the declared bounds is a finding naming the node and the overshoot", function()
		local findings = audit.outOfBounds(overflowRects(), BOUNDS)
		expect(#findings > 0).toBe(true)
		local worst = findings[1]
		expect(worst.check).toBe("outOfBounds")
		expect(string.find(worst.fix, "scroll") ~= nil).toBe(true)
		-- the band AND its escaping child are both named (each is out on its own)
		local named: { [string]: boolean } = {}
		for _, f in findings do
			named[f.node] = true
		end
		expect(named["/S/Band"]).toBe(true)
		expect(named["/S/Band/B"]).toBe(true)
	end)

	it("...and is gone once a declared scroll host owns the escaping subtree", function()
		local findings = audit.outOfBounds(overflowRects(), BOUNDS, { scrollHosts = { "/S/Band" } })
		-- descendants of the host are exempt; the HOST itself must still fit
		local named: { [string]: boolean } = {}
		for _, f in findings do
			named[f.node] = true
		end
		expect(named["/S/Band/B"]).toBeNil()
		expect(named["/S/Band"]).toBe(true)
	end)

	it("a one-pixel overshoot is antialiasing slop, not a finding", function()
		local rects = {
			["/S"] = { rect = rect(0, 0, 390, 844), kind = "vstack" },
			["/S/Edge"] = { rect = rect(0, 0, 391, 40), kind = "text" },
		}
		expect(#audit.outOfBounds(rects, BOUNDS)).toBe(0)
	end)

	it("a hidden losing candidate escapes nobody's bounds", function()
		local rects = overflowRects()
		rects["/S/Band"].hidden = true
		expect(#audit.outOfBounds(rects, BOUNDS)).toBe(0)
	end)

	it("two runs over equal input produce equal, deterministically ordered out-of-bounds findings", function()
		local a = audit.outOfBounds(overflowRects(), BOUNDS)
		local b = audit.outOfBounds(overflowRects(), BOUNDS)
		expect(#a).toBe(#b)
		for i, f in a do
			expect(f.node).toBe(b[i].node)
		end
	end)

	it("text_audit.outOfBounds refuses an unknown opts key", function()
		local ok, err = pcall(function()
			return audit.outOfBounds(overflowRects(), BOUNDS, { epsilonn = 2 })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "epsilonn") ~= nil).toBe(true)
	end)
end)
