--!strict
-- SelectionIndicator spec (navigation-and-menus brief §2 D4) — the sliding
-- selection seam D5's TabView and D6's segmented Picker both consume.
--
-- The two decisions that carry the deliverable are PURE functions of plain
-- numbers and booleans (`resolveIndicatorRect`, `resolveTransition`), so they
-- are tested as arithmetic before anything is mounted — `popup_button
-- .resolvePresentation`'s idiom. Everything below that runs through a real
-- presenter: solved rects arrive on the arrange cadence, motion runs on the
-- presenter's own clock, and the reduced-motion claim is proved by COUNTING the
-- rect writes the adapter receives across twenty ticks rather than by reading a
-- flag back out of the environment.
--
-- The control is NON-INTERACTIVE by construction (an Anchor holding a Box, both
-- outside the FOCUSABLE set) — so instead of four input-class proofs it owes one
-- proof that it stays out of the way: wrapping a strip must leave that strip's
-- focus document order byte-identical.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local serde = require("@lune/serde")

local Facet = require("../src") :: any
local selection_indicator = require("../src/controls/selection_indicator")
local fake_target = require("../tests/lib/fake_target")
local focus_map = require("../src/present/focus_map")

local UI = Facet.UI

-- ===== the harness ========================================================
-- A two-segment horizontal strip of Buttons wrapped by the indicator. Segment
-- widths are DELIBERATELY unequal (`fixed` 120 and 80) so every rect assertion
-- below would fail if anything interpolated an index instead of a rect.
local function world(opts: any?)
	local options = opts or {}
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	if options.reducedMotion == true then
		env:set("reducedMotion", true)
	end
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local selected = core:signal(options.initial or "a")
	local axis = options.axis or "x"
	local widths = options.widths or { 120, 80 }
	local segmentDim = function(px: number)
		return { type = "fixed", px = px }
	end
	local kids = {}
	for i, label in { "A", "B" } do
		local w = if axis == "x" then segmentDim(widths[i]) else segmentDim(100)
		local h = if axis == "x" then segmentDim(48) else segmentDim(widths[i])
		table.insert(kids, UI.Button({ id = label, label = label, width = w, height = h }))
	end
	local strip = if axis == "x"
		then UI.HStack({ id = "Strip", gap = 0, children = kids })
		else UI.VStack({ id = "Strip", gap = 0, children = kids })
	local indicator = selection_indicator.build(Facet, core, {
		id = "Tabs",
		content = strip,
		segments = { { value = "a", id = "A" }, { value = "b", id = "B" } },
		selected = selected,
		skin = options.skin or "underline",
		axis = axis,
		env = env,
	})
	-- a sibling ABOVE the wrapper whose height a test can change: growing it moves
	-- the whole indicator, layer and segments together, which is what a scroll or
	-- a re-flowing header does in the shipped case
	local spacerHeight = core:signal(0)
	local handle = pres.present(UI.Screen({
		id = "S",
		children = {
			UI.VStack({
				id = "Page",
				gap = 0,
				children = {
					UI.Box({
						id = "Head",
						height = core:memo(function(use)
							return { type = "fixed", px = use(spacerHeight) }
						end),
					}),
					indicator.blueprint,
				},
			}),
		},
	}))
	pres.refresh()
	return {
		core = core,
		env = env,
		adapter = adapter,
		pres = pres,
		handle = handle,
		indicator = indicator,
		selected = selected,
		spacerHeight = spacerHeight,
	}
end

local BAR = "/S/Page/Tabs/Layer/Bar"

local function barRect(w: any): any
	local node = w.adapter.node(BAR)
	return if node == nil then nil else node.rect
end

-- how many times the adapter was told to move the bar since the last drain
local function barWrites(w: any): number
	local n = 0
	for _, op in w.adapter.takeOps() do
		if string.find(op, `rect {BAR} `, 1, true) == 1 then
			n += 1
		end
	end
	return n
end

describe("D4 geometry: one arithmetic, two skins, both axes", function()
	local HOST = { x = 10, y = 20, w = 300, h = 48 }

	it("pill: the chip is the segment box inset on all four sides, in the layer's space", function()
		local rect = selection_indicator.resolveIndicatorRect(
			{ x = 130, y = 20, w = 80, h = 48 },
			HOST,
			{ skin = "pill", axis = "x", thickness = 4, inset = 4 }
		)
		expect(rect.x).toBe(124) -- 130 - 10 + 4
		expect(rect.y).toBe(4) -- 20 - 20 + 4
		expect(rect.w).toBe(72) -- 80 - 2*4
		expect(rect.h).toBe(40) -- 48 - 2*4
	end)

	it("underline x: a bar on the segment's bottom edge, spanning its full width", function()
		local rect = selection_indicator.resolveIndicatorRect(
			{ x = 10, y = 20, w = 120, h = 48 },
			HOST,
			{ skin = "underline", axis = "x", thickness = 4, inset = 4 }
		)
		expect(rect.x).toBe(0)
		expect(rect.y).toBe(44) -- 0 + 48 - 4
		expect(rect.w).toBe(120) -- the WHOLE segment, so a 1.4x label widens the bar
		expect(rect.h).toBe(4)
	end)

	it("underline y: a VERTICAL strip underlines the leading edge and spans the height", function()
		-- f1's left rail. The same function, no second code path: only which edge
		-- the thickness is spent on changes.
		local rect = selection_indicator.resolveIndicatorRect(
			{ x = 0, y = 100, w = 64, h = 52 },
			{ x = 0, y = 0, w = 64, h = 200 },
			{ skin = "underline", axis = "y", thickness = 4, inset = 4 }
		)
		expect(rect.x).toBe(0)
		expect(rect.y).toBe(100)
		expect(rect.w).toBe(4)
		expect(rect.h).toBe(52) -- the segment's own height, never a constant
	end)

	it("the transition is between RECTS, not indices: unequal segments give unequal bars", function()
		local opts = { skin = "underline", axis = "x", thickness = 4, inset = 4 }
		local first = selection_indicator.resolveIndicatorRect({ x = 0, y = 0, w = 120, h = 48 }, HOST, opts)
		local second = selection_indicator.resolveIndicatorRect({ x = 120, y = 0, w = 80, h = 48 }, HOST, opts)
		expect(first.w).toBe(120)
		expect(second.w).toBe(80)
		-- an index interpolation could not produce two different widths at all
		expect(first.w ~= second.w).toBe(true)
	end)

	it("an underline is never thicker than the box it decorates", function()
		local rect = selection_indicator.resolveIndicatorRect(
			{ x = 0, y = 0, w = 40, h = 3 },
			{ x = 0, y = 0, w = 100, h = 3 },
			{ skin = "underline", axis = "x", thickness = 12, inset = 0 }
		)
		expect(rect.h).toBe(3)
		expect(rect.y).toBe(0)
	end)

	it("a pill never inverts: an inset wider than the box clamps to zero", function()
		local rect = selection_indicator.resolveIndicatorRect(
			{ x = 0, y = 0, w = 6, h = 6 },
			{ x = 0, y = 0, w = 100, h = 40 },
			{ skin = "pill", axis = "x", thickness = 4, inset = 20 }
		)
		expect(rect.w).toBe(0)
		expect(rect.h).toBe(0)
	end)

	it("nothing to point at resolves to nil rather than to the origin", function()
		local opts = { skin = "pill", axis = "x", thickness = 4, inset = 4 }
		expect(selection_indicator.resolveIndicatorRect(nil, HOST, opts)).toBeNil()
		expect(selection_indicator.resolveIndicatorRect({ x = 0, y = 0, w = 1, h = 1 }, nil, opts)).toBeNil()
	end)
end)

describe("D4 motion policy: place or slide, decided before anything moves", function()
	it("first paint PLACES: the indicator never slides in from nowhere", function()
		expect(selection_indicator.resolveTransition(false, false)).toBe("place")
		expect(selection_indicator.resolveTransition(false, true)).toBe("place")
	end)

	it("a selection change SLIDES", function()
		expect(selection_indicator.resolveTransition(true, true)).toBe("slide")
	end)

	it("a re-solve under an unchanged selection PLACES, so a rotation cannot make the bar swim", function()
		expect(selection_indicator.resolveTransition(true, false)).toBe("place")
	end)
end)

describe("D4 mounted: the bar tracks the SOLVED rect of the selected child", function()
	it("mounts one bar behind the strip and lands on the initial selection with no travel", function()
		local w = world()
		expect(w.core:lastError()).toBeNil()
		local a = w.adapter.node("/S/Page/Tabs/Strip/A").rect
		local bar = barRect(w)
		expect(bar.x).toBe(a.x)
		expect(bar.w).toBe(a.w) -- 120, the wide segment
		expect(bar.y).toBe(a.y + a.h - 4) -- space.xs under Studio Neutral
		expect(bar.h).toBe(4)
		-- FIRST PAINT DOES NOT ANIMATE: nothing is on the clock, and the dump
		-- records a placement rather than a slide
		expect(w.indicator.state().slides).toBe(0)
		expect(w.indicator.state().placed).toBe(true)
		-- and the layer is declared FIRST, so the bar paints BEHIND the strip
		-- (ZIndexBehavior is Sibling: a later sibling paints on top)
		local kids = w.handle.root.node.children[1].children[2].children
		expect(kids[1].id).toBe("Layer")
		expect(kids[2].id).toBe("Strip")
	end)

	it("a selection change slides the bar between the two solved rects", function()
		local w = world()
		local a = w.adapter.node("/S/Page/Tabs/Strip/A").rect
		local b = w.adapter.node("/S/Page/Tabs/Strip/B").rect
		barWrites(w) -- drain
		w.selected:set("b")
		w.pres.refresh()
		-- the flight has started but has NOT teleported
		expect(barRect(w).x < b.x).toBe(true)
		expect(barRect(w).x >= a.x).toBe(true)
		local intermediate = 0
		for _ = 1, 60 do
			w.pres.tick(1 / 60)
			w.pres.refresh()
			local r = barRect(w)
			if r.x > a.x and r.x < b.x then
				intermediate += 1
			end
		end
		-- a real flight: many frames strictly between the two rects...
		expect(intermediate > 3).toBe(true)
		-- ...landing exactly on the new segment, at the NEW segment's width
		expect(barRect(w).x).toBe(b.x)
		expect(barRect(w).w).toBe(b.w)
		expect(b.w ~= a.w).toBe(true)
		expect(w.indicator.state().slides).toBe(1)
	end)

	it("REDUCED MOTION SNAPS: one rect write, then twenty ticks of silence", function()
		-- The claim is about FRAMES, so it is counted in frames. Reading
		-- `env:get("reducedMotion")` back would prove only that the fixture set it.
		local w = world({ reducedMotion = true })
		local b = w.adapter.node("/S/Page/Tabs/Strip/B").rect
		barWrites(w) -- drain
		w.selected:set("b")
		w.pres.refresh()
		expect(barWrites(w)).toBe(1) -- exactly one move: the placement
		expect(barRect(w).x).toBe(b.x) -- already there, with no frame in between
		expect(barRect(w).w).toBe(b.w)
		for _ = 1, 20 do
			w.pres.tick(1 / 60)
			w.pres.refresh()
		end
		expect(barWrites(w)).toBe(0) -- nothing animated afterwards either
		expect(w.pres.motionClock:activeCount()).toBe(0)
	end)

	it("full motion spends MANY frames on the same change, which is what reduced motion removes", function()
		-- the differential the row above needs to mean anything
		local w = world()
		barWrites(w)
		w.selected:set("b")
		w.pres.refresh()
		local writes = barWrites(w)
		for _ = 1, 60 do
			w.pres.tick(1 / 60)
			w.pres.refresh()
			writes += barWrites(w)
		end
		expect(writes > 10).toBe(true)
	end)

	it("the indicator is never a focus stop: wrapping a strip leaves its document order identical", function()
		local w = world()
		local wrapped: { string } = {}
		focus_map.collectFocusables(w.handle.root.node, wrapped)
		expect(#wrapped).toBe(2)
		expect(wrapped[1]).toBe("/S/Page/Tabs/Strip/A")
		expect(wrapped[2]).toBe("/S/Page/Tabs/Strip/B")
		-- neither of the two classes the indicator mounts is focusable at all
		expect(focus_map.FOCUSABLE.Anchor).toBeNil()
		expect(focus_map.FOCUSABLE.Box).toBeNil()
	end)

	it("a viewport change under an UNCHANGED selection re-places the bar rather than flying it", function()
		local w = world()
		w.env:set("viewportRect", { x = 0, y = 0, w = 600, h = 400 })
		w.pres.refresh()
		local a = w.adapter.node("/S/Page/Tabs/Strip/A").rect
		expect(barRect(w).x).toBe(a.x)
		expect(barRect(w).w).toBe(a.w)
		expect(w.indicator.state().slides).toBe(0) -- a re-solve is not a transition
	end)

	it("repeated geometry feeds with UNCHANGED rects cost nothing (the by-value guard)", function()
		-- syncGeometry is fed on EVERY solve and EVERY refresh with a FRESH table,
		-- so an identity-compared intake would notify eleven times here and re-run
		-- the target derivation eleven times. Both stages are guarded; this counts
		-- the FIRST one, which the second would otherwise mask.
		local w = world()
		barWrites(w)
		local updatesBefore = w.indicator.state().geometryUpdates
		for _ = 1, 10 do
			w.pres.refresh()
		end
		expect(barWrites(w)).toBe(0)
		expect(w.indicator.state().geometryUpdates).toBe(updatesBefore)
		expect(w.indicator.state().transitions).toBe(1) -- the initial placement, once
	end)

	it("...and the comparator refuses a nested field rather than half-comparing it", function()
		-- the renderer's own deliberate conservatism (renderer.luau:2764-2777): a
		-- rebuilt-outer/reused-inner shape compared by identity would report a
		-- false "unchanged", which is a MISSED update, not a spare one
		local same = selection_indicator.sameGeometry
		expect(same({ 1, 2, 3 }, { 1, 2, 3 })).toBe(true)
		expect(same({ 1, 2, 3 }, { 1, 2, 4 })).toBe(false)
		expect(same({ 1, 2, 3 }, { 1, 2 })).toBe(false) -- a key on one side only
		expect(same({ 1, 2 }, { 1, 2, 3 })).toBe(false) -- ...in both directions
		local shared = { 9 }
		expect(same({ shared }, { shared })).toBe(false) -- nested: refused
	end)

	it("a geometry change that does not move the bar cannot interrupt a flight in progress", function()
		-- the SECOND by-value guard, and the one whose absence is a visible defect
		-- rather than a cost: `fed` notifies on any rect in the strip moving, so an
		-- identity-compared target would re-place — and therefore SNAP — the bar
		-- mid-slide every time a sibling surface re-solved.
		local w = world()
		local a = w.adapter.node("/S/Page/Tabs/Strip/A").rect
		local b = w.adapter.node("/S/Page/Tabs/Strip/B").rect
		w.selected:set("b")
		w.pres.refresh()
		for _ = 1, 6 do
			w.pres.tick(1 / 60)
			w.pres.refresh()
		end
		local midFlight = barRect(w).x
		expect(midFlight > a.x and midFlight < b.x).toBe(true)
		-- something above the strip grows, so EVERY rect this indicator is fed
		-- moves — host and segments alike, by the same delta. The bar's own rect
		-- inside the layer is unchanged, so the flight must continue from where it
		-- is instead of being re-placed (which would snap it).
		local updatesBefore = w.indicator.state().geometryUpdates
		w.spacerHeight:set(24)
		w.pres.refresh()
		expect(w.indicator.state().geometryUpdates > updatesBefore).toBe(true) -- fed DID change
		expect(barRect(w).x).toBe(midFlight)
		for _ = 1, 60 do
			w.pres.tick(1 / 60)
			w.pres.refresh()
		end
		expect(barRect(w).x).toBe(b.x)
		expect(w.indicator.state().slides).toBe(1) -- one transition, not three
	end)

	it("a vertical pill moves along y, and the same mechanism draws it", function()
		local w = world({ axis = "y", skin = "pill", widths = { 60, 44 } })
		local a = w.adapter.node("/S/Page/Tabs/Strip/A").rect
		local b = w.adapter.node("/S/Page/Tabs/Strip/B").rect
		expect(barRect(w).y).toBe(a.y + 4)
		expect(barRect(w).h).toBe(a.h - 8)
		w.selected:set("b")
		w.pres.refresh()
		for _ = 1, 60 do
			w.pres.tick(1 / 60)
			w.pres.refresh()
		end
		expect(barRect(w).y).toBe(b.y + 4)
		expect(barRect(w).h).toBe(b.h - 8)
		expect(w.indicator.state().axis).toBe("y")
		expect(w.indicator.state().skin).toBe("pill")
	end)

	it("a selection change is a re-solve, not a rebuild: zero factory reruns", function()
		local w = world()
		local before = w.handle.root.counters().factoryRuns
		w.selected:set("b")
		w.pres.refresh()
		for _ = 1, 30 do
			w.pres.tick(1 / 60)
			w.pres.refresh()
		end
		expect(w.handle.root.counters().factoryRuns).toBe(before)
	end)

	it("a wider label widens the bar with it (localization-safe by construction)", function()
		-- the indicator is a function of the SOLVED rect, so a 1.4x expansion that
		-- grows the segment grows the bar; it can never be painted at a size
		-- nobody measured
		local narrow = world({ widths = { 120, 80 } })
		local wide = world({ widths = { 168, 112 } }) -- 1.4x
		expect(barRect(narrow).w).toBe(120)
		expect(barRect(wide).w).toBe(168)
	end)

	it("state() is deterministic and reports what a bug report needs", function()
		local w = world()
		local first = serde.encode("json", w.indicator.state(), true)
		expect(first).toBe(serde.encode("json", w.indicator.state(), true))
		local d = w.indicator.state()
		expect(d.segments).toBe(2)
		expect(d.resolved).toBe(2)
		expect(#d.unresolved).toBe(0)
		expect(d.selectedId).toBe("A")
		expect(d.animated).toBe(true)
		expect(d.semanticText).toBe("underline indicator on A (2/2 segments resolved)")
	end)

	it("build/mount/select/dispose returns every registry to baseline", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local baseline = core:counters() -- AFTER the long-lived singletons

		local selected = core:signal("a")
		local strip = UI.HStack({
			id = "Strip",
			children = {
				UI.Button({ id = "A", label = "A", width = { type = "fixed", px = 120 } }),
				UI.Button({ id = "B", label = "B", width = { type = "fixed", px = 80 } }),
			},
		})
		local indicator = selection_indicator.build(Facet, core, {
			id = "Tabs",
			content = strip,
			segments = { { value = "a", id = "A" }, { value = "b", id = "B" } },
			selected = selected,
			env = env,
		})
		local handle = pres.present(UI.Screen({ id = "S", children = { indicator.blueprint } }))
		pres.refresh()
		-- FIVE round trips, so a per-transition allocation would show up as five
		-- times whatever one costs rather than as a constant
		for _ = 1, 5 do
			selected:set("b")
			pres.refresh()
			pres.tick(1)
			selected:set("a")
			pres.refresh()
			pres.tick(1)
		end

		pres.dismiss(handle)
		indicator.dispose()
		selected:dispose()

		local after = core:counters()
		for k, v in baseline :: any do
			expect((after :: any)[k]).toBe(v)
		end
	end)
end)

describe("D4 authoring: the spec is closed and the ids are checked", function()
	local function bare()
		local core = Facet.newCore()
		local strip = UI.HStack({ id = "Strip", children = { UI.Button({ id = "A", label = "A" }) } })
		return core, strip
	end

	it("an unknown spec key is an authoring error, never a silent no-op", function()
		local core, strip = bare()
		local ok, err = pcall(function()
			selection_indicator.build(
				Facet,
				core,
				{
					content = strip,
					segments = { { value = "a", id = "A" } },
					selected = core:signal("a"),
					underlineThickness = 3, -- not a key this control reads
				} :: any
			)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "underlineThickness", 1, true) ~= nil).toBe(true)
	end)

	it("a segment id that names no child of `content` is caught at build", function()
		local core, strip = bare()
		local ok, err = pcall(function()
			selection_indicator.build(Facet, core, {
				content = strip,
				segments = { { value = "z", id = "Nope" } },
				selected = core:signal("z"),
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "'Nope'", 1, true) ~= nil).toBe(true)
	end)

	it("a strip built from a When/ForEach is trusted instead, and reports what never resolved", function()
		local core = Facet.newCore()
		local flag = core:signal(false)
		local strip = UI.HStack({
			id = "Strip",
			children = {
				UI.Button({ id = "A", label = "A" }),
				UI.When({
					id = "Extra",
					condition = flag,
					thenView = function()
						return UI.Button({ id = "B", label = "B" })
					end,
				}),
			},
		})
		local indicator = selection_indicator.build(Facet, core, {
			content = strip,
			segments = { { value = "a", id = "A" }, { value = "b", id = "B" } },
			selected = core:signal("a"),
		})
		expect(indicator.state().unresolved[1]).toBe("A") -- nothing has been solved yet
		indicator.dispose()
	end)

	it("an unknown skin or axis names the legal set", function()
		local core, strip = bare()
		local segments = { { value = "a", id = "A" } }
		local ok, err = pcall(function()
			selection_indicator.build(
				Facet,
				core,
				{ content = strip, segments = segments, selected = core:signal("a"), skin = "glow" }
			)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "underline | pill", 1, true) ~= nil).toBe(true)
		local ok2, err2 = pcall(function()
			selection_indicator.build(
				Facet,
				core,
				{ content = strip, segments = segments, selected = core:signal("a"), axis = "z" }
			)
		end)
		expect(ok2).toBe(false)
		expect(string.find(tostring(err2), "x | y", 1, true) ~= nil).toBe(true)
	end)

	it("with NO presenter (a bare mount) it still places the bar, instantly", function()
		-- the supported degradation: `bindMotion` never runs, so every retarget is
		-- an instant placement rather than a flight
		local core = Facet.newCore()
		local strip = UI.HStack({
			id = "Strip",
			children = {
				UI.Button({ id = "A", label = "A", width = { type = "fixed", px = 100 } }),
				UI.Button({ id = "B", label = "B", width = { type = "fixed", px = 100 } }),
			},
		})
		local selected = core:signal("a")
		local indicator = selection_indicator.build(Facet, core, {
			content = strip,
			segments = { { value = "a", id = "A" }, { value = "b", id = "B" } },
			selected = selected,
		})
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 200 })
		local adapter = fake_target.new()
		local root = Facet.mount(core, UI.Screen({ id = "S", children = { indicator.blueprint } }))
		local controller = Facet.renderer.attach(core, root, env, adapter)
		controller.initialRender()
		-- no presenter walked the tree, so nothing fed geometry: the bar is hidden
		-- rather than painted at the origin
		expect(indicator.state().placed).toBe(false)
		expect(indicator.state().animated).toBe(false)
		-- ...and once its own geometry is fed by hand, it places INSTANTLY: with no
		-- clock there is no flight to run, which is the degradation the seam owes a
		-- caller who mounts it without a presenter
		local bundle = Facet.contribution.read(root.node.children[1])
		bundle.syncGeometry(controller.rectOf, root.node.children[1])
		expect(indicator.state().placed).toBe(true)
		expect(indicator.state().rect.w).toBe(100)
		expect(indicator.state().slides).toBe(0)
		controller.dispose()
		indicator.dispose()
	end)
end)

--[[ THE PUBLIC SURFACE. Director ruling 2026-08-16: nobody instantiates the seam
	— `indicator = "underline" | "pill" | "none"` on the controls that consume it
	is the whole authoring surface, so these cases drive it the way an author
	will, through `newPicker`, and never touch the module. ]]
describe("D4 through the public property: newPicker's `indicator` and `axis`", function()
	local function pickerWorld(spec: any?)
		local options = spec or {}
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		if options.reducedMotion == true then
			env:set("reducedMotion", true)
		end
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local selected = core:signal("grid")
		local p = Facet.newPicker(Facet, core, {
			id = "View",
			selected = selected,
			options = { { value = "grid", label = "Grid" }, { value = "list", label = "Listing" } },
			presentation = "segmented",
			indicator = options.indicator,
			axis = options.axis,
			env = env,
		})
		local handle = pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		return { core = core, adapter = adapter, pres = pres, picker = p, selected = selected, handle = handle }
	end

	local PBAR = "/S/View/Indicator/Layer/Bar"
	-- with an indicator on, the options sit one level deeper: the decoration layer
	-- and the option stack have to share one parent, and that parent is the
	-- wrapper. Documented on `newPicker`, and asserted here so the move is a fact
	-- rather than a surprise.
	local function optPath(w: any, n: number): string
		local base = if w.picker.dump().indicator == "none" then "/S/View/Options" else "/S/View/Indicator/Options"
		return `{base}/Opt{n}`
	end

	it('indicator = "none" is byte-identical to the pre-D4 control', function()
		-- D4 shipped this as the DEFAULT so that nothing already on screen moved.
		-- D6 flipped the default to the pill (an unconsumed mechanism is an
		-- unproven one) and kept `"none"` as the documented escape hatch — so what
		-- this case guards is unchanged, and it now has to ask for it.
		-- `tests/picker_segments.spec.luau` owns the new default.
		local w = pickerWorld({ indicator = "none" })
		expect(w.adapter.node(PBAR)).toBeNil()
		-- ...and selection is still the style tag it always was
		expect(w.adapter.node(optPath(w, 1)).props.selected).toBe(true)
		expect(w.adapter.node(optPath(w, 2)).props.selected).toBe(false)
		expect(w.picker.dump().indicator).toBe("none")
	end)

	it('indicator = "pill" slides a chip between two unequal segments', function()
		local w = pickerWorld({ indicator = "pill" })
		local a = w.adapter.node(optPath(w, 1)).rect
		local b = w.adapter.node(optPath(w, 2)).rect
		expect(w.adapter.node(PBAR) ~= nil).toBe(true)
		expect(w.adapter.node(PBAR).rect.x).toBe(a.x + 4)
		w.selected:set("list")
		w.pres.refresh()
		local moved = false
		for _ = 1, 60 do
			w.pres.tick(1 / 60)
			w.pres.refresh()
			local r = w.adapter.node(PBAR).rect
			if r.x > a.x + 4 and r.x < b.x + 4 then
				moved = true
			end
		end
		expect(moved).toBe(true)
		expect(w.adapter.node(PBAR).rect.x).toBe(b.x + 4)
		expect(w.picker.dump().indicator.slides).toBe(1)
	end)

	it("turning it on makes the INDICATOR the selection paint, not a second one", function()
		-- a style tag AND a chip is the same statement twice, and an opaque button
		-- would paint over the chip meant to sit behind its label
		local w = pickerWorld({ indicator = "pill" })
		expect(w.adapter.node(optPath(w, 1)).props.selected).toBeNil()
		expect(w.adapter.node(optPath(w, 1)).props.surface).toBe("plain")
	end)

	it('axis = "y" is a real VERTICAL PILL, and it does not overload `inline`', function()
		local w = pickerWorld({ indicator = "pill", axis = "y" })
		local a = w.adapter.node(optPath(w, 1)).rect
		local b = w.adapter.node(optPath(w, 2)).rect
		expect(b.y > a.y).toBe(true) -- the options stack downward...
		expect(b.x).toBe(a.x) -- ...in one column
		expect(w.picker.dump().axis).toBe("y")
		expect(w.adapter.node(PBAR).rect.y).toBe(a.y + 4)
		w.selected:set("list")
		w.pres.refresh()
		for _ = 1, 60 do
			w.pres.tick(1 / 60)
			w.pres.refresh()
		end
		expect(w.adapter.node(PBAR).rect.y).toBe(b.y + 4)
		-- and `inline` still means the ROW LIST it always meant: a distinct shape
		local core = Facet.newCore()
		local inline = Facet.newPicker(Facet, core, {
			id = "P",
			selected = core:signal("a"),
			options = { { value = "a", label = "A" }, { value = "b", label = "B" } },
			presentation = "inline",
			axis = "x", -- inert: a stacked list is a column by definition
		})
		expect(inline.dump().axis).toBe("y")
		inline.dispose()
	end)

	it("the picker's own dump carries the indicator's state — there is no second schema", function()
		local w = pickerWorld({ indicator = "underline" })
		local d = w.picker.dump()
		expect(d.schema).toBe("facet-picker-dump/1")
		expect(d.indicator.skin).toBe("underline")
		expect(d.indicator.resolved).toBe(2)
		expect(d.indicator.placed).toBe(true)
		expect(d.indicator.rect ~= nil).toBe(true)
		expect(serde.encode("json", w.picker.dump(), true)).toBe(serde.encode("json", w.picker.dump(), true))
	end)

	it("an unknown indicator or axis names the legal set", function()
		local core = Facet.newCore()
		local function build(extra: any)
			local spec: any = {
				id = "P",
				selected = core:signal("a"),
				options = { { value = "a", label = "A" } },
			}
			for k, v in extra do
				spec[k] = v
			end
			return Facet.newPicker(Facet, core, spec)
		end
		local ok, err = pcall(build, { indicator = "glow" })
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "automatic | none | underline | pill", 1, true) ~= nil).toBe(true)
		local ok2, err2 = pcall(build, { axis = "z" })
		expect(ok2).toBe(false)
		expect(string.find(tostring(err2), "x | y", 1, true) ~= nil).toBe(true)
	end)

	it("wrapping does not collapse a `fill` strip — the options keep their width", function()
		-- WRAPPING IS NOT FREE, and this is the defect the Rascal Rally rider found
		-- first: a `fill` option inside a content-sized wrapper has nothing to fill
		-- and solves to ZERO. The wrapper therefore inherits the option stack's own
		-- dimension, and this compares the indicated control against the plain one
		-- rather than against a number somebody chose.
		local plain = pickerWorld({ indicator = "none" })
		local lit = pickerWorld({ indicator = "pill" })
		local plainWidth = plain.adapter.node(optPath(plain, 1)).rect.w
		expect(plainWidth > 0).toBe(true)
		expect(lit.adapter.node(optPath(lit, 1)).rect.w).toBe(plainWidth)
		expect(lit.adapter.node(PBAR).rect.w).toBe(plainWidth - 8)
	end)

	it("selection still works at the deeper path: a tap and a Return both choose", function()
		-- the wrapper moves every option one level down, and picker's Activate
		-- dispatch matches the LEAF segment — so this is the case that proves the
		-- move did not quietly break the control it decorates
		local w = pickerWorld({ indicator = "pill" })
		w.adapter.tap(optPath(w, 2))
		w.pres.refresh()
		expect(w.selected:get()).toBe("list")
		expect(w.picker.dump().indicator.selectedId).toBe("Opt2")
	end)

	it("an indicated picker is still exactly two focus stops, in order", function()
		local w = pickerWorld({ indicator = "pill" })
		local paths: { string } = {}
		focus_map.collectFocusables(w.handle.root.node, paths)
		expect(#paths).toBe(2)
		expect(paths[1]).toBe(optPath(w, 1))
		expect(paths[2]).toBe(optPath(w, 2))
	end)

	it("REDUCED MOTION snaps the picker's chip too: one write, then silence", function()
		local w = pickerWorld({ indicator = "pill", reducedMotion = true })
		local b = w.adapter.node(optPath(w, 2)).rect
		local function writes(): number
			local n = 0
			for _, op in w.adapter.takeOps() do
				if string.find(op, `rect {PBAR} `, 1, true) == 1 then
					n += 1
				end
			end
			return n
		end
		writes()
		w.selected:set("list")
		w.pres.refresh()
		expect(writes()).toBe(1)
		expect(w.adapter.node(PBAR).rect.x).toBe(b.x + 4)
		for _ = 1, 20 do
			w.pres.tick(1 / 60)
			w.pres.refresh()
		end
		expect(writes()).toBe(0)
	end)

	it("an indicated picker is registry-neutral: build, mount, switch, dispose", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local baseline = core:counters()
		local selected = core:signal("grid")
		local p = Facet.newPicker(Facet, core, {
			id = "View",
			selected = selected,
			options = { { value = "grid", label = "Grid" }, { value = "list", label = "Listing" } },
			presentation = "segmented",
			indicator = "pill",
			env = env,
		})
		local handle = pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		for _ = 1, 5 do
			selected:set("list")
			pres.refresh()
			pres.tick(1)
			selected:set("grid")
			pres.refresh()
			pres.tick(1)
		end
		pres.dismiss(handle)
		p.dispose()
		selected:dispose()
		local after = core:counters()
		for k, v in baseline :: any do
			expect((after :: any)[k]).toBe(v)
		end
	end)
end)

-- ===== the seam survives being RE-HOMED (found by D5) =====================
-- D5's TabView moves its strip between four `When`-gated homes as
-- `adaptive.navPlacement` changes — a leading rail on a desktop, a trailing band
-- on a phone. That REMOUNTS the wrapped strip at a different path, and the first
-- shipped version of this module learned the layer's path and every segment's
-- path EXACTLY ONCE (`if rootNode ~= nil and layerPath == nil`). After a
-- re-home, `rectOf(layerPath)` answered nil for a path that no longer exists,
-- `syncGeometry` returned early, and the bar froze at the rect it had before the
-- rotation — a chip painted in a place nobody measured, which is the defect
-- family this repo already has a name for.
--
-- It is a real latent bug for ANY consumer that mounts an indicated strip inside
-- a `When` that toggles, not a TabView special case, so the fix belongs here.
describe("D5 found: the paths are RE-RESOLVED when the strip is re-homed", function()
	local function homedWorld()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local selected = core:signal("a")
		local kids = {}
		for i, label in { "A", "B" } do
			table.insert(
				kids,
				UI.Button({
					id = label,
					label = label,
					width = { type = "fixed", px = if i == 1 then 120 else 80 },
					height = { type = "fixed", px = 48 },
				})
			)
		end
		local indicator = selection_indicator.build(Facet, core, {
			id = "Tabs",
			content = UI.HStack({ id = "Strip", gap = 0, children = kids }),
			segments = { { value = "a", id = "A" }, { value = "b", id = "B" } },
			selected = selected,
			skin = "pill",
			env = env,
		})
		-- the SAME wrapper blueprint declared in two mutually-exclusive homes, one
		-- leading and one trailing: exactly the shape the reference shells use for
		-- a nav bar, and exactly the shape TabView now owns
		local atTop = core:signal(true)
		local bottom = core:memo(function(use)
			return not use(atTop)
		end)
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "Page",
					gap = 0,
					children = {
						UI.When({
							id = "Top",
							condition = atTop,
							thenView = function()
								return indicator.blueprint
							end,
						}),
						UI.Box({ id = "Body", height = { type = "fixed", px = 100 } }),
						UI.When({
							id = "Bottom",
							condition = bottom,
							thenView = function()
								return indicator.blueprint
							end,
						}),
					},
				}),
			},
		}))
		pres.refresh()
		return { core = core, adapter = adapter, pres = pres, indicator = indicator, selected = selected, atTop = atTop }
	end

	it("re-homing the strip re-resolves the layer and every segment, and the bar follows", function()
		local w = homedWorld()
		expect(w.adapter.node("/S/Page/Top/then/Tabs/Layer/Bar") ~= nil).toBe(true)
		local before = w.indicator.state()
		expect(before.resolved).toBe(2)
		expect(#before.unresolved).toBe(0)
		local topRect = w.adapter.node("/S/Page/Top/then/Tabs/Layer/Bar").rect
		w.atTop:set(false)
		w.pres.refresh()
		-- the bar exists in its new home, still resolving both segments...
		local after = w.indicator.state()
		expect(after.resolved).toBe(2)
		expect(#after.unresolved).toBe(0)
		-- ...AND THE GEOMETRY REALLY ARRIVED. This is the assertion that fails when
		-- the paths are learned once: a stale `layerPath` makes `rectOf` answer nil
		-- and `syncGeometry` return early, so the seam goes silently deaf while
		-- every count it reports still looks right.
		expect(after.geometryUpdates > before.geometryUpdates).toBe(true)
		local moved = w.adapter.node("/S/Page/Bottom/then/Tabs/Layer/Bar")
		expect(moved ~= nil).toBe(true)
		expect(w.adapter.node("/S/Page/Top/then/Tabs/Layer/Bar")).toBeNil()
		-- ...and it is over the FIRST segment in the new home, not frozen at the
		-- rect it held in the old one
		local segment = w.adapter.node("/S/Page/Bottom/then/Tabs/Strip/A").rect
		expect(math.abs(moved.rect.x - (segment.x + 4)) < 0.001).toBe(true)
		expect(moved.rect.y ~= topRect.y).toBe(true)
	end)

	it("...and a selection change in the NEW home still moves the bar", function()
		local w = homedWorld()
		w.atTop:set(false)
		w.pres.refresh()
		local a = w.adapter.node("/S/Page/Bottom/then/Tabs/Strip/A").rect
		local b = w.adapter.node("/S/Page/Bottom/then/Tabs/Strip/B").rect
		expect(b.x > a.x).toBe(true)
		w.selected:set("b")
		for _ = 1, 200 do
			w.pres.tick(1 / 60)
			w.pres.refresh()
		end
		expect(math.abs(w.adapter.node("/S/Page/Bottom/then/Tabs/Layer/Bar").rect.x - (b.x + 4)) < 0.001).toBe(true)
		w.indicator.dispose()
	end)
end)
