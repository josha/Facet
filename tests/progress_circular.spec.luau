--!strict
-- THE CIRCULAR PROGRESS INDICATOR, BOTH FORMS (swiftui-parity round 3, item D2).
--
-- `presentation = "circular"` is the one shape in the family that accepts BOTH
-- modes, and both are the SAME function of ONE scalar:
--
--   determinate    arc(0, 360 * fraction)          -- a fixed head, a growing sweep
--   indeterminate  arc(360 * phase, SPIN_SWEEP)    -- a fixed sweep, a travelling head
--
-- Everything here is the consequence of that. `Path.points` is
-- `dirty = { "paint" }, channel = "binding"` and the control owns the binding, so
-- both forms animate for ZERO re-solves — the same instrument tests/path.spec
-- uses (a points change is one prop op and no solves), applied to a control that
-- writes a new arc every frame.
--
-- WHAT THIS FILE IS FOR that display_controls.spec is not: the REFUSAL registry
-- lives there beside the other two shapes' refusals; the GEOMETRY, the paint-only
-- contract, the zero off-path cost and the per-theme stroke-fit invariant live
-- here, because each one is a measurement rather than an authoring rule.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local LuauUI = require("../src") :: any
local UI = require("../src/blueprint")
local environment = require("../src/env/environment")
local presenterLib = require("../src/present/presenter")
local actionsLib = require("../src/input/actions")
local motionClockLib = require("../src/motion/clock")
local fake_target = require("../tests/lib/fake_target")
local progress_view = require("../src/controls/progress_view")
local themes = LuauUI.themes
local device_views = require("./lib/device_views")

local RING = "/S/Load/Ring"
local ARC = RING .. "/Arc"
local TRACK = RING .. "/Track"

local function harness(w: number?, h: number?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = w or 400, h = h or 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local adapter = fake_target.new()
	local system = actionsLib.newSystem(core)
	local pres = presenterLib.new(core, env, adapter, system)
	return core, env, adapter, pres
end

local function clockWorld(policy: string?)
	local core, env, adapter, pres = harness()
	local now = { t = 0 }
	local clock = motionClockLib.new(core, {
		now = function()
			return now.t
		end,
		motionPolicy = core:signal(policy or "full"),
	})
	return core, env, adapter, pres, clock, now
end

-- the angle (screen convention, 0 = up, clockwise) of a point on the ring
local function angleOf(p: any): number
	local a = math.deg(math.atan2(p.x - 0.5, 0.5 - p.y))
	return (a + 360) % 360
end

describe("ProgressView circular: the DETERMINATE ring is the value's own arc", function()
	it("draws an arc over a full backing ring, and no bar at all", function()
		local core, _, adapter, pres = harness()
		local p = LuauUI.newProgressView(LuauUI, core, { id = "Load", value = 0.25, presentation = "circular" })
		local handle = pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		expect(#handle.controller.diagnostics()).toBe(0)
		expect(adapter.node("/S/Load/Bar")).toBeNil()
		expect(adapter.node("/S/Load/Spinner")).toBeNil()
		expect(adapter.node(TRACK) ~= nil).toBe(true)
		expect(adapter.node(ARC) ~= nil).toBe(true)
		-- the ring is SQUARE and sized from the theme metric, never from a call
		local rect = adapter.node(RING).rect
		expect(rect.w).toBe(rect.h)
		expect(rect.w > 0).toBe(true)
		local d = p.dump()
		expect(d.presentation).toBe("circular")
		expect(d.indeterminate).toBe(false)
		expect(d.fraction).toBe(0.25)
		p.dispose()
	end)

	it("the SWEEP is the value: 25% ends at 3 o'clock, 100% closes the ring", function()
		local core, _, adapter, pres = harness()
		local v = core:signal(0.25)
		local p = LuauUI.newProgressView(LuauUI, core, { id = "Load", value = v, presentation = "circular" })
		pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		local pts = adapter.node(ARC).props.points
		expect(math.abs(angleOf(pts[1]) - 0) < 0.001).toBe(true)
		expect(math.abs(angleOf(pts[#pts]) - 90) < 0.001).toBe(true)
		v:set(0.5)
		pres.refresh()
		pts = adapter.node(ARC).props.points
		expect(math.abs(angleOf(pts[#pts]) - 180) < 0.001).toBe(true)
		v:set(1)
		pres.refresh()
		pts = adapter.node(ARC).props.points
		-- a full sweep returns to the head: the ring closes
		expect(math.abs(pts[#pts].x - pts[1].x) < 1e-6).toBe(true)
		expect(math.abs(pts[#pts].y - pts[1].y) < 1e-6).toBe(true)
		p.dispose()
	end)

	it("a value change is PAINT ONLY: one prop write on `points`, zero re-solves", function()
		local core, _, adapter, pres = harness()
		local v = core:signal(0.25)
		local p = LuauUI.newProgressView(LuauUI, core, { id = "Load", value = v, presentation = "circular" })
		local handle = pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		adapter.takeOps()
		local stats = handle.controller.stats()
		local solves, arranged, measured = stats.solves, stats.lastArranged, stats.lastMeasured
		v:set(0.75)
		pres.refresh()
		local ops = adapter.takeOps()
		expect(#ops).toBe(1)
		expect(string.find(ops[1], `prop {ARC}.points`, 1, true) ~= nil).toBe(true)
		local after = handle.controller.stats()
		-- the falsifiable prediction: commit moves, GEOMETRY DOES NOT
		expect(after.solves).toBe(solves)
		expect(after.lastArranged).toBe(arranged)
		expect(after.lastMeasured).toBe(measured)
		p.dispose()
	end)
end)

describe("ProgressView circular: the INDETERMINATE ring rotates its own start angle", function()
	local function ringWorld(policy: string?)
		local core, _, adapter, pres, clock, now = clockWorld(policy)
		local p = LuauUI.newProgressView(LuauUI, core, {
			id = "Load",
			presentation = "circular",
			motionClock = clock,
			scope = core:scope("surface"),
		})
		local handle = pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		expect(#handle.controller.diagnostics()).toBe(0)
		return core, adapter, pres, clock, now, p, handle
	end

	it("the HEAD travels while the sweep stays fixed — and there is no backing ring", function()
		local _, adapter, pres, clock, now, p = ringWorld()
		-- an indeterminate ring is a travelling head on empty plate: a full backing
		-- ring would read as a determinate ring stuck at 100%
		expect(adapter.node(TRACK)).toBeNil()
		local function head(): number
			return angleOf(adapter.node(ARC).props.points[1])
		end
		local function sweep(): number
			local pts = adapter.node(ARC).props.points
			return (angleOf(pts[#pts]) - angleOf(pts[1]) + 360) % 360
		end
		local startHead, startSweep = head(), sweep()
		local moved = false
		for _ = 1, 10 do
			now.t += 0.05
			clock:step()
			pres.refresh()
			if math.abs(head() - startHead) > 0.001 then
				moved = true
			end
			-- the SWEEP is a constant: only the start angle is a function of phase
			expect(math.abs(sweep() - startSweep) < 0.001).toBe(true)
		end
		expect(moved).toBe(true)
		p.dispose()
		clock:dispose()
	end)

	it("rotating is PAINT: 60 frames of travel write points and never re-solve", function()
		local _, adapter, pres, clock, now, p, handle = ringWorld()
		adapter.takeOps()
		local stats = handle.controller.stats()
		local solves, creates = stats.solves, stats.creates
		local pointOps = 0
		for _ = 1, 60 do
			now.t += 1 / 60
			clock:step()
			pres.refresh()
			for _, op in adapter.takeOps() do
				if string.find(op, ".points", 1, true) ~= nil then
					pointOps += 1
				end
			end
		end
		expect(pointOps > 0).toBe(true)
		local after = handle.controller.stats()
		expect(after.solves).toBe(solves)
		expect(after.creates).toBe(creates)
		p.dispose()
		clock:dispose()
	end)

	it("takes the SAME single clock entry the dots take — no second one for the arc", function()
		local core, _, _, clock, _, p = ringWorld()
		expect(clock:activeCount()).toBe(1)
		-- ...and a second, DOT spinner beside it takes exactly one more: the arc did
		-- not quietly acquire a private cycle
		local dots = LuauUI.newProgressView(LuauUI, core, {
			id = "Dots",
			presentation = "spinner",
			motionClock = clock,
			scope = core:scope("s2"),
		})
		expect(clock:activeCount()).toBe(2)
		dots.dispose()
		p.dispose()
		clock:dispose()
	end)

	it("under REDUCED motion the ring keeps advancing, on the quantized tick", function()
		local _, adapter, pres, clock, now, p = ringWorld("reduced")
		local function head(): number
			return angleOf(adapter.node(ARC).props.points[1])
		end
		local start = head()
		now.t += 0.05
		clock:step()
		pres.refresh()
		expect(math.abs(head() - start) < 1e-9).toBe(true) -- quantized: no write inside the tick
		now.t += 0.3
		clock:step()
		pres.refresh()
		expect(math.abs(head() - start) > 0.001).toBe(true) -- ...and it MOVED, rather than froze
		p.dispose()
		clock:dispose()
	end)

	it("with no clock it holds its rest pose and says so", function()
		local core, _, adapter, pres = harness()
		local p = LuauUI.newProgressView(LuauUI, core, {
			id = "Load",
			presentation = "circular",
			scope = core:scope("surface"),
		})
		pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		expect(adapter.node(ARC) ~= nil).toBe(true)
		local d = p.dump()
		expect(d.animating).toBe(false)
		expect(d.phase).toBe(0)
		expect(d.semanticText).toBe("Loading")
		p.dispose()
	end)
end)

describe("ProgressView circular: the OFF-PATH cost is exactly zero", function()
	it("no circular indicator mounted = no Path instance and no `points` op, ever", function()
		-- The arc is the first per-frame PAINT this control has drawn, so the first
		-- thing it owes is that a caller who does not use it pays nothing. Both
		-- pre-existing shapes are mounted here and driven for 120 clock steps: if a
		-- single Path is materialised, or a single `points` op reaches the adapter,
		-- the new shape has leaked into the old ones.
		local core, _, adapter, pres, clock, now = clockWorld()
		local bar = LuauUI.newProgressView(LuauUI, core, { id = "Bar", value = core:signal(0.4), height = 12 })
		local dots = LuauUI.newProgressView(LuauUI, core, {
			id = "Dots",
			presentation = "spinner",
			motionClock = clock,
			scope = core:scope("surface"),
		})
		pres.present(UI.Screen({ id = "S", children = { bar.blueprint, dots.blueprint } }))
		pres.refresh()
		local instances = #adapter.paths()
		adapter.takeOps()
		local pointOps = 0
		for _ = 1, 120 do
			now.t += 1 / 60
			clock:step()
			pres.refresh()
			for _, op in adapter.takeOps() do
				if string.find(op, ".points", 1, true) ~= nil then
					pointOps += 1
				end
			end
		end
		expect(pointOps).toBe(0)
		expect(#adapter.paths() - instances).toBe(0)
		for _, path in adapter.paths() do
			expect(adapter.node(path).props.points).toBeNil()
		end
		bar.dispose()
		dots.dispose()
		clock:dispose()
	end)
end)

--[[ ===== THE TWO SHAPES ARE THEME-SIZED, AND A THEME HAS TO SAY SO ===========
	(director round 2026-08-14: *"we need to make sure the circular progress bars
	and dots spinner are themeable"*.)

	THE MECHANISM WAS THERE AND NOBODY WAS USING IT. Measured before any of it was
	written, over the eight packages the theme picker offers a player:

	    controls.progress.spinnerDotSize     authored by 0 of 8
	    controls.progress.circularSize       authored by 0 of 8
	    controls.progress.circularThickness  authored by 0 of 8
	    the `spinner` decoration slot         declared by 0 of 8

	while `barTrack` / `barFill` — the bar's two slots — are declared by four of
	them and its `trackHeight` by four. So the bar was genuinely themed and the two
	shapes round 3 added were uniformly falling through `snapshot.resolve`'s
	fill-in, which derives them from the theme's own SPACE scale (`space.s` for the
	dot, `space.l` for the ring). A spacing step is a gap between elements, and it
	is a poor proxy for the diameter of an indicator: Classic Desktop's `space.l`
	is 12, so its "ring" resolved to a 12px circle with a 2px stroke — smaller than
	the label beside it, and nothing in the repository could see that, because
	every check asked whether the number was CONSISTENT and none asked whether a
	package had ever CHOSEN it.

	These are therefore two different propositions and both are checks:
	  1. every shipped package AUTHORS all three, in its own definition — the
	     fallback stays for a third-party package that declares nothing, and stops
	     being what the reference corpus ships;
	  2. what it authored is its OWN, not a copy of Studio Neutral's — the
	     "themeable" claim is only worth making if the themes visibly differ.
]]
describe("the two theme-sized shapes are AUTHORED by every shipped package", function()
	-- the eight packages the showcase's theme picker offers a player: the same
	-- list, in the same order, that the always-on overflow sweep's theme axis
	-- runs (tests/overflow_sweep.spec.luau PACKAGE_MODULES)
	local SHIPPED = {
		"classic_desktop",
		"compact_pointer",
		"fantasy_ornate",
		"fantasy_parchment",
		"glossy_mobile",
		"glossy_touch",
		"pixel_quest",
		"scifi_hud",
	}
	-- the three the fill-in covers, i.e. exactly `package.CONTROL_FAMILY_OPTIONAL.progress`
	local SHAPE_METRICS = { "spinnerDotSize", "circularSize", "circularThickness" }

	-- the package's OWN definition table, before `define` merges the neutral base
	-- into it. Read here rather than off the built package because the base IS
	-- Studio Neutral: `pkg.metrics.controls.progress.trackHeight` answers 6 for a
	-- package that never mentioned a progress bar, so the built package cannot
	-- tell "authored" from "inherited" and this is the only surface that can.
	local function ownProgress(name: string): any
		local definition = (require)(`../examples/themes/{name}`).definition(themes)
		return ((definition.metrics or {}).controls or {}).progress
	end

	for _, name in SHIPPED do
		it(`{name} authors all three, rather than inheriting the space scale`, function()
			local own = ownProgress(name)
			for _, field in SHAPE_METRICS do
				local value = if type(own) == "table" then (own :: any)[field] else nil
				expect(`{name}.{field} = {tostring(value)}`).toBe(`{name}.{field} = {tostring(tonumber(value))}`)
				expect(`{name}.{field} > 0 is {tostring((tonumber(value) or 0) > 0)}`).toBe(
					`{name}.{field} > 0 is true`
				)
			end
		end)
	end

	it("every package's shapes are its OWN, not Studio Neutral's numbers", function()
		local neutral = themes.resolve(themes.neutralPackage(), nil, {}).controls.progress
		local same: { string } = {}
		for _, name in SHIPPED do
			local own = ownProgress(name)
			local identical = true
			for _, field in SHAPE_METRICS do
				if (own :: any)[field] ~= (neutral :: any)[field] then
					identical = false
				end
			end
			if identical then
				table.insert(same, name)
			end
		end
		-- a package free to author anything and choosing the default in all three
		-- is a package that has not made a decision — which is the state this whole
		-- block exists to end
		expect(`packages identical to Studio Neutral: {table.concat(same, ", ")}`).toBe(
			"packages identical to Studio Neutral: "
		)
	end)

	it("the corpus SPANS the two shapes: the largest ring is at least twice the smallest", function()
		-- ONE NUMBER FOR "unmistakably different". Eight packages that all landed
		-- within a few pixels of each other would satisfy every check above and
		-- still look like one theme, so the spread itself is the proposition. 2x is
		-- the ratio between the smallest ring a pointer package wants and the
		-- carved one an ornate package wants; it is a FLOOR on the corpus, not a
		-- rule any single package has to obey.
		local rings: { number } = {}
		local dots: { number } = {}
		for _, name in SHIPPED do
			local own = ownProgress(name)
			table.insert(rings, (own :: any).circularSize)
			table.insert(dots, (own :: any).spinnerDotSize)
		end
		table.sort(rings)
		table.sort(dots)
		expect(`rings {rings[1]}..{rings[#rings]} span {rings[#rings] / rings[1] >= 2}`).toBe(
			`rings {rings[1]}..{rings[#rings]} span true`
		)
		expect(`dots {dots[1]}..{dots[#dots]} span {dots[#dots] / dots[1] >= 2}`).toBe(
			`dots {dots[1]}..{dots[#dots]} span true`
		)
	end)

	it("a package that authors NOTHING still answers all three (the fill-in stays)", function()
		-- the other half of the same contract, and the reason the three fields are
		-- in `CONTROL_FAMILY_OPTIONAL` rather than in the required list: a
		-- third-party package written before these shapes existed must still
		-- resolve, and it does — from the theme's own space scale.
		local stub = (require)("../examples/themes/fantasy_parchment_stub").build(themes)
		local family = themes.resolve(stub, nil, {}).controls.progress
		for _, field in SHAPE_METRICS do
			expect(`stub.{field} = {type((family :: any)[field])}`).toBe(`stub.{field} = number`)
		end
	end)
end)

describe("ProgressView circular: the stroke fits inside its own box, in every shipped theme", function()
	-- THE PAINT FACT NO HEADLESS SOLVE CAN SEE. A Path2D stroke is centred on the
	-- curve, so a ring drawn at radius r inside a box of size d paints out to
	-- `r * d / 2 + thickness / 2`. If that exceeds `d / 2` the stroke is painted
	-- outside the box the solver measured — the "painted at a size nobody
	-- measured" family, and invisible to every diagnostic in this suite. The
	-- relationship is therefore ARITHMETIC, guaranteed where the two numbers are
	-- both known (snapshot.resolve fills the thickness against the size), and this
	-- is the check that the guarantee holds for every theme that ships.
	local PACKAGES = {
		"fantasy_ornate",
		"fantasy_parchment",
		"pixel_quest",
		"glossy_touch",
		"glossy_mobile",
		"compact_pointer",
		"classic_desktop",
		"scifi_hud",
	}
	it("radius * size / 2 + thickness / 2 never exceeds size / 2", function()
		local snaps: { { name: string, snap: any } } = {
			{ name = "neutral", snap = themes.resolve(themes.neutralPackage(), nil, {}) },
		}
		for _, name in PACKAGES do
			local pkg = (require)(`../examples/themes/{name}`).build(themes)
			table.insert(snaps, { name = name, snap = themes.resolve(pkg, nil, {}) })
		end
		for _, row in snaps do
			local family = row.snap.controls.progress
			local size = family.circularSize
			local thickness = family.circularThickness
			expect(`{row.name} size={type(size)}`).toBe(`{row.name} size=number`)
			expect(`{row.name} thickness={type(thickness)}`).toBe(`{row.name} thickness=number`)
			local painted = progress_view.CIRCULAR_RADIUS * size / 2 + thickness / 2
			-- the failure message carries the two numbers, so one red line is the
			-- whole measurement rather than the start of a guessing loop
			expect(`{row.name} paints {painted} of {size / 2}: fits={painted <= size / 2}`).toBe(
				`{row.name} paints {painted} of {size / 2}: fits=true`
			)
			-- ...and it is still a RING, not a filled disc
			expect(`{row.name} visible={thickness > 0}`).toBe(`{row.name} visible=true`)
		end
	end)
end)

describe("ProgressView circular: it lays out in every shipped theme, at every swept viewport", function()
	-- The showcase rule's theme half, asked of the control directly as well as of
	-- the scenario: Pixel Quest snaps every length UP to its pixel unit and
	-- Parchment carries its own space scale, and each has broken a layout Studio
	-- Neutral survived.
	local PACKAGES = { "fantasy_ornate", "fantasy_parchment", "pixel_quest", "glossy_touch", "compact_pointer" }
	it("no solver diagnostic, and the label never overlaps the ring", function()
		local problems: { string } = {}
		for _, name in PACKAGES do
			local pkg = (require)(`../examples/themes/{name}`).build(themes)
			for _, view in device_views.VIEWS do
				local core, env, adapter, pres = harness(view.w, view.h)
				env:set("themeMetrics", themes.resolve(pkg, nil, {}))
				local p = LuauUI.newProgressView(LuauUI, core, {
					id = "Load",
					label = "Loading the race",
					value = 0.42,
					presentation = "circular",
				})
				local handle = pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
				pres.refresh()
				pres.refresh()
				for _, finding in handle.controller.diagnostics() do
					table.insert(problems, `{name} {view.id}: {finding.node} {finding.issue}`)
				end
				local label = adapter.node("/S/Load/Label")
				local ring = adapter.node(RING)
				if label ~= nil and ring ~= nil then
					local labelEnd = label.rect.x + label.rect.w
					if labelEnd > ring.rect.x then
						table.insert(
							problems,
							`{name} {view.id}: the label ends at {labelEnd} and the ring starts at {ring.rect.x}`
						)
					end
				end
				p.dispose()
			end
		end
		expect(`problems: {table.concat(problems, " | ")}`).toBe("problems: ")
	end)

	--[[ O-23, measured 2026-08-14 by the overflow sweep's theme axis.

		THE ROW'S FLEXIBLE HALF IS THE LABEL, AND IT COULD NOT SHRINK. Two of the
		three shapes are a fixed px box from a theme metric — the spinner is five
		`controls.progress.spinnerDotSize` dots plus four `xs` gaps, the ring is
		`CIRCULAR_SIZE` — so on a narrow screen nothing in the row could give up a
		pixel and it simply painted past its own box. Measured on the shipped
		`progress_ring` scenario at 320x640 at the DEFAULT preference: 40px past
		under Glossy Mobile and Glossy Touch, 6px under Fantasy Ornate and
		Parchment, and clean under Studio Neutral with 110px to spare — which is why
		nothing in this repository saw it.

		THE CASE ABOVE COULD NOT SEE IT and that is the interesting part: it asks
		the same question of the same packages, with a short label on a wide screen,
		so every row fit by accident. The narrow viewport and the long label are the
		whole test.
	]]
	it("a LONG label on a NARROW screen still fits — every presentation, every package", function()
		local ALL = {
			"fantasy_ornate",
			"fantasy_parchment",
			"pixel_quest",
			"glossy_touch",
			"glossy_mobile",
			"compact_pointer",
			"classic_desktop",
			"scifi_hud",
		}
		local problems: { string } = {}
		for _, name in ALL do
			local pkg = (require)(`../examples/themes/{name}`).build(themes)
			for _, presentation in { "bar", "spinner", "circular" } do
				local core, env, adapter, pres = harness(320, 640)
				env:set("themeMetrics", themes.resolve(pkg, nil, {}))
				local spec: any = {
					id = "Load",
					label = "Downloading the season pass",
					presentation = presentation,
				}
				if presentation == "spinner" then
					spec.motionClock = pres.motionClock
					spec.scope = core:scope("o23")
				else
					spec.value = 0.42
				end
				local p = LuauUI.newProgressView(LuauUI, core, spec)
				local handle = pres.present(UI.Screen({ id = "S", padding = 16, children = { p.blueprint } }))
				pres.refresh()
				pres.refresh()
				for _, finding in handle.controller.diagnostics() do
					table.insert(problems, `{name}/{presentation}: {finding.node} {finding.issue}`)
				end
				p.dispose()
			end
		end
		expect(`problems: {table.concat(problems, " | ")}`).toBe("problems: ")
	end)
end)
