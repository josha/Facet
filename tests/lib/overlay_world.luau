--!strict
local Compose = require("../../src/vendor/compose/core")
local Roblox = require("../../src/vendor/compose/roblox")
local controls = require("../../src/ui")
local engines = require("./native_engine")

local world = {}

function world.find(root: any, name: string): any
	if root == nil then
		return nil
	end
	if root.Name == name then
		return root
	end
	for _, child in root:GetChildren() do
		local found = world.find(child, name)
		if found then
			return found
		end
	end
	return nil
end

function world.findAll(root: any, name: string): { any }
	local out = {}
	local function walk(node: any)
		if node.Name == name then
			table.insert(out, node)
		end
		for _, child in node:GetChildren() do
			walk(child)
		end
	end
	walk(root)
	return out
end

function world.action(root: any, name: string): any
	for _, node in root:GetDescendants() do
		if node:IsA("InputContext") and node.Name == "Facet" .. name and node.Enabled then
			return node:FindFirstChild(name)
		end
	end
	return nil
end

function world.new(build: (any, any, any, any, any) -> any, options: any?): any
	local o = options or {}
	local engine = engines.new()
	local now = 0
	engine.clock = function()
		return now
	end
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	local runtime = Roblox.createRuntime(engine)
	local UI = controls(Compose, runtime, {
		types = engine.types,
		services = {
			GuiService = gui,
			UserInputService = input,
			RunService = if o.runService then { Heartbeat = engine.heartbeat } else nil,
		},
		theme = o.theme,
		reducedMotion = o.reducedMotion,
		controlSize = o.controlSize,
		onError = o.onError,
	})
	local target = engine.new("Folder")
	local V = engine.types.Vector2
	local stop, screen = runtime.mount(function()
		return runtime.constructors.ScreenGui({ build(UI, runtime.constructors, engine, gui, runtime) })
	end, target)
	local size = o.size or V.new(800, 600)
	screen.AbsoluteSize = size
	local self: any = {
		engine = engine,
		gui = gui,
		input = input,
		runtime = runtime,
		screen = screen,
		UI = UI,
		Vector2 = V,
		Enum = engine.types.Enum,
	}
	function self.find(name: string): any
		return world.find(screen, name)
	end
	function self.findAll(name: string): { any }
		return world.findAll(screen, name)
	end
	function self.action(name: string): any
		return world.action(screen, name)
	end
	function self.size(node: any, x: number, y: number)
		node.AbsoluteSize = V.new(x, y)
	end
	function self.at(node: any, x: number, y: number)
		node.AbsolutePosition = V.new(x, y)
	end
	function self.advance(seconds: number, steps: number?)
		local count = steps or 1
		for _ = 1, count do
			now += seconds / count
			engine.heartbeat.fire(seconds / count)
		end
	end
	function self.tick(seconds: number)
		now += seconds
	end
	function self.stop()
		stop()
		runtime:dispose()
	end
	return self
end

return world
