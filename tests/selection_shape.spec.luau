--!strict
--[[ SELECTION SHAPE — what a selected thing LOOKS LIKE, across the picker family
	(user visual review, 2026-09-12). Four findings, one file, because all four
	are the same question asked of four different nodes: what decides the corner
	radius and the silhouette of the thing that says "this one is chosen".

	  * THE SEGMENTED STRIP IS ONE STRIP. It used to be a fully-rounded pill
	    holding fully-rounded segments separated by a gap, so it read as a row of
	    disconnected chips beside a page whose every other box wears the theme's
	    control radius. It is now one track: the theme's control radius on the
	    OUTER ends only, square touching segments inside, and a hairline seam
	    between each pair.
	  * THE FILL TAKES THE SHAPE OF THE SEGMENT IT IS ON. A sliding bar with its
	    own permanent pill cannot sit inside a square middle segment without
	    leaving four slivers of track showing, so the bar's per-corner data
	    follows the SELECTED INDEX, reactively.
	  * A SQUARE THEME GETS A SQUARE SELECTION. `radii.control`, never a
	    hard-coded `"pill"` — so Pixel Quest and Fantasy Ornate draw the
	    selection with the corner they draw every other control with, and a
	    package whose control radius IS a pill still gets one.
	  * A TEN-FOOT ROW IS THE SAME SHAPE WHETHER OR NOT IT IS CHOSEN, and the
	    FOCUSED one lifts by a paint-only 1.05 that moves nothing in the layout
	    and never overlaps its neighbour.

	Everything below reads solved rects and authored props off the fake target;
	nothing reaches into a control's private. The corner assertions read the
	normalized data the paint seam reads (`styling.paintCorners`), because the
	authored number is the NEUTRAL package's and the painted one is the active
	theme's — the two differ, and the second is the one a player sees. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")

local Facet = require("../src") :: any
local worldLib = require("./lib/world")
local snapshot = require("../src/themes/snapshot")
local styling = require("../src/tokens/styling")
local selectionIndicator = require("../src/controls/selection_indicator")

local UI = Facet.UI

-- ===== the harness =========================================================

local function packageMetrics(name: string): any
	local pkg = (require)(`../examples/themes/{name}`).build(Facet.themes)
	return snapshot.resolve(pkg, nil, {})
end

local THREE = {
	{ value = "a", label = "One" },
	{ value = "b", label = "Two" },
	{ value = "c", label = "Tri" },
}

--[[ ONE mounted picker on the SHARED headless substrate (`tests/lib/world.luau`,
	ruling R12: the next spec file that would have added a hand-rolled presenter
	builder migrates onto it instead). `tenFoot` switches the display to the
	distance profile the row-list cases are about; `metrics` installs a theme
	package the way a game does, through the environment. ]]
local function world(options: any?)
	local opts: any = options or {}
	local w = worldLib.new({
		viewport = { x = 0, y = 0, w = opts.viewport or 640, h = 720 },
		safeInsets = { top = 0, bottom = 0, left = 0, right = 0 },
		displaySize = if opts.tenFoot then "Large" else nil,
		capabilities = if opts.tenFoot then { keyboard = false, mouse = false, touch = false, gamepad = true } else nil,
		preferredInput = if opts.tenFoot then "Gamepad" else nil,
		env = if opts.tenFoot then { overscanInsets = "none" } else nil,
		reducedMotion = opts.reducedMotion,
		themeMetrics = opts.metrics,
	})
	local selected = w.core:signal(opts.initial or "a")
	local spec: any = {
		id = "View",
		selected = selected,
		options = opts.options or THREE,
		env = w.env,
		presentation = opts.presentation or "segmented",
	}
	for _, key in { "axis", "indicator", "track", "sizing" } do
		if opts[key] ~= nil then
			spec[key] = opts[key]
		end
	end
	local picker = Facet.Controls.Picker(w.core, spec)
	w.present(UI.Screen({ id = "S", children = { picker.blueprint } }))
	local out: any = w
	out.picker = picker
	out.selected = selected
	return out
end

local function optPath(w: any, n: number): string
	local base = if w.picker.dump().indicator == "none" then "/S/View/Options" else "/S/View/Indicator/Options"
	return `{base}/Opt{n}`
end
local function sepPath(w: any, n: number): string
	return `/S/View/Indicator/Options/Sep{n}`
end
local BAR = "/S/View/Indicator/Layer/Bar"
local TRACK = "/S/View/Indicator/Track"

-- the corner a PAINTER would spend, given the style the target is painting
-- with. `nil` style = the neutral package, which is what an unthemed world
-- draws with.
local function painted(node: any, style: any?): any
	if node == nil then
		return nil
	end
	return styling.paintCorners(node.props.corners, style)
end

local function radii(metrics: any?): any
	local snap = if metrics ~= nil then metrics else snapshot.neutral()
	return snap.radii
end

-- a corner report a failure message can read out loud
local function cornerText(data: any): string
	if data == nil then
		return "none"
	end
	if data.form == "uniform" then
		return `uniform {data.radius}`
	end
	return `tl {data.topLeft} tr {data.topRight} bl {data.bottomLeft} br {data.bottomRight}`
end

-- ===========================================================================
describe("item 2: the segmented strip is ONE strip, not a row of pills", function()
	it("only the outer ends round, and they round with the theme's control radius", function()
		local w = world()
		local control = radii().control
		expect(cornerText(painted(w.adapter.node(optPath(w, 1))))).toBe(`tl {control} tr 0 bl {control} br 0`)
		expect(cornerText(painted(w.adapter.node(optPath(w, 2))))).toBe("tl 0 tr 0 bl 0 br 0")
		expect(cornerText(painted(w.adapter.node(optPath(w, 3))))).toBe(`tl 0 tr {control} bl 0 br {control}`)
	end)

	it("a vertical rail rounds the TOP and BOTTOM ends instead", function()
		local w = world({ axis = "y" })
		local control = radii().control
		expect(cornerText(painted(w.adapter.node(optPath(w, 1))))).toBe(`tl {control} tr {control} bl 0 br 0`)
		expect(cornerText(painted(w.adapter.node(optPath(w, 2))))).toBe("tl 0 tr 0 bl 0 br 0")
		expect(cornerText(painted(w.adapter.node(optPath(w, 3))))).toBe(`tl 0 tr 0 bl {control} br {control}`)
	end)

	it("the segments TOUCH: only the hairline seam sits between them", function()
		local w = world()
		local one = w.adapter.node(optPath(w, 1)).rect
		local sep = w.adapter.node(sepPath(w, 1)).rect
		local two = w.adapter.node(optPath(w, 2)).rect
		expect(sep ~= nil).toBe(true)
		expect(`one ends where the seam starts: {math.abs(one.x + one.w - sep.x) < 0.001}`).toBe(
			"one ends where the seam starts: true"
		)
		expect(`the seam ends where two starts: {math.abs(sep.x + sep.w - two.x) < 0.001}`).toBe(
			"the seam ends where two starts: true"
		)
		-- a hairline, not a gap: the seam is the theme's stroke weight
		expect(sep.w <= 2).toBe(true)
		-- ...and it is inset off the segment's full height
		expect(sep.h < one.h).toBe(true)
	end)

	it("the two seams touching the selection are hidden, and the rest stay drawn", function()
		local w = world({ initial = "b" })
		-- Opt2 is selected: both seams touch it
		expect(w.adapter.node(sepPath(w, 1)).visible).toBe(false)
		expect(w.adapter.node(sepPath(w, 2)).visible).toBe(false)
		w.selected:set("a")
		w.pres.refresh()
		-- Opt1 selected: the seam between 2 and 3 is clear of the chip again
		expect(w.adapter.node(sepPath(w, 1)).visible).toBe(false)
		expect(w.adapter.node(sepPath(w, 2)).visible).never().toBe(false)
	end)

	it("hiding a seam never moves a segment: the layout box stays reserved", function()
		local w = world({ initial = "a" })
		local before = w.adapter.node(optPath(w, 3)).rect.x
		w.selected:set("c")
		w.pres.refresh()
		expect(w.adapter.node(optPath(w, 3)).rect.x).toBe(before)
	end)

	it("the track plate wears the same outer radius as the strip's ends", function()
		local w = world()
		local control = radii().control
		expect(cornerText(painted(w.adapter.node(TRACK)))).toBe(`uniform {control}`)
	end)
end)

-- ===========================================================================
describe("item 2b: the sliding fill takes the shape of the segment it is on", function()
	it("on an end segment the bar rounds that end only", function()
		local w = world({ initial = "a" })
		local control = radii().control
		expect(cornerText(painted(w.adapter.node(BAR)))).toBe(`tl {control} tr 0 bl {control} br 0`)
	end)

	it("...and in the middle it is square, reactively", function()
		local w = world({ initial = "a" })
		w.selected:set("b")
		w.pres.refresh()
		expect(cornerText(painted(w.adapter.node(BAR)))).toBe("tl 0 tr 0 bl 0 br 0")
		w.selected:set("c")
		w.pres.refresh()
		local control = radii().control
		expect(cornerText(painted(w.adapter.node(BAR)))).toBe(`tl 0 tr {control} bl 0 br {control}`)
	end)

	it("a vertical rail's bar follows the same rule on the other axis", function()
		local w = world({ axis = "y", initial = "c" })
		local control = radii().control
		expect(cornerText(painted(w.adapter.node(BAR)))).toBe(`tl 0 tr 0 bl {control} br {control}`)
	end)

	it("a single-segment strip is rounded on both ends, because it IS both ends", function()
		local w = world({ options = { { value = "a", label = "One" } } })
		local control = radii().control
		expect(cornerText(painted(w.adapter.node(BAR)))).toBe(`uniform {control}`)
	end)
end)

-- ===========================================================================
describe("item 6: a square theme gets a square selection", function()
	local PACKAGES = { "pixel_quest", "fantasy_ornate", "glossy_touch" }

	it("the selection's corner is the ACTIVE theme's control radius, in every package", function()
		for _, name in PACKAGES do
			local metrics = packageMetrics(name)
			local w = world({ metrics = metrics, initial = "b" })
			local control = radii(metrics).control
			expect(`{name} bar: {cornerText(painted(w.adapter.node(BAR), metrics))}`).toBe(
				`{name} bar: tl 0 tr 0 bl 0 br 0`
			)
			expect(`{name} track: {cornerText(painted(w.adapter.node(TRACK), metrics))}`).toBe(
				`{name} track: uniform {control}`
			)
			expect(`{name} end segment: {cornerText(painted(w.adapter.node(optPath(w, 1)), metrics))}`).toBe(
				`{name} end segment: tl {control} tr 0 bl {control} br 0`
			)
		end
	end)

	it("the seam's own default is the control radius, not a pill", function()
		expect(selectionIndicator.DEFAULT_CORNER).toBe("control")
	end)

	it("an explicitly authored corner still wins — `corner` stays the caller's", function()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 480, h = 640 } })
		local core = w.core
		local selected = core:signal("a")
		local strip = UI.HStack({
			id = "Strip",
			gap = 0,
			children = {
				UI.Button({ id = "A", label = "A", width = { type = "fixed", px = 80 } }),
				UI.Button({ id = "B", label = "B", width = { type = "fixed", px = 80 } }),
			},
		})
		local ind = selectionIndicator.build(Facet, core, {
			id = "I",
			content = strip,
			segments = { { value = "a", id = "A" }, { value = "b", id = "B" } },
			selected = selected,
			skin = "pill",
			corner = "pill",
			env = w.env,
		})
		w.present(UI.Screen({ id = "S", children = { ind.blueprint } }))
		expect(cornerText(painted(w.adapter.node("/S/I/Layer/Bar")))).toBe(`uniform {radii().pill}`)
		ind.dispose()
	end)
end)

-- ===========================================================================
describe("item 5: the ten-foot row list", function()
	local LIFT = 1.05

	local function rows(w: any): { string }
		local out = {}
		for i = 1, 3 do
			table.insert(out, optPath(w, i))
		end
		return out
	end

	it("a chosen row is the SAME silhouette as an unchosen one", function()
		local w = world({ tenFoot = true, presentation = "inline", initial = "b" })
		local first = painted(w.adapter.node(optPath(w, 1)))
		local chosen = painted(w.adapter.node(optPath(w, 2)))
		expect(first ~= nil).toBe(true)
		expect(cornerText(chosen)).toBe(cornerText(first))
		expect(cornerText(first)).toBe(`uniform {radii().control}`)
	end)

	it("the FOCUSED row lifts by a paint-only 1.05 — and the solved box never moves", function()
		local w = world({ tenFoot = true, presentation = "inline" })
		local target = optPath(w, 2)
		local box = w.adapter.node(target).rect
		w.pres.focus.focusOn(target)
		w.pres.refresh()
		w.settle(240)
		local node = w.adapter.node(target)
		local scale = (node.props.transform or {}).scale or 1
		expect(`scale {math.abs(scale - LIFT) < 0.005} ({scale})`).toBe(`scale true ({scale})`)
		-- the SOLVER never saw it: same box, same place
		expect(`box {node.rect.x},{node.rect.y} {node.rect.w}x{node.rect.h}`).toBe(
			`box {box.x},{box.y} {box.w}x{box.h}`
		)
	end)

	it("...and it ARRIVES, rather than popping: the scale is still short of the lift one frame in", function()
		local w = world({ tenFoot = true, presentation = "inline" })
		local target = optPath(w, 2)
		w.pres.focus.focusOn(target)
		w.pres.refresh()
		w.settle(1)
		local first = (w.adapter.node(target).props.transform or {}).scale or 1
		expect(`one frame in, short of the lift: {first > 1 and first < LIFT}` .. ` ({first})`).toBe(
			`one frame in, short of the lift: true ({first})`
		)
	end)

	it("reduced motion lands the lift on the SAME frame", function()
		local w = world({ tenFoot = true, presentation = "inline", reducedMotion = true })
		local target = optPath(w, 2)
		w.pres.focus.focusOn(target)
		w.pres.refresh()
		w.settle(1)
		local now = (w.adapter.node(target).props.transform or {}).scale or 1
		expect(`reduced lands at once: {math.abs(now - LIFT) < 0.001} ({now})`).toBe(
			`reduced lands at once: true ({now})`
		)
	end)

	it("a NEAR row list never lifts — the treatment belongs to the distance profile", function()
		local w = world({ presentation = "inline" })
		local target = optPath(w, 2)
		w.pres.focus.focusOn(target)
		w.pres.refresh()
		w.settle(60)
		local scale = (w.adapter.node(target).props.transform or {}).scale
		expect(`near list scale: {scale == nil or scale == 1}`).toBe("near list scale: true")
	end)

	it("no row overlaps its neighbour while one is lifted", function()
		local w = world({ tenFoot = true, presentation = "inline" })
		local target = optPath(w, 2)
		w.pres.focus.focusOn(target)
		w.pres.refresh()
		w.settle(240)
		local painted_: { any } = {}
		for _, path in rows(w) do
			local node = w.adapter.node(path)
			table.insert(painted_, node.presentedVisualRect or node.rect)
		end
		for i = 1, #painted_ - 1 do
			local a, b = painted_[i], painted_[i + 1]
			expect(`row {i} clears row {i + 1}: {a.y + a.h <= b.y + 0.001} ({a.y + a.h} vs {b.y})`).toBe(
				`row {i} clears row {i + 1}: true ({a.y + a.h} vs {b.y})`
			)
		end
	end)
end)

-- ===========================================================================
describe("item 10: the level picker speaks the same shape language", function()
	local function lpWorld(spec: any)
		local w = worldLib.new({
			viewport = { x = 0, y = 0, w = 480, h = 640 },
			safeInsets = { top = 0, bottom = 0, left = 0, right = 0 },
		})
		local built: any = table.clone(spec)
		built.env = w.env
		built.value = w.core:signal(spec.value or 2)
		local control = Facet.Controls.LevelPicker(w.core, built)
		w.present(UI.Screen({ id = "S", children = { control.blueprint } }))
		local out: any = w
		out.control = control
		return out
	end

	it("`Controls.LevelPicker` is still here, and still listed in the gallery", function()
		expect(type(Facet.Controls.LevelPicker)).toBe("function")
		-- the scenario index is an ENGINE module (`script:WaitForChild`), so it is
		-- read as text rather than required: the claim is that the name is listed
		local source = fs.readFile("examples/gallery/scenarios/init.luau")
		expect(string.find(source, '"level_picker"', 1, true) ~= nil).toBe(true)
		expect(fs.isFile("examples/gallery/scenarios/level_picker.luau")).toBe(true)
	end)

	it("a bar picker plates a track, and rounds only the run's two ends", function()
		local w = lpWorld({ id = "LP", count = 4 })
		local control = radii().control
		expect(cornerText(painted(w.adapter.node("/S/LP/Track")))).toBe(`uniform {control}`)
		expect(cornerText(painted(w.adapter.node("/S/LP/Levels/Level1")))).toBe(`tl {control} tr 0 bl {control} br 0`)
		expect(cornerText(painted(w.adapter.node("/S/LP/Levels/Level2")))).toBe("tl 0 tr 0 bl 0 br 0")
		expect(cornerText(painted(w.adapter.node("/S/LP/Levels/Level4")))).toBe(`tl 0 tr {control} bl 0 br {control}`)
	end)

	it("a glyph picker plates nothing — a star is a mark, not a segment of a track", function()
		local w = lpWorld({ id = "LP", count = 5, segment = "glyph" })
		expect(w.adapter.node("/S/LP/Track")).toBeNil()
		expect(w.adapter.node("/S/LP/Levels/Level1").props.corners).toBeNil()
	end)
end)
