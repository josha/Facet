--!strict
-- Milestone A — adaptive layout (docs/plans/swiftui-parity-next.md investment 5;
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
		local atVisible = string.find(source, "function adapter.setVisible", 1, true)
		expect(atVisible ~= nil).toBe(true)
		local visibleBody = string.sub(source, atVisible :: number, (atVisible :: number) + 700)
		-- setVisible carries the expander with the control it belongs to
		expect(string.find(visibleBody, "hitExpander", 1, true) ~= nil).toBe(true)
		local atHit = string.find(source, "function adapter.setHitRect", 1, true)
		expect(atHit ~= nil).toBe(true)
		local hitBody = string.sub(source, atHit :: number, (atHit :: number) + 2200)
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
		local source = require("@lune/fs").readFile("src/client/screen_target.luau")
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
		local source = require("@lune/fs").readFile("src/client/screen_target.luau")
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
		local source = require("@lune/fs").readFile("src/client/screen_target.luau")
		local atApply = string.find(source, "local function applyRect", 1, true)
		expect(atApply ~= nil).toBe(true)
		-- (window widened 900→1500 when applyRect grew the centered-pivot branch,
		-- director fix round 2026-07-28 — the invariant itself is unchanged)
		local applyBody = string.sub(source, atApply :: number, (atApply :: number) + 1500)
		expect(string.find(applyBody, "applyHitExpander", 1, true) ~= nil).toBe(true)
		-- and the placement itself reads the clip-host origin exactly once, in that
		-- shared helper, rather than being duplicated at the seam
		local atHelper = string.find(source, "local function applyHitExpander", 1, true)
		expect(atHelper ~= nil).toBe(true)
		local helperBody = string.sub(source, atHelper :: number, (atHelper :: number) + 700)
		expect(string.find(helperBody, "handle.clipHost", 1, true) ~= nil).toBe(true)
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
-- (device report 2026-07-29, iPhone 15 Pro).
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
		-- tablet shape: roomy + touch + a display the engine calls Medium/Large
		expect(adaptive.navPlacement({
			sizeClass = "wide",
			heightClass = "tall",
			primary = "touch",
			displaySize = "Medium",
		})).toBe("topBar")
		-- touch WITHOUT a differentiating display fact: a roomy canvas the
		-- DisplaySize cannot tell from a phone stays a phone -> bottom tabs
		expect(adaptive.navPlacement({ sizeClass = "wide", heightClass = "tall", primary = "touch" })).toBe("bottomBar")
		expect(adaptive.navPlacement({
			sizeClass = "regular",
			heightClass = "medium",
			primary = "touch",
			displaySize = "Small",
		})).toBe("bottomBar")
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
		-- a tablet-shaped canvas on the same touch session, but the engine
		-- calls the display SMALL (the default here is Medium, so the phone
		-- fact is set explicitly): a panel the display fact cannot tell from a
		-- phone keeps bottom tabs...
		env:set("displaySize", "Small")
		env:set("viewportRect", { x = 0, y = 0, w = 1080, h = 810 })
		expect(c.navPlacement:get()).toBe("bottomBar")
		-- ...and gets the centered top bar once the display says otherwise
		env:set("displaySize", "Medium")
		expect(c.navPlacement:get()).toBe("topBar")
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
