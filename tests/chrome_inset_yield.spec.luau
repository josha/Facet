--!strict
-- A CONTROL NARROWER THAN ITS OWN CHROME (director report, 2026-07-28, defect 3:
-- "in glossy touch, all controls, the compact glyph doesn't appear at all.
-- Compact item text is also funky").
--
-- Measured live before the fix. Under Glossy Touch a Button costs:
--
--     buttonPadding   12 + 12   (the library default; the package authors none)
--   + control inset   14 + 14   (the skin's carved border, ADR-0019 §5)
--   = 52px of horizontal chrome
--
-- The scenario's compact buttons are `width = { fixed, px = 52 }`. So the content
-- box was EXACTLY ZERO, and everything downstream was honest about it:
--
--   * the lifted label solved to `AbsoluteSize = 0, 47` and drew nothing -- and
--     the label is not optional decoration, it is the only thing that redraws the
--     button's text above the plate that covers it;
--   * the button with no compact form measured "Edit item" against a ZERO wrap
--     width and drew through a 0px lift, so what reached the screen was a single
--     clipped "E" in a box 85px tall next to its 63px siblings. That is the
--     "funky" in the report.
--
-- Nothing errored. A green suite and a blank control.
--
-- THE RULE: a chrome inset is a REQUEST, not a right. It is spent only if the
-- content box survives it; on a node too small to afford it, it is not spent at
-- all and the author is told. Authored padding is never touched -- that is an
-- explicit instruction and the framework does not get to overrule it.
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local Facet = require("../src") :: any
local customFactory = require("../src/core/custom")
local environment = require("../src/env/environment")
local mountLib = require("../src/mount")
local rendererLib = require("../src/render/renderer")
local chrome_slots = require("../src/tokens/chrome_slots")
local snapshot = require("../src/themes/snapshot")
local fake_target = require("./lib/fake_target")

local PACKAGES = {
	"classic_desktop",
	"compact_pointer",
	"fantasy_ornate",
	"fantasy_parchment",
	"glossy_mobile",
	"glossy_touch",
	"pixel_quest",
	"scifi_hud",
}

local function packageOf(name: string): any
	return (require)(`../examples/themes/{name}`).build(Facet.themes)
end

-- mount one Button at a fixed width and report the rect AND the solver's
-- diagnostics for that solve. `px` is a number for the fixed-width form every
-- case below the first group uses, or a whole DIMENSION table for the
-- ceiling-shape sweep (review finding I3) — the two are the same question asked
-- through two spellings, which is exactly what that finding was about.
local function solveButton(props: any, px: any, pkg: any?): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 400 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	if pkg ~= nil then
		env:set("themeMetrics", snapshot.resolve(pkg, nil, {}))
	end
	local adapter = fake_target.new()
	local spec: any = table.clone(props)
	spec.id = "B"
	spec.width = if type(px) == "table" then px.width else { type = "fixed", px = px }
	if type(px) == "table" and px.height ~= nil then
		spec.height = px.height
	end
	local root = mountLib.mount(core, UI.Screen({ id = "S", padding = 0, children = { UI.Button(spec) } }))
	local controller = rendererLib.attach(core, root, env, adapter, {})
	controller.initialRender()
	local node = adapter.node("/S/B")
	local out = { w = node.rect.w, h = node.rect.h, label = node.props.label, diagnostics = controller.diagnostics() }
	controller.dispose()
	root.dispose()
	return out
end

local function issuesMatching(diagnostics: any, needle: string): { string }
	local hits = {}
	for _, entry in diagnostics or {} do
		if string.find(entry.issue, needle, 1, true) ~= nil then
			table.insert(hits, entry.issue)
		end
	end
	return hits
end

describe("the yield rule is pure arithmetic", function()
	it("an inset the box can afford is spent in full", function()
		-- 52px wide, 24 of authored padding, 20 of chrome: content survives at 8,
		-- so nothing changes. The overwhelming majority of nodes take this path.
		expect(chrome_slots.spendInset(52, 24, 20)).toBe(20)
	end)

	it("an inset that would leave nothing is not spent at all", function()
		-- the report's exact numbers
		expect(chrome_slots.spendInset(52, 24, 28)).toBe(0)
		-- and one pixel past the edge is still past it
		expect(chrome_slots.spendInset(52, 24, 29)).toBe(0)
	end)

	it("the boundary is CONTENT SURVIVES, not content is non-negative", function()
		-- exactly zero content is the defect, not the acceptable edge of it: a
		-- 0px box draws nothing, which is what the report saw.
		expect(chrome_slots.spendInset(52, 24, 28)).toBe(0)
		expect(chrome_slots.spendInset(52, 24, 27)).toBe(27)
	end)

	it("authored padding alone can still collapse a box, and is left alone", function()
		-- the framework does not overrule an explicit instruction. There is no
		-- chrome here to give back, so there is nothing to do but report it.
		expect(chrome_slots.spendInset(52, 60, 0)).toBe(0)
		expect(chrome_slots.spendInset(20, 20, 8)).toBe(0)
	end)

	it("an unbounded axis affords everything", function()
		-- a node free to grow pays its chrome and grows by it; the yield exists
		-- only for a node whose size was decided for it.
		expect(chrome_slots.spendInset(math.huge, 24, 28)).toBe(28)
	end)
end)

describe("a control narrower than its own chrome still draws", function()
	it("no package leaves a fixed-width Button with a zero content box", function()
		-- the invariant, swept across every shipped configuration rather than
		-- pinned to the one package the report happened to name
		for _, name in PACKAGES do
			local pkg = packageOf(name)
			local out = solveButton({ label = "Edit item", compactLabel = "Ed" }, 52, pkg)
			local collapsed = issuesMatching(out.diagnostics, "content box collapses to 0px on x")
			expect(`{name}: {#collapsed} collapse diagnostics`).toBe(`{name}: 0 collapse diagnostics`)
		end
	end)

	it("...and says so, so the author learns the control is too small", function()
		-- repaired is not the same as silent. The condition that forced the yield
		-- is exactly the condition an author needs to know about, and it names the
		-- slot whose numbers could not be afforded.
		local out = solveButton({ label = "Edit item", compactLabel = "Ed" }, 52, packageOf("glossy_touch"))
		local yielded = issuesMatching(out.diagnostics, "chrome contentInsets could not be spent")
		expect(#yielded > 0).toBe(true)
		expect(string.find(yielded[1], "control", 1, true) ~= nil).toBe(true)
	end)

	it("a squeezed label wraps against a real width, never a zero one", function()
		-- Defect 3's second half, stated precisely. `CmpNone` (no compact form)
		-- solved 85px tall beside its 63px siblings, and it is worth being exact
		-- about why: at a ZERO wrap width "Edit item" broke at its space into two
		-- lines, and at the 28px this fix gives it, it breaks at the same space
		-- into the same two lines. The HEIGHT is unchanged. What changed is that
		-- the text is now measured against a box it can actually be drawn in, and
		-- the lifted label that draws it is no longer 0px wide (see the third
		-- group below, which is where the visible defect actually lived).
		--
		-- This is kept as the guard against a real wrap explosion: a squeezed
		-- label can never be taller than the same text in the same box under the
		-- FLAT package, plus the theme's own carved border.
		local flat = solveButton({ label = "Edit item" }, 52, nil)
		for _, name in PACKAGES do
			local pkg = packageOf(name)
			local snap = snapshot.resolve(pkg, nil, {})
			local inset = snap.chromeInsets.control or { top = 0, bottom = 0 }
			local out = solveButton({ label = "Edit item" }, 52, pkg)
			-- the only legitimate vertical difference is the theme's own line
			-- height and its carved border; a wrap explosion is many times that
			local ceiling = flat.h * 2 + inset.top + inset.bottom
			expect(`{name}: h={out.h} ceiling={ceiling} within={out.h <= ceiling}`).toBe(
				`{name}: h={out.h} ceiling={ceiling} within=true`
			)
		end
	end)

	--[[ ...AND THE RULE MAY NOT DEPEND ON HOW THE CEILING WAS SPELLED (task THEME
		fix round, 2026-08-28, review finding I3). The affordability test reads the
		axis's extent, and the extent used to mean "a literal `fixed` px" alone — so
		the SAME 36px control filed two yields spelled `fixed` and NONE spelled
		`minMax{max = 36}`, with a 12px content box holding a 16px glyph and nothing
		anywhere saying so. `max` is a ceiling exactly the way a `fixed` px is: an
		axis that never solves wider than 36 cannot fit a frame 36 cannot fit. The
		third spelling is the one that made it a defect rather than a gap — one axis
		each way, on one control, reporting half the truth.

		Swept over every package rather than pinned to the one that surfaced it, and
		asserted as an EQUALITY between the spellings rather than as a count, so a
		package that legitimately affords the frame contributes a matching zero. ]]
	it("a ceiling spelled `minMax{max}` affords exactly what the same `fixed` px affords", function()
		local SHAPES: { { id: string, dims: any } } = {
			{
				id = "fixed x fixed",
				dims = { width = { type = "fixed", px = 36 }, height = { type = "fixed", px = 36 } },
			},
			{
				id = "minMax x minMax",
				dims = { width = { type = "minMax", max = 36 }, height = { type = "minMax", max = 36 } },
			},
			{
				id = "minMax x fixed",
				dims = { width = { type = "minMax", max = 36 }, height = { type = "fixed", px = 36 } },
			},
		}
		for _, name in PACKAGES do
			local pkg = packageOf(name)
			local baseline: number? = nil
			for _, shape in SHAPES do
				local out = solveButton({ label = "X" }, shape.dims, pkg)
				local yielded = #issuesMatching(out.diagnostics, "chrome contentInsets could not be spent")
				if baseline == nil then
					baseline = yielded
				end
				expect(`{name} / {shape.id}: {yielded}`).toBe(`{name} / {shape.id}: {baseline}`)
			end
		end
	end)

	it("...and an axis with no ceiling at all is still free to grow and pay for it", function()
		-- `minMax` carrying only a `min` is an axis that grows, which is
		-- `math.huge` and the no-op the rule always was. The negative control that
		-- keeps the branch above from becoming "every minMax refuses".
		expect(chrome_slots.spendInset(math.huge, 0, 28, 16)).toBe(28)
		local out = solveButton(
			{ label = "X" },
			{ width = { type = "minMax", min = 4 }, height = { type = "minMax", min = 4 } },
			packageOf("fantasy_ornate")
		)
		expect(#issuesMatching(out.diagnostics, "chrome contentInsets could not be spent")).toBe(0)
	end)

	it("a Button with room pays its chrome exactly as before — nothing that fit moves", function()
		-- the yield must be unreachable for every node that was already correct,
		-- or this "fix" is a geometry change to the whole library.
		for _, name in PACKAGES do
			local pkg = packageOf(name)
			local roomy = solveButton({ label = "Edit item" }, 400, pkg)
			local yielded = issuesMatching(roomy.diagnostics, "could not be spent")
			expect(`{name}: {#yielded}`).toBe(`{name}: 0`)
		end
	end)
end)

describe("the lifted label is never smaller than the text it stands in for", function()
	it("a lift box that would collapse falls back to the host's own content box", function()
		-- the lift exists to redraw the node's text ABOVE the decoration that
		-- covers it. Under Glossy Touch it solved to `{1, -28}` inside a host
		-- whose padded space was 28 -- exactly zero -- while the engine text it
		-- replaced would have drawn at 28px wide. It disagreed with the thing it
		-- is a copy of.
		local box =
			chrome_slots.liftGeometry({ contentInsets = { top = 8, right = 14, bottom = 8, left = 14 } }, 28, 47)
		expect(box.size.xOffset).toBe(0)
		expect(box.position.xOffset).toBe(0)
		expect(box.size.xScale).toBe(1)
	end)

	it("a lift box with room keeps the recipe's insets untouched", function()
		local box =
			chrome_slots.liftGeometry({ contentInsets = { top = 8, right = 14, bottom = 8, left = 14 } }, 200, 60)
		expect(box.size.xOffset).toBe(-28)
		expect(box.position.xOffset).toBe(14)
	end)

	it("with no host box known, the recipe is honoured as before", function()
		-- the create path can reach the lift before the first rect
		local box = chrome_slots.liftGeometry({ contentInsets = { top = 8, right = 14, bottom = 8, left = 14 } })
		expect(box.size.xOffset).toBe(-28)
	end)
end)
