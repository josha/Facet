--!strict
-- Milestone A — adaptive layout (docs/plans/parity-next.md investment 5;
-- acceptance rows A-AL1..A-AL3) and the axis-aware Divider (A-LV3).
--
-- The plan's rule: adaptation comes from available space, viewing distance, live
-- interaction classes and accessibility facts. "Phone", "Xbox" and "VR" must not
-- appear as screen-level layout branches. These tests therefore drive the
-- BREAKPOINT and the ENVIRONMENT, never a device name.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local adaptive = require("../src/layout/adaptive")
local fake_target = require("../tests/lib/fake_target")
local text_metrics = require("../src/layout/text_metrics")
local adapter_source = require("./lib/adapter_source")

local function fill(weight: number?)
	return { type = "fill", weight = weight or 1 }
end
local function fixed(px: number)
	return { type = "fixed", px = px }
end

describe("A-AL3: pure adaptive decisions (no device names)", function()
	it("classifies width into compact / regular / wide at the documented breakpoints", function()
		expect(adaptive.sizeClass(320)).toBe("compact")
		expect(adaptive.sizeClass(599)).toBe("compact")
		expect(adaptive.sizeClass(600)).toBe("regular")
		expect(adaptive.sizeClass(999)).toBe("regular")
		expect(adaptive.sizeClass(1000)).toBe("wide")
	end)

	it("a ten-foot display never resolves the densest class, however wide it is", function()
		expect(adaptive.sizeClass(1920, { distanceProfile = "ten-foot" })).toBe("regular")
		expect(adaptive.sizeClass(1920, { distanceProfile = "near" })).toBe("wide")
	end)

	it("chooses a stack axis from available width, not a platform name", function()
		expect(adaptive.axisFor(400, { stackAbove = 600 })).toBe("y")
		expect(adaptive.axisFor(800, { stackAbove = 600 })).toBe("x")
	end)

	it("derives a column count from a minimum cell width and gap", function()
		expect(adaptive.columnsFor(300, 90, 6)).toBe(3)
		expect(adaptive.columnsFor(100, 90, 6)).toBe(1)
		expect(adaptive.columnsFor(0, 90, 6)).toBe(1)
	end)

	--[[ ADAPT-23 — THE ONE FUNCTION THAT DECIDES DENSITY WAS THE ONE WITHOUT THE
		CAP. `sizeClass` and `heightClass` both refuse the densest arrangement at
		three metres and say why; `columnsFor` did not, so the framework's own
		documented adaptive-grid route answered ELEVEN columns on a television
		against NINE on a desktop — the module capping on the two functions that
		describe and not on the one that decides. The cap is the same one, against
		the same constant, and the lanes still divide the whole extent: fewer,
		larger cards at distance, which is what the rule was always for. ]]
	it("ADAPT-23: the ten-foot cap reaches the column count too", function()
		-- the audit's own case, at 160px cards with an 8px gutter: a 1920 television
		-- against a 1600 desktop, which is the pair it measured (11 against 9)
		expect(adaptive.columnsFor(1920, 160, 8)).toBe(11)
		expect(adaptive.columnsFor(1600, 160, 8)).toBe(9)
		local tv = adaptive.columnsFor(1920, 160, 8, { distanceProfile = "ten-foot" })
		expect(tv).toBe(adaptive.columnsFor(1000, 160, 8))
		expect(tv < adaptive.columnsFor(1600, 160, 8)).toBe(true) -- LESS dense than a desktop
		-- near distance is byte-identical to no opts at all
		expect(adaptive.columnsFor(1920, 160, 8, { distanceProfile = "near" })).toBe(11)
	end)

	it("tolerates a nonsense width instead of producing a nonsense class", function()
		expect(adaptive.sizeClass(0 / 0)).toBe("compact")
		expect(adaptive.sizeClass(-50)).toBe("compact")
	end)
end)

describe("A-AL3: reactive conditions over the environment", function()
	local function makeConditions(w: number, displaySize: string?)
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = w, h = 800 })
		if displaySize ~= nil then
			env:set("displaySize", displaySize)
		end
		return core, env, adaptive.conditions(core, env)
	end

	it("exposes the class and its boolean tests as Readables", function()
		local _, _, c = makeConditions(400)
		expect(c.sizeClass:get()).toBe("compact")
		expect(c.isCompact:get()).toBe(true)
		expect(c.isRegular:get()).toBe(false)
		expect(c.isWide:get()).toBe(false)
	end)

	it("re-resolves live when the viewport changes, with no remount", function()
		local _, env, c = makeConditions(400)
		expect(c.isCompact:get()).toBe(true)
		env:set("viewportRect", { x = 0, y = 0, w = 1200, h = 800 })
		expect(c.sizeClass:get()).toBe("wide")
		expect(c.isWide:get()).toBe(true)
		expect(c.isCompact:get()).toBe(false)
	end)

	it("isTenFoot follows the distance profile, not the input class", function()
		local _, _, near = makeConditions(1920, "Medium")
		expect(near.isTenFoot:get()).toBe(false)
		local _, _, far = makeConditions(1920, "Large")
		expect(far.isTenFoot:get()).toBe(true)
		-- and the ten-foot density floor applies
		expect(far.sizeClass:get()).toBe("regular")
	end)

	it("axis is a Readable an AdaptiveStack can bind directly", function()
		local _, env, c = makeConditions(400)
		expect(c.axis:get()).toBe("y")
		env:set("viewportRect", { x = 0, y = 0, w = 900, h = 800 })
		expect(c.axis:get()).toBe("x")
	end)

	it("REFUSES the engine's placeholder viewport: a degenerate write keeps the last real fact", function()
		--[[ Director clip 2026-08-04 (textpop.mov) + the boot watcher, measured:
			the camera reports 1x1 for the first client frame(s), and a surface
			painted from it derived the COMPACT class on a desktop-sized screen —
			then re-derived when the real number landed a frame later (the
			role-pick sub-copy visibly re-wrapped: two lines -> one, box widened).
			The environment's own rule applies at the fact boundary: an engine
			placeholder is not a fact (the `interactionClasses` precedent, worded
			there as "a preference the player has not expressed cannot outvote
			what the device is"). A viewport write without two real >1px axes is
			refused, and the fact keeps its last real value — the already-wired
			change signal delivers the true size within a frame. ]]
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 801, h = 392 })
		local BAD: { any } = {
			{ x = 0, y = 0, w = 1, h = 1 }, -- the measured boot placeholder
			{ x = 0, y = 0, w = 0, h = 720 },
			{ x = 0, y = 0, w = 1280, h = 0 },
			{ x = 0, y = 0, w = 0 / 0, h = 720 },
			{ x = 0, y = 0, w = 1280 }, -- h missing
			"garbage",
		}
		for i, bad in BAD do
			env:set("viewportRect", bad)
			local vp = env:get("viewportRect"):get()
			expect(`{i}:{vp.w}x{vp.h}`).toBe(`{i}:801x392`)
		end
		-- and nil is refused the same way, not stored
		env:set("viewportRect", nil)
		local vp = env:get("viewportRect"):get()
		expect(`{vp.w}x{vp.h}`).toBe("801x392")
		-- a REAL write still lands (the refusal is about placeholders, not writes)
		env:set("viewportRect", { x = 0, y = 0, w = 375, h = 812 })
		expect(env:get("viewportRect"):get().w).toBe(375)
	end)
end)

describe("A-AL2: AdaptiveStack changes axis without rebuilding anything", function()
	local function makeStack(core: any, env: any, axis: any)
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.AdaptiveStack({
					id = "Bar",
					axis = axis,
					gap = 8,
					width = fill(),
					height = fill(),
					children = {
						UI.Box({ id = "A", width = fixed(40), height = fixed(40) }),
						UI.Box({ id = "B", width = fixed(40), height = fixed(40) }),
					},
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		return root, adapter, controller
	end

	it("lays out vertically for axis y and horizontally for axis x", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		local _, adapterY = makeStack(core, env, "y")
		expect(adapterY.node("/S/Bar/A").rect.x).toBe(adapterY.node("/S/Bar/B").rect.x)
		expect(adapterY.node("/S/Bar/B").rect.y - adapterY.node("/S/Bar/A").rect.y).toBe(48)

		local core2 = customFactory.new()
		local env2 = environment.new(core2)
		env2:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		local _, adapterX = makeStack(core2, env2, "x")
		expect(adapterX.node("/S/Bar/A").rect.y).toBe(adapterX.node("/S/Bar/B").rect.y)
		expect(adapterX.node("/S/Bar/B").rect.x - adapterX.node("/S/Bar/A").rect.x).toBe(48)
	end)

	it("flipping the bound axis re-solves WITHOUT a factory rerun or a remount", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		local axis = core:signal("y")
		local root, adapter, controller = makeStack(core, env, axis)
		local factoryRunsBefore = root.counters().factoryRuns
		local mountedBefore = root.counters().mounted
		local createsBefore = controller.stats().creates
		adapter.takeOps()

		axis:set("x")
		controller.refresh()

		-- the layout actually changed
		expect(adapter.node("/S/Bar/A").rect.y).toBe(adapter.node("/S/Bar/B").rect.y)
		-- ...and nothing was rebuilt: this is the whole point of one class with a
		-- reactive axis instead of swapping VStack for HStack through a When
		expect(root.counters().factoryRuns).toBe(factoryRunsBefore)
		expect(root.counters().mounted).toBe(mountedBefore)
		expect(controller.stats().creates).toBe(createsBefore)
		expect(controller.stats().removes).toBe(0)
	end)

	it("an axis flip driven by a viewport change preserves node identity", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		local conditions = adaptive.conditions(core, env)
		local root, adapter, controller = makeStack(core, env, conditions.axis)
		expect(adapter.node("/S/Bar/A").rect.x).toBe(adapter.node("/S/Bar/B").rect.x)
		local createsBefore = controller.stats().creates

		env:set("viewportRect", { x = 0, y = 0, w = 900, h = 400 })
		controller.refresh()

		expect(adapter.node("/S/Bar/A").rect.y).toBe(adapter.node("/S/Bar/B").rect.y)
		expect(controller.stats().creates).toBe(createsBefore)
		expect(root.counters().factoryRuns).toBe(4) -- Screen, Bar, A, B — unchanged
	end)

	it("gap is reactive too, so spacing adapts without a rebuild", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		local gap = core:signal(8)
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.AdaptiveStack({
					id = "Bar",
					axis = "y",
					gap = gap,
					width = fill(),
					height = fill(),
					children = {
						UI.Box({ id = "A", width = fixed(40), height = fixed(40) }),
						UI.Box({ id = "B", width = fixed(40), height = fixed(40) }),
					},
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local createsBefore = controller.stats().creates
		gap:set(24)
		controller.refresh()
		expect(adapter.node("/S/Bar/B").rect.y - adapter.node("/S/Bar/A").rect.y).toBe(64)
		expect(controller.stats().creates).toBe(createsBefore)
	end)

	it("rejects an axis outside the closed set at construction", function()
		local ok, err = pcall(function()
			return UI.AdaptiveStack({ id = "Bar", axis = "diagonal" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "one of y | x", 1, true) ~= nil).toBe(true)
	end)
end)

describe("A-LV3: Divider is axis-aware", function()
	local function solveDivider(parentClass: string)
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 300, h = 300 })
		local ctor = (UI :: any)[parentClass]
		local bp = UI.Screen({
			id = "S",
			children = {
				ctor({
					id = "P",
					width = fill(),
					height = fill(),
					children = {
						UI.Box({ id = "A", width = fixed(20), height = fixed(20) }),
						UI.Divider({ id = "D" }),
						UI.Box({ id = "B", width = fixed(20), height = fixed(20) }),
					},
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		return adapter
	end

	it("draws a horizontal hairline in a vertical stack", function()
		local adapter = solveDivider("VStack")
		local d = adapter.node("/S/P/D").rect
		expect(d.h).toBe(1)
		expect(d.w).toBe(300) -- spans the stack's cross axis
	end)

	it("draws a vertical hairline in a horizontal stack", function()
		local adapter = solveDivider("HStack")
		local d = adapter.node("/S/P/D").rect
		expect(d.w).toBe(1)
		expect(d.h).toBe(300)
	end)

	it("an explicit orientation overrides the inferred one", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 300, h = 300 })
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "P",
					width = fill(),
					height = fill(),
					children = { UI.Divider({ id = "D", axis = "x" }) },
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect(adapter.node("/S/P/D").rect.w).toBe(1)
	end)

	it("follows an AdaptiveStack's axis flip with no rebuild", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 300, h = 300 })
		local axis = core:signal("y")
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.AdaptiveStack({
					id = "P",
					axis = axis,
					width = fill(),
					height = fill(),
					children = {
						UI.Box({ id = "A", width = fixed(20), height = fixed(20) }),
						UI.Divider({ id = "D" }),
					},
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect(adapter.node("/S/P/D").rect.h).toBe(1)
		local createsBefore = controller.stats().creates
		axis:set("x")
		controller.refresh()
		expect(adapter.node("/S/P/D").rect.w).toBe(1)
		expect(controller.stats().creates).toBe(createsBefore)
	end)

	it("is non-interactive and takes no children", function()
		local ok = pcall(function()
			return UI.Divider({ id = "D", children = { UI.Box({ id = "c" }) } })
		end)
		expect(ok).toBe(false)
	end)
end)

-- ===== A-AL1: ViewThatFits =================================================
-- Candidate layouts tried in declared order against the REAL measurement
-- contract, so the choice depends on the space the container actually received
-- rather than on a viewport-wide guess or a device name. Every candidate stays
-- MOUNTED (so a resize is a re-solve, not a rebuild); the unchosen ones are
-- hidden and — critically — removed from focus order, so keyboard and gamepad
-- navigation can never land on an invisible control.

describe("A-AL1: ViewThatFits", function()
	local presenterLib = require("../src/present/presenter")
	local actionsLib = require("../src/input/actions")

	local function makeFits(viewportW: number)
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = viewportW, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.ViewThatFits({
					id = "Fits",
					width = fill(),
					children = {
						-- widest first: the declared order IS the preference order
						UI.Box({ id = "Wide", width = fixed(500), height = fixed(40) }),
						UI.Box({ id = "Mid", width = fixed(250), height = fixed(40) }),
						UI.Box({ id = "Narrow", width = fixed(100), height = fixed(40) }),
					},
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		return core, env, root, adapter, controller
	end

	it("picks the first candidate that fits the available space", function()
		local _, _, _, adapter = makeFits(600)
		expect(adapter.node("/S/Fits/Wide").rect.w).toBe(500)
		expect(adapter.node("/S/Fits/Mid").rect.w).toBe(0)
		expect(adapter.node("/S/Fits/Narrow").rect.w).toBe(0)
	end)

	it("falls through to a later candidate when the first does not fit", function()
		local _, _, _, adapter = makeFits(300)
		expect(adapter.node("/S/Fits/Wide").rect.w).toBe(0)
		expect(adapter.node("/S/Fits/Mid").rect.w).toBe(250)
		expect(adapter.node("/S/Fits/Narrow").rect.w).toBe(0)
	end)

	it("uses the LAST candidate as the fallback when none fits", function()
		local _, _, _, adapter = makeFits(60)
		expect(adapter.node("/S/Fits/Wide").rect.w).toBe(0)
		expect(adapter.node("/S/Fits/Mid").rect.w).toBe(0)
		expect(adapter.node("/S/Fits/Narrow").rect.w).toBe(100)
	end)

	it("re-chooses on a live resize WITHOUT remounting any candidate", function()
		local _, env, root, adapter, controller = makeFits(600)
		expect(adapter.node("/S/Fits/Wide").rect.w).toBe(500)
		local factoryRunsBefore = root.counters().factoryRuns
		local createsBefore = controller.stats().creates

		env:set("viewportRect", { x = 0, y = 0, w = 300, h = 400 })
		controller.refresh()

		expect(adapter.node("/S/Fits/Mid").rect.w).toBe(250)
		expect(adapter.node("/S/Fits/Wide").rect.w).toBe(0)
		-- every candidate stayed mounted: a resize is a re-solve, not a rebuild
		expect(root.counters().factoryRuns).toBe(factoryRunsBefore)
		expect(controller.stats().creates).toBe(createsBefore)
		expect(controller.stats().removes).toBe(0)
	end)

	it("measures against the CONTAINER's space, not the viewport's", function()
		-- the chooser sits inside a narrow column of a wide screen; the wide
		-- candidate must lose even though the viewport could hold it
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1200, h = 400 })
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.HStack({
					id = "Cols",
					width = fill(),
					children = {
						UI.Box({ id = "Sidebar", width = fixed(1000), height = fixed(40) }),
						UI.ViewThatFits({
							id = "Fits",
							width = fill(),
							children = {
								UI.Box({ id = "Wide", width = fixed(500), height = fixed(40) }),
								UI.Box({ id = "Narrow", width = fixed(100), height = fixed(40) }),
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
		expect(adapter.node("/S/Cols/Fits/Wide").rect.w).toBe(0)
		expect(adapter.node("/S/Cols/Fits/Narrow").rect.w).toBe(100)
	end)

	it("an unchosen candidate's focusables are removed from focus order", function()
		-- the reachability requirement: navigation must never land on a hidden
		-- control just because it is still mounted
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 200, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.ViewThatFits({
					id = "Fits",
					width = fill(),
					children = {
						UI.Button({ id = "WideBtn", label = "w", width = fixed(500), height = fixed(44) }),
						UI.Button({ id = "NarrowBtn", label = "n", width = fixed(100), height = fixed(44) }),
					},
				}),
			},
		}))
		pres.refresh()
		-- drive REAL navigation and watch where focus can land, rather than
		-- reading an internal order list
		local visited = {}
		for _ = 1, 6 do
			system.deviceKey("DPadDown", true)
			system.deviceKey("DPadDown", false)
			pres.refresh()
			local f = pres.focus.focused:get()
			if f ~= nil then
				visited[f] = true
			end
		end
		local joined = ""
		for path in visited do
			joined ..= path .. ","
		end
		expect(string.find(joined, "NarrowBtn", 1, true) ~= nil).toBe(true)
		expect(string.find(joined, "WideBtn", 1, true)).toBe(nil)
	end)

	it("focus order follows the choice when the space changes", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 200, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.ViewThatFits({
					id = "Fits",
					width = fill(),
					children = {
						UI.Button({ id = "WideBtn", label = "w", width = fixed(500), height = fixed(44) }),
						UI.Button({ id = "NarrowBtn", label = "n", width = fixed(100), height = fixed(44) }),
					},
				}),
			},
		}))
		local function reachable(): string
			local seen = ""
			for _ = 1, 6 do
				system.deviceKey("DPadDown", true)
				system.deviceKey("DPadDown", false)
				pres.refresh()
				local f = pres.focus.focused:get()
				if f ~= nil then
					seen ..= f .. ","
				end
			end
			return seen
		end
		pres.refresh()
		local narrowPhase = reachable()
		expect(string.find(narrowPhase, "NarrowBtn", 1, true) ~= nil).toBe(true)
		expect(string.find(narrowPhase, "WideBtn", 1, true)).toBe(nil)

		env:set("viewportRect", { x = 0, y = 0, w = 900, h = 400 })
		pres.refresh()
		local widePhase = reachable()
		expect(string.find(widePhase, "WideBtn", 1, true) ~= nil).toBe(true)
		expect(string.find(widePhase, "NarrowBtn", 1, true)).toBe(nil)
	end)

	it("the exclusion holds when the candidates are STACKS, so nav is grouped", function()
		-- REGRESSION (found building RascalRally's results CTA band, 2026-07-30):
		-- the two tests above pass BARE buttons, which derives the FLAT ring — the
		-- one path that filtered hidden nodes. The real shape of a reflowing action
		-- band is row-of-two vs column-of-two, and an HStack of focusables derives a
		-- GROUPED scope, which skipped the filter entirely: a pad walked onto the
		-- hidden COLUMN's buttons and could not reach the visible ROW at all.
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 900, h = 700 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		local function pair(prefix: string): { any }
			return {
				UI.Button({ id = `{prefix}A`, label = "aa", width = fixed(170), height = fixed(52) }),
				UI.Button({ id = `{prefix}B`, label = "bb", width = fixed(170), height = fixed(52) }),
			}
		end
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.ViewThatFits({
					id = "Fits",
					children = {
						UI.HStack({ id = "Row", gap = 8, children = pair("Row") }),
						UI.VStack({ id = "Col", gap = 8, children = pair("Col") }),
					},
				}),
			},
		}))
		pres.refresh()
		local function reachableBoth(): string
			local seen = ""
			for _, key in { "DPadDown", "DPadRight" } do
				for _ = 1, 6 do
					system.deviceKey(key, true)
					system.deviceKey(key, false)
					pres.refresh()
					local f = pres.focus.focused:get()
					if f ~= nil then
						seen ..= f .. ","
					end
				end
			end
			return seen
		end
		-- wide: the ROW candidate wins and is the ONLY thing a pad can reach
		expect(adapter.visibleOf("/S/Fits/Row")).toBe(true)
		local wide = reachableBoth()
		expect(string.find(wide, "/S/Fits/Row/", 1, true) ~= nil).toBe(true)
		expect(string.find(wide, "/S/Fits/Col/", 1, true)).toBe(nil)

		-- narrow: the choice flips and so does the ring, with no remount
		env:set("viewportRect", { x = 0, y = 0, w = 300, h = 700 })
		pres.refresh()
		expect(adapter.visibleOf("/S/Fits/Col")).toBe(true)
		local narrow = reachableBoth()
		expect(string.find(narrow, "/S/Fits/Col/", 1, true) ~= nil).toBe(true)
		expect(string.find(narrow, "/S/Fits/Row/", 1, true)).toBe(nil)
	end)

	it("a losing candidate is HIDDEN, not merely zero-sized", function()
		-- REGRESSION (found live): a zero rect is not invisibility. The losing
		-- action column's text still wrapped and painted inside a 0px box, running
		-- its labels down the screen edge in the adaptive_controls capture.
		local _, _, _, adapter = makeFits(600)
		expect(adapter.visibleOf("/S/Fits/Wide")).toBe(true)
		expect(adapter.visibleOf("/S/Fits/Mid")).toBe(false)
		expect(adapter.visibleOf("/S/Fits/Narrow")).toBe(false)
	end)

	it("visibility follows the choice on a resize", function()
		local _, env, _, adapter, controller = makeFits(600)
		expect(adapter.visibleOf("/S/Fits/Wide")).toBe(true)
		env:set("viewportRect", { x = 0, y = 0, w = 300, h = 400 })
		controller.refresh()
		expect(adapter.visibleOf("/S/Fits/Wide")).toBe(false)
		expect(adapter.visibleOf("/S/Fits/Mid")).toBe(true)
	end)

	it("a hidden candidate's DESCENDANTS are hidden too", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 200, h = 400 })
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.ViewThatFits({
					id = "Fits",
					width = fill(),
					children = {
						UI.HStack({
							id = "WideRow",
							width = fixed(500),
							children = { UI.Text({ id = "Deep", text = "wide" }) },
						}),
						UI.Text({ id = "Small", text = "narrow" }),
					},
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect(adapter.visibleOf("/S/Fits/WideRow")).toBe(false)
		expect(adapter.visibleOf("/S/Fits/WideRow/Deep")).toBe(false)
		expect(adapter.visibleOf("/S/Fits/Small")).toBe(true)
	end)

	it("a single candidate is always chosen", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 50, h = 400 })
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.ViewThatFits({
					id = "Fits",
					width = fill(),
					children = { UI.Box({ id = "Only", width = fixed(500), height = fixed(40) }) },
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect(adapter.node("/S/Fits/Only").rect.w).toBe(500)
	end)

	it("requires at least one candidate", function()
		local ok = pcall(function()
			return UI.ViewThatFits({ id = "Fits" })
		end)
		expect(ok).toBe(false)
	end)

	--[[ ── A CANDIDATE THAT ONLY "FITS" BECAUSE ITS LABEL WAS CUT DOES NOT FIT ────
		(DIR wave contract 7, 2026-08-18; director device round 2026-08-17 —
		`artifacts/release-candidate-review/rename/dir-reproductions.md`: the topbar
		objective chip's width swap *"measures with neutral metrics"*, and under
		fantasy-ornate the styled "Round 3 · Capture" spilled its plate instead of
		swapping to "R3".)

		THE MECHANISM, and it is one line away from the fix that caused it. A
		single-line text node clamps its reported width to the box it will occupy —
		`min(measured, availW)` — which landed on 2026-08-13 so that `truncated`
		would be honest about a `fixed(150)` Button whose line wants 340px. Correct
		there, and fatal HERE: `chosenCandidate` asks each candidate to measure at
		the offer and takes the first one whose width is `<= availW`. With the clamp
		in the way a candidate holding a single-line label can NEVER report more than
		the offer, so **the first candidate always fits** and every ViewThatFits over
		text has been picking its richest rung and letting the engine ellipsize it.

		`fitProbe` is the seam that already exists for exactly this question — it is
		on while a candidate is being judged, and its own comment says the candidate
		is "judged at the size it would like, the ideal size". The clamp was the
		one measure-side reduction it did not suppress.

		THE VERDICTS ARE UNTOUCHED: `recordTextFacts` still runs before the return, so
		`truncated` is still computed against the real box and `clippedEssential` is
		as sharp as it was. Only the SIZE the probe is answered with moves. ]]
	--[[ THE SHAPE THIS CASE HAS TO DRIVE, and it is not the obvious one. A phrase
		whose longest WORD still fits the offer does not clamp — it WRAPS, and the
		`lineLimit` then caps it, which is the author's own instruction being followed
		rather than the box being too small (see `chosenCandidate`). The defect is the
		CLAMPED cut: a line the box cannot hold at all. So the offer here is narrower
		than the longest word in the label, which is what forces the single-line
		measure and the clamp with it. ]]
	local function chipFits(viewportW: number): any
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = viewportW, h = 200 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.ViewThatFits({
					id = "Fits",
					children = {
						-- ONE UNBROKEN WORD, so no wrap can save it: the box either holds
						-- the line or clamps it, which is the shape the rule is about
						UI.Text({ id = "Long", text = "Reconfiguration" }),
						UI.Text({ id = "Short", text = "R3" }),
					},
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		return adapter
	end

	it("DIR-7: a candidate whose single-line label would be CUT does not count as fitting", function()
		local adapter = chipFits(40)
		local long = adapter.node("/S/Fits/Long")
		local short = adapter.node("/S/Fits/Short")
		expect(`both candidates are mounted: {long ~= nil and short ~= nil}`).toBe("both candidates are mounted: true")
		--[[ THE PREMISE: the long label really does want more than the offer. Without
			this the case passes on a viewport where both candidates fit and proves
			nothing at all — and the number comes from the same measurer the solve
			uses, so it cannot drift from what the solve believes. ]]
		local wants = text_metrics.minWidth("Reconfiguration", "BuilderSans#Regular#Normal", 14)
		expect(`the long label wants {wants}px against a 40px offer: {wants > 40}`).toBe(
			`the long label wants {wants}px against a 40px offer: true`
		)
		-- ...so the SHORT rung is the one on screen, and the long one is hidden
		expect(`the short rung won: {adapter.visibleOf("/S/Fits/Short") ~= false}`).toBe("the short rung won: true")
		expect(`the long rung is hidden: {adapter.visibleOf("/S/Fits/Long") == false}`).toBe(
			"the long rung is hidden: true"
		)
	end)

	--[[ ── M1a: A NESTED LADDER'S REJECTED RUNG IS NOT THE OUTER LADDER'S CUT ────
		(fresh-context review of the DIR wave, 2026-08-18.)

		`ctx.fitCuts` is solve-wide and an enclosing `ViewThatFits` reads its DELTA
		across the whole candidate subtree, so every rung an INNER ladder rejected
		was being billed to the outer one. The A/B is the reviewer's, and its point
		is that both trees paint exactly the same characters — only the inner
		ladder's first, rejected rung differs:

		  A: inner rung 1 is a word the inner offer cannot hold, so the inner ladder
		     correctly takes its short rung;
		  B: inner rung 1 already fits, so nothing is cut anywhere.

		Before the fix the outer ladder kept its rich rung in B and dropped it in A.
		A subtree CONTAINING a cut and a subtree that WILL PAINT one are different
		facts, and only the second is a fit failure. ]]
	local function nestedFits(innerRich: string): any
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 200 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.ViewThatFits({
					id = "Outer",
					children = {
						-- the RICH rung: a fixed 40px box beside a ladder of its own
						UI.HStack({
							id = "Rich",
							gap = 4,
							children = {
								UI.Box({ id = "Mark", width = fixed(20), height = fixed(20) }),
								UI.ViewThatFits({
									id = "Inner",
									children = {
										UI.Text({ id = "InnerRich", text = innerRich }),
										UI.Text({ id = "InnerShort", text = "R3" }),
									},
									width = fixed(40),
								}),
							},
						}),
						UI.Text({ id = "Plain", text = "R3" }),
					},
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		return adapter
	end

	it("M1a: a nested ladder that resolves internally costs the outer ladder nothing", function()
		local cut = nestedFits("Reconfiguration")
		local clean = nestedFits("R3")
		--[[ THE PREMISE: the inner ladder really did reject its own rich rung in A
			and really did not have to in B. Without this the case compares two trees
			that took the same inner path and proves nothing about the leak. ]]
		expect(`A: the inner ladder took its short rung: {cut.visibleOf("/S/Outer/Rich/Inner/InnerShort") ~= false}`).toBe(
			"A: the inner ladder took its short rung: true"
		)
		expect(`B: the inner ladder kept its rich rung: {clean.visibleOf("/S/Outer/Rich/Inner/InnerRich") ~= false}`).toBe(
			"B: the inner ladder kept its rich rung: true"
		)
		-- ...and BOTH outer ladders keep the rich rung, because both paint "R3"
		expect(`B: the outer ladder kept its rich rung: {clean.visibleOf("/S/Outer/Rich") ~= false}`).toBe(
			"B: the outer ladder kept its rich rung: true"
		)
		expect(`A: the outer ladder kept its rich rung too: {cut.visibleOf("/S/Outer/Rich") ~= false}`).toBe(
			"A: the outer ladder kept its rich rung too: true"
		)
	end)

	--[[ ── M1b: AN AUTHORED WIDTH IS AN INSTRUCTION, NOT A SHORTAGE ──────────────
		Same review. `clampedWidth` is true whenever a measured line exceeds the
		width the node will occupy — and when that width is the author's own
		`{ type = "fixed" }`, nobody was short of anything. Measured by the reviewer
		on a 400px screen with no pressure at all: a rung of
		`HStack{ Box 20, Text(pinned 30) }` was refused and the plain fallback won.

		The `truncated` VERDICT is deliberately untouched: an authored pin that cuts
		a label is still a cut label and `clippedEssential` still says so. What
		changes is only whether the LADDER treats it as a failure to fit. ]]
	it("M1b: an author-pinned label's own width does not lose its rung", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 200 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.ViewThatFits({
					id = "Fits",
					children = {
						UI.HStack({
							id = "Rich",
							gap = 4,
							children = {
								UI.Box({ id = "Mark", width = fixed(20), height = fixed(20) }),
								UI.Text({ id = "Pinned", text = "Reconfiguration", width = fixed(30) }),
							},
						}),
						UI.Text({ id = "Plain", text = "R3" }),
					},
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		--[[ THE PREMISE: there is no pressure at all — the rich rung measures well
			inside a 400px screen — so anything that loses it lost it for the pin. ]]
		local rich = adapter.node("/S/Fits/Rich")
		expect(`the rich rung is nowhere near the offer: {rich ~= nil and rich.rect.w < 200}`).toBe(
			"the rich rung is nowhere near the offer: true"
		)
		expect(`the author's pin kept its rung: {adapter.visibleOf("/S/Fits/Rich") ~= false}`).toBe(
			"the author's pin kept its rung: true"
		)
		--[[ ...AND THE VERDICT IS STILL HONEST. The pin really does cut the label,
			and the framework must still say so — the ladder ignoring it is a
			DIFFERENT question from `clippedEssential` reporting it. ]]
		local facts = controller.textAt("/S/Fits/Rich/Pinned")
		expect(`the pinned label is still reported truncated: {facts ~= nil and facts.truncated}`).toBe(
			"the pinned label is still reported truncated: true"
		)
	end)

	--[[ THE CONTROL FOR THE CASE ABOVE: a candidate that genuinely fits still wins,
		so the fix did not simply teach ViewThatFits to always take its fallback. ]]
	it("DIR-7 control: a candidate that really does fit is still the one chosen", function()
		local adapter = chipFits(600)
		expect(`the long rung won on a wide screen: {adapter.visibleOf("/S/Fits/Long") ~= false}`).toBe(
			"the long rung won on a wide screen: true"
		)
		expect(`...and it is not truncated: {adapter.node("/S/Fits/Long").rect.w > 40}`).toBe(
			"...and it is not truncated: true"
		)
	end)
end)

-- ===== RS-A16-D1: a hidden candidate keeps no LIVE hit target ===============
-- Found by the rich-skinning-v2 five-view matrix drive (2026-07-26), under the
-- FLAT default, with real injected clicks: the losing action COLUMN was
-- Visible=false at 0x0, but the renderer still asked for an expanded HIT rect for
-- each of its zero-width buttons (they are below the 44px floor), and the adapter
-- realised each as a TextButton parented at the ScreenGui ROOT with
-- ZIndex = target - 1. Because the loser is emitted after the winner, its 108..110
-- out-ranked the visible row's 103..105: GetGuiObjectsAtPosition(315, 970) — inside
-- the visible "Save changes" — returned the expander first, and a real click there
-- activated a control that was not on screen while the visible button got nothing.
--
-- Two halves, two places (execution contract §6). The renderer DECISION is pure:
-- a hidden node must request no hit geometry, and a node that BECOMES hidden must
-- have its expander retracted. The adapter half is structural: an expander mirrors
-- its host's visibility, so the class cannot come back through a future caller.

describe("RS-A16-D1: a hidden ViewThatFits candidate requests no hit geometry", function()
	local function makeFits(viewportW: number)
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = viewportW, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		-- both candidates hold a SUB-FLOOR button, which is what makes each of them
		-- an expander request while it is hidden (a hidden candidate solves to zero
		-- width, so every control inside it is under the floor)
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.ViewThatFits({
					id = "Fits",
					width = fill(),
					children = {
						UI.HStack({
							id = "Row",
							width = fixed(500),
							children = {
								UI.Button({ id = "Wide", label = "w", width = fixed(22), height = fixed(22) }),
							},
						}),
						UI.VStack({
							id = "Col",
							width = fixed(100),
							children = {
								UI.Button({ id = "Narrow", label = "n", width = fixed(22), height = fixed(22) }),
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
		return env, adapter, controller
	end

	it("a hidden candidate's sub-floor control asks for NO hit rect", function()
		local _, adapter = makeFits(200) -- narrow: the Row loses, the Col wins
		expect(adapter.visibleOf("/S/Fits/Row")).toBe(false)
		expect(adapter.visibleOf("/S/Fits/Row/Wide")).toBe(false)
		-- the defect: the hidden button solved to 0x22, fell under the floor and got
		-- a live 44x44 activation surface at the ScreenGui root
		expect(adapter.hitRectOf("/S/Fits/Row/Wide")).toBe(nil)
	end)

	it("the VISIBLE winner's hit geometry is unchanged by the fix", function()
		local _, adapter = makeFits(200)
		local node = adapter.node("/S/Fits/Col/Narrow")
		expect(node.rect.w).toBe(22)
		local hit = adapter.hitRectOf("/S/Fits/Col/Narrow") :: any
		expect(hit ~= nil).toBe(true)
		expect(hit.w).toBe(44)
		expect(hit.h).toBe(44)
		expect(hit.x).toBe(node.rect.x - 11)
		expect(hit.y).toBe(node.rect.y - 11)
	end)

	it("a node hidden AFTER expansion has its expander RETRACTED", function()
		-- the transition case: a mid-session ViewThatFits re-choice must retract the
		-- loser's activation surface, not merely stop refreshing it
		local env, adapter, controller = makeFits(600) -- wide: the Row wins
		expect(adapter.visibleOf("/S/Fits/Row/Wide")).toBe(true)
		expect((adapter.hitRectOf("/S/Fits/Row/Wide") :: any).w).toBe(44)

		adapter.takeOps()
		env:set("viewportRect", { x = 0, y = 0, w = 200, h = 400 })
		controller.refresh()

		expect(adapter.visibleOf("/S/Fits/Row/Wide")).toBe(false)
		expect(adapter.hitRectOf("/S/Fits/Row/Wide")).toBe(nil)
		-- and the adapter was TOLD to remove it (a stale cache that merely stops
		-- writing would leave the instance alive in the real target)
		local ops = table.concat(adapter.takeOps(), "\n")
		expect(string.find(ops, "hitrect /S/Fits/Row/Wide=nil", 1, true) ~= nil).toBe(true)
		-- the new winner is expanded in the same commit
		expect((adapter.hitRectOf("/S/Fits/Col/Narrow") :: any).w).toBe(44)
	end)

	it("re-choosing BACK re-expands the control that became visible again", function()
		local env, adapter, controller = makeFits(200)
		expect(adapter.hitRectOf("/S/Fits/Row/Wide")).toBe(nil)
		env:set("viewportRect", { x = 0, y = 0, w = 600, h = 400 })
		controller.refresh()
		expect(adapter.visibleOf("/S/Fits/Row/Wide")).toBe(true)
		expect((adapter.hitRectOf("/S/Fits/Row/Wide") :: any).w).toBe(44)
		expect(adapter.hitRectOf("/S/Fits/Col/Narrow")).toBe(nil)
	end)

	it("hiddenness reaches a DEEP descendant, not just the candidate root", function()
		-- nextHidden marks the candidate ROOT only; the walk has to carry it down,
		-- exactly as the visibility walk does
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 200, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.ViewThatFits({
						id = "Fits",
						width = fill(),
						children = {
							UI.HStack({
								id = "Row",
								width = fixed(500),
								children = {
									UI.VStack({
										id = "Group",
										children = {
											UI.Button({
												id = "Deep",
												label = "d",
												width = fixed(22),
												height = fixed(22),
											}),
										},
									}),
								},
							}),
							UI.Button({ id = "Small", label = "s", width = fixed(22), height = fixed(22) }),
						},
					}),
				},
			})
		)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect(adapter.visibleOf("/S/Fits/Row/Group/Deep")).toBe(false)
		expect(adapter.hitRectOf("/S/Fits/Row/Group/Deep")).toBe(nil)
		expect((adapter.hitRectOf("/S/Fits/Small") :: any).w).toBe(44)
	end)

	it("the adapter mirrors its host's visibility onto the expander (structural half)", function()
		-- the renderer decision above is provable headlessly; that an expander can
		-- never outlive or out-rank a hidden host is an ADAPTER property, asserted at
		-- the source anchors (screen_target.luau is engine-only)
		local source = require("@lune/fs").readFile("src/client/screen_target.luau")
		--[[ THE WINDOW IS THE FUNCTION, NOT A CHARACTER COUNT.

			These two anchors used to slice a fixed 700 and 2200 characters after
			the declaration. That makes the assertion depend on how long the
			COMMENTS inside the function are: a plain-language rewrite that grew
			one comment by a few characters pushed `hitExpander` one character
			past the 700 mark and reddened this case with nothing about the
			behaviour changed. The window now ends where the next adapter method
			begins, so only the function's own contents decide it. ]]
		local function methodBody(name: string): string
			local at = string.find(source, `function adapter.{name}`, 1, true)
			expect(at ~= nil).toBe(true)
			local nextAt = string.find(source, "\n\tfunction adapter.", (at :: number) + 1, true)
			return string.sub(source, at :: number, if nextAt == nil then #source else nextAt)
		end
		local visibleBody = methodBody("setVisible")
		-- setVisible carries the expander with the control it belongs to
		expect(string.find(visibleBody, "hitExpander", 1, true) ~= nil).toBe(true)
		local hitBody = methodBody("setHitRect")
		-- a freshly created expander starts at its host's CURRENT visibility, so it
		-- cannot flash live for a control that is already hidden
		expect(string.find(hitBody, "expander.Visible = instance.Visible", 1, true) ~= nil).toBe(true)
		-- and activation refuses a host the player cannot see
		expect(string.find(hitBody, "handle.instance.Visible", 1, true) ~= nil).toBe(true)
	end)

	--[[ BOTH ACTIVATE PRODUCERS BUILD THEIR META THROUGH THE ONE SHARED BUILDER
		(redteam item 2, HIGH; 2026-08-13) ────────────────────────────────────────
		The hit expander is a second real `GuiButton` that activates the host
		control, and it used to send `{ source = "hitExpander" }` — a meta that
		EXISTS but names no pointer kind, which satisfies neither half of a
		control's `meta == nil or meta.pointer == "touch"` test and therefore
		answered every finger in a short row's 44px overhang as a mouse click.
		Measured on an edit-mode multi-select Table: three taps built r1,r2,r3 and
		one tap in the overhang replace-selected r4, discarding the lot; two
		overhang taps inside the double-click window opened the row, i.e. a
		double-tap-to-open on a phone.

		`screen_target.luau` is engine-only, so this is asserted at the source
		anchors — and it asserts the SHAPE OF THE FIX (one builder, two callers)
		rather than a string in each producer, because a second copy of the meta
		is exactly how this defect comes back. ]]
	it("both activate producers build their meta through the one shared builder", function()
		-- THE WHOLE ADAPTER, not one of its files: the builder and producer 1 went to
		-- `screen_pointer` with the pointer seam when screen_target crossed the
		-- 200_000-char Source cap, while producer 2 (the hit expander) stayed with
		-- `setHitRect`. Reading the parts as one text is what makes "exactly one
		-- builder" mean what it says — a copy in ANY part of the adapter now reddens
		-- this, where a single-file read could only ever see one file's copies.
		local source = adapter_source.live()
		-- the builder exists, exactly once, and it classifies the pointer kind
		local atBuilder = string.find(source, "local function pointerActivateMeta", 1, true)
		expect(atBuilder ~= nil).toBe(true)
		expect(string.find(source, "local function pointerActivateMeta", (atBuilder :: number) + 1, true)).toBe(nil)
		local builder = string.sub(source, atBuilder :: number, (atBuilder :: number) + 1400)
		expect(string.find(builder, "Enum.UserInputType.Touch", 1, true) ~= nil).toBe(true)
		expect(string.find(builder, 'pointer = "touch"', 1, true) ~= nil).toBe(true)
		expect(string.find(builder, "pointer = pointer", 1, true) ~= nil).toBe(true)
		expect(string.find(builder, 'source = "pointer"', 1, true) ~= nil).toBe(true)

		-- producer 1: the control's own GuiButton
		local atHandler = string.find(source, "function adapter.setActivateHandler", 1, true)
		expect(atHandler ~= nil).toBe(true)
		local handlerBody = string.sub(source, atHandler :: number, (atHandler :: number) + 600)
		expect(string.find(handlerBody, "fn(pointerActivateMeta(inputObject))", 1, true) ~= nil).toBe(true)

		-- producer 2: the minimum-target hit expander, from ITS OWN InputObject
		local atExpander = string.find(source, "expander.Activated:Connect", 1, true)
		expect(atExpander ~= nil).toBe(true)
		local expanderBody = string.sub(source, atExpander :: number, (atExpander :: number) + 500)
		expect(string.find(expanderBody, "function(inputObject: InputObject)", 1, true) ~= nil).toBe(true)
		expect(string.find(expanderBody, "handle.activate(pointerActivateMeta(inputObject))", 1, true) ~= nil).toBe(
			true
		)

		-- and the partial meta is GONE, not merely unused. The CALL is what is
		-- asserted absent, not the words: the builder's own comment above names
		-- the retired shape on purpose, and a test that forbade naming it would
		-- forbid explaining it.
		expect(string.find(source, 'handle.activate({ source = "hitExpander" })', 1, true)).toBe(nil)
	end)

	--[[ THE EXPANDER RUNS THE HOST'S GESTURE, NOT ONLY ITS ACTIVATION (director
		ruling 2026-08-14) ────────────────────────────────────────────────────────
		`handle.activate` is assigned for TAPPABLE classes only (Button, Toggle,
		TextField — `renderer.luau`'s own TAPPABLE table). A `Grip` is a POINTER ZONE,
		so wiring the expander to `Activated` alone made it a `GuiButton` that sank
		`InputBegan` and forwarded nothing: measured live on the Table's 8x28 resize
		divider, a click in the 26px band the expander covers did NOTHING while the
		same click clear of it cycled the sort — and the floor bought the divider no
		drag target either, because the expander is painted BEHIND its host.

		Asserted at the source anchors because `screen_target.luau` is engine-only,
		and asserted as the SHAPE OF THE FIX — one capture body, reached from two
		surfaces — because a second copy of "what a press starts" is exactly how the
		two would come to disagree. The live drive is in
		`docs/lessons/a-forty-four-pixel-floor-under-an-eight-pixel-divider.md`. ]]
	it("the minimum-target expander begins the host's pointer capture, through the one shared body", function()
		-- THE WHOLE ADAPTER, not one of its files: `dropHitExpander` left for
		-- `screen_presentation` when screen_target crossed the Source cap, and a pin
		-- that kept reading a single file would have stopped seeing the teardown it
		-- names (tests/lib/adapter_source.luau)
		local source = adapter_source.live()
		-- ONE body, extracted rather than copied
		local atBegin = string.find(source, "local function beginPointerCapture", 1, true)
		expect(atBegin ~= nil).toBe(true)
		expect(string.find(source, "local function beginPointerCapture", (atBegin :: number) + 1, true)).toBe(nil)
		-- ...and exactly one place that connects it, used by both surfaces
		local atConnect = string.find(source, "local function connectPointerBegan", 1, true)
		expect(atConnect ~= nil).toBe(true)
		local connectBody = string.sub(source, atConnect :: number, (atConnect :: number) + 400)
		expect(string.find(connectBody, "instance.InputBegan:Connect", 1, true) ~= nil).toBe(true)
		expect(string.find(connectBody, "beginPointerCapture(handle, handlers, inputObject)", 1, true) ~= nil).toBe(
			true
		)
		-- surface 1: the control's own instance
		local atHandlers = string.find(source, "function adapter.setPointerHandlers", 1, true)
		local handlersBody = string.sub(source, atHandlers :: number, (atHandlers :: number) + 900)
		expect(string.find(handlersBody, "connectPointerBegan(handle, instance, handlers)", 1, true) ~= nil).toBe(true)
		-- surface 2: the expander, wired from WHICHEVER of the two seams runs first —
		-- the renderer pushes hit geometry from the solve and handlers from the
		-- structural sync, and neither order is guaranteed
		expect(string.find(handlersBody, "connectPointerBegan(handle, handle.hitExpander, handlers)", 1, true) ~= nil).toBe(
			true
		)
		local atHit = string.find(source, "function adapter.setHitRect", 1, true)
		local hitBody = string.sub(source, atHit :: number, (atHit :: number) + 2600)
		expect(string.find(hitBody, "connectPointerBegan(handle, expander, handle.pointer)", 1, true) ~= nil).toBe(true)
		-- ...and it comes down with the expander, in ONE teardown both call sites use
		local atDrop = string.find(source, "local function dropHitExpander", 1, true)
		expect(atDrop ~= nil).toBe(true)
		local dropBody = string.sub(source, atDrop :: number, (atDrop :: number) + 400)
		expect(string.find(dropBody, "handle.hitExpanderPointerConn:Disconnect()", 1, true) ~= nil).toBe(true)
		expect(string.find(dropBody, "handle.hitExpander:Destroy()", 1, true) ~= nil).toBe(true)
		-- no second, un-torn-down copy of the destroy
		local firstDestroy = string.find(source, "handle.hitExpander:Destroy()", 1, true)
		expect(string.find(source, "handle.hitExpander:Destroy()", (firstDestroy :: number) + 1, true)).toBe(nil)
	end)

	it("RS-A16-D1b: the expander is placed by the SAME path that places its control", function()
		-- FOUND LIVE while proving the fix above (2026-07-26, stamp 1dc16785-1707271).
		-- `pushHitRects` runs BEFORE the commit that writes rects, so on a FRESH build
		-- a clip host's origin is not yet current when the expander is positioned, and
		-- because the renderer caches only the WANTED rect the wrong placement is never
		-- corrected until that rect itself moves. Measured after `reset()`: the TbBack
		-- expander sat at 636,129 for a control at 624,55 — a 44x46 activation surface
		-- 74px BELOW the button it belongs to. It only looked correct on the first boot
		-- because the text-premeasurement re-solve happened to move the wanted rect.
		-- The fix is structural: `applyRect` — the one function that re-bases a node
		-- from its clip host, including when the host's rect arrives late — places the
		-- expander too, so the two can never disagree about the origin.
		-- Read as the WHOLE adapter: `applyRect` and `applyHitExpander` are
		-- `screen_presentation`'s since the Source-cap split, and the invariant is
		-- that ONE function places both — which is a claim about the adapter, not
		-- about a file.
		local source = adapter_source.live()
		-- READ TO THE NEXT DECLARATION, NOT TO A CHARACTER COUNT. This window was
		-- a fixed 900, then a fixed 1500 ("widened when applyRect grew the
		-- centered-pivot branch, director fix round 2026-07-28 — the invariant
		-- itself is unchanged"), and it ran out a third time when ADR-0032's
		-- write-skip explanation landed inside `applyRect`. Each widening was
		-- correct and none of them fixed the instrument: a pin that reddens because
		-- somebody EXPLAINED the code teaches people to stop explaining it.
		local applyBody = adapter_source.bodyOf(source, "local function applyRect")
		expect(applyBody ~= "").toBe(true)
		expect(string.find(applyBody, "applyHitExpander", 1, true) ~= nil).toBe(true)
		-- and the placement itself reads the instance-host origin exactly once, in
		-- that shared helper, rather than being duplicated at the seam
		local helperBody = adapter_source.bodyOf(source, "local function applyHitExpander")
		expect(helperBody ~= "").toBe(true)
		expect(string.find(helperBody, "handle.instanceHost", 1, true) ~= nil).toBe(true)
		expect(string.find(helperBody, "rect.x - ox", 1, true) ~= nil).toBe(true)
		expect(string.find(helperBody, "rect.y - oy", 1, true) ~= nil).toBe(true)
		-- the wanted rect is REMEMBERED on the handle, which is what makes a late
		-- re-base possible at all
		local atHit = string.find(source, "function adapter.setHitRect", 1, true)
		local hitBody = string.sub(source, atHit :: number, (atHit :: number) + 2200)
		expect(string.find(hitBody, "handle.hitRectWant = rect", 1, true) ~= nil).toBe(true)
		-- ...and z follows too: a structural sync re-assigns ZIndex without moving a
		-- rect, and an expander that stopped being exactly one BEHIND its control
		-- would start swallowing the control's own clicks
		local atZ = string.find(source, "function adapter.setZOrder", 1, true)
		expect(atZ ~= nil).toBe(true)
		local zBody = string.sub(source, atZ :: number, (atZ :: number) + 500)
		expect(string.find(zBody, "handle.hitExpander.ZIndex = z - 1", 1, true) ~= nil).toBe(true)
	end)
end)

-- ===== D-6: the matrix driver must FAIL on a broken fixture =================
-- A green matrix is only meaningful if the same assertions reject a screen that is
-- actually wrong. These are the driver's three load-bearing checks, run against
-- deliberately broken trees.

describe("D-6: the matrix assertions reject a broken fixture", function()
	local function measure(bp: any, w: number, h: number)
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		return adapter
	end

	-- the driver's check: the smallest VISIBLE button must clear the 44px floor
	local function minVisibleButtonHeight(adapter: any): number
		local smallest = math.huge
		for _, path in adapter.paths() do
			local node = adapter.node(path)
			if node ~= nil and node.class == "Button" and adapter.visibleOf(path) ~= false then
				local hit = adapter.hitRectOf(path)
				smallest = math.min(smallest, math.max(node.rect.h, if hit ~= nil then (hit :: any).h else 0))
			end
		end
		return smallest
	end

	it("the hit-floor assertion fails when a control is pinned below the floor", function()
		-- an explicit fixed height BELOW the floor with the expander suppressed is
		-- the shape the assertion has to catch
		local adapter = measure(
			UI.Screen({
				id = "S",
				children = { UI.Button({ id = "Tiny", label = "x", height = fixed(20), width = fixed(20) }) },
			}),
			400,
			400
		)
		-- the framework's own expander lifts it, which is the POINT — the assertion
		-- reads the effective target, so a control the framework did NOT lift fails
		expect(minVisibleButtonHeight(adapter) >= 44).toBe(true)
		-- ...and with the seam absent (an adapter that cannot expand) it fails
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		local root = mountLib.mount(
			core,
			UI.Screen({ id = "S", children = { UI.Button({ id = "Tiny", label = "x", height = fixed(20) }) } })
		)
		local bare = fake_target.new();
		(bare :: any).setHitRect = nil
		local controller = renderer.attach(core, root, env, bare, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect(minVisibleButtonHeight(bare) >= 44).toBe(false)
	end)

	it("the hidden-candidate assertion fails when a losing candidate still paints", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 200, h = 400 })
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.ViewThatFits({
						id = "Fits",
						width = fill(),
						children = {
							UI.Box({ id = "Wide", width = fixed(500), height = fixed(20) }),
							UI.Box({ id = "Narrow", width = fixed(50), height = fixed(20) }),
						},
					}),
				},
			})
		)
		-- an adapter WITHOUT the visibility seam is the regressed world: the losing
		-- candidate keeps painting, and the assertion must notice
		local blind = fake_target.new();
		(blind :: any).setVisible = nil
		local controller = renderer.attach(core, root, env, blind, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect(blind.visibleOf("/S/Fits/Wide") == false).toBe(false)

		local seeing = measure(
			UI.Screen({
				id = "S",
				children = {
					UI.ViewThatFits({
						id = "Fits",
						width = fill(),
						children = {
							UI.Box({ id = "Wide", width = fixed(500), height = fixed(20) }),
							UI.Box({ id = "Narrow", width = fixed(50), height = fixed(20) }),
						},
					}),
				},
			}),
			200,
			400
		)
		expect(seeing.visibleOf("/S/Fits/Wide")).toBe(false)
	end)

	it("the adaptation assertion fails when a screen hard-codes one axis", function()
		-- a screen built on a PLAIN HStack cannot adapt: the driver's axis assertion
		-- must distinguish it from an AdaptiveStack
		local function axisOf(bp: any, w: number): string
			local adapter = measure(bp, w, 400)
			local a, b = adapter.node("/S/Bar/A"), adapter.node("/S/Bar/B")
			return if a.rect.y == b.rect.y then "x" else "y"
		end
		local function tree(ctor: any, axis: any)
			local spec: any = {
				id = "Bar",
				width = fill(),
				height = fill(),
				children = {
					UI.Box({ id = "A", width = fixed(40), height = fixed(40) }),
					UI.Box({ id = "B", width = fixed(40), height = fixed(40) }),
				},
			}
			if axis ~= nil then
				spec.axis = axis
			end
			return UI.Screen({ id = "S", children = { ctor(spec) } })
		end
		-- the broken fixture: identical axis at both extremes
		expect(axisOf(tree(UI.HStack, nil), 320)).toBe("x")
		expect(axisOf(tree(UI.HStack, nil), 1280)).toBe("x")
		-- the correct one: the axis follows the space
		expect(axisOf(tree(UI.AdaptiveStack, "y"), 320)).toBe("y")
		expect(axisOf(tree(UI.AdaptiveStack, "x"), 1280)).toBe("x")
	end)
end)

-- ===========================================================================
-- THE PRIMARY CLASS IS A CAPABILITY QUESTION BEFORE IT IS A PREFERENCE ONE
-- (device report 2026-07-29, a physical phone).
--
-- `UserInputService.PreferredInput` reports the most recently USED input, so on a
-- phone that has not been touched yet it reads KeyboardAndMouse — the engine's
-- default, not a fact about the device. The primary class fell through to
-- "pointer" on the strength of it, so a phone booted into the POINTER layout and
-- reflowed to the touch one the moment a finger landed. Measured on the shipped
-- playlist example: rows 36px -> 48px, page canvas 409 -> 553, and the native
-- scrollbar thumb shrank by the same ratio, which is what the report described
-- ("the scrollbar size looks very small [while dragging]").
--
-- A preference the player has not expressed yet cannot outvote what the device
-- physically is.
-- ===========================================================================
describe("interactionClasses: the primary class before any input has happened", function()
	local function classesFor(caps: any, preferred: string?): any
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("capabilities", caps)
		if preferred ~= nil then
			env:set("preferredInput", preferred)
		end
		return env:get("interactionClasses"):get()
	end

	it("a touch-only device is TOUCH-primary even while PreferredInput still says KeyboardAndMouse", function()
		local classes =
			classesFor({ keyboard = false, mouse = false, touch = true, gamepad = false }, "KeyboardAndMouse")
		expect(classes.primary).toBe("touch")
		expect(classes.touch).toBe(true)
	end)

	it("a gamepad-only device is GAMEPAD-primary on the same argument", function()
		local classes =
			classesFor({ keyboard = false, mouse = false, touch = false, gamepad = true }, "KeyboardAndMouse")
		expect(classes.primary).toBe("gamepad")
	end)

	it("a real mouse still wins: a desktop is pointer-primary", function()
		local classes =
			classesFor({ keyboard = true, mouse = true, touch = false, gamepad = false }, "KeyboardAndMouse")
		expect(classes.primary).toBe("pointer")
	end)

	it("a HYBRID (mouse AND touch) stays pointer until the player says otherwise", function()
		-- a touchscreen laptop is not a phone: it has a mouse, so the dense layout
		-- is the right default and the first touch still flips it
		local classes = classesFor({ keyboard = true, mouse = true, touch = true, gamepad = false }, "KeyboardAndMouse")
		expect(classes.primary).toBe("pointer")
		local touched = classesFor({ keyboard = true, mouse = true, touch = true, gamepad = false }, "Touch")
		expect(touched.primary).toBe("touch")
	end)

	it("effectiveInput speaks the platform fact's vocabulary, resolved", function()
		-- the affordance-label half of the same defect: `inputHint` and the gallery
		-- hint used to read the RAW preferredInput, so an untouched phone was told
		-- to "Press Enter". They read this instead.
		local function effective(caps: any, preferred: string?): string
			local core = customFactory.new()
			local env = environment.new(core)
			env:set("capabilities", caps)
			if preferred ~= nil then
				env:set("preferredInput", preferred)
			end
			return env:get("effectiveInput"):get()
		end
		expect(effective({ keyboard = false, mouse = false, touch = true, gamepad = false }, "KeyboardAndMouse")).toBe(
			"Touch"
		)
		expect(effective({ keyboard = false, mouse = false, touch = false, gamepad = true }, "KeyboardAndMouse")).toBe(
			"Gamepad"
		)
		expect(effective({ keyboard = true, mouse = true, touch = false, gamepad = false }, "KeyboardAndMouse")).toBe(
			"KeyboardAndMouse"
		)
		-- an expressed preference still leads
		expect(effective({ keyboard = true, mouse = true, touch = true, gamepad = false }, "Touch")).toBe("Touch")
	end)

	it("an EXPRESSED preference still wins over capability", function()
		expect(classesFor({ keyboard = false, mouse = false, touch = true, gamepad = true }, "Gamepad").primary).toBe(
			"gamepad"
		)
		expect(classesFor({ keyboard = true, mouse = true, touch = true, gamepad = false }, "Touch").primary).toBe(
			"touch"
		)
	end)
end)

--[[ THE PLATFORM TOPBAR BAND (director visual round 3, DV3-1) — WITH ITS
	SEMANTICS CORRECTED AGAINST THE LIVE ENGINE, 2026-08-14 (ADR-0027).

	A game that docks its own control into the platform's topbar row — beside the
	engine's control cluster, where a player already looks for chrome — has to be
	able to say WHERE that row is.

	WHAT THIS FILE USED TO SAY, AND WHY IT WAS WRONG. The recorded belief was that
	`GuiService.TopbarInset` states its rect RELATIVE to the topbar-safe area, so a
	window-space band was `topbarSafeInsets.left + topbarInset.x`. Measured on the
	live engine (Studio, Play, showcase place, viewport 735x413) it is not — the
	engine reports

	    GetGuiInset            top = (0, 58)
	    CoreUISafeInsets  raw  min = (0, 0)     max = (735, 355)
	    TopbarSafeInsets  raw  min = (164, -58) max = (735, 0)
	    TopbarInset            min = (164, 0)   size = 571 x 58

	— and a probe Frame parented to a `ScreenInsets = None` ScreenGui at
	`TopbarInset.Min` lands exactly on the free strip (AbsolutePosition (164,-58),
	which is physical (164, 0)). So `TopbarInset` is ALREADY IN PHYSICAL WINDOW
	SPACE, and `topbarSafeInsets` — the same band through the four-edge conversion
	— states the SAME rect: x 164..735, y 0..58. Adding them double-counts the
	cluster and pushes a docked control a cluster-width too far right, which is
	precisely the "TopbarInset is not physical space" burn this repo already
	recorded once, with the sign flipped.

	Both facts are kept, because they are two encodings of one rect and either can
	be missing (an engine without `GetInsetArea` publishes no `topbarSafeInsets`;
	a headless environment publishes no `topbarInset`), and `platformChrome`
	INTERSECTS them rather than adding them.
]]
describe("DV3-1: the topbar band is addressable from facts alone", function()
	local function bandOf(env: any): { x: number, y: number, w: number, h: number }
		local band = env:get("platformChrome"):get().band
		return band or { x = 0, y = 0, w = 0, h = 0 }
	end

	it("defaults to the desktop/no-notch answer rather than to a guess", function()
		local core = customFactory.new()
		local env = environment.new(core)
		local safe = env:get("topbarSafeInsets"):get()
		expect(`{safe.top}|{safe.bottom}|{safe.left}|{safe.right}`).toBe("0|0|0|0")
		-- with no topbar reported at all there is NO BAND — not a band at the
		-- window origin, which is the reading that puts content under CoreGui
		expect(env:get("platformChrome"):get().band).toBe(nil)
		local band = bandOf(env)
		expect(`{band.x}|{band.y}|{band.w}|{band.h}`).toBe("0|0|0|0")
	end)

	it("a NOTCHED phone puts the band right of the cluster, not at the window origin", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 812, h = 375 })
		env:set("coreSafeInsets", { top = 58, bottom = 0, left = 59, right = 59 })
		-- a landscape notch: the engine's own cluster ends 273px in (59px of notch
		-- plus a 214px cluster), and BOTH facts say so in window space
		env:set("topbarSafeInsets", { top = 0, bottom = 317, left = 273, right = 59 })
		env:set("topbarInset", { x = 273, y = 0, w = 480, h = 58 })
		local band = bandOf(env)
		expect(`{band.x}|{band.y}|{band.w}|{band.h}`).toBe("273|0|480|58")
		-- the band is where the PLATFORM says, never at the window origin
		expect(band.x).toBe(env:get("topbarInset"):get().x)
	end)

	it("the band is reachable from an edgeToEdge surface and NOT from a safe one", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 812, h = 375 })
		env:set("coreSafeInsets", { top = 58, bottom = 0, left = 59, right = 59 })
		env:set("topbarSafeInsets", { top = 0, bottom = 317, left = 273, right = 59 })
		env:set("topbarInset", { x = 273, y = 0, w = 480, h = 58 })
		local band = bandOf(env)
		local root = UI.Screen({
			id = "S",
			children = {
				UI.Anchor({
					id = "Band",
					width = fill(),
					height = fill(),
					children = {
						UI.Box({
							id = "Chip",
							anchor = "topLeft",
							offsetX = band.x,
							offsetY = band.y,
							width = fixed(120),
							height = fixed(band.h),
						}),
					},
				}),
			},
		})
		local function chipRect(policy: string): any
			local adapter = fake_target.new()
			local c2 = customFactory.new()
			local mounted = mountLib.mount(c2, root)
			local controller = renderer.attach(c2, mounted, env, adapter, { rootPolicy = policy })
			controller.initialRender()
			local rect = adapter.node("/S/Band/Chip").rect
			controller.dispose()
			return rect
		end
		-- edgeToEdge: window space, so the chip lands IN the strip beside the cluster
		local edge = chipRect("edgeToEdge")
		expect(`{edge.x}|{edge.y}|{edge.h}`).toBe("273|0|58")
		-- the default policy measures from the CONTENT rect, so the same numbers
		-- land a whole topbar's height below the strip — which is why this needs a
		-- surface of its own rather than an offset inside a content-safe one
		local safe = chipRect("coreSafeContent")
		expect(`{safe.x}|{safe.y}`).toBe(`{273 + 59}|{58}`)
	end)
end)

--[[ ADR-0027: `platformChrome` — WHERE THE PLATFORM'S OWN CONTROLS ARE.

	`coreSafeInsets` says "the top 58px of this window belongs to the engine". That
	is TRUE AS A BOUNDING BOX and blunt as a fact: the engine's own controls occupy
	x 0..164 of that band and the rest of it — the strip `TopbarInset` names — is
	explicitly the developer's. A surface insetting by the bounding box cannot put
	anything level with the platform's buttons, which is the top-centre HUD row
	every shipped Roblox game has (director, 2026-08-14).

	So the same geometry is published as RECTS as well as insets:

	  band       the FREE strip, window space, or nil — never a zero rect at the
	             origin, because "no strip" and "a strip at (0,0)" are the same
	             table and opposite instructions
	  rects      what the platform's OWN controls occupy — the top band MINUS the
	             free strip, so the L a bounding box cannot express
	  insets     clear everything (byte-identical to what `deviceSafeContent`
	             applies — pinned against the live policy below)
	  bandInsets clear everything EXCEPT the free band, for a surface that means
	             to ride it

	Every number is derived from facts the adapter already published. Nothing here
	knows 164, or 58, or a device name.
]]
describe("ADR-0027: platformChrome states the L, not its bounding box", function()
	local function chromeOf(env: any): any
		return env:get("platformChrome"):get()
	end
	local function rectStr(r: any): string
		return if r == nil then "nil" else `{r.x},{r.y} {r.w}x{r.h}`
	end
	local function rectsStr(list: { any }): string
		local out = {}
		for _, r in list do
			table.insert(out, rectStr(r))
		end
		return table.concat(out, " + ")
	end

	it("with NO platform facts there is no band and no chrome — zeroes read as absence", function()
		local core = customFactory.new()
		local env = environment.new(core)
		local chrome = chromeOf(env)
		expect(chrome.band).toBe(nil)
		expect(#chrome.rects).toBe(0)
		expect(`{chrome.insets.top}|{chrome.bandInsets.top}`).toBe("0|0")
	end)

	it("the LIVE DESKTOP measurement: chrome is x 0..164 of a 58px band, and the rest is free", function()
		local core = customFactory.new()
		local env = environment.new(core)
		-- verbatim from the live engine (Studio, Play, showcase place, 2026-08-14),
		-- through the same `insetsFromArea` conversion `roblox_env` applies
		env:set("viewportRect", { x = 0, y = 0, w = 735, h = 413 })
		env:set("coreSafeInsets", { top = 58, bottom = 0, left = 0, right = 0 })
		env:set("deviceSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		env:set("topbarSafeInsets", { top = 0, bottom = 355, left = 164, right = 0 })
		env:set("topbarInset", { x = 164, y = 0, w = 571, h = 58 })
		local chrome = chromeOf(env)
		expect(rectStr(chrome.band)).toBe("164,0 571x58")
		expect(rectsStr(chrome.rects)).toBe("0,0 164x58")
		-- the whole point: clearing EVERYTHING spends the band; clearing everything
		-- but the free strip spends nothing, so a surface can reach y=0
		expect(chrome.insets.top).toBe(58)
		expect(chrome.bandInsets.top).toBe(0)
	end)

	it("a platform that reports NO strip keeps the blunt full-width band", function()
		local core = customFactory.new()
		local env = environment.new(core)
		-- an engine without `GetInsetArea`: `roblox_env` falls back to GetGuiInset
		-- for coreSafeInsets and publishes NEITHER topbar fact
		env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
		env:set("coreSafeInsets", { top = 58, bottom = 0, left = 0, right = 0 })
		local chrome = chromeOf(env)
		expect(chrome.band).toBe(nil)
		-- the whole top band is the platform's, which is today's answer and the
		-- conservative one — a HUD riding this loses nothing and gains nothing
		expect(rectsStr(chrome.rects)).toBe("0,0 1280x58")
		expect(chrome.bandInsets.top).toBe(chrome.insets.top)
	end)

	it("a strip reported with NO topbar-safe area still rides: the rect fact is enough", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
		env:set("coreSafeInsets", { top = 58, bottom = 0, left = 0, right = 0 })
		env:set("topbarInset", { x = 164, y = 0, w = 1116, h = 58 })
		local chrome = chromeOf(env)
		expect(rectStr(chrome.band)).toBe("164,0 1116x58")
		expect(rectsStr(chrome.rects)).toBe("0,0 164x58")
	end)

	it("a NOTCHED landscape phone: chrome on BOTH sides of the band, and the notch is still spent", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 812, h = 375 })
		env:set("coreSafeInsets", { top = 58, bottom = 0, left = 59, right = 59 })
		env:set("deviceSafeInsets", { top = 0, bottom = 21, left = 47, right = 47 })
		env:set("topbarSafeInsets", { top = 0, bottom = 317, left = 273, right = 59 })
		env:set("topbarInset", { x = 273, y = 0, w = 480, h = 58 })
		local chrome = chromeOf(env)
		expect(rectStr(chrome.band)).toBe("273,0 480x58")
		-- the cluster on the left AND the notch strip on the right are both the
		-- platform's: an L is not always one rect, so this fact is a LIST
		expect(rectsStr(chrome.rects)).toBe("0,0 273x58 + 753,0 59x58")
		-- the per-edge max of core and device, exactly like `deviceSafeContent`
		expect(`{chrome.insets.top}|{chrome.insets.bottom}|{chrome.insets.left}|{chrome.insets.right}`).toBe(
			"58|21|59|59"
		)
		-- riding the band spends the top only down to where the band starts; every
		-- other edge is unchanged, because a notch is not negotiable
		expect(`{chrome.bandInsets.top}|{chrome.bandInsets.bottom}|{chrome.bandInsets.left}`).toBe("0|21|59")
	end)

	it("garbage platform facts clamp to 'no band' rather than to a band at a wrong origin", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 735, h = 413 })
		env:set("coreSafeInsets", { top = 58, bottom = 0, left = 0, right = 0 })
		env:set("topbarInset", { x = 0 / 0, y = 0, w = 571, h = 58 })
		expect(chromeOf(env).band).toBe(nil)
		env:set("topbarInset", { x = 164, y = 0, w = -20, h = 58 })
		expect(chromeOf(env).band).toBe(nil)
		-- ...and a strip the platform places entirely outside its own top band is
		-- not a strip this framework will hand anyone
		env:set("topbarInset", { x = 164, y = 300, w = 571, h = 58 })
		expect(chromeOf(env).band).toBe(nil)
	end)

	it("`insets` IS what deviceSafeContent applies — one authority, pinned to the live policy", function()
		local core = customFactory.new()
		local env = environment.new(core)
		local function rootRect(): any
			local adapter = fake_target.new()
			local c2 = customFactory.new()
			local mounted = mountLib.mount(c2, UI.Screen({ id = "S", width = fill(), height = fill(), children = {} }))
			local controller = renderer.attach(c2, mounted, env, adapter, { rootPolicy = "deviceSafeContent" })
			controller.initialRender()
			local rect = adapter.node("/S").rect
			controller.dispose()
			return rect
		end
		local function agrees(w: number, h: number)
			local rect, insets = rootRect(), chromeOf(env).insets
			-- the fact and the policy are two readings of one thing; if they ever
			-- disagree a HUD riding the band is inset by a number nothing applies
			expect(`{rect.x}|{rect.y}`).toBe(`{insets.left}|{insets.top}`)
			expect(`{rect.w}|{rect.h}`).toBe(`{w - insets.left - insets.right}|{h - insets.top - insets.bottom}`)
		end
		env:set("viewportRect", { x = 0, y = 0, w = 812, h = 375 })
		env:set("coreSafeInsets", { top = 58, bottom = 0, left = 59, right = 59 })
		env:set("deviceSafeInsets", { top = 0, bottom = 21, left = 47, right = 47 })
		agrees(812, 375)
		-- ...including the ten-foot overscan the same policy composes on top, which
		-- a fact that stopped at the safe area would have under-inset on a TV
		env:set("viewportRect", { x = 0, y = 0, w = 1920, h = 1080 })
		env:set("displaySize", "Large")
		agrees(1920, 1080)
	end)
end)

-- ===========================================================================
-- ADR-0023: the HEIGHT half of adaptive.conditions.
--
-- Additive by contract. The first describe is a REGRESSION PIN, not a feature
-- test: it fixes the exact answer of every pre-existing fact across a matrix of
-- widths and distance profiles, so a future change to this module that moves any
-- of them fails here instead of on a device. The ten-foot demotion is pinned
-- explicitly because it is the one non-monotonic rule in the file.
-- ===========================================================================

describe("ADR-0023 regression pin: the width facts are byte-unchanged", function()
	local WIDTHS = { 0, 1, 320, 599, 600, 601, 999, 1000, 1001, 1920, 3840 }

	it("sizeClass answers exactly what it answered before the height half landed", function()
		local near, far = {}, {}
		for _, w in WIDTHS do
			table.insert(near, adaptive.sizeClass(w))
			table.insert(far, adaptive.sizeClass(w, { distanceProfile = "ten-foot" }))
		end
		expect(table.concat(near, ",")).toBe(
			"compact,compact,compact,compact,regular,regular,regular,wide,wide,wide,wide"
		)
		-- the ten-foot cap: every `wide` becomes `regular`, nothing else moves
		expect(table.concat(far, ",")).toBe(
			"compact,compact,compact,compact,regular,regular,regular,regular,regular,regular,regular"
		)
	end)

	it("axisFor answers exactly what it answered before", function()
		local out = {}
		for _, w in WIDTHS do
			table.insert(out, adaptive.axisFor(w))
		end
		expect(table.concat(out, ",")).toBe("y,y,y,y,x,x,x,x,x,x,x")
	end)

	it("BREAKPOINTS and DEFAULT_STACK_ABOVE are the same numbers", function()
		expect(adaptive.BREAKPOINTS.regular).toBe(600)
		expect(adaptive.BREAKPOINTS.wide).toBe(1000)
		expect(adaptive.DEFAULT_STACK_ABOVE).toBe(600)
	end)

	it("every conditions key that existed before still resolves the same, height facts present", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1920, h = 1080 })
		env:set("displaySize", "Large")
		local c = adaptive.conditions(core, env)
		expect(c.sizeClass:get()).toBe("regular") -- the ten-foot demotion, untouched
		expect(c.isCompact:get()).toBe(false)
		expect(c.isRegular:get()).toBe(true)
		expect(c.isWide:get()).toBe(false)
		expect(c.isTenFoot:get()).toBe(true)
		expect(c.viewportWidth:get()).toBe(1920)
		expect(c.contentWidth:get()).toBe(1920)
		expect(c.axis:get()).toBe("x")
	end)
end)

describe("ADR-0023: height and orientation are facts, not device names", function()
	it("classifies height at the same breakpoints as width", function()
		expect(adaptive.heightClass(313)).toBe("short")
		expect(adaptive.heightClass(599)).toBe("short")
		expect(adaptive.heightClass(600)).toBe("medium")
		expect(adaptive.heightClass(999)).toBe("medium")
		expect(adaptive.heightClass(1000)).toBe("tall")
		expect(adaptive.HEIGHT_BREAKPOINTS).toBe(adaptive.BREAKPOINTS)
	end)

	it("a ten-foot display never resolves the densest VERTICAL arrangement either", function()
		expect(adaptive.heightClass(1080, { distanceProfile = "ten-foot" })).toBe("medium")
		expect(adaptive.heightClass(1080, { distanceProfile = "near" })).toBe("tall")
	end)

	it("degrades a nonsense height rather than producing a nonsense class", function()
		expect(adaptive.heightClass(0 / 0)).toBe("short")
		expect(adaptive.heightClass(-50)).toBe("short")
	end)

	it("orientation is a SHAPE fact: a windowed pane on a desktop is portrait", function()
		expect(adaptive.orientationFor(733, 313)).toBe("landscape")
		expect(adaptive.orientationFor(420, 1180)).toBe("portrait")
		expect(adaptive.orientationFor(600, 600)).toBe("square")
	end)

	it("a rotation maps a class pair onto its mirror", function()
		expect(`{adaptive.sizeClass(733)}|{adaptive.heightClass(313)}`).toBe("regular|short")
		expect(`{adaptive.sizeClass(313)}|{adaptive.heightClass(733)}`).toBe("compact|medium")
	end)

	it("exposes the height half as Readables that re-resolve in place", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 733, h = 313 })
		local c = adaptive.conditions(core, env)
		expect(c.heightClass:get()).toBe("short")
		expect(c.isShort:get()).toBe(true)
		expect(c.isTall:get()).toBe(false)
		expect(c.viewportHeight:get()).toBe(313)
		expect(c.orientation:get()).toBe("landscape")
		expect(c.isLandscape:get()).toBe(true)

		env:set("viewportRect", { x = 0, y = 0, w = 313, h = 1180 })
		expect(c.heightClass:get()).toBe("tall")
		expect(c.isShort:get()).toBe(false)
		expect(c.isTall:get()).toBe(true)
		expect(c.viewportHeight:get()).toBe(1180)
		expect(c.orientation:get()).toBe("portrait")
		expect(c.isLandscape:get()).toBe(false)
	end)

	it("opts.scope owns ALL of them, so the height half cannot leak", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local baseline = core:counters()
		local scope = core:scope("conditions")
		local c = adaptive.conditions(core, env, { scope = scope })
		-- touch every memo so none is lazily uncreated
		local _ = c.sizeClass:get()
			.. tostring(c.isCompact:get())
			.. tostring(c.isRegular:get())
			.. tostring(c.isWide:get())
			.. tostring(c.isTenFoot:get())
			.. tostring(c.viewportWidth:get())
			.. c.axis:get()
			.. c.heightClass:get()
			.. tostring(c.isShort:get())
			.. tostring(c.isTall:get())
			.. tostring(c.viewportHeight:get())
			.. c.orientation:get()
			.. tostring(c.isLandscape:get())
		scope:dispose()
		expect(core:counters().observers).toBe(baseline.observers)
	end)
end)

describe("navPlacement: the tab/sidebar policy is shape and input facts, never a device", function()
	it("pure: the five canonical shapes land where the ruling puts them", function()
		-- phone portrait: compact width -> full bottom bar
		expect(adaptive.navPlacement({ sizeClass = "compact", heightClass = "medium" })).toBe("bottomBar")
		-- phone landscape: roomy width but SHORT height -> the same bar, inline form
		expect(adaptive.navPlacement({ sizeClass = "regular", heightClass = "short", primary = "touch" })).toBe(
			"bottomBarCompact"
		)
		-- ten-foot: centered top bar, whatever the input class says
		expect(adaptive.navPlacement({
			sizeClass = "regular",
			heightClass = "medium",
			distanceProfile = "ten-foot",
			primary = "gamepad",
		})).toBe("topBar")
		-- tablet shape: roomy + touch. The DISPLAY fact is not consulted (ADAPT-2)
		expect(adaptive.navPlacement({
			sizeClass = "wide",
			heightClass = "tall",
			primary = "touch",
			displaySize = "Medium",
		})).toBe("topBar")
		--[[ RE-PINNED (ADAPT-2, audit 2026-08-18). Both rows below asserted
			`bottomBar` and both were the DEFECT, not the rule: the engine calls a
			tablet `DisplaySize.Small` ("Most tablet/mobile/handheld devices"), so the
			tablet branch was reachable only by a touchscreen laptop and no tablet
			could ever take the tablet paradigm. The discriminator is now the SHORT
			SIDE — a roomy canvas that is roomy on BOTH axes is a tablet whichever way
			it is held — which is what these two facts already say. ]]
		expect(adaptive.navPlacement({ sizeClass = "wide", heightClass = "tall", primary = "touch" })).toBe("topBar")
		expect(adaptive.navPlacement({
			sizeClass = "regular",
			heightClass = "medium",
			primary = "touch",
			displaySize = "Small",
		})).toBe("topBar")
		-- near-distance gamepad handheld (Small display): bottom tabs too
		expect(adaptive.navPlacement({
			sizeClass = "regular",
			heightClass = "medium",
			primary = "gamepad",
			displaySize = "Small",
		})).toBe("bottomBar")
		-- desktop shape: roomy + pointer-primary -> sidebar
		expect(adaptive.navPlacement({ sizeClass = "wide", heightClass = "medium", primary = "pointer" })).toBe(
			"sidebar"
		)
	end)

	it("precedence: compact beats short beats ten-foot beats input class", function()
		-- a compact-width canvas is a bottom bar even at ten-foot facts
		expect(adaptive.navPlacement({ sizeClass = "compact", heightClass = "short", distanceProfile = "ten-foot" })).toBe(
			"bottomBar"
		)
		-- short height wins over the pointer sidebar (a short desktop pane tabs)
		expect(adaptive.navPlacement({ sizeClass = "wide", heightClass = "short", primary = "pointer" })).toBe(
			"bottomBarCompact"
		)
		-- an unknown primary is NOT a pointer and NOT touch/gamepad: top bar
		expect(adaptive.navPlacement({ sizeClass = "regular", heightClass = "medium" })).toBe("topBar")
	end)

	--[[ ADAPT-2 — A PORTRAIT TABLET IS THE CASE THE OBVIOUS FIX GETS WRONG.

		The audit tested two candidates rather than one: "a tablet is `sizeClass ==
		"wide"`" still fails a portrait tablet, because 768-810px of width lands in
		`regular` — the same class as a landscape phone. The discriminator that
		holds in BOTH orientations is the short side against the SAME 600px
		breakpoint the classes already use, which is why this needs no new number
		and no new fact: `sizeClass ~= "compact"` says the short side clears it when
		the canvas is portrait, `heightClass ~= "short"` says it when the canvas is
		landscape, and the policy has already answered both of those cases above by
		the time it asks about the tablet. ]]
	it("ADAPT-2: a tablet takes the tablet paradigm in BOTH orientations, a phone in neither", function()
		local function placementFor(w: number, h: number, primary: string?, displaySize: string?): string
			return adaptive.navPlacement({
				sizeClass = adaptive.sizeClass(w),
				heightClass = adaptive.heightClass(h),
				primary = primary or "touch",
				displaySize = displaySize,
			})
		end
		-- every phone, both ways up, on the display fact the engine really sends
		expect(placementFor(390, 844, "touch", "Small")).toBe("bottomBar")
		expect(placementFor(844, 390, "touch", "Small")).toBe("bottomBarCompact")
		expect(placementFor(932, 430, "touch", "Small")).toBe("bottomBarCompact")
		-- ...and every tablet, both ways up, on the SAME display fact
		expect(placementFor(1079, 809, "touch", "Small")).toBe("topBar")
		expect(placementFor(810, 1080, "touch", "Small")).toBe("topBar") -- portrait
		expect(placementFor(768, 1024, "touch", "Small")).toBe("topBar") -- the small one
		-- the intuitive rule, shown failing: a portrait tablet is NOT `wide`
		expect(adaptive.sizeClass(810)).toBe("regular")
		expect(adaptive.sizeClass(844)).toBe("regular") -- and neither is a landscape phone
	end)

	it("reactive: the conditions memo re-resolves in place when facts move", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 360, h = 691 })
		env:set("capabilities", { touch = true, mouse = false, keyboard = false, gamepad = false })
		env:set("preferredInput", "Touch")
		local c = adaptive.conditions(core, env)
		expect(c.navPlacement:get()).toBe("bottomBar")
		-- rotate the same phone: inline bottom bar, no remount decision changes hands
		env:set("viewportRect", { x = 0, y = 0, w = 691, h = 360 })
		expect(c.navPlacement:get()).toBe("bottomBarCompact")
		--[[ a tablet-shaped canvas on the same touch session, with the engine
			calling the display SMALL — which is what the engine calls EVERY tablet
			("Most tablet/mobile/handheld devices"), so this is the live tablet row
			and not an edge case. RE-PINNED from `bottomBar` (ADAPT-2): the short
			side is 810px, the canvas is roomy whichever way it is held, and the
			display fact is no longer consulted at all. ]]
		env:set("displaySize", "Small")
		env:set("viewportRect", { x = 0, y = 0, w = 1080, h = 810 })
		expect(c.navPlacement:get()).toBe("topBar")
		-- ...and the same canvas is the same answer whatever the display says
		env:set("displaySize", "Medium")
		expect(c.navPlacement:get()).toBe("topBar")
		-- rotate that tablet: still a tablet (the case `sizeClass` alone fails)
		env:set("displaySize", "Small")
		env:set("viewportRect", { x = 0, y = 0, w = 810, h = 1080 })
		expect(c.navPlacement:get()).toBe("topBar")
		env:set("viewportRect", { x = 0, y = 0, w = 1080, h = 810 })
		-- the same canvas on a pointer session: sidebar (display fact irrelevant)
		env:set("capabilities", { touch = false, mouse = true, keyboard = true, gamepad = false })
		env:set("preferredInput", "KeyboardAndMouse")
		expect(c.navPlacement:get()).toBe("sidebar")
		-- ten-foot facts: top bar again
		env:set("viewportRect", { x = 0, y = 0, w = 1920, h = 1080 })
		env:set("displaySize", "Large")
		expect(c.navPlacement:get()).toBe("topBar")
	end)
end)

--[[ NM-H4a — AN EDGE INSET MEASURED AGAINST ANOTHER VIEWPORT.

	The director, on a phone, 2026-08-17 (`a.jpeg`): the `hud` demo in landscape,
	the right-hand rail's discs gone, and the paint probe reading

	    Paint probe · 734x393 · solve 15
	    13 of 14 rows wanted
	    skipped: Objective
	    NOT RIDING · no platform band · coreTop=120

	`coreTop = 120`, so `bandH = min(120, 393)` passed and it was the INTERSECTION
	that collapsed. `topbarSafeInsets` is stored as EDGE INSETS, which only mean
	anything against the viewport they were measured on — the band derivation turns
	them back into a rect with `W - right` and `H - bottom`. An orientation change
	updates `Camera.ViewportSize` and `GuiService:GetInsetArea` on DIFFERENT frames,
	so one `pushViewportFacts` can capture a new viewport beside an inset measured
	against the old one; `env:batch` makes the write atomic and cannot make the two
	engine reads agree.

	A topbar-safe area of y 0..58 on an 852-tall portrait window stores
	`bottom = 794`. Read against 393, `H - bottom = -401`, the band is nil, `riding`
	goes false, and the HUD moves onto the no-band rung — where it stays, because
	nothing republishes until the next platform event. Rotating again is what
	repaired it, which is exactly the recovery the director reported. ]]
describe("NM-H4a: a topbar-safe inset that cannot describe this viewport is discarded", function()
	local function chromeWith(facts: any): any
		local core = customFactory.new()
		local env = environment.new(core)
		for key, value in facts do
			env:set(key, value)
		end
		return env:get("platformChrome"):get()
	end

	local LANDSCAPE = {
		viewportRect = { x = 0, y = 0, w = 734, h = 393 },
		coreSafeInsets = { top = 120, right = 0, bottom = 0, left = 0 },
		deviceSafeInsets = { top = 0, right = 59, bottom = 21, left = 59 },
		topbarInset = { x = 164, y = 0, w = 570, h = 58 },
	}

	local function withSafe(bottom: number, right: number?): any
		local facts = {}
		for k, v in LANDSCAPE do
			facts[k] = v
		end
		facts.topbarSafeInsets = { top = 0, bottom = bottom, left = 164, right = right or 0 }
		return facts
	end

	it("the two encodings agreeing is an identity — the healthy platform", function()
		local band = chromeWith(withSafe(393 - 58)).band
		expect(band ~= nil).toBe(true)
		expect(`{band.x}|{band.y}|{band.w}|{band.h}`).toBe("164|0|570|58")
	end)

	it("an inset from the OTHER orientation no longer erases the band", function()
		-- 852 - 58: the same topbar-safe area, measured while the phone was portrait
		local band = chromeWith(withSafe(852 - 58)).band
		expect(band ~= nil).toBe(true)
		-- it degrades to the other encoding, which is already window-space, rather
		-- than to nothing
		expect(`{band.x}|{band.y}|{band.w}|{band.h}`).toBe("164|0|570|58")
	end)

	it("...and a HORIZONTALLY impossible one is discarded on the same rule", function()
		local band = chromeWith(withSafe(393 - 58, 734)).band
		expect(band ~= nil).toBe(true)
		expect(`{band.x}|{band.y}|{band.w}|{band.h}`).toBe("164|0|570|58")
	end)

	it("a TRUTHFUL inset still narrows the band, because the belt is not switched off", function()
		-- 164 + 300 < 734, so this one can describe the viewport: it is a real
		-- reservation and the band must still be cut down to it
		local band = chromeWith(withSafe(393 - 58, 300)).band
		expect(band ~= nil).toBe(true)
		expect(`{band.x}|{band.y}|{band.w}|{band.h}`).toBe("164|0|270|58")
	end)

	it("no topbar rect at all is still NO BAND — the discard is not a manufacture", function()
		local facts = withSafe(852 - 58)
		facts.topbarInset = { x = 0, y = 0, w = 0, h = 0 }
		expect(chromeWith(facts).band).toBe(nil)
	end)
end)
