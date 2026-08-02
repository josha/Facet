--!strict
-- Input-axis framework gaps (affordance matrix §D.5 / §B-Table; UI-PARADIGM-001/003).
-- Two presenter/input-layer packages, both driven through the REAL device paths
-- (never a direct callback):
--
--   1. Thumbstick1 Navigate tolerance (UI-PARADIGM-003, matrix §D.5). A pad that
--      delivers the D-pad (or stick) as an analog Thumbstick1 axis must still
--      Navigate. The headless action system gains an AXIS binding with a
--      deadzone/threshold LATCH (crossing ±threshold fires ONE step; the stick
--      must re-center below the release threshold before the next step — no
--      autorepeat storm), and the presenter binds Thumbstick1 on Navigate /
--      NavigateH alongside DPad*. The headless latch is authoritative; the IAS
--      realization is a Studio-drive/physical rider (DevForum Thumbstick1 binding
--      bug + synthetic-gamepad-unreachable lesson).
--
--   2. Bare-Table Adjust auto-wiring (UI-PARADIGM-001, matrix §B-Table). The
--      contribution bundle gains `adjustTargets(rootNode) -> { [path]: true }` +
--      `handleAdjust(path, direction) -> boolean`. The presenter binds the Adjust
--      keys DYNAMICALLY — only while the FOCUSED path is a declared adjust target,
--      so a non-modal screen never shadows gameplay arrow/bumper keys while focus
--      sits elsewhere. Consumer opts.onAdjust still wins per-opt (back-compat).
--      Proven with a SYNTHETIC contribution (a fake control declaring one
--      adjustable node), the way tests/auto_input.spec.luau exercises the seam.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local actionsLib = require("../src/input/actions")
local LuauUI = require("../src") :: any
local contribution = require("../src/input/contribution")
local fake_target = require("../tests/lib/fake_target")

-- ===========================================================================
-- Part 1 — axis-binding latch semantics (headless authority)
-- ===========================================================================
describe("input-axis: Thumbstick1 latch (deadzone + re-center, no autorepeat)", function()
	local function axisWorld()
		local core = customFactory.new()
		local system = actionsLib.newSystem(core)
		local ctx = system.createContext({ name = "Nav", priority = 1500 })
		local navigate = ctx.createAction("Navigate", "Direction1D")
		navigate.bindAxis({ axis = "Thumbstick1", component = "y", threshold = 0.5, releaseThreshold = 0.35 })
		local steps: { number } = {}
		core:observe(navigate.state, function(dir)
			if dir == 1 or dir == -1 then
				table.insert(steps, dir)
			end
		end)
		return { system = system, navigate = navigate, steps = steps }
	end

	it("crossing +threshold fires exactly one step; holding past it does NOT repeat", function()
		local w = axisWorld()
		w.system.deviceAxis("Thumbstick1", 0, 0.6) -- cross +: one step
		w.system.deviceAxis("Thumbstick1", 0, 0.7) -- held: no step (latched)
		w.system.deviceAxis("Thumbstick1", 0, 0.95) -- held harder: still no step
		expect(#w.steps).toBe(1)
		expect(w.steps[1]).toBe(1)
	end)

	it("must re-center below the release threshold before the next step re-arms", function()
		local w = axisWorld()
		w.system.deviceAxis("Thumbstick1", 0, 0.6) -- step 1
		w.system.deviceAxis("Thumbstick1", 0, 0.4) -- in the hysteresis band: no re-arm, no step
		w.system.deviceAxis("Thumbstick1", 0, 0.8) -- still latched (never dropped below 0.35): no step
		expect(#w.steps).toBe(1)
		w.system.deviceAxis("Thumbstick1", 0, 0.2) -- re-center below release: re-arm
		w.system.deviceAxis("Thumbstick1", 0, 0.8) -- cross again: step 2
		expect(#w.steps).toBe(2)
	end)

	it("the opposite direction steps once re-centered (negative crossing)", function()
		local w = axisWorld()
		w.system.deviceAxis("Thumbstick1", 0, 0.6) -- +1
		w.system.deviceAxis("Thumbstick1", 0, 0.0) -- re-center
		w.system.deviceAxis("Thumbstick1", 0, -0.7) -- -1
		expect(#w.steps).toBe(2)
		expect(w.steps[2]).toBe(-1)
	end)

	it("deadzone: a sub-threshold push never steps", function()
		local w = axisWorld()
		w.system.deviceAxis("Thumbstick1", 0, 0.3) -- inside the deadzone (< 0.5)
		w.system.deviceAxis("Thumbstick1", 0, 0.49)
		expect(#w.steps).toBe(0)
	end)

	it("the bound component is respected: an x-only push does NOT drive a y binding", function()
		local w = axisWorld()
		w.system.deviceAxis("Thumbstick1", 0.9, 0.0) -- pure horizontal
		expect(#w.steps).toBe(0)
	end)

	it("a higher-priority Sink context consumes the axis (arbitration parity)", function()
		local core = customFactory.new()
		local system = actionsLib.newSystem(core)
		local ctxHigh = system.createContext({ name = "High", priority = 2000, sink = true })
		local navHigh = ctxHigh.createAction("Navigate", "Direction1D")
		navHigh.bindAxis({ axis = "Thumbstick1", component = "y" })
		local ctxLow = system.createContext({ name = "Low", priority = 100, sink = false })
		local navLow = ctxLow.createAction("Navigate", "Direction1D")
		navLow.bindAxis({ axis = "Thumbstick1", component = "y" })
		local hi, lo = 0, 0
		core:observe(navHigh.state, function(d)
			if d == 1 or d == -1 then
				hi += 1
			end
		end)
		core:observe(navLow.state, function(d)
			if d == 1 or d == -1 then
				lo += 1
			end
		end)
		system.deviceAxis("Thumbstick1", 0, 0.8)
		expect(hi).toBe(1)
		expect(lo).toBe(0) -- sunk by the higher context
		ctxHigh.setEnabled(false)
		system.deviceAxis("Thumbstick1", 0, 0.8)
		expect(lo).toBe(1) -- released to the lower context
	end)

	it("axis bindings never leak into the keyCode (deviceKey) path", function()
		local w = axisWorld()
		w.system.deviceKey("Thumbstick1", true) -- a keyCode of the same name: no axis binding matches
		w.system.deviceKey("Thumbstick1", false)
		expect(#w.steps).toBe(0)
	end)
end)

-- ===========================================================================
-- Part 1 — presenter wires Thumbstick1 onto Navigate / NavigateH
-- ===========================================================================
local function harness()
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	return core, env, system, adapter, pres
end

describe("input-axis: presenter binds Thumbstick1 for Navigate (vertical, flat ring)", function()
	it("a Thumbstick1 y push moves focus down like DPadDown, with the latch", function()
		local _, _, system, _, pres = harness()
		local screen = LuauUI.UI.Screen({
			id = "S",
			children = {
				LuauUI.UI.Button({ id = "a", label = "a" }),
				LuauUI.UI.Button({ id = "b", label = "b" }),
			},
		})
		pres.present(screen) -- ZERO opts
		pres.refresh()
		expect(pres.focus.focused:get()).toBe("/S/a")
		system.deviceAxis("Thumbstick1", 0, 0.7) -- push down: one step
		expect(pres.focus.focused:get()).toBe("/S/b")
		system.deviceAxis("Thumbstick1", 0, 0.8) -- held: no autorepeat, focus holds
		expect(pres.focus.focused:get()).toBe("/S/b")
		system.deviceAxis("Thumbstick1", 0, 0.0) -- re-center
		system.deviceAxis("Thumbstick1", 0, -0.7) -- push up: back to a
		expect(pres.focus.focused:get()).toBe("/S/a")
	end)
end)

describe("input-axis: presenter binds Thumbstick1 for NavigateH (horizontal, grouped)", function()
	it("a Thumbstick1 x push walks an HStack row like DPadRight", function()
		local _, _, system, _, pres = harness()
		local screen = LuauUI.UI.Screen({
			id = "S",
			children = {
				LuauUI.UI.HStack({
					id = "Row",
					children = {
						LuauUI.UI.Button({ id = "a", label = "a" }),
						LuauUI.UI.Button({ id = "b", label = "b" }),
						LuauUI.UI.Button({ id = "c", label = "c" }),
					},
				}),
			},
		})
		pres.present(screen) -- ZERO opts; layout-derived groups make Row the horizontal axis
		pres.refresh()
		expect(pres.focus.focused:get()).toBe("/S/Row/a")
		system.deviceAxis("Thumbstick1", 0.7, 0) -- right one step
		expect(pres.focus.focused:get()).toBe("/S/Row/b")
		system.deviceAxis("Thumbstick1", 0.0, 0) -- re-center
		system.deviceAxis("Thumbstick1", 0.7, 0) -- right again
		expect(pres.focus.focused:get()).toBe("/S/Row/c")
	end)
end)

-- ===========================================================================
-- Part 2 — dynamic Adjust auto-wiring from a contribution
-- ===========================================================================
-- a fake control: a vertical pair of focusable Buttons whose SECOND node is
-- declared adjustable, exactly the shape a Table grip would take (this proves
-- the seam without touching src/controls/table.luau).
local function fakeAdjustControl(id: string)
	local root = LuauUI.UI.VStack({
		id = id,
		children = {
			LuauUI.UI.Button({ id = "Plain", label = "Plain" }),
			LuauUI.UI.Button({ id = "Adj", label = "Adj" }),
		},
	})
	local adjustHits: { any } = {}
	local adjPath = "/S/" .. id .. "/Adj"
	local bundle = {
		adjustTargets = function(_rootNode: any): { [string]: boolean }
			return { [adjPath] = true }
		end,
		handleAdjust = function(path: string, dir: number): boolean
			table.insert(adjustHits, { path = path, dir = dir })
			return true
		end,
	}
	return { blueprint = contribution.attach(root, bundle), adjustHits = adjustHits, adjPath = adjPath }
end

describe("input-axis: bare-control Adjust auto-wiring (dynamic, focus-gated)", function()
	local function world(presOpts: any?)
		local _, _, system, adapter, pres = harness()
		local ctl = fakeAdjustControl("Ctl")
		local screen = LuauUI.UI.Screen({ id = "S", children = { ctl.blueprint } })
		local handle = pres.present(screen, presOpts)
		pres.refresh()
		return { system = system, adapter = adapter, pres = pres, handle = handle, ctl = ctl }
	end

	local PLAIN = "/S/Ctl/Plain"
	local ADJ = "/S/Ctl/Adj"

	it("no Adjust key is bound while focus sits on a NON-target (no gameplay shadow)", function()
		local w = world()
		expect(w.pres.focus.focused:get()).toBe(PLAIN)
		-- the Adjust action carries ZERO keyCode bindings: the keys are unbound,
		-- so gameplay Left/Right/bumpers are never shadowed while focus is elsewhere
		expect(#w.handle.actions.adjust.bindings).toBe(0)
		w.system.deviceKey("Left", true)
		w.system.deviceKey("Left", false)
		expect(#w.ctl.adjustHits).toBe(0) -- nothing handled: the key was not bound
	end)

	it("Adjust keys bind the moment focus lands on the declared target", function()
		local w = world()
		-- navigate down onto the adjustable node
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(w.pres.focus.focused:get()).toBe(ADJ)
		expect(#w.handle.actions.adjust.bindings > 0).toBe(true) -- now bound
	end)

	it("keyboard Adjust (Left/Comma) on the focused target routes to handleAdjust", function()
		local w = world()
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(w.pres.focus.focused:get()).toBe(ADJ)
		w.system.deviceKey("Left", true)
		w.system.deviceKey("Left", false)
		expect(#w.ctl.adjustHits).toBe(1)
		expect(w.ctl.adjustHits[1].path).toBe(ADJ)
		expect(w.ctl.adjustHits[1].dir).toBe(-1)
		w.system.deviceKey("Period", true) -- '.' increments
		w.system.deviceKey("Period", false)
		expect(#w.ctl.adjustHits).toBe(2)
		expect(w.ctl.adjustHits[2].dir).toBe(1)
	end)

	it("gamepad Adjust (ButtonR1) on the focused target routes to handleAdjust", function()
		local w = world()
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		w.system.deviceKey("ButtonR1", true)
		w.system.deviceKey("ButtonR1", false)
		expect(#w.ctl.adjustHits).toBe(1)
		expect(w.ctl.adjustHits[1].dir).toBe(1)
	end)

	it("moving focus back OFF the target unbinds the Adjust keys again", function()
		local w = world()
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(w.pres.focus.focused:get()).toBe(ADJ)
		expect(#w.handle.actions.adjust.bindings > 0).toBe(true)
		-- back up to the non-target
		w.system.deviceKey("DPadUp", true)
		w.system.deviceKey("DPadUp", false)
		expect(w.pres.focus.focused:get()).toBe(PLAIN)
		expect(#w.handle.actions.adjust.bindings).toBe(0) -- unbound again
	end)

	it("consumer opts.onAdjust wins per-opt and binds unconditionally (back-compat)", function()
		local optHits: { any } = {}
		local w = world({
			onAdjust = function(path: string, dir: number)
				table.insert(optHits, { path = path, dir = dir })
			end,
		})
		-- legacy opt: Adjust keys bound from the start, regardless of focus
		expect(#w.handle.actions.adjust.bindings > 0).toBe(true)
		expect(w.pres.focus.focused:get()).toBe(PLAIN)
		w.system.deviceKey("Left", true)
		w.system.deviceKey("Left", false)
		-- the opt received the adjust; the contribution's handleAdjust did NOT
		expect(#optHits).toBe(1)
		expect(optHits[1].dir).toBe(-1)
		expect(#w.ctl.adjustHits).toBe(0)
	end)
end)
