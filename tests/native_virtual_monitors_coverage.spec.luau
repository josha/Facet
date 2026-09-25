--!strict
local t = require("./lib/testkit")
local fs = require("@lune/fs")
local Compose = require("../src/vendor/compose/core")
local Roblox = require("../src/vendor/compose/roblox")
local engineModule = require("./lib/native_engine")
local Facet = require("../src") :: any
local modelModule = require("../examples/virtual_monitors/model")
local screens = require("../examples/virtual_monitors/screens")
local desktop = require("../examples/virtual_monitors/desktop")
local theme = require("../examples/virtual_monitors/theme")

local function sortedKeys(source: { [string]: any }, keep: (any) -> boolean): { string }
	local names = {}
	for key, value in source do
		if keep(value) then
			table.insert(names, key)
		end
	end
	table.sort(names)
	return names
end

local function tracker()
	local used: { [string]: boolean } = {}
	local function counted(prefix: string, source: any): any
		return setmetatable({}, {
			__index = function(_, key)
				used[prefix .. tostring(key)] = true
				return source[key]
			end,
		})
	end
	local themes = counted("themes.", Facet.themes)
	local tracked = setmetatable({}, {
		__index = function(_, key)
			used["Facet." .. tostring(key)] = true
			if key == "controls" then
				return function(runtime, options)
					return counted("UI.", Facet.controls(runtime, options))
				end
			elseif key == "themes" then
				return themes
			end
			return Facet[key]
		end,
	})
	return tracked, used
end

local function entryFields(): { [string]: boolean }
	local source = fs.readFile("examples/virtual_monitors/main.client.luau")
	local fields = {}
	for name in string.gmatch(source, "Facet%.([%a_]+)") do
		fields["Facet." .. name] = true
	end
	for name in string.gmatch(source, "Facet%.themes%.([%a_]+)") do
		fields["themes." .. name] = true
	end
	return fields
end

local function find(node: any, name: string): any
	if node.Name == name then
		return node
	end
	for _, child in node:GetChildren() do
		local found = find(child, name)
		if found then
			return found
		end
	end
	return nil
end

local function press(root: any, name: string)
	local node = find(root, name)
	assert(node, `the tour needs {name}`)
	node.Activated.fire()
	return node
end

local function tour(world: any)
	local model, target, types = world.model, world.target, world.types
	local discover = world.Discover
	press(discover, "WakeMonitor")
	find(discover, "DiscoverBody").AbsoluteSize = types.Vector2.new(1000, 800)
	find(discover, "Games").AbsoluteWindowSize = types.Vector2.new(820, 260)
	model.catalog.seen(35)
	model.step(0.1, true)
	for _ = 1, 4 do
		world.engine.heartbeat.fire(1 / 60)
	end
	local card = find(discover, "Game_1")
	card:_fireSignal("MouseEnter")
	press(card, "Primary")
	card:_fireSignal("MouseLeave")
	press(card, "Body")
	press(press(target, "Play"), "Primary")
	press(target, "AboutRating")
	press(find(target, "DetailSection"), "similar")
	press(target, "close")
	press(discover, "Saved")
	press(discover, "Browse")
	model.query:set("definitely absent")
	press(discover, "ClearFilters")
	press(discover, "About")
	press(target, "done")
	press(discover, "Profile")
	press(find(find(target, "PresenceCard"), "Presence"), "busy")
	local avatar = world.Avatar
	press(avatar, "WakeMonitor")
	press(avatar, "Summary")
	press(target, "Done")
	press(avatar, "MotionRow")
	local chat = world.Chat
	press(chat, "WakeMonitor")
	model.chat.draft:set("What game should I play with friends?")
	press(chat, "Send")
	find(chat, "Messages").AbsoluteWindowSize = types.Vector2.new(850, 400)
	for _ = 1, 80 do
		model.step(0.1, true)
	end
	t.expect(find(chat, "Feedback") ~= nil).toBe(true)
	local desktop = world.Desktop
	t.expect(find(desktop, "Apps") ~= nil).toBe(true)
end

t.describe("native virtual monitors coverage", function()
	t.it("uses every public Facet field, control and theme function in the mounted showcase", function()
		local tracked, used = tracker()
		local engine = engineModule.new()
		local runtime = Roblox.createRuntime(engine)
		local target = engine.new("ScreenGui")
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		input.IsKeyDown = function()
			return false
		end
		local lifetime = Compose.createRootOwner(function()
			local model = modelModule.new(Compose)
			Compose.cleanup(model.dispose)
			local world: any = { model = model, engine = engine, types = engine.types, target = target }
			local function config(name: string, spatial: boolean): any
				return {
					model = model,
					types = engine.types,
					services = { GuiService = gui, UserInputService = input },
					reducedMotion = true,
					spatial = spatial,
					theme = theme.create(tracked, name),
				}
			end
			for _, name in { "Discover", "Avatar", "Chat" } do
				local views = screens.create(tracked, runtime, config(name, true))
				local _, node = runtime.mount(views[name], target)
				world[name] = node
			end
			local flat = screens.create(tracked, runtime, config("Discover", false))
			local _, root = runtime.mount(
				desktop.create(
					tracked,
					runtime,
					flat,
					model,
					Compose.cell(1),
					{ types = engine.types, theme = theme.create(tracked, "Discover") }
				),
				target
			)
			world.Desktop = root
			tour(world)
		end, runtime.reactor)
		lifetime.dispose()
		runtime:dispose()

		local entry = entryFields()
		local missing, total = {}, 0
		local function check(prefix: string, names: { string })
			for _, name in names do
				total += 1
				if not used[prefix .. name] and not entry[prefix .. name] then
					table.insert(missing, prefix .. name)
				end
			end
		end
		check(
			"Facet.",
			sortedKeys(Facet, function()
				return true
			end)
		)
		local probe = engineModule.new()
		check(
			"UI.",
			sortedKeys(Facet.controls(Roblox.createRuntime(probe), { types = probe.types }), function(value)
				return type(value) == "function"
			end)
		)
		check(
			"themes.",
			sortedKeys(Facet.themes, function(value)
				return type(value) == "function"
			end)
		)
		t.expect(total > 60).toBe(true)
		if #missing > 0 then
			error(`{total - #missing}/{total} used; unused: {table.concat(missing, ", ")}`, 0)
		end
	end)
end)
