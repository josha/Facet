--!strict
local harness = require("./lib/harness")
local t = require("./lib/testkit")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local coreFactory = harness.coreFactory
local Compose = require("../src").Compose
local releases = {}
t.afterEach(function()
	for i = #releases, 1, -1 do
		releases[i]()
	end
	table.clear(releases)
end)
local function event()
	local callbacks = {}
	return {
		Connect = function(_, fn)
			local c = { live = true }
			function c:Disconnect()
				self.live = false
			end
			table.insert(callbacks, { c, fn })
			return c
		end,
		fire = function(_, ...)
			for _, pair in callbacks do
				if pair[1].live then
					pair[2](...)
				end
			end
		end,
	}
end
local function rig(labels, images)
	local held = {}
	local enum = setmetatable({}, {
		__index = function(self, k)
			local e = setmetatable({}, {
				__index = function(_, n)
					return n
				end,
			})
			rawset(self, k, e)
			return e
		end,
	})
	local input = {
		GetStringForKeyCode = function(_, key)
			return (labels or {})[key] or ""
		end,
		GetImageForKeyCode = function(_, key)
			return (images or {})[key] or ""
		end,
		GetLastInputType = function()
			return { Name = "Gamepad1" }
		end,
		GetConnectedGamepads = function()
			return { "Gamepad1" }
		end,
		IsGamepadButtonDown = function(_, _, key)
			return held[key] == true
		end,
		IsKeyDown = function(_, key)
			return held[key] == true
		end,
	}
	local services = { Players = { LocalPlayer = {} }, UserInputService = input, ReplicatedStorage = {} }
	local game = {
		GetService = function(_, name)
			return services[name]
		end,
	}
	local instance = {
		new = function(class)
			return {
				ClassName = class,
				Enabled = true,
				StateChanged = event(),
				Pressed = event(),
				Released = event(),
				Destroy = function(self)
					self.destroyed = true
				end,
			}
		end,
	}
	local adapter = luau.load(fs.readFile("src/client/roblox_input.luau"), {
		environment = {
			game = game,
			Instance = instance,
			Enum = enum,
			require = function(path)
				if path == "../vendor/compose/core" then
					return require("../src").Compose
				end
				if path == "../input/key_names" then
					return require("../src/input/key_names")
				end
				assert(path == "../input/binding_owner", "unexpected adapter dependency: " .. path)
				return require("../src/input/binding_owner")
			end,
		},
	})()
	local system = adapter.newSystem(coreFactory.new())
	table.insert(releases, system.dispose)
	return system, held
end

t.describe("native held input metadata", function()
	t.it("records the held physical binding before delivering state and checks ownership", function()
		local system, held = rig()
		local context = system.createContext({ name = "screen" })
		local action = context.createAction("Navigate", "Direction1D")
		local binding = action.bind({ keyCode = "DPadDown", direction = 1 })
		held.DPadDown = true
		action.instance.StateChanged:fire(1)
		t.expect(action.lastGamepad).toBe(true)
		t.expect(action.lastBinding).toBe(binding)
		t.expect(system.wouldWinArbitration(context, binding)).toBe(true)
		local modal = system.createContext({ name = "modal", priority = 2000, sink = true })
		modal.createAction("Navigate", "Direction1D").bind({ keyCode = "DPadDown", direction = 1 })
		t.expect(system.wouldWinArbitration(context, binding)).toBe(false)
		modal.destroy()
		binding.remove()
		t.expect(system.wouldWinArbitration(context, binding)).toBe(false)
		system.dispose()
	end)
	t.it("keeps an analog direction held until recenter and re-arms afterwards", function()
		local system = rig()
		local action = system.createContext({ name = "screen" }).createAction("Navigate", "Direction1D")
		local binding = action.bindAxis({ axis = "Thumbstick1", component = "y" })
		local Vector2 = require("@lune/roblox").Vector2
		binding.axisInstance.StateChanged:fire(Vector2.new(0, -1))
		t.expect(action.state:peek()).toBe(1)
		t.expect(action.lastGamepad).toBe(true)
		t.expect(action.lastBinding).toBe(binding)
		binding.axisInstance.StateChanged:fire(Vector2.new(0, -0.7))
		t.expect(action.state:peek()).toBe(1)
		binding.axisInstance.StateChanged:fire(Vector2.new(0, 0))
		t.expect(action.state:peek()).toBe(0)
		binding.axisInstance.StateChanged:fire(Vector2.new(0, 1))
		t.expect(action.state:peek()).toBe(-1)
		system.dispose()
	end)
end)

t.describe("action naming and revision on both input implementations", function()
	for _, native in { false, true } do
		local function systemOf()
			if native then
				return rig()
			end
			local system = require("../src/input/actions").newSystem(coreFactory.new())
			table.insert(releases, system.dispose)
			return system
		end
		t.it(`resolved class owns preferred binding selection, native {native}`, function()
			local system = systemOf()
			local action = system.createContext({ name = "keys" }).createAction("Go", "Bool")
			local keyboard = action.bind({ keyCode = "Return" })
			local pad = action.bind({ keyCode = "ButtonA" })
			if native then
				action.instance.PreferredBinding = keyboard.instance
			else
				action.enginePreferred = keyboard
			end
			t.expect(action.preferredBinding("Gamepad")).toBe(pad)
			t.expect(action.preferredBinding("Touch")).toBeNil()
			if native then
				action.instance.PreferredBinding = pad.instance
			else
				action.enginePreferred = pad
			end
			t.expect(action.preferredBinding("KeyboardAndMouse")).toBe(keyboard)
			pad.remove()
			t.expect(action.preferredBinding("Gamepad")).toBe(keyboard) -- established non-touch fallback
			keyboard.remove()
			t.expect(action.preferredBinding("Gamepad")).toBeNil()
		end)

		t.it(`publishes revisions after every naming mutation with complete bindings, native {native}`, function()
			local system = systemOf()
			local owner = Compose.createOwner(Compose.reactor())
			table.insert(releases, owner.dispose)
			local seen = {}
			owner.watchStatic(system.revision, function(n)
				local action = system.actionNamed("Go")
				local complete = true
				for _, binding in if action then action.bindings else {} do
					complete = complete and type(binding.remove) == "function"
				end
				table.insert(seen, { revision = n, action = action, complete = complete })
			end)
			local function advance(fn)
				local prior = system.revision:peek()
				local result = fn()
				t.expect(system.revision:peek()).toBe(prior + 1)
				t.expect(seen[#seen].revision).toBe(prior + 1)
				t.expect(seen[#seen].complete).toBe(true)
				return result
			end
			local context = advance(function()
				return system.createContext({ name = "keys" })
			end)
			local action = advance(function()
				return context.createAction("Go", "Direction1D")
			end)
			local plain = advance(function()
				return action.bind({ keyCode = "Right", direction = 1 })
			end)
			local modifier = advance(function()
				return action.bind({ keyCode = "Left", modifiers = { shift = true }, direction = -1 })
			end)
			local axis = advance(function()
				return action.bindAxis({ axis = "Thumbstick1", component = "x" })
			end)
			advance(plain.remove)
			advance(modifier.remove)
			advance(axis.remove)
			advance(function()
				context.setEnabled(false)
			end)
			t.expect(seen[#seen].action).toBeNil()
			advance(function()
				context.setEnabled(true)
			end)
			t.expect(seen[#seen].action).toBe(action)
			advance(context.destroy)
			t.expect(seen[#seen].action).toBeNil()
			local atDispose = system.revision:peek()
			system.dispose()
			context.setEnabled(false)
			t.expect(system.revision:peek()).toBe(atDispose)
		end)

		t.it(`prefers a live disabled own context before enabled priority fallback, native {native}`, function()
			local system = systemOf()
			local low = system.createContext({ name = "low", priority = 1 })
			local own = low.createAction("Activate", "Bool")
			local high = system.createContext({ name = "high", priority = 20 })
			local outer = high.createAction("Activate", "Bool")
			local tie = system.createContext({ name = "tie", priority = 20 })
			tie.createAction("Activate", "Bool")
			low.setEnabled(false)
			t.expect(system.actionNamed("Activate", low)).toBe(own)
			t.expect(system.actionNamed("Activate")).toBe(outer)
			low.destroy()
			t.expect(system.actionNamed("Activate", low)).toBe(outer)
			high.setEnabled(false)
			t.expect(system.actionNamed("Activate")).toBe(tie.actions[1])
			tie.destroy()
			t.expect(system.actionNamed("Activate")).toBeNil()
		end)
	end
end)

t.describe("native key names and provider lifetime", function()
	t.it("asks the actual adapter provider and keeps authored and readable fallbacks", function()
		local names = require("../src/input/key_names")
		local hint = require("../src/input/hint")
		local system = rig(
			{ Return = "", Space = "  ", ButtonA = "Cross", LeftShift = "LeftShift", Q = "A" },
			{ ButtonA = "rbxassetid://101" }
		)
		t.expect(names.label("Q")).toBe("A")
		t.expect(names.label("Return")).toBe("Enter")
		t.expect(names.label("Space")).toBe("Space")
		t.expect(names.label("LeftShift")).toBe("Shift")
		t.expect(hint.labelOf({ keyCode = "ButtonA" })).toBe("Cross")
		t.expect(hint.labelOf({ keyCode = "ButtonA", displayName = "Own button" })).toBe("Own button")
		t.expect(hint.labelOf({ keyCode = "UnlistedKey" })).toBe("UnlistedKey")
		t.expect(names.image("ButtonA")).toBe("rbxassetid://101")
		system.dispose()
		t.expect(names.label("ButtonA")).toBe("A")
	end)

	t.it("out-of-order native teardown cannot resurrect a removed provider", function()
		local names = require("../src/input/key_names")
		local first = rig({ Q = "first" })
		local second = rig({ Q = "second" })
		t.expect(names.label("Q")).toBe("second")
		first.dispose()
		t.expect(names.label("Q")).toBe("second")
		second.dispose()
		t.expect(names.label("Q")).toBeNil()
		first.dispose()
		t.expect(names.label("Q")).toBeNil()
	end)
end)
