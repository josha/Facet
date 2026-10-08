--!strict
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local cases: { any } = {}

local function pointer(t: any)
	local virtual = (UserInputService :: any):CreateVirtualInput()
	local inset = GuiService:GetGuiInset()
	local seen
	local connection = UserInputService.InputBegan:Connect(function(input)
		seen = Vector2.new(input.Position.X, input.Position.Y)
	end)
	local probe = Vector2.new(8, 160)
	virtual:SendMousePosition(probe)
	virtual:SendMouseButton(probe, Enum.UserInputType.MouseButton1, true)
	t.settle(2)
	virtual:SendMouseButton(probe, Enum.UserInputType.MouseButton1, false)
	t.settle(2)
	connection:Disconnect()
	if seen then
		inset = probe - seen
	end
	return virtual, inset
end

local function painted(node: GuiObject): boolean
	local current: Instance? = node
	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		if current:IsA("CanvasGroup") and current.GroupTransparency >= 0.999 then
			return false
		end
		local fade = current:FindFirstChild("FadePaint")
		if fade and fade:IsA("UIGradient") and fade.Transparency.Keypoints[1].Value >= 0.999 then
			return false
		end
		current = current.Parent
	end
	return true
end

local function sample(t: any, root: Instance, name: string)
	local frames = {}
	for _ = 1, 40 do
		RunService.RenderStepped:Wait()
		local frame = {}
		for _, node in root:GetDescendants() do
			if (node:IsA("TextButton") or node:IsA("TextLabel")) and node.Text ~= "" and painted(node) then
				frame[node] = { node.AbsolutePosition, node.AbsoluteSize, node.TextBounds }
			end
		end
		table.insert(frames, frame)
	end
	local last = frames[#frames]
	local largest, measured = 0, 0
	for _, frame in frames do
		for node, before in frame do
			local after = last[node]
			if after then
				measured += 1
				for index = 1, 3 do
					largest = math.max(largest, (before[index] - after[index]).Magnitude)
				end
			end
		end
	end
	t.check(name .. " sampled visible text", measured > 0, measured)
	t.check(name .. " visible text stays in its final layout", largest <= 1, largest)
end

table.insert(cases, {
	id = "search-accessory-layout",
	run = function(t: any)
		for _, theme in t.themes do
			local stage = t.mount(function(UI: any, _: any, C: any)
				return UI.TextInput "Search" {
					value = C.cell("Mint"),
					presentation = "search",
				}
			end, { theme = theme.package, size = Vector2.new(390, 740), environment = { preferredInput = "Touch" } })
			local field, icon, clear = t.find(stage, "Field"), t.find(stage, "SearchIcon"), t.find(stage, "Clear")
			local f, i, c = t.rect(field), t.rect(icon), t.rect(clear)
			t.check(theme.name .. " editor clears search icon", f.x >= i.r, { editor = f, icon = i })
			t.check(theme.name .. " editor clears clear button", f.r <= c.x, { editor = f, clear = c })
			t.check(theme.name .. " editor has usable width", f.w >= 180, f.w)
			t.cleanup()
		end
	end,
})

table.insert(cases, {
	id = "segmented-opening-layout",
	run = function(t: any)
		local stage = t.mount(function(UI: any, _: any, C: any)
			return UI.Picker "Motion" {
				label = "Motion",
				style = "segmented",
				selected = C.cell("device"),
				options = {
					{ value = "device", label = "Device" },
					{ value = "normal", label = "Normal" },
					{ value = "limited", label = "Limited" },
					{ value = "none", label = "None" },
				},
			}
		end, { size = Vector2.new(350, 740), frames = 0 })
		sample(t, stage, "Motion picker")
	end,
})

table.insert(cases, {
	id = "colour-opening-layout",
	run = function(t: any)
		local open
		local stage = t.mount(function(UI: any, _: any, C: any)
			open = C.cell(false)
			return UI.ColorPicker "Colour" {
				value = C.cell(Color3.new(1, 0, 0)),
				onChange = function() end,
				isPresented = open,
				onPresentedChange = function(value: boolean)
					open:set(value)
				end,
			}
		end, { size = Vector2.new(390, 740), environment = { preferredInput = "Touch" } })
		open:set(true)
		sample(t, t.find(stage, "ColorPickerModal"), "Colour picker")
		t.check("scrim has no native border", t.find(stage, "DismissOutside").BorderSizePixel == 0)
	end,
})

table.insert(cases, {
	id = "files-auxiliary-panes",
	run = function(t: any)
		for _, theme in t.themes do
			if theme.name ~= "Neutral" and theme.name ~= "pixel_quest" then
				continue
			end
			local model
			local size = t.Facet.Compose.cell(Vector2.new(390, 740))
			local stage = t.mount(function(UI: any, Host: any, C: any, env: any)
				local built = require(game.ReplicatedStorage.FacetScenarios.collection_workbench).build(
					t.context(UI, Host, C, env)
				)
				model = built.model
				return built.screen()
			end, { theme = theme.package, size = size, environment = { preferredInput = "Touch" } })
			model.linked:set(true)
			model.transfers:set(true)
			t.settle(20)
			t.check(theme.name .. " enabling views keeps Files visible", t.visible(t.find(stage, "PrimaryView")))
			t.check(theme.name .. " empty Inbox does not replace Files", not t.visible(t.find(stage, "InboxView")))
			model.transfers:set(false)
			size:set(Vector2.new(844, 390))
			t.settle(20)
			local linked = t.find(stage, "LinkedView")
			t.check(theme.name .. " landscape linked view is visible", t.visible(linked))
			local header = t.find(linked, "Header")
			local name = header:FindFirstChild("name")
			t.check(theme.name .. " file column keeps its minimum", name.AbsoluteSize.X >= 259, name.AbsoluteSize)
			local details = t.find(linked, "Details")
			t.check(
				theme.name .. " field details have a distinct name",
				details:GetAttribute("label") == "Show details"
			)
			local actions = t.find(linked, "CellActions")
			model.editingEnabled:set(false)
			t.settle(10)
			t.check(theme.name .. " read-only rows hide editing actions", not actions.Visible)
			t.near(
				theme.name .. " read-only rows reclaim action space",
				actions.Parent.Content.AbsoluteSize.X,
				actions.Parent.AbsoluteSize.X
			)
			t.check(theme.name .. " read-only rows retain information", t.visible(details))
			model.editingEnabled:set(true)
			t.settle(10)
			t.check(theme.name .. " editable rows restore actions", actions.Visible and actions.AbsoluteSize.X >= 44)
			t.cleanup()
		end
	end,
})

table.insert(cases, {
	id = "radial-touch-origin",
	run = function(t: any)
		local stage = t.mount(function(UI: any)
			return UI.RadialMenu "Quick" {
				label = "Quick actions",
				Position = UDim2.fromOffset(24, 240),
				items = {
					{ id = "gear", label = "Gear" },
					{ id = "edit", label = "Edit" },
					{ id = "flag", label = "Flag" },
					{ id = "trash", label = "Trash" },
				},
			}
		end, { size = Vector2.new(390, 740), motionLevel = "normal", environment = { preferredInput = "Touch" } })
		local launcher = t.find(stage, "Launcher")
		local virtual, inset = pointer(t)
		local point = launcher.AbsolutePosition + launcher.AbsoluteSize / 2 + inset
		virtual:SendMousePosition(point)
		t.settle(2)
		virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, true)
		local frames = {}
		local samples = {}
		for index = 1, 40 do
			RunService.RenderStepped:Wait()
			local center = t.find(stage, "Center")
			if center then
				local at = center.AbsolutePosition + center.AbsoluteSize / 2
				table.insert(frames, at)
				local gear = t.find(stage, "gear")
				table.insert(samples, {
					frame = index,
					center = { at.X, at.Y },
					form = if gear and gear.Size.X.Scale == 1 then "list" else "ring",
				})
			end
			if index == 5 then
				virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, false)
			end
		end
		t.check("real pointer press opened the radial menu", #frames >= 30, #frames)
		local shift = 0
		for _, at in frames do
			shift = math.max(shift, (at - frames[#frames]).Magnitude)
		end
		t.note("radial center frames", samples)
		t.check("center stays fixed through press and release", shift <= 1, shift)
	end,
})

table.insert(cases, {
	id = "hud-collapse-content",
	run = function(t: any)
		local stage = t.mount(function(UI: any, Host: any)
			return UI.Composition "Hud" {
				Position = UDim2.fromOffset(0, 200),
				Size = UDim2.fromOffset(200, 100),
				gap = 8,
				padding = 0,
				topbar = false,
				UI.Region "Tasks" {
					zone = "left",
					rank = 1,
					Host.Frame "TasksFull" { Size = UDim2.fromOffset(240, 130) },
					Host.Frame "TasksChip" { Size = UDim2.fromOffset(90, 30) },
				},
			}
		end, { size = Vector2.new(390, 740), motionLevel = "normal", environment = { preferredInput = "Touch" } })
		local full = t.find(stage, "TasksFull")
		local home = full.Parent
		local virtual, inset = pointer(t)
		local function click(at: Vector2)
			virtual:SendMousePosition(at + inset)
			t.settle(2)
			virtual:SendMouseButton(at + inset, Enum.UserInputType.MouseButton1, true)
			t.settle(2)
			virtual:SendMouseButton(at + inset, Enum.UserInputType.MouseButton1, false)
		end
		local expand = t.find(stage, "Expand")
		click(expand.AbsolutePosition + expand.AbsoluteSize / 2)
		t.settle(40)
		local modal = t.find(stage, "ExpandModal")
		t.check("expanded HUD owns the full content", modal ~= nil and full:IsDescendantOf(modal))
		click(Vector2.new(350, 650))
		t.settle(1)
		t.check("closing HUD retains content during its fade", modal ~= nil and full:IsDescendantOf(modal))
		t.settle(50)
		t.check("closed HUD returns content home", full.Parent == home)
		t.check("closed HUD removes its modal and scrim", t.find(stage, "ExpandModal") == nil)
	end,
})

table.insert(cases, {
	id = "swipe-action-stretch",
	run = function(t: any)
		t.device({ device = "iphone_14", input = Enum.PreferredInput.Touch })
		local stage = t.mount(function(UI: any)
			return UI.RowActions "Row" {
				Position = UDim2.fromOffset(12, 240),
				Size = UDim2.fromOffset(360, 56),
				content = UI.Text { text = "Message", Size = UDim2.fromScale(1, 1) },
				trailing = { { id = "delete", label = "Delete", role = "destructive", onActivate = function() end } },
			}
		end, { size = Vector2.new(390, 740), environment = { preferredInput = "Touch" } })
		local virtual, inset = pointer(t)
		local row = t.find(stage, "Row")
		local at = row.AbsolutePosition + Vector2.new(300, 28)
		virtual:SendMousePosition(at + inset)
		t.settle(2)
		virtual:SendMouseButton(at + inset, Enum.UserInputType.MouseButton1, true)
		for index = 1, 12 do
			virtual:SendMousePosition(at + inset - Vector2.new(index * 10, 0))
			t.settle(1)
		end
		t.settle(3)
		local tray = t.find(row, "trailing")
		local button = t.find(tray, "delete")
		t.check("swipe reveals more than the action's base width", tray.AbsoluteSize.X >= 110, tray.AbsoluteSize.X)
		t.check(
			"action fills the revealed width",
			math.abs(button.AbsoluteSize.X - tray.AbsoluteSize.X) <= 1,
			{ button.AbsoluteSize.X, tray.AbsoluteSize.X }
		)
		virtual:SendMouseButton(at + inset - Vector2.new(120, 0), Enum.UserInputType.MouseButton1, false)
	end,
})

table.insert(cases, {
	id = "topbar-regions-side-by-side",
	run = function(t: any)
		t.mount(function(UI: any, Host: any)
			return UI.Composition "Hud" {
				gap = 8,
				padding = 0,
				UI.Region "Objective" {
					zone = "topbar",
					rank = 2,
					Host.Frame "ObjectiveFull" { Size = UDim2.fromOffset(120, 32) },
				},
				UI.Region "Timer" {
					zone = "topbar",
					rank = 1,
					Host.Frame "TimerFull" { Size = UDim2.fromOffset(90, 32) },
				},
			}
		end)
		t.settle(6)
		local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
		local strip = playerGui:FindFirstChild("CompositionTopbar")
		t.check(
			"the strip rides the Roblox top bar",
			strip ~= nil and strip.ScreenInsets == Enum.ScreenInsets.TopbarSafeInsets,
			GuiService.TopbarInset
		)
		if not strip then
			return
		end
		local first, second = t.rect(t.find(strip, "ObjectiveFull")), t.rect(t.find(strip, "TimerFull"))
		t.note("topbar regions", { first, second })
		t.check("both topbar regions keep their full form", first.w == 120 and second.w == 90, { first, second })
		t.check(
			"topbar regions sit on one row",
			math.abs((first.y + first.h / 2) - (second.y + second.h / 2)) <= 1,
			{ first, second }
		)
		t.check(
			"the second region starts after the first with the gap",
			math.abs(second.x - (first.r + 8)) <= 1,
			{ first, second }
		)
	end,
})

return cases
