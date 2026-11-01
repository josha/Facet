--!strict

type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
local Compose = require("../../src/vendor/compose/core")
local Roblox = require("../../src/vendor/compose/roblox")
local controls = require("../../src/ui")
local engines = require("./native_engine")
local Shared = require("../../src/ui/types")
local Facet = require("../../src")

export type Setup = {
	inputs: boolean?,
	runService: boolean?,
	preRender: boolean?,
	lastInputType: Enum.UserInputType?,
	size: Vector2?,
}

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

function world.new(
	build: (FacetControls, RobloxHost, engines.Engine, any, ComposeRuntime) -> Shared.Child,
	options: Shared.Config?,
	setup: Setup?
): any
	local o: Setup = setup or {}
	local engine: engines.Engine = engines.new()
	local now = 0
	engine.clock = function()
		return now
	end
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	local lastInputType: Enum.UserInputType? = o.lastInputType
	if lastInputType then
		input.GetLastInputType = function()
			return lastInputType
		end
	end
	input.GetFocusedTextBox = function()
		return nil
	end
	local runtime: ComposeRuntime = Roblox.createRuntime(engine)
	local target = engine.new("Folder")
	local config: Shared.Config = options or {}
	config = table.clone(config)
	config.types = engine.types
	config.inputParent = if o.inputs then target else nil
	config.services = {
		GuiService = gui,
		UserInputService = input,
		RunService = if o.runService
			then { Heartbeat = engine.heartbeat, PreRender = if o.preRender then engine.heartbeat else nil } :: any
			else nil,
	}
	local UI = controls(Compose, runtime, config)
	local V = engine.types.Vector2
	local Host: RobloxHost = Facet.host(runtime)
	local stop, screen: any = runtime.mount(function()
		local props: Shared.ScreenGuiNativeProps = {
			build(UI, Host, engine, gui, runtime),
		}
		return Host.ScreenGui(props)
	end, target)
	local size = o.size or V.new(800, 600)
	engine.environment.poke(screen, "AbsoluteSize", size)
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
		self.engine.environment.poke(node, "AbsoluteSize", V.new(x, y))
	end
	function self.at(node: any, x: number, y: number)
		self.engine.environment.poke(node, "AbsolutePosition", V.new(x, y))
	end
	function self.advance(seconds: number, steps: number?)
		local count = steps or 1
		for _ = 1, count do
			now += seconds / count
			engine.heartbeat:Fire(seconds / count)
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
