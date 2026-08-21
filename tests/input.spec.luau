--!strict
-- P1.5 input pipeline tests (UI-INPUT-001/003/004): the headless model must
-- reproduce the ENGINE semantics measured in the Studio spike (T1-T6a),
-- including the scriptable-bypasses-arbitration truth, plus focus wiring
-- (Navigate2D/Activate/Cancel driving the logical focus graph).

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local actionsLib = require("../src/input/actions")
local focus_graph = require("../src/focus/focus_graph")

local function spikeSetup()
	local core = customFactory.new()
	local system = actionsLib.newSystem(core)
	local ctxLow = system.createContext({ name = "CtxLow", priority = 100, sink = false })
	local actLow = ctxLow.createAction("ActLow", "Bool")
	actLow.bind({ keyCode = "E" })
	local lowScript = actLow.bind({ scriptable = true })
	local ctxHigh = system.createContext({ name = "CtxHigh", priority = 2000, sink = true })
	local actHigh = ctxHigh.createAction("ActHigh", "Bool")
	actHigh.bind({ keyCode = "E" })
	local lowPresses, highPresses = 0, 0
	actLow.onPressed(function()
		lowPresses += 1
	end)
	actHigh.onPressed(function()
		highPresses += 1
	end)
	local function pressE()
		system.deviceKey("E", true)
		system.deviceKey("E", false)
	end
	return {
		core = core,
		system = system,
		ctxLow = ctxLow,
		ctxHigh = ctxHigh,
		lowScript = lowScript,
		pressE = pressE,
		low = function()
			return lowPresses
		end,
		high = function()
			return highPresses
		end,
	}
end

describe("input: engine-mirrored arbitration (spike parity)", function()
	it("T1: a higher-priority Sink context blocks the lower context on the same key", function()
		local s = spikeSetup()
		s.pressE()
		expect(s.high()).toBe(1)
		expect(s.low()).toBe(0)
	end)

	it("T2: disabling the high context releases the key to the lower one", function()
		local s = spikeSetup()
		s.pressE()
		s.ctxHigh.setEnabled(false)
		s.pressE()
		expect(s.high()).toBe(1)
		expect(s.low()).toBe(1)
	end)

	it("T3: a scriptable fire bypasses arbitration even under an active sink", function()
		local s = spikeSetup()
		s.ctxHigh.setEnabled(true)
		s.lowScript.fire(true)
		s.lowScript.fire(false)
		expect(s.low()).toBe(1) -- fired despite the sink: engine truth
		expect(s.high()).toBe(0)
	end)

	it("T4/dedup: repeated identical states are deduplicated like the engine", function()
		local s = spikeSetup()
		s.ctxHigh.setEnabled(false)
		s.system.deviceKey("E", true)
		s.system.deviceKey("E", true) -- key repeat: no second press
		s.system.deviceKey("E", false)
		expect(s.low()).toBe(1)
	end)

	it("T6a: firing a binding of a destroyed context is a silent no-op", function()
		local s = spikeSetup()
		s.ctxHigh.setEnabled(false)
		s.ctxLow.destroy()
		local ok = pcall(function()
			s.lowScript.fire(true)
		end)
		expect(ok).toBe(true)
		expect(s.low()).toBe(0)
		s.pressE() -- device path also dead for the destroyed context
		expect(s.low()).toBe(0)
	end)

	it("disabling a context resets held Bool state", function()
		local s = spikeSetup()
		s.system.deviceKey("E", true) -- high holds E down
		expect(s.ctxHigh.actions[1].state:get()).toBe(true)
		s.ctxHigh.setEnabled(false)
		expect(s.ctxHigh.actions[1].state:get()).toBe(false)
	end)
end)

describe("input: hints", function()
	it("preferredBinding follows the preferred input kind and tolerates nil", function()
		local core = customFactory.new()
		local system = actionsLib.newSystem(core)
		local ctx = system.createContext({ name = "Nav" })
		local activate = ctx.createAction("Activate", "Bool")
		activate.bind({ keyCode = "Return", displayName = "Enter" })
		activate.bind({ uiButton = "ActivateButton", displayName = "Tap" })
		expect(activate.preferredBinding("KeyboardAndMouse").displayName).toBe("Enter")
		expect(activate.preferredBinding("Touch").displayName).toBe("Tap")
		local bare = ctx.createAction("Bare", "Bool")
		expect(bare.preferredBinding("Gamepad")).toBe(nil) -- nil-tolerant (spike)
	end)
end)

describe("input: focus wiring", function()
	it("Navigate2D/Activate drive the logical focus graph through actions only", function()
		local core = customFactory.new()
		local system = actionsLib.newSystem(core)
		local graph = focus_graph.new(core)
		graph.pushScope({ name = "Settings", trap = false, order = { "Music", "Sfx", "Save" } })

		local nav = system.createContext({ name = "Navigation", priority = 1500 })
		local navigate = nav.createAction("Navigate", "Direction1D")
		local activate = nav.createAction("Activate", "Bool")
		navigate.bind({ keyCode = "Down" })
		local navScript = navigate.bind({ scriptable = true })
		local activateScript = activate.bind({ scriptable = true })

		core:observe(navigate.state, function(dir)
			if dir == 1 then
				graph.navigate(1)
			elseif dir == -1 then
				graph.navigate(-1)
			end
		end)
		local activated: string? = nil
		activate.onPressed(function()
			activated = graph.focused:get()
		end)

		navScript.fire(1)
		navScript.fire(0)
		navScript.fire(1)
		expect(graph.focused:get()).toBe("Save")
		navScript.fire(0)
		navScript.fire(-1)
		expect(graph.focused:get()).toBe("Sfx")
		activateScript.fire(true)
		expect(activated).toBe("Sfx")
	end)
end)

describe("input: modifier state (Phase B)", function()
	local actions = require("../src/input/actions")
	local customCore = require("../src/core/custom")

	it("deviceKey tracks shift and ctrl/cmd modifier state", function()
		local core = customCore.new()
		local system = actions.newSystem(core)
		expect(system.modifiers().shift).toBe(false)
		expect(system.modifiers().toggle).toBe(false)
		system.deviceKey("LeftShift", true)
		expect(system.modifiers().shift).toBe(true)
		system.deviceKey("LeftShift", false)
		expect(system.modifiers().shift).toBe(false)
		-- either control or meta reads as the toggle modifier
		system.deviceKey("LeftControl", true)
		expect(system.modifiers().toggle).toBe(true)
		system.deviceKey("LeftControl", false)
		system.deviceKey("RightMeta", true)
		expect(system.modifiers().toggle).toBe(true)
		system.deviceKey("RightMeta", false)
		expect(system.modifiers().toggle).toBe(false)
	end)
end)

-- Task 8b: the additive `modifiers` slot on a keyCode binding, and the
-- Return/Activate collision (Task 8 report §Shift+Return) it exists to
-- resolve — a higher-priority Sink context's modified binding must preempt
-- an unmodified sibling on the SAME key while its modifier is held, and must
-- not touch it at all otherwise. Shaped after `spikeSetup` above (a low/high
-- priority pair on one key) so this reuses the same engine-mirrored
-- arbitration T1 already proves, rather than asserting a new rule.
describe("input: modifier-gated bindings (Task 8b)", function()
	local function shiftCollisionSetup()
		local core = customFactory.new()
		local system = actionsLib.newSystem(core)
		-- mirrors the real base screen's own unconditional Activate/Return
		local ctxBase = system.createContext({ name = "Base", priority = 1500, sink = false })
		local actBase = ctxBase.createAction("Activate", "Bool")
		actBase.bind({ keyCode = "Return" })
		-- mirrors RowActionsKeys: high priority, sink=true, modifier-gated
		local ctxMenu = system.createContext({ name = "RowActionsKeys", priority = 10000, sink = true })
		local actMenu = ctxMenu.createAction("RowActionsMenu", "Bool")
		actMenu.bind({ keyCode = "Return", modifiers = { shift = true } })
		local basePresses, menuPresses = 0, 0
		actBase.onPressed(function()
			basePresses += 1
		end)
		actMenu.onPressed(function()
			menuPresses += 1
		end)
		return {
			system = system,
			actBase = actBase,
			actMenu = actMenu,
			base = function()
				return basePresses
			end,
			menu = function()
				return menuPresses
			end,
		}
	end

	it("a modified binding fires only while its modifier is held", function()
		local s = shiftCollisionSetup()
		s.system.deviceKey("Return", true)
		s.system.deviceKey("Return", false)
		expect(s.menu()).toBe(0) -- shift not held: never a candidate
		s.system.deviceKey("LeftShift", true)
		s.system.deviceKey("Return", true)
		s.system.deviceKey("Return", false)
		expect(s.menu()).toBe(1)
	end)

	it("an unmodified sibling is unaffected when the modifier is NOT held (byte-identical)", function()
		local s = shiftCollisionSetup()
		s.system.deviceKey("Return", true)
		s.system.deviceKey("Return", false)
		expect(s.base()).toBe(1)
		expect(s.menu()).toBe(0)
	end)

	it(
		"a modified binding preempts an unmodified sibling on the same key when held (T1 arbitration, not a new rule)",
		function()
			local s = shiftCollisionSetup()
			s.system.deviceKey("LeftShift", true)
			s.system.deviceKey("Return", true)
			s.system.deviceKey("Return", false)
			s.system.deviceKey("LeftShift", false)
			expect(s.menu()).toBe(1)
			expect(s.base()).toBe(0) -- the base Activate context never saw it
		end
	)

	it("plain Return keeps working normally after a shifted press (no stuck preemption)", function()
		local s = shiftCollisionSetup()
		s.system.deviceKey("LeftShift", true)
		s.system.deviceKey("Return", true)
		s.system.deviceKey("Return", false)
		s.system.deviceKey("LeftShift", false)
		s.system.deviceKey("Return", true)
		s.system.deviceKey("Return", false)
		expect(s.base()).toBe(1)
		expect(s.menu()).toBe(1)
	end)

	it(
		"gamepad bindings ignore modifier slots entirely: an unmodified ButtonX binding is unaffected by held shift",
		function()
			local core = customFactory.new()
			local system = actionsLib.newSystem(core)
			local ctx = system.createContext({ name = "RowActionsKeys", priority = 10000, sink = true })
			local menuAction = ctx.createAction("RowActionsMenu", "Bool")
			menuAction.bind({ keyCode = "ButtonX" }) -- no `modifiers` — the real shape shipped
			local presses = 0
			menuAction.onPressed(function()
				presses += 1
			end)
			system.deviceKey("LeftShift", true) -- held throughout; irrelevant to a gamepad button
			system.deviceKey("ButtonX", true)
			system.deviceKey("ButtonX", false)
			expect(presses).toBe(1)
		end
	)

	-- Fix round 2 (platform review, MAJOR-1 — HEADLESS, independently
	-- reproduced against the fix-round-1 commit): the key-up escape hatch
	-- was `action.state:get() == true` — ACTION-scoped, not BINDING-scoped
	-- — so a modified binding could re-enter candidacy on a key-up it never
	-- actually received the matching key-down for, preempt an unmodified
	-- sibling's own release via the higher-priority Sink context, and leave
	-- that sibling's Bool `state` stuck `true` — silently swallowing the
	-- NEXT legitimate press (`_deliver`'s own `previous == value` dedup).
	-- Both repros are reproduced VERBATIM from the review findings
	-- (task-8b-review-findings.md MAJOR-1) as the corrective tests.
	it("MAJOR-1 repro A1: tapping shift WHILE plain Return is held does not steal that Return's own key-up", function()
		local s = shiftCollisionSetup()
		s.system.deviceKey("Return", true)
		s.system.deviceKey("LeftShift", true)
		s.system.deviceKey("Return", false)
		s.system.deviceKey("LeftShift", false)
		s.system.deviceKey("Return", true)
		s.system.deviceKey("Return", false)
		expect(s.base()).toBe(2)
	end)

	it(
		"MAJOR-1 repro A2: holding an unmodified sibling (ButtonX) on the SAME action does not steal a later plain Return's key-up",
		function()
			local core = customFactory.new()
			local system = actionsLib.newSystem(core)
			local ctxBase = system.createContext({ name = "Base", priority = 1500, sink = false })
			local actBase = ctxBase.createAction("Activate", "Bool")
			actBase.bind({ keyCode = "Return" })
			local ctxMenu = system.createContext({ name = "RowActionsKeys", priority = 10000, sink = true })
			local actMenu = ctxMenu.createAction("RowActionsMenu", "Bool")
			actMenu.bind({ keyCode = "ButtonX" })
			actMenu.bind({ keyCode = "Return", modifiers = { shift = true } })
			local basePresses = 0
			actBase.onPressed(function()
				basePresses += 1
			end)
			system.deviceKey("ButtonX", true) -- the SAME action's OTHER binding, unmodified, held
			system.deviceKey("Return", true) -- plain Return, shift never touched
			system.deviceKey("Return", false)
			system.deviceKey("ButtonX", false)
			system.deviceKey("Return", true)
			system.deviceKey("Return", false)
			expect(basePresses).toBe(2)
		end
	)

	it("a chord's key-up reaches its binding even if the modifier released first (no stuck Bool state)", function()
		local s = shiftCollisionSetup()
		s.system.deviceKey("LeftShift", true)
		s.system.deviceKey("Return", true)
		expect(s.actMenu.state:get()).toBe(true)
		s.system.deviceKey("LeftShift", false) -- released BEFORE Return
		s.system.deviceKey("Return", false) -- must still reach actMenu, or its Bool sticks true
		expect(s.actMenu.state:get()).toBe(false)
		-- proof it isn't stuck: the NEXT full shifted press fires again (a
		-- stuck-true state would dedupe this second `_deliver(true)` away)
		s.system.deviceKey("LeftShift", true)
		s.system.deviceKey("Return", true)
		s.system.deviceKey("Return", false)
		s.system.deviceKey("LeftShift", false)
		expect(s.menu()).toBe(2)
	end)

	it("resetModifiers clears tracked held-modifier state (the documented stuck-modifier escape hatch)", function()
		local core = customFactory.new()
		local system = actionsLib.newSystem(core)
		system.deviceKey("LeftShift", true) -- simulates an interrupted chord: no matching key-up
		expect(system.modifiers().shift).toBe(true)
		system.resetModifiers()
		expect(system.modifiers().shift).toBe(false)
	end)
end)
