--!strict
local harness = require("./lib/harness")
local t = require("./lib/testkit")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local coreFactory = harness.coreFactory
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
local function rig()
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
				assert(path == "../input/binding_owner", "unexpected adapter dependency: " .. path)
				return require("../src/input/binding_owner")
			end,
		},
	})()
	local system = adapter.newSystem(coreFactory.new())
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
