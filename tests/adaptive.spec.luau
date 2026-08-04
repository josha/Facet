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

--[[ THE PLATFORM TOPBAR BAND (director visual round 3, DV3-1).

	A game that docks its own control into the platform's topbar row — beside the
	engine's control cluster, where a player already looks for chrome — has to be
	able to say WHERE that row is. `topbarInset` alone cannot: the engine states
	that rect relative to the TOPBAR-SAFE area, so on a notched device placing it
	raw puts the content under the platform's own cluster (and on desktop it
	coincides, which is how that class of bug survives a desktop review).

	`topbarSafeInsets` is the missing half — the same four-edge, window-space
	shape as `coreSafeInsets`/`deviceSafeInsets` — and the pair is placeable with
	no engine call and no platform branch.
]]
describe("DV3-1: the topbar band is addressable from facts alone", function()
	local function bandOf(env: any): { x: number, y: number, w: number, h: number }
		local safe = env:get("topbarSafeInsets"):get()
		local free = env:get("topbarInset"):get()
		return { x = safe.left + free.x, y = safe.top + free.y, w = free.w, h = free.h }
	end

	it("defaults to the desktop/no-notch answer rather than to a guess", function()
		local core = customFactory.new()
		local env = environment.new(core)
		local safe = env:get("topbarSafeInsets"):get()
		expect(`{safe.top}|{safe.bottom}|{safe.left}|{safe.right}`).toBe("0|0|0|0")
		-- with no topbar reported at all the band is empty, so a surface placed in
		-- it measures nothing — never a box at a wrong origin
		local band = bandOf(env)
		expect(`{band.x}|{band.y}|{band.w}|{band.h}`).toBe("0|0|0|0")
	end)

	it("a NOTCHED phone puts the band right of the cluster, not at the window origin", function()
		local core = customFactory.new()
		local env = environment.new(core)
		-- a landscape notch: the topbar-safe area starts 59px in, and the engine's
		-- own cluster takes the first 214px of THAT
		env:set("topbarSafeInsets", { top = 0, bottom = 0, left = 59, right = 59 })
		env:set("topbarInset", { x = 214, y = 0, w = 480, h = 58 })
		local band = bandOf(env)
		expect(`{band.x}|{band.y}|{band.w}|{band.h}`).toBe("273|0|480|58")
		-- the fact everyone had before this one would have placed it at 214 —
		-- 59px INSIDE the cluster, which is under CoreGui and invisible
		expect(band.x - env:get("topbarInset"):get().x).toBe(59)
	end)

	it("the band is reachable from an edgeToEdge surface and NOT from a safe one", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 812, h = 375 })
		env:set("coreSafeInsets", { top = 58, bottom = 0, left = 59, right = 59 })
		env:set("topbarSafeInsets", { top = 0, bottom = 0, left = 59, right = 59 })
		env:set("topbarInset", { x = 214, y = 0, w = 480, h = 58 })
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
