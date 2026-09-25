--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local Roblox = require("../src/vendor/compose/roblox")
local controls = require("../src/ui")
local engines = require("./lib/native_engine")
local function setup(spec, animated)
	local engine, now = engines.new(), 0
	local gui, input = engine.new("GuiService"), engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	engine.clock = function()
		return now
	end
	local runtime = Roblox.createRuntime(engine)
	local UI = controls(Compose, runtime, {
		types = engine.types,
		services = { GuiService = gui, UserInputService = input },
		reducedMotion = not animated,
	})
	local opened = spec.isPresented or Compose.cell(true)
	spec.isPresented = opened
	local stop, screen = runtime.mount(function()
		return runtime.constructors.ScreenGui({ UI.RadialMenu(spec) })
	end, engine.new("Folder"))
	return {
		engine = engine,
		gui = gui,
		input = input,
		screen = screen,
		opened = opened,
		find = function(name)
			return screen:FindFirstChild(name, true)
		end,
		step = function(seconds)
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
local function compass(callback)
	local entries = {}
	for _, id in { "N", "E", "S", "W" } do
		table.insert(entries, {
			id = id,
			slot = id,
			label = id,
			completion = "stay",
			onSelect = function()
				callback(id)
			end,
		})
	end
	return entries
end
local function pointer(world, x, y)
	return {
		UserInputType = world.engine.types.Enum.UserInputType.Touch,
		UserInputState = world.engine.types.Enum.UserInputState.Begin,
		Position = world.engine.types.Vector3.new(x, y, 0),
	}
end
t.describe("native radial interaction policies", function()
	t.it("keeps the ring's aim, commit and direction actions in one input context", function()
		local picked = {}
		local world = setup({
			distribution = "compass",
			items = compass(function(id)
				table.insert(picked, id)
			end),
		})
		world.step(0.1)
		local context = world.find("FacetRadial")
		t.expect(context ~= nil and context:IsA("InputContext")).toBe(true)
		local names = {}
		for _, action in context:GetChildren() do
			table.insert(names, action.Name)
		end
		table.sort(names)
		t.expect(table.concat(names, ",")).toBe("Radial-down,Radial-left,Radial-right,Radial-up,RadialAim,RadialCommit")
		t.expect(world.find("FacetRadialCommit")).toBeNil()
		world.opened:set(false)
		world.step(0.5)
		t.expect(world.find("FacetRadial")).toBeNil()
		world.stop()
	end)

	t.it("NRAD-1 analog hold commits once and respects dead-zone hysteresis", function()
		local engine, picked = engines.new(), {}
		local hold = engine.new("InputAction")
		local world = setup({
			isPresented = Compose.cell(false),
			holdAction = hold,
			distribution = "compass",
			items = compass(function(id)
				table.insert(picked, id)
			end),
		})
		hold.Pressed.fire()
		local axis = world.find("RadialAim")
		t.expect(axis.Type).toBe(world.engine.types.Enum.InputActionType.Direction2D)
		axis.StateChanged.fire(world.engine.types.Vector2.new(0, 0.3))
		hold.Released.fire()
		t.expect(#picked).toBe(0)
		hold.Pressed.fire()
		axis.StateChanged.fire(world.engine.types.Vector2.new(0, 0.8))
		axis.StateChanged.fire(world.engine.types.Vector2.new(0, 0.3))
		hold.Released.fire()
		hold.Released.fire()
		t.expect(table.concat(picked, ",")).toBe("N")
		world.stop()
		t.expect(hold.Pressed.count()).toBe(0)
		t.expect(hold.Released.count()).toBe(0)
	end)
	t.it("NRAD-2 ignores foreign touch release and cancels captured touch", function()
		local count = 0
		local world = setup({ distribution = "compass", items = compass(function()
			count += 1
		end) })
		local panel, touch = world.find("RadialPanel"), pointer(world, 320, 110)
		panel.InputBegan.fire(touch)
		world.input.InputEnded.fire(pointer(world, 320, 110))
		t.expect(count).toBe(0)
		touch.UserInputState = world.engine.types.Enum.UserInputState.Cancel
		world.input.InputEnded.fire(touch)
		t.expect(count).toBe(0)
		world.stop()
	end)
	t.it("NRAD-3 suppresses the native activation echo after gesture commit", function()
		local count = 0
		local world = setup({ distribution = "compass", items = compass(function()
			count += 1
		end) })
		local touch = pointer(world, 320, 110)
		world.find("N").InputBegan.fire(touch)
		world.input.InputEnded.fire(touch)
		world.find("N").Activated.fire(touch)
		t.expect(count).toBe(1)
		world.find("N").InputBegan.fire(touch)
		world.input.InputEnded.fire(touch)
		t.expect(count).toBe(2)
		world.stop()
	end)
	t.it("NRAD-4 direction gestures work outside paint while bounded gestures cancel", function()
		for _, mode in { "direction", "bounded" } do
			local count = 0
			local world = setup({
				distribution = "compass",
				gestureSelection = mode,
				items = compass(function()
					count += 1
				end),
			})
			local touch = pointer(world, 320, 110)
			world.find("RadialPanel").InputBegan.fire(touch)
			touch.Position = world.engine.types.Vector3.new(320, -600, 0)
			world.input.InputChanged.fire(touch)
			world.input.InputEnded.fire(touch)
			t.expect(count).toBe(if mode == "direction" then 1 else 0)
			world.stop()
		end
	end)
	t.it("NRAD-5 freezes idle-follow anchor during capture then resumes", function()
		local anchor = Compose.cell({ x = 320, y = 240 })
		local world = setup({ anchor = anchor, distribution = "compass", items = compass(function() end) })
		local touch = pointer(world, 320, 110)
		world.find("RadialPanel").InputBegan.fire(touch)
		anchor:set({ x = 400, y = 240 })
		t.expect(world.find("N").Position.X.Offset).toBe(320)
		world.input.InputEnded.fire(touch)
		t.expect(world.find("N").Position.X.Offset).toBe(400)
		anchor:set({ x = 400, y = 240, visible = false })
		t.expect(world.opened:peek()).toBe(false)
		world.stop()
	end)
	t.it("NRAD-6 adapts into native scrolling list without losing a branch", function()
		local count = 0
		local world = setup({
			items = {
				{
					id = "Branch",
					label = "Branch",
					children = {
						{
							id = "Child",
							label = "Child",
							onSelect = function()
								count += 1
							end,
						},
					},
				},
			},
		})
		world.find("Branch").Activated.fire()
		world.find("Modal").AbsoluteSize = world.engine.types.Vector2.new(180, 180)
		local panel = world.find("RadialPanel")
		t.expect(panel:GetAttribute("Presentation")).toBe("list")
		t.expect(panel.ScrollingEnabled).toBe(true)
		t.expect(panel:FindFirstChildWhichIsA("UIListLayout") ~= nil).toBe(true)
		t.expect(world.find("Child").Size.Y.Offset).toBe(44)
		world.find("Child").Activated.fire()
		t.expect(count).toBe(1)
		world.stop()
	end)
	t.it("NRAD-7 state items stay open and completion precedes callbacks", function()
		local checked, selected, count, during = Compose.cell(false), Compose.cell("a"), 0, nil
		local opened = Compose.cell(true)
		local world = setup({
			isPresented = opened,
			items = {
				{ id = "Check", label = "Check", checked = checked },
				{
					id = "Radio",
					label = "Radio",
					selected = selected,
					value = "b",
					onChange = function()
						count += 1
					end,
				},
				{
					id = "Done",
					label = "Done",
					onSelect = function()
						during = opened:peek()
					end,
				},
			},
		})
		world.find("Check").Activated.fire()
		t.expect(checked:peek()).toBe(true)
		t.expect(opened:peek()).toBe(true)
		world.find("Radio").Activated.fire()
		world.find("Radio").Activated.fire()
		t.expect(count).toBe(1)
		world.find("Done").Activated.fire()
		t.expect(during).toBe(false)
		world.stop()
	end)
	t.it("NRAD-8 nested expansion preserves parents and completion back returns", function()
		local world = setup({
			navigation = "replace",
			gestureSelection = "direction",
			items = {
				{
					id = "Branch",
					label = "Branch",
					navigation = "expand",
					expansion = "fan",
					children = { { id = "Child", label = "Child", completion = "back" } },
				},
			},
		})
		world.find("Branch").Activated.fire()
		t.expect(world.find("Branch") ~= nil).toBe(true)
		t.expect(world.find("Child") ~= nil).toBe(true)
		world.find("Child").Activated.fire()
		t.expect(world.find("Branch") ~= nil).toBe(true)
		t.expect(world.find("Child")).toBe(nil)
		world.stop()
	end)
	t.it("NRAD-9 Compose exit presence releases native ownership after animation", function()
		local world = setup({ items = compass(function() end) }, true)
		world.step(0.3)
		local panel = world.find("RadialPanel")
		world.opened:set(false)
		t.expect(world.find("RadialPanel")).toBe(panel)
		t.expect(panel.Interactable).toBe(false)
		world.step(0.3)
		t.expect(world.find("RadialPanel")).toBe(nil)
		t.expect(panel.isDestroyed()).toBe(true)
		world.stop()
	end)
	t.it("NRAD-10 reduced motion closes immediately and releases listeners", function()
		local world = setup({ items = compass(function() end) })
		t.expect(world.input.InputEnded.count() > 0).toBe(true)
		world.opened:set(false)
		t.expect(world.find("RadialPanel")).toBe(nil)
		t.expect(world.input.InputEnded.count()).toBe(0)
		world.stop()
	end)
	t.it("NRAD-11 native image skins retain upright labels", function()
		local world = setup({
			appearance = "buttons",
			buttonSurface = "none",
			skin = { item = { default = "rbxassetid://1", pressed = "rbxassetid://2" } },
			distribution = "compass",
			items = compass(function() end),
		})
		local button = world.find("N")
		t.expect(button.BackgroundTransparency).toBe(1)
		t.expect(button:FindFirstChild("RadialSkin").Image).toBe("rbxassetid://1")
		button.GuiState = world.engine.types.Enum.GuiState.Press
		t.expect(button:FindFirstChild("RadialSkin").Image).toBe("rbxassetid://2")
		t.expect(button.Rotation).toBe(0)
		world.stop()
	end)
	t.it("draws icon items in the buttons appearance as icon-only circles and names Close with an icon", function()
		local world = setup({
			appearance = "buttons",
			center = "close",
			items = {
				{ id = "Look", label = "Look", icon = "menu", onSelect = function() end },
				{ id = "Words", label = "Words only", onSelect = function() end },
			},
		})
		local look = world.find("Look")
		t.expect(look.Text).toBe("")
		local launcher = world.find("Launcher")
		if launcher then
			t.expect(launcher:FindFirstChild("Title", true)).toBeNil()
			t.expect(launcher:FindFirstChild("LeadingIcon", true) ~= nil).toBe(true)
		end
		t.expect(look:GetAttribute("AccessibleLabel") or look:GetAttribute("FacetLabel") or look.Name).toBe("Look")
		local words = world.find("Words")
		t.expect((words:FindFirstChild("Title", true) or words).Text).toBe("Words only")
		local close = world.find("$navigation")
		if close then
			t.expect(close:FindFirstChild("LeadingIcon", true) ~= nil).toBe(true)
		end
		world.stop()
	end)

	t.it("draws Close as an icon in a ring whose items are all icons", function()
		local world = setup({
			center = "close",
			items = {
				{ id = "A", label = "Alpha", icon = "menu", labelStyle = "icon", onSelect = function() end },
				{ id = "B", label = "Beta", icon = "menu", labelStyle = "icon", onSelect = function() end },
			},
		})
		local close = world.find("$navigation")
		if close then
			t.expect(close.Text).toBe("")
			t.expect(close:FindFirstChild("LeadingIcon", true) ~= nil).toBe(true)
		end
		world.stop()
	end)

	t.it("NRAD-12 empty center keeps ring Back and full-label preview", function()
		local world = setup({
			center = "empty",
			items = {
				{
					id = "Branch",
					label = "Branch",
					children = {
						{
							id = "Action",
							label = "Long readable action",
							compactLabel = { icon = "menu", prefer = true },
						},
					},
				},
			},
		})
		world.find("Branch").Activated.fire()
		world.find("Action").MouseEnter.fire()
		t.expect(world.find("SelectionPreview").Text).toBe("Long readable action")
		t.expect(world.find("SelectionPreview").TextXAlignment).toBe(world.engine.types.Enum.TextXAlignment.Center)
		world.find("$navigation").Activated.fire()
		t.expect(world.find("Branch") ~= nil).toBe(true)
		world.stop()
	end)
	t.it("NRAD-13 gallery nearby item uses native owned scene and real actions", function()
		local engine = engines.new()
		local runtime = Roblox.createRuntime(engine)
		local ctx = {
			Compose = Compose,
			runtime = runtime,
			Host = runtime.constructors,
			types = engine.types,
			viewport = Compose.cell({ width = 1280, height = 720 }),
			UI = controls(
				Compose,
				runtime,
				{ types = engine.types, services = { GuiService = engine.new("GuiService") }, reducedMotion = true }
			),
		}
		local built
		local stop, screen = runtime.mount(function()
			built = require("../examples/gallery/scenarios/radial_menu").build(ctx)
			return runtime.constructors.ScreenGui({ built.screen() })
		end, engine.new("Folder"))
		built.steps.world()
		local stage = screen:FindFirstChild("TrailPack", true)
		t.expect(stage:IsA("ViewportFrame")).toBe(true)
		screen:FindFirstChild("Launcher", true).Activated.fire()
		screen:FindFirstChild("inspect", true).Activated.fire()
		t.expect(built.report().world.angle).toBe(45)
		screen:FindFirstChild("resize", true).Activated.fire()
		t.expect(built.report().world.unpacked).toBe(true)
		screen:FindFirstChild("take", true).Activated.fire()
		t.expect(built.report().world.taken).toBe(true)
		t.expect(stage.Visible).toBe(false)
		stop()
		t.expect(stage.isDestroyed()).toBe(true)
		runtime:dispose()
	end)
	t.it("NRAD-14 launcher press slide releases directly into an action", function()
		local count = 0
		local world = setup({
			isPresented = Compose.cell(false),
			distribution = "compass",
			items = compass(function()
				count += 1
			end),
		})
		local launcher, touch = world.find("Launcher"), pointer(world, 0, 0)
		launcher.InputBegan.fire(touch)
		t.expect(world.opened:peek()).toBe(true)
		touch.Position = world.engine.types.Vector3.new(320, 110, 0)
		world.input.InputChanged.fire(touch)
		world.input.InputEnded.fire(touch)
		launcher.Activated.fire(touch)
		t.expect(count).toBe(1)
		t.expect(world.opened:peek()).toBe(true)
		world.stop()
	end)
	t.it("NRAD-15 branch replacement retains fading geometry and reclaims interrupted presence", function()
		for _, animated in { true, false } do
			local world = setup({
				items = {
					{
						id = "Branch",
						label = "Branch",
						children = { { id = "Leaf", label = "Leaf", onSelect = function() end } },
					},
				},
			}, animated)
			world.step(0.3)
			local parent = world.find("Sector-Branch")
			local position = parent:FindFirstChild("Paint").Position
			world.find("Branch").Activated.fire()
			local child = world.find("Sector-Leaf")
			t.expect(child ~= nil).toBe(true)
			if animated then
				t.expect(parent.isDestroyed()).toBe(false)
				t.expect(parent.Parent.Interactable).toBe(false)
				world.step(0.04)
				t.expect(parent.GroupTransparency > 0 and parent.GroupTransparency < 1).toBe(true)
				t.expect(parent:FindFirstChild("Paint").Position).toBe(position)
				world.find("Center").Activated.fire()
				t.expect(world.find("Sector-Branch")).toBe(parent)
				world.find("Branch").Activated.fire()
				world.step(0.3)
			end
			t.expect(parent.isDestroyed()).toBe(true)
			world.stop()
			t.expect(child.isDestroyed()).toBe(true)
		end
	end)
	t.it("NRAD-16 keeps round button swatches circular and expands the same targets into compact rows", function()
		local selected = Compose.cell("sage")
		local world = setup({
			appearance = "buttons",
			items = {
				{ id = "sage", label = "Sage", selected = selected, value = "sage" },
				{ id = "clay", label = "Clay", selected = selected, value = "clay" },
				{ id = "iris", label = "Iris", selected = selected, value = "iris" },
			},
		})
		local modal, panel = world.find("Modal"), world.find("RadialPanel")
		modal.AbsoluteSize = world.engine.types.Vector2.new(920, 640)
		local button = world.find("iris")
		local corner = button:FindFirstChildWhichIsA("UICorner")
		t.expect(panel:GetAttribute("Presentation")).toBe("radial")
		t.expect(button.Size.X.Scale).toBe(0)
		t.expect(button.Size.Y.Scale).toBe(0)
		t.expect(button.Size.X.Offset).toBe(button.Size.Y.Offset)
		t.expect(button.Size.X.Offset >= 44).toBe(true)
		t.expect(corner.CornerRadius.Scale).toBe(1)
		t.expect(corner.CornerRadius.Offset).toBe(0)
		t.expect(world.find("Sector-iris"):FindFirstChild("Paint").Visible).toBe(false)
		modal.AbsoluteSize = world.engine.types.Vector2.new(180, 180)
		t.expect(world.find("iris")).toBe(button)
		t.expect(panel:GetAttribute("Presentation")).toBe("list")
		t.expect(button.Size.X.Scale).toBe(1)
		t.expect(button.Size.X.Offset).toBe(-8)
		t.expect(button.Size.Y.Offset).toBe(44)
		t.expect(button:FindFirstChildWhichIsA("UIAspectRatioConstraint")).toBe(nil)
		button.Activated.fire()
		t.expect(selected:peek()).toBe("iris")
		modal.AbsoluteSize = world.engine.types.Vector2.new(920, 640)
		t.expect(world.find("iris")).toBe(button)
		t.expect(button.Size.X.Offset).toBe(button.Size.Y.Offset)
		t.expect(button:FindFirstChildWhichIsA("UICorner")).toBe(corner)
		world.stop()
	end)
end)
return t
