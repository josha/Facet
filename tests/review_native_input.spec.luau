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
		count = function()
			local live = 0
			for _, pair in callbacks do
				if pair[1].live then
					live += 1
				end
			end
			return live
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
local function rig(labels, images, opts)
	local held = {}
	local enum = setmetatable({}, {
		__index = function(self, k)
			local e = setmetatable({}, {
				__index = function(_, n)
					assert(n ~= "UnlistedKey", "invalid Enum member")
					return n
				end,
			})
			rawset(self, k, e)
			return e
		end,
	})
	local input = {
		GetStringForKeyCode = function(_, key)
			local value = (labels or {})[key]
			return if type(value) == "function" then value() else value or ""
		end,
		GetImageForKeyCode = function(_, key)
			local value = (images or {})[key]
			return if type(value) == "function" then value() else value or ""
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
	local services = {
		Players = { LocalPlayer = if opts and opts.server then nil else {} },
		UserInputService = input,
		ReplicatedStorage = {},
	}
	local game = {
		GetService = function(_, name)
			return services[name]
		end,
	}
	local created = {}
	local instance = {
		new = function(class)
			local properties = {}
			local object = {
				GetPropertyChangedSignal = function(_, name)
					if not properties[name] then
						properties[name] = event()
					end
					return properties[name]
				end,
				ClassName = class,
				Enabled = true,
				StateChanged = event(),
				Pressed = event(),
				Released = event(),
				Destroy = function(self)
					self.destroyed = true
				end,
			}
			table.insert(created, object)
			return object
		end,
	}
	local adapter = luau.load(fs.readFile("src/client/roblox_input.luau"), {
		environment = {
			game = game,
			Instance = instance,
			Enum = enum,
			task = require("@lune/task"),
			require = function(path)
				if path == "../vendor/compose/core" then
					return if opts and opts.compose then opts.compose else require("../src").Compose
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
	return system, held, created
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
	-- the engine twin of the headless rule: a Bool action armed
	-- while its key is down swallows that press and release; the next press lands
	t.it("a key already down when its binding arms reaches no handler until it is pressed again", function()
		local system, held = rig()
		held.Delete = true
		local context = system.createContext({ name = "tag" })
		local action = context.createAction("ChipRemove", "Bool")
		action.bind({ keyCode = "Delete" })
		local calls = {}
		action.onPressed(function()
			table.insert(calls, "pressed")
		end)
		action.onReleased(function()
			table.insert(calls, "released")
		end)
		action.instance.Pressed:fire()
		held.Delete = false
		require("@lune/task").wait(0.05) -- the adapter polls the release once a frame
		action.instance.Released:fire()
		t.expect(table.concat(calls, " ")).toBe("")
		held.Delete = true
		action.instance.Pressed:fire()
		action.instance.Released:fire()
		t.expect(table.concat(calls, " ")).toBe("pressed released")
		-- re-enabling mid-hold arms again
		context.setEnabled(false)
		context.setEnabled(true)
		action.instance.Pressed:fire()
		t.expect(table.concat(calls, " ")).toBe("pressed released")
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

t.describe("native preferred binding invalidation", function()
	t.it("publishes same-class engine tie changes once and disconnects on teardown", function()
		local system = rig()
		local context = system.createContext({ name = "keys" })
		local action = context.createAction("Go", "Bool")
		local first = action.bind({ keyCode = "Return" })
		local second = action.bind({ keyCode = "Space" })
		local owner = Compose.createOwner()
		table.insert(releases, owner.dispose)
		local seen = {}
		owner.watch(function(use)
			use(system.revision)
			table.insert(seen, action.preferredBinding("KeyboardAndMouse").keyCode)
		end)
		local changed = action.instance:GetPropertyChangedSignal("PreferredBinding")
		t.expect(changed.count()).toBe(1)
		local count = system.revision:peek()
		action.instance.PreferredBinding = second.instance
		changed:fire()
		t.expect(system.revision:peek()).toBe(count + 1)
		t.expect(seen).toEqual({ "Return", "Space" })
		context.destroy()
		count = system.revision:peek()
		t.expect(changed.count()).toBe(0)
		action.instance.PreferredBinding = first.instance
		changed:fire()
		t.expect(system.revision:peek()).toBe(count)
	end)

	t.it("maps either modifier sibling instance to its authored binding", function()
		local system, _, created = rig()
		local action = system.createContext({ name = "keys" }).createAction("Go", "Bool")
		action.bind({ keyCode = "Q" })
		local modified = action.bind({ keyCode = "K", modifiers = { shift = true }, displayName = "Shift K" })
		local right
		for _, object in created do
			if object.ClassName == "InputBinding" and object.PrimaryModifier == "RightShift" then
				right = object
			end
		end
		t.expect(right ~= nil).toBe(true)
		action.instance.PreferredBinding = right
		t.expect(action.preferredBinding("KeyboardAndMouse")).toBe(modified)
	end)
end)

t.describe("native key names and provider lifetime", function()
	t.it("asks the actual adapter provider and keeps authored and readable fallbacks", function()
		local names = require("../src/input/key_names")
		local hint = require("../src/input/hint")
		local system = rig(
			{ Return = "", Space = "  ", ButtonA = "Cross", LeftShift = "LeftShift", Q = "A" },
			{ ButtonA = "rbxassetid://101", Space = "  " }
		)
		t.expect(names.label("Q")).toBe("A")
		t.expect(names.label("Return")).toBe("Enter")
		t.expect(names.label("Space")).toBe("Space")
		t.expect(names.image("Space")).toBeNil()
		t.expect(names.label("LeftShift")).toBe("Shift")
		t.expect(hint.labelOf({ keyCode = "ButtonA" })).toBe("Cross")
		t.expect(hint.labelOf({ keyCode = "ButtonA", displayName = "Own button" })).toBe("Own button")
		t.expect(hint.labelOf({ keyCode = "UnlistedKey" })).toBe("UnlistedKey")
		t.expect(names.image("ButtonA")).toBe("rbxassetid://101")
		system.dispose()
		t.expect(names.label("ButtonA")).toBe("A")
	end)

	t.it("native service failures retain readable labels and optional images", function()
		local names = require("../src/input/key_names")
		local function unavailable()
			error("native service unavailable")
		end
		rig({ Return = unavailable }, { ButtonA = unavailable })
		t.expect(names.label("Return")).toBe("Enter")
		t.expect(names.image("ButtonA")).toBeNil()
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

t.describe("provider restoration and refused system ownership", function()
	t.it("refuses a non-client before allocating the system revision", function()
		local cells = 0
		local compose = {
			cell = function()
				cells += 1
				error("unexpected allocation")
			end,
		}
		local ok, err = pcall(function()
			rig(nil, nil, { server = true, compose = compose })
		end)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "must run on a live client", 1, true) ~= nil).toBe(true)
		t.expect(cells).toBe(0)
	end)
	for _, oldestFirst in { true, false } do
		t.it(`restores native providers in either disposal order: oldest first {oldestFirst}`, function()
			local names = require("../src/input/key_names")
			local a = rig({ Q = "first" })
			local b = rig({ Q = "second" })
			t.expect(names.label("Q")).toBe("second")
			local first, last = if oldestFirst then a else b, if oldestFirst then b else a
			first.dispose()
			t.expect(names.label("Q")).toBe(if oldestFirst then "second" else "first")
			first.dispose()
			last.dispose()
			last.dispose()
			t.expect(names.label("Q")).toBe(nil)
		end)
	end
	t.it("retains nil-provider registrations through out-of-order removal", function()
		local names = require("../src/input/key_names")
		local function install(value)
			local release = names.setPlatform(value)
			table.insert(releases, release)
			return release
		end
		local a = install({
			label = function()
				return "first"
			end,
		})
		local empty = install(nil)
		t.expect(names.label("Q")).toBe(nil)
		local b = install({
			label = function()
				return "second"
			end,
		})
		a()
		t.expect(names.label("Q")).toBe("second")
		b()
		t.expect(names.label("Q")).toBe(nil)
		empty()
		empty()
		t.expect(names.label("Q")).toBe(nil)
	end)
end)
