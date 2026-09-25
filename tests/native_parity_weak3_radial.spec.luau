--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose

type World = {
	engine: any,
	gui: any,
	root: any,
	step: (number) -> (),
	stop: () -> (),
}

local function setup(build: (any) -> any, animated: boolean): World
	local engine: any = engineLib.new()
	local now = 0
	engine.clock = function()
		return now
	end
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	input.IsKeyDown = function()
		return false
	end
	local root = engine.new("ScreenGui")
	local UI = Facet.controls(
		runtime,
		{
			types = engine.types,
			guiService = gui,
			services = { GuiService = gui, UserInputService = input },
			inputParent = root,
			reducedMotion = not animated,
		} :: any
	)
	local stop = runtime.mount(function()
		return build(UI)
	end, root)
	return {
		engine = engine,
		gui = gui,
		root = root,
		step = function(seconds: number)
			for _ = 1, math.ceil(seconds * 60) do
				now += 1 / 60
				engine.heartbeat.fire(1 / 60)
			end
		end,
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
end

local function find(root: any, name: string): any
	return root:FindFirstChild(name, true)
end

local function offset(node: any): (number, number)
	return node.Position.X.Offset, node.Position.Y.Offset
end

local function distance(ax: number, ay: number, bx: number, by: number): number
	return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

local function arena(world: World)
	local modal = find(world.root, "Modal")
	modal.AbsoluteSize = world.engine.types.Vector2.new(920, 640)
end

t.describe("radial ring arrival motion", function()
	t.it("a replacement branch slides out from its parent and settles on its own slot", function()
		for _, appearance in { "buttons", "wedges" } do
			local world = setup(function(UI)
				return UI.RadialMenu({
					isPresented = Compose.cell(true),
					appearance = appearance,
					items = {
						{ id = "Wave", label = "Wave", onSelect = function() end },
						{
							id = "Gear",
							label = "Gear",
							children = {
								{ id = "Tool", label = "Tool", onSelect = function() end },
								{ id = "Lamp", label = "Lamp", onSelect = function() end },
							},
						},
					},
				})
			end, true)
			arena(world)
			world.step(0.3)
			local gx, gy = offset(find(world.root, "Gear"))
			find(world.root, "Gear").Activated.fire()
			world.step(1 / 60)
			local tool = find(world.root, "Tool")
			local paint = find(world.root, "Sector-Tool"):FindFirstChild("Paint")
			local ex, ey = offset(tool)
			local px, py = offset(paint)
			world.step(0.3)
			local fx, fy = offset(tool)
			local qx, qy = offset(paint)
			t.expect(distance(ex, ey, fx, fy) > 20).toBe(true)
			t.expect(distance(ex, ey, gx, gy) < distance(fx, fy, gx, gy)).toBe(true)
			t.expect(distance(px - qx, py - qy, ex - fx, ey - fy) <= 2).toBe(true)
			world.step(0.3)
			local sx, sy = offset(tool)
			t.expect(sx).toBe(fx)
			t.expect(sy).toBe(fy)
			world.stop()
		end
	end)

	t.it("a held D-pad stays on one ring stop because the ring pins engine selection", function()
		local world = setup(function(UI)
			return UI.RadialMenu({
				isPresented = Compose.cell(true),
				appearance = "buttons",
				items = {
					{ id = "North", label = "North" },
					{ id = "East", label = "East" },
					{ id = "South", label = "South" },
					{ id = "West", label = "West" },
				},
			})
		end, false)
		world.step(0.2)
		local north = find(world.root, "North")
		world.gui.SelectedObject = north
		world.step(0.05)
		for _, direction in { "Up", "Down", "Left", "Right" } do
			t.expect(`{direction}: {tostring(north["NextSelection" .. direction] == north)}`).toBe(`{direction}: true`)
		end
		world.stop()
	end)

	t.it("a slot added to an open ring slides in from the center", function()
		local items = Compose.cell({
			{ id = "Wave", label = "Wave", onSelect = function() end },
			{ id = "Point", label = "Point", onSelect = function() end },
		} :: { any })
		local world = setup(function(UI)
			return UI.RadialMenu({ isPresented = Compose.cell(true), appearance = "buttons", items = items })
		end, true)
		arena(world)
		world.step(0.3)
		local center = find(world.root, "Center")
		local cx, cy = offset(center)
		items:set({
			{ id = "Wave", label = "Wave", onSelect = function() end },
			{ id = "Point", label = "Point", onSelect = function() end },
			{ id = "Cheer", label = "Cheer", onSelect = function() end },
		})
		world.step(1 / 60)
		local cheer = find(world.root, "Cheer")
		local ex, ey = offset(cheer)
		world.step(0.4)
		local fx, fy = offset(cheer)
		t.expect(distance(ex, ey, fx, fy) > 1).toBe(true)
		t.expect(distance(ex, ey, cx, cy) < distance(fx, fy, cx, cy)).toBe(true)
		world.stop()
	end)

	t.it("reduced motion places a replacement branch on its slot at once", function()
		local world = setup(function(UI)
			return UI.RadialMenu({
				isPresented = Compose.cell(true),
				appearance = "buttons",
				items = {
					{
						id = "Gear",
						label = "Gear",
						children = { { id = "Tool", label = "Tool", onSelect = function() end } },
					},
				},
			})
		end, false)
		arena(world)
		world.step(0.3)
		find(world.root, "Gear").Activated.fire()
		world.step(1 / 60)
		local tool = find(world.root, "Tool")
		local ex, ey = offset(tool)
		world.step(0.3)
		local fx, fy = offset(tool)
		t.expect(ex).toBe(fx)
		t.expect(ey).toBe(fy)
		world.stop()
	end)
end)

local function route(root: any, key: any): any
	local best, bestAction = nil, nil
	for _, context in root:GetDescendants() do
		if context:IsA("InputContext") and context.Enabled then
			for _, candidate in context:GetChildren() do
				if candidate:IsA("InputAction") then
					for _, binding in candidate:GetChildren() do
						if binding:IsA("InputBinding") and binding.KeyCode == key then
							if best == nil or context.Priority > best.Priority then
								best, bestAction = context, candidate
							end
						end
					end
				end
			end
		end
	end
	return bestAction
end

t.describe("value repeat under gameplay arbitration", function()
	t.it("a higher priority gameplay binding cancels value repeat and receives the next press", function()
		local value = Compose.cell(1)
		local world = setup(function(UI)
			return UI.Slider("Control")({ value = value, min = 0, max = 10, step = 1 })
		end, false)
		local R1 = world.engine.types.Enum.KeyCode.ButtonR1
		local owner: any = nil
		local function press()
			local target = route(world.root, R1)
			owner = target
			if target and target.Name ~= "Boost" then
				target.GetState = function()
					return owner == target
				end
			end
			target.Pressed.fire()
		end
		local function release()
			local target = owner
			owner = nil
			if target then
				target.Released.fire()
			end
		end
		world.gui.SelectedObject = find(world.root, "Track")
		press()
		t.expect(value:peek()).toBe(2)
		world.step(0.45)
		t.expect(value:peek()).toBe(3)
		local gameplay = world.engine.new("InputContext")
		gameplay.Name = "Gameplay"
		gameplay.Priority = 100000
		gameplay.Sink = true
		local boost = world.engine.new("InputAction")
		boost.Name = "Boost"
		local binding = world.engine.new("InputBinding")
		binding.KeyCode = R1
		binding.Parent = boost
		boost.Parent = gameplay
		gameplay.Parent = world.root
		local increase = route(world.root, R1)
		t.expect(increase).toBe(boost)
		for _, context in world.root:GetDescendants() do
			if context:IsA("InputContext") and context.Name == "FacetIncrease" then
				t.expect(context.Priority < gameplay.Priority).toBe(true)
			end
		end
		owner = boost
		local presses = 0
		boost.Pressed:Connect(function()
			presses += 1
		end)
		world.step(0.6)
		t.expect(value:peek()).toBe(3)
		release()
		press()
		release()
		t.expect(presses).toBe(1)
		t.expect(value:peek()).toBe(3)
		gameplay:Destroy()
		world.step(0.6)
		t.expect(value:peek()).toBe(3)
		press()
		release()
		t.expect(value:peek()).toBe(4)
		world.stop()
	end)
end)
