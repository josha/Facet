--!strict
local Facet = require("../../src")
local engineLib = require("./native_engine")

export type World = {
	engine: any,
	runtime: any,
	gui: any,
	input: any,
	screen: any,
	UI: any,
	Host: any,
	stop: () -> (),
	find: (string, any?) -> any,
	findAll: (string, any?) -> { any },
	action: (string) -> any,
	V2: (number, number) -> any,
	resize: (any, number, number) -> (),
	bounds: (any, number, number?) -> (),
}

local function find(root: any, name: string): any
	if root.Name == name then
		return root
	end
	for _, child in root:GetChildren() do
		local found = find(child, name)
		if found then
			return found
		end
	end
	return nil
end

local function new(build: (any, any, any) -> any, options: { [string]: any }?): World
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	input.IsKeyDown = function()
		return false
	end
	local config: { [string]: any } = {
		types = engine.types,
		guiService = gui,
		services = { GuiService = gui, UserInputService = input },
	}
	for key, value in (options or {}) :: { [string]: any } do
		config[key] = value
	end
	local UI = Facet.controls(runtime, config :: any)
	local Host = runtime.constructors
	local stop, screen = runtime.mount(function()
		return Host.ScreenGui({ build(UI, Host, engine) })
	end, engine.new("Folder"))
	local world: World
	world = {
		engine = engine,
		runtime = runtime,
		gui = gui,
		input = input,
		screen = screen,
		UI = UI,
		Host = Host,
		stop = function()
			stop()
			runtime:dispose()
		end,
		find = function(name: string, root: any?): any
			return find(root or screen, name)
		end,
		findAll = function(name: string, root: any?): { any }
			local found = {}
			for _, node in (root or screen):GetDescendants() do
				if node.Name == name then
					table.insert(found, node)
				end
			end
			return found
		end,
		action = function(name: string): any
			for _, node in screen:GetDescendants() do
				if node:IsA("InputContext") and node.Name == "Facet" .. name and node.Enabled then
					return node:FindFirstChild(name)
				end
			end
			return nil
		end,
		V2 = function(x: number, y: number): any
			return engine.types.Vector2.new(x, y)
		end,
		resize = function(node: any, x: number, y: number)
			node.AbsoluteSize = engine.types.Vector2.new(x, y)
		end,
		bounds = function(node: any, x: number, y: number?)
			node.TextBounds = engine.types.Vector2.new(x, y or 20)
		end,
	}
	return world
end

local function mountError(build: (any, any) -> any): string?
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local UI =
		Facet.controls(runtime, { types = engine.types, guiService = gui, services = { GuiService = gui } } :: any)
	local Host = runtime.constructors
	local ok, message = pcall(function()
		local stop = runtime.mount(function()
			return Host.ScreenGui({ build(UI, Host) })
		end, engine.new("Folder"))
		stop()
	end)
	runtime:dispose()
	return if ok then nil else tostring(message)
end

return { new = new, mountError = mountError, find = find }
