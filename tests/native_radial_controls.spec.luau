--!strict
local t = require("./lib/testkit")
local fadeKit = require("./lib/fade")
local Compose = require("../src/vendor/compose/core")
local Roblox = require("../src/vendor/compose/roblox")
local controls = require("../src/ui")
local engines = require("./lib/native_engine")
local function setup(spec, animated)
	local engine, now = engines.new(), 0
	if type(spec) == "function" then
		spec = spec(engine)
	end
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
		local north = world.find("N").Position
		local touch = pointer(world, north.X.Offset, north.Y.Offset)
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
			local position = parent:FindFirstChild("Paint", true).Position
			world.find("Branch").Activated.fire()
			local child = world.find("Sector-Leaf")
			t.expect(child ~= nil).toBe(true)
			if animated then
				t.expect(parent.isDestroyed()).toBe(false)
				t.expect(parent.Parent.Interactable).toBe(false)
				world.step(0.04)
				t.expect(fadeKit.of(parent) > 0 and fadeKit.of(parent) < 1).toBe(true)
				t.expect(parent:FindFirstChild("Paint", true).Position).toBe(position)
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
	t.it("presents on the modal layer over a dimmed page and a still tap outside the ring closes it", function()
		local world = setup({ distribution = "compass", items = compass(function() end) })
		local modal = world.find("Modal")
		t.expect(modal.Parent).toBe(world.screen)
		t.expect(modal.ZIndex >= 100).toBe(true)
		t.expect(world.find("DismissOutside"):HasTag("facet-scrim")).toBe(true)
		local near = pointer(world, 330, 250)
		world.find("RadialPanel").InputBegan.fire(near)
		world.input.InputEnded.fire(near)
		t.expect(world.opened:peek()).toBe(true)
		local slide = pointer(world, 630, 10)
		world.find("RadialPanel").InputBegan.fire(slide)
		slide.Position = world.engine.types.Vector3.new(600, 40, 0)
		world.input.InputChanged.fire(slide)
		world.input.InputEnded.fire(slide)
		t.expect(world.opened:peek()).toBe(true)
		local outside = pointer(world, 630, 10)
		world.find("RadialPanel").InputBegan.fire(outside)
		world.input.InputEnded.fire(outside)
		t.expect(world.opened:peek()).toBe(false)
		world.stop()
	end)
	t.it("opens centred on its measured launcher and pulls the ring inside the safe area", function()
		local world = setup({
			isPresented = Compose.cell(false),
			clearance = 60,
			ringWidth = 48,
			distribution = "compass",
			items = compass(function() end),
		})
		local V2 = world.engine.types.Vector2
		local launcher = world.find("Launcher")
		local function centre(x, y)
			launcher.AbsolutePosition, launcher.AbsoluteSize = V2.new(x, y), V2.new(40, 40)
			world.opened:set(true)
			local at = world.find("Center").Position
			world.opened:set(false)
			return at.X.Offset, at.Y.Offset + (4 + 12 + 4) / 2
		end
		local x, y = centre(140, 200)
		t.expect(x).toBe(160)
		t.expect(y).toBe(220)
		x, y = centre(600, 440)
		t.expect(x).toBe(640 - 120)
		t.expect(y).toBe(480 - 128)
		world.stop()
	end)
	t.it("sizes the default ring band from its labels and the theme metrics, never from an engine reading", function()
		local items = {}
		for index = 1, 4 do
			table.insert(items, { id = "item" .. index, label = "Item " .. index, onSelect = function() end })
		end
		local world = setup({ items = items })
		local wide = #"Item 1" * 18 * 0.6
		local expected = 40 + (wide + 2 * 8) / 2
		local function reach()
			return 240 - world.find("item1").Position.Y.Offset
		end
		t.expect(math.abs(reach() - expected) <= 1).toBe(true)
		local V2 = world.engine.types.Vector2
		for round = 1, 3 do
			for _, node in world.screen:GetDescendants() do
				if node:IsA("TextLabel") or node:IsA("TextButton") then
					node.TextBounds = V2.new(40 * round, 10 * round)
				end
			end
			t.expect(math.abs(reach() - expected) <= 1).toBe(true)
		end
		world.stop()
	end)
	t.it(
		"scrim sets the ring's dim: dark by default, the theme scrim when light, none clear, and refuses other words",
		function()
			for _, case in
				{ { nil, true, true }, { "dark", true, true }, { "light", true, false }, { "none", false, false } }
			do
				local world = setup({ distribution = "compass", scrim = case[1], items = compass(function() end) })
				local scrim = world.find("DismissOutside")
				t.expect(`{case[1]}:{scrim:HasTag("facet-scrim")}:{scrim:HasTag("facet-radial-scrim")}`)
					.toBe(`{case[1]}:{case[2]}:{case[3]}`)
				t.expect(scrim.Visible).toBe(true)
				if case[1] == "none" then
					t.expect(scrim.BackgroundTransparency).toBe(1)
				end
				world.stop()
			end
			local ok, message = pcall(setup, { scrim = "heavy", items = compass(function() end) })
			t.expect(ok).toBe(false)
			t.expect(string.find(tostring(message), "scrim", 1, true) ~= nil).toBe(true)
		end
	)

	t.it("puts a small plate-less close and the highlighted name inside the hole over a full dark scrim", function()
		for _, label in { false, "Leave the wheel" } do
			local world = setup({
				distribution = "compass",
				centerLabel = if label then label else nil,
				items = compass(function() end),
			})
			local scrim = world.find("DismissOutside")
			t.expect(scrim:HasTag("facet-scrim") and scrim:HasTag("facet-radial-scrim") and scrim.Visible).toBe(true)
			t.expect(scrim.Position.X.Offset < 0 and scrim.Position.Y.Offset < 0).toBe(true)
			t.expect(scrim.Size.X.Scale >= 1 and scrim.Size.X.Offset >= -2 * scrim.Position.X.Offset).toBe(true)
			t.expect(scrim.Size.Y.Scale >= 1 and scrim.Size.Y.Offset >= -2 * scrim.Position.Y.Offset).toBe(true)
			local centre = world.find("Center")
			local w, h = centre.Size.X.Offset, centre.Size.Y.Offset
			t.expect(w).toBe(h)
			t.expect(w).toBe(32)
			t.expect(centre.AutomaticSize).toBe(world.engine.types.Enum.AutomaticSize.None)
			t.expect(centre:HasTag("facet-appearance-utility")).toBe(true)
			local hit = world.find("CenterHit")
			t.expect(hit.Size.X.Offset == 44 and hit.Size.Y.Offset == 44).toBe(true)
			t.expect(hit.Selectable).toBe(false)
			t.expect(hit.AnchorPoint).toBe(world.engine.types.Vector2.new(0.5, 0.5))
			t.expect(hit.Position).toBe(centre.Position)
			t.expect(centre.Position.X.Offset).toBe(320)
			local function inside(x, y)
				return (x - 320) ^ 2 + (y - 240) ^ 2 <= 40 * 40 + 0.5
			end
			for _, dx in { -w / 2, w / 2 } do
				for _, dy in { -h / 2, h / 2 } do
					t.expect(inside(centre.Position.X.Offset + dx * 0.71, centre.Position.Y.Offset + dy * 0.71))
						.toBe(true)
				end
			end
			t.expect(centre.Text).toBe("")
			t.expect(centre:FindFirstChild("LeadingIcon", true) ~= nil).toBe(true)
			t.expect(centre:GetAttribute("label")).toBe(if label then label else "Close")
			local preview = world.find("SelectionPreview")
			t.expect(preview.Text).toBe("")
			world.find("N").MouseEnter.fire()
			t.expect(preview.Text).toBe("N")
			local px, py = preview.Position.X.Offset, preview.Position.Y.Offset
			local pw, ph = preview.Size.X.Offset, preview.Size.Y.Offset
			t.expect(preview.AnchorPoint.X == 0.5 and preview.AnchorPoint.Y == 0.5).toBe(true)
			t.expect(pw > 0 and ph > 0).toBe(true)
			for _, dx in { -pw / 2, pw / 2 } do
				for _, dy in { -ph / 2, ph / 2 } do
					t.expect(inside(px + dx, py + dy)).toBe(true)
				end
			end
			t.expect(py - ph / 2 >= centre.Position.Y.Offset + h / 2).toBe(true)
			world.stop()
		end
	end)
	t.it("opens with nothing highlighted until the player points, steps or aims", function()
		local world = setup({ distribution = "compass", items = compass(function() end) })
		for _, node in world.screen:GetDescendants() do
			t.expect(node:HasTag("facet-radial-candidate")).toBe(false)
			if node:IsA("TextButton") and node.Name ~= "Center" then
				t.expect(node.Parent.Name .. ":" .. tostring(node.Selected == true)).toBe(node.Parent.Name .. ":false")
			end
		end
		world.find("E").MouseEnter.fire()
		t.expect(world.find("Sector-E"):FindFirstChild("Sector", true):HasTag("facet-radial-candidate")).toBe(true)
		world.stop()
	end)
	t.it("a corner ring keeps Close on its corner and names the item outside the ring", function()
		local items = {}
		for _, id in { "look", "pack", "wave" } do
			table.insert(items, { id = id, label = id, onSelect = function() end })
		end
		local world = setup({
			isPresented = Compose.cell(false),
			preset = "bottom-left",
			center = "empty",
			appearance = "buttons",
			items = items,
		})
		local V2 = world.engine.types.Vector2
		local launcher = world.find("Launcher")
		launcher.AbsolutePosition, launcher.AbsoluteSize = V2.new(20, 420), V2.new(40, 40)
		world.opened:set(true)
		t.expect(world.find("Sector-$navigation")).toBeNil()
		local centre = world.find("Center")
		t.expect(centre.Position.X.Offset).toBe(40)
		t.expect(centre.Position.Y.Offset).toBe(440)
		t.expect(centre.Visible).toBe(true)
		world.find("pack").MouseEnter.fire()
		local preview = world.find("SelectionPreview")
		t.expect(preview.Text).toBe("pack")
		local reach = 0
		for _, id in { "look", "pack", "wave" } do
			local at = world.find(id).Position
			reach = math.max(reach, math.sqrt((at.X.Offset - 40) ^ 2 + (at.Y.Offset - 440) ^ 2))
		end
		t.expect(preview.Position.X.Offset > 40 + reach * 0.7).toBe(true)
		t.expect(preview.Position.Y.Offset < 440 - reach * 0.7).toBe(true)
		t.expect(preview.AnchorPoint).toBe(V2.new(0, 1))
		centre.Activated.fire()
		t.expect(world.opened:peek()).toBe(false)
		world.stop()
	end)
	t.it("blooms from its launcher on a measured screen instead of travelling in from a default one", function()
		local world = setup({
			isPresented = Compose.cell(false),
			distribution = "compass",
			items = compass(function() end),
		}, true)
		local V2 = world.engine.types.Vector2
		world.screen.AbsoluteSize = V2.new(1600, 900)
		local launcher = world.find("Launcher")
		launcher.AbsolutePosition, launcher.AbsoluteSize = V2.new(1380, 680), V2.new(40, 40)
		world.opened:set(true)
		local function offset(name)
			local at = world.find(name).Position
			return at.X.Offset - 1400, at.Y.Offset - 700
		end
		local _, early = offset("N")
		t.expect(select(1, offset("Center"))).toBe(0)
		world.step(0.4)
		t.expect(select(1, offset("Center"))).toBe(0)
		local _, settled = offset("N")
		t.expect(math.abs(early) < math.abs(settled) * 0.5).toBe(true)
		world.stop()
	end)
	t.it("takes ringWidth as a theme width or pixels and grows a ring until each label fits", function()
		local function band(width, label)
			local world = setup({
				ringWidth = width,
				items = {
					{ id = "a", label = label, onSelect = function() end },
					{ id = "b", label = "B", onSelect = function() end },
					{ id = "c", label = "C", onSelect = function() end },
				},
			})
			local reach = 240 - world.find("a").Position.Y.Offset
			world.stop()
			return reach
		end
		t.expect(band("wide", "A")).toBe(band(88, "A"))
		t.expect(band("narrow", "A")).toBe(band(48, "A"))
		t.expect(band("wide", "A") > band("narrow", "A")).toBe(true)
		t.expect(band(48, "Wear the lantern") > band(48, "A")).toBe(true)
		local ok, message = pcall(band, "huge", "A")
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(message), "ringWidth", 1, true) ~= nil).toBe(true)
	end)
	t.it("shows either a glyph or a word on a ring item, never both over each other", function()
		local world = setup({
			appearance = "buttons",
			items = {
				{ id = "map", label = "Map", compactLabel = { icon = "flag" }, onSelect = function() end },
				{ id = "wave", label = "Wave", icon = "flag", onSelect = function() end },
			},
		})
		local function shown(button)
			local words = button.Text
			for _, node in button:GetDescendants() do
				if node:IsA("TextLabel") and node.Visible then
					words ..= node.Text
				end
			end
			return words .. "|" .. tostring(button:FindFirstChild("LeadingIcon", true).Visible)
		end
		t.expect(shown(world.find("map"))).toBe("Map|false")
		t.expect(shown(world.find("wave"))).toBe("|true")
		world.stop()
	end)
	t.it("puts the launcher over the object it is anchored to", function()
		local anchor
		local world = setup(function(engine)
			anchor = engine.new("Frame")
			return {
				isPresented = Compose.cell(false),
				anchor = anchor,
				distribution = "compass",
				items = compass(function() end),
			}
		end)
		local V2 = world.engine.types.Vector2
		anchor.AbsolutePosition, anchor.AbsoluteSize = V2.new(300, 200), V2.new(80, 120)
		world.find("RadialMenu").AbsolutePosition = V2.new(20, 400)
		local launcher = world.find("Launcher")
		t.expect(launcher.AnchorPoint).toBe(V2.new(0.5, 0.5))
		t.expect(launcher.Position.X.Offset).toBe(320)
		t.expect(launcher.Position.Y.Offset).toBe(-140)
		world.stop()
	end)
end)
t.describe("RadialMenu navigation placement (restored from 0.11)", function()
	local function actions(count)
		local items = {}
		for index = 1, count do
			table.insert(items, { id = `a{index}`, label = `A{index}`, onSelect = function() end })
		end
		return items
	end
	local function nested()
		return {
			{ id = "gear", label = "Gear", children = { { id = "tool", label = "Tool", onSelect = function() end } } },
			{ id = "wave", label = "Wave", onSelect = function() end },
		}
	end
	local function angleOf(node)
		local dx, dy = node.Position.X.Offset - 320, node.Position.Y.Offset - 240
		return math.deg(math.atan2(dx, -dy)) % 360
	end
	local function visibleCenter(world)
		local centre = world.find("Center")
		return if centre and centre.Visible then centre else nil
	end

	t.it("an empty or content centre puts Back/Close on the ring at the lower left of an even ring", function()
		for _, center in { "empty", "content", "root", "close" } do
			local world = setup({ center = center, items = actions(3) })
			local nav = world.find("$navigation")
			t.expect(`{center}: {nav ~= nil}`).toBe(`{center}: true`)
			t.expect(`{center}: {math.abs(angleOf(nav) - 225) <= 1}`).toBe(`{center}: true`)
			world.stop()
		end
	end)

	t.it("a back centre uses only the centre control, which goes back and closes at the root", function()
		local world = setup({ items = nested() })
		t.expect(world.find("$navigation")).toBeNil()
		local centre = visibleCenter(world)
		t.expect(centre:GetAttribute("label")).toBe("Close")
		world.find("gear").Activated.fire()
		t.expect(visibleCenter(world):GetAttribute("label")).toBe("Back")
		visibleCenter(world).Activated.fire()
		t.expect(world.find("wave") ~= nil).toBe(true)
		t.expect(world.opened:peek()).toBe(true)
		visibleCenter(world).Activated.fire()
		t.expect(world.opened:peek()).toBe(false)
		world.stop()
	end)

	t.it("an empty centre shows no centre control while the ring holds Back", function()
		local world = setup({ center = "empty", items = actions(3) })
		t.expect(visibleCenter(world)).toBeNil()
		world.stop()
	end)

	t.it("a full compass with an empty centre uses the external control at the centre", function()
		local items = {}
		for _, slot in { "N", "NE", "E", "SE", "S", "SW", "W", "NW" } do
			table.insert(items, { id = slot, slot = slot, label = slot, onSelect = function() end })
		end
		local world = setup({ center = "empty", distribution = "compass", items = items })
		t.expect(world.find("$navigation")).toBeNil()
		local centre = visibleCenter(world)
		t.expect(centre ~= nil).toBe(true)
		t.expect(centre.Position.X.Offset).toBe(320)
		t.expect(centre:GetAttribute("label")).toBe("Close")
		centre.Activated.fire()
		t.expect(world.opened:peek()).toBe(false)
		world.stop()
	end)

	t.it("a compass ring takes the first free slot from SW, S, SE", function()
		local items = {}
		for _, slot in { "N", "E", "SW", "W" } do
			table.insert(items, { id = slot, slot = slot, label = slot, onSelect = function() end })
		end
		local world = setup({ center = "empty", distribution = "compass", items = items })
		t.expect(math.abs(angleOf(world.find("$navigation")) - 180) <= 1).toBe(true)
		world.stop()
	end)

	t.it("a corner ring puts Back/Close on the corner whatever the centre, and never on the ring", function()
		for _, center in { "back", "root", "close", "empty", "content" } do
			local world = setup({
				isPresented = Compose.cell(false),
				preset = "bottom-left",
				center = center,
				centerLabel = "Home base",
				items = nested(),
			})
			local V2 = world.engine.types.Vector2
			local launcher = world.find("Launcher")
			launcher.AbsolutePosition, launcher.AbsoluteSize = V2.new(20, 420), V2.new(40, 40)
			world.opened:set(true)
			t.expect(world.find("$navigation")).toBeNil()
			local centre = visibleCenter(world)
			t.expect(`{center}: {centre.Position.X.Offset},{centre.Position.Y.Offset}`).toBe(`{center}: 40,440`)
			t.expect(`{center}: {centre:GetAttribute("label")}`).toBe(`{center}: Close`)
			world.find("gear").Activated.fire()
			t.expect(`{center}: {visibleCenter(world):GetAttribute("label")}`).toBe(`{center}: Back`)
			visibleCenter(world).Activated.fire()
			t.expect(`{center}: {world.find("wave") ~= nil and world.opened:peek()}`).toBe(`{center}: true`)
			visibleCenter(world).Activated.fire()
			t.expect(`{center}: {world.opened:peek()}`).toBe(`{center}: false`)
			world.stop()
		end
	end)

	t.it("the list fallback has one round Back/Close at the top right for every centre policy", function()
		for _, center in { "empty", "back", "root", "close", "content" } do
			local world = setup({ center = center, items = nested() })
			world.find("Modal").AbsoluteSize = world.engine.types.Vector2.new(180, 180)
			t.expect(world.find("RadialPanel"):GetAttribute("Presentation")).toBe("list")
			t.expect(`{center}: {world.find("$navigation") == nil}`).toBe(`{center}: true`)
			local centre = visibleCenter(world)
			t.expect(`{center}: {centre ~= nil}`).toBe(`{center}: true`)
			t.expect(centre.Position.X.Scale).toBe(1)
			t.expect(centre.Position.X.Offset + centre.Size.X.Offset * (1 - centre.AnchorPoint.X)).toBe(-16)
			t.expect(centre.Position.Y.Scale).toBe(0)
			t.expect(centre.Size.X.Offset).toBe(centre.Size.Y.Offset)
			t.expect(`{center}: {centre:GetAttribute("label")}`).toBe(`{center}: Close`)
			centre.Activated.fire()
			t.expect(`{center}: {world.opened:peek()}`).toBe(`{center}: false`)
			world.stop()
		end
	end)
end)

t.describe("RadialMenu centre and corner controls (restored from 0.11)", function()
	local themes = require("../src/ui/themes")(Compose)
	local function nested()
		return {
			{ id = "gear", label = "Gear", children = { { id = "tool", label = "Tool", onSelect = function() end } } },
			{ id = "wave", label = "Wave", onSelect = function() end },
		}
	end
	t.it("the 44 px hit area around the 32 px centre control does what the control does", function()
		local world = setup({ items = nested() })
		world.find("gear").Activated.fire()
		world.find("CenterHit").Activated.fire()
		t.expect(world.find("wave") ~= nil and world.opened:peek()).toBe(true)
		world.find("CenterHit").Activated.fire()
		t.expect(world.opened:peek()).toBe(false)
		world.stop()
	end)
	t.it("Home in the centre is the up chevron", function()
		local world = setup({
			center = "root",
			items = { { id = "a", label = "A", onSelect = function() end } },
		})
		local glyph = world.find("Center"):FindFirstChild("LeadingIcon", true)
		t.expect(glyph.Image).toBe(themes.resolveIcon({} :: any, "chevron.up"))
		t.expect(world.find("Center"):GetAttribute("label")).toBe("Home")
		world.stop()
	end)
	t.it("the list fallback names the highlighted item at the bottom left", function()
		local world = setup({ items = nested() })
		world.find("Modal").AbsoluteSize = world.engine.types.Vector2.new(180, 180)
		local preview = world.find("SelectionPreview")
		t.expect(preview.AnchorPoint).toBe(world.engine.types.Vector2.new(0, 1))
		t.expect(preview.Position.X.Scale == 0 and preview.Position.Y.Scale == 1).toBe(true)
		t.expect(preview.TextXAlignment).toBe(world.engine.types.Enum.TextXAlignment.Left)
		world.stop()
	end)
	t.it("a corner control grows out of the launcher and back into it, crossfading the glyphs", function()
		local world = setup({
			isPresented = Compose.cell(false),
			preset = "bottom-left",
			items = nested(),
		}, true)
		local V2 = world.engine.types.Vector2
		world.screen.AbsoluteSize = V2.new(640, 480)
		local launcher = world.find("Launcher")
		launcher.AbsolutePosition, launcher.AbsoluteSize = V2.new(20, 420), V2.new(40, 40)
		world.opened:set(true)
		local function state()
			local centre = world.find("Center")
			if not centre then
				return nil
			end
			local back = centre:FindFirstChild("LeadingIcon", true)
			local own = centre:FindFirstChild("LauncherIcon", true)
			return centre.Size.X.Offset, centre.Size.Y.Offset, 1 - back.ImageTransparency, 1 - own.ImageTransparency
		end
		local w, h, back, own = state()
		t.expect(w == 40 and h == 40).toBe(true)
		t.expect(launcher.Visible).toBe(false)
		t.expect(back == 0 and own == 1).toBe(true)
		local glyph = world.find("Center"):FindFirstChild("LauncherIcon", true)
		t.expect(glyph.Image).toBe(themes.resolveIcon({} :: any, "more"))
		world.step(0.1)
		w, h, back, own = state()
		t.expect(w > 32 and w < 40 and w == h).toBe(true)
		t.expect(math.abs(back + own - 1) < 0.001 and back > 0 and own > 0).toBe(true)
		world.step(0.3)
		w, h, back, own = state()
		t.expect(w == 32 and back == 1 and own == 0).toBe(true)
		world.opened:set(false)
		local frames, grew = 0, false
		for _ = 1, 30 do
			world.step(1 / 60)
			local size, _, b, o = state()
			if size == nil then
				break
			end
			frames += 1
			grew = grew or size > 32
			t.expect(math.abs(b + o - 1) < 0.001).toBe(true)
		end
		t.expect(frames > 2 and grew).toBe(true)
		t.expect(world.find("Center")).toBeNil()
		t.expect(launcher.Visible).toBe(true)
		world.stop()
	end)
	t.it("a gamepad replacing a level lands on the new level's first item", function()
		local world = setup({ items = nested() })
		world.gui.SelectedObject = world.find("gear")
		world.find("gear").Activated.fire()
		t.expect(world.gui.SelectedObject).toBe(world.find("tool"))
		world.stop()
	end)
end)
return t
