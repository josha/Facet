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
		-- either control or meta reads as the toggle modifier (cmd on mac)
		system.deviceKey("LeftControl", true)
		expect(system.modifiers().toggle).toBe(true)
		system.deviceKey("LeftControl", false)
		system.deviceKey("RightMeta", true)
		expect(system.modifiers().toggle).toBe(true)
		system.deviceKey("RightMeta", false)
		expect(system.modifiers().toggle).toBe(false)
	end)
end)
