--!strict
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
type Live = any
local cases: { any } = {}

local function pointer(t: Live)
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

local function sample(t: Live, root: Instance, name: string)
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
	if name == "Motion picker" or name == "Colour picker" then
		local notes = {}
		for index, frame in frames do
			local paintedText = {}
			for node, bounds in frame do
				table.insert(paintedText, {
					path = node:GetFullName(),
					text = node.Text,
					position = bounds[1],
					size = bounds[2],
					textBounds = bounds[3],
				})
			end
			table.insert(notes, { frame = index, text = paintedText })
		end
		t.note(if name == "Motion picker" then "segmented opening frames" else "colour opening frames", notes)
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
	run = function(t: Live)
		for _, theme in t.themes do
			local stage = t.mount(function(UI: any, _: any, C: any)
				return UI.TextInput { Name = "Search", value = C.cell("Mint"), presentation = "search" }
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
	run = function(t: Live)
		local stage = t.mount(function(UI: any, _: any, C: any)
			return UI.Picker {
				Name = "Motion",
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
	run = function(t: Live)
		local open
		local stage = t.mount(function(UI: any, _: any, C: any)
			open = C.cell(false)
			return UI.ColorPicker {
				Name = "Colour",
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
	run = function(t: Live)
		for _, theme in t.themes do
			if theme.name ~= "Neutral" and theme.name ~= "pixel_quest" then
				continue
			end
			local model
			local size = t.Facet.Compose.cell(Vector2.new(390, 740))
			local stage = t.mount(function(UI: any, Host: Live, C: any, env: any)
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
	run = function(t: Live)
		local stage = t.mount(function(UI: any)
			return UI.RadialMenu {
				Name = "Quick",
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
	run = function(t: Live)
		local stage = t.mount(function(UI: any, Host: Live)
			return UI.Composition {
				Name = "Hud",
				Position = UDim2.fromOffset(0, 200),
				Size = UDim2.fromOffset(200, 100),
				gap = 8,
				padding = 0,
				topbar = false,
				UI.Region {
					Name = "Tasks",
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
	run = function(t: Live)
		t.device({ device = "iphone_14", input = Enum.PreferredInput.Touch })
		local stage = t.mount(function(UI: any)
			return UI.RowActions {
				Name = "Row",
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
	run = function(t: Live)
		t.mount(function(UI: any, Host: Live)
			return UI.Composition {
				Name = "Hud",
				gap = 8,
				padding = 0,
				UI.Region {
					Name = "Objective",
					zone = "topbar",
					rank = 2,
					Host.Frame "ObjectiveFull" { Size = UDim2.fromOffset(120, 32) },
				},
				UI.Region {
					Name = "Timer",
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

table.insert(cases, {
	id = "word-game-pixel-captions",
	run = function(t: Live)
		for _, width in { 350, 390, 844 } do
			local theme = assert(require(game.ReplicatedStorage.FacetThemes.pixel_quest).build(t.Facet.themes))
			local stage = t.mount(function(UI: Live, Host: Live, C: Live, env: Live)
				local ctx = t.context(UI, Host, C, env)
				ctx.theme = env.theme
				return require(game.ReplicatedStorage.FacetExamples["05_word_game"]).build(ctx).screen()
			end, { theme = theme, size = Vector2.new(width, 620), frames = 60 })
			local keys = t.find(stage, "kb")
			for _, key in keys:GetDescendants() do
				if key:IsA("TextButton") and string.match(key.Name, "^key_%u$") then
					local label = t.find(key, "Label")
					t.check(
						width .. " " .. key.Name .. " shows its letter",
						label and label.TextFits and label.TextBounds.X > 0,
						label and { label.AbsoluteSize, label.TextBounds }
					)
				end
			end
			local page = t.find(stage, "page")
			page.CanvasPosition = Vector2.new(0, 10000)
			t.settle(30)
			local restart = t.find(stage, "Restart")
			t.inside(width .. " restart can scroll fully into view", restart, page)
			t.cleanup()
		end
	end,
})

table.insert(cases, {
	id = "colour-format-layout",
	run = function(t: Live)
		for _, width in { 350, 390, 844 } do
			local open
			local stage = t.mount(function(UI: Live, _: Live, C: Live)
				open = C.cell(false)
				return UI.ColorPicker {
					Name = "Colour",
					value = C.cell(Color3.fromRGB(171, 205, 109)),
					isPresented = open,
					modes = { "spectrum", "sliders" },
				}
			end, { size = Vector2.new(width, 740), frames = 90, environment = { preferredInput = "Touch" } })
			local virtual, inset = pointer(t)
			open:set(true)
			t.settle(90)
			local panel, body = t.find(stage, "Panel"), t.find(stage, "Body")
			local at, size, bodyAt = panel.AbsolutePosition, panel.AbsoluteSize, body.AbsolutePosition
			for _, format in { "hsv", "hex", "rgb", "hex", "hsv", "rgb" } do
				local button = t.find(t.find(stage, "Format"), format)
				local point = button.AbsolutePosition + button.AbsoluteSize / 2 + inset
				virtual:SendMousePosition(point)
				virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, true)
				t.settle(1)
				virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, false)
				local shift = 0
				for _ = 1, 25 do
					RunService.RenderStepped:Wait()
					shift = math.max(
						shift,
						(panel.AbsolutePosition - at).Magnitude,
						(panel.AbsoluteSize - size).Magnitude,
						(body.AbsolutePosition - bodyAt).Magnitude
					)
				end
				t.check(
					width .. " " .. format .. " selected by pointer",
					t.find(stage, "Colour"):GetAttribute("format") == format
				)
				t.check(width .. " " .. format .. " keeps panel and spectrum still", shift <= 1, shift)
			end
			t.cleanup()
		end
	end,
})

table.insert(cases, {
	id = "drag-demo-status-layout",
	run = function(t: Live)
		for _, size in { Vector2.new(390, 740), Vector2.new(844, 390) } do
			local touch = size.X < 600
			t.device({
				device = "iphone_14",
				orientation = if touch then Enum.ScreenOrientation.Portrait else Enum.ScreenOrientation.LandscapeLeft,
			})
			local stage = t.mount(function(UI: Live, Host: Live, C: Live, env: Live)
				return require(game.ReplicatedStorage.Lab.drag_drop_demo)(t.context(UI, Host, C, env))
			end, { size = size, frames = 90 })
			local virtual, inset = pointer(t)
			local area = t.find(stage, "WorldDropArea")
			local at, extent = area.AbsolutePosition, area.AbsoluteSize
			local source = t.find(stage, "AssetRed")
			local point = source.AbsolutePosition + source.AbsoluteSize / 2 + inset
			local shift = 0
			local connection = RunService.RenderStepped:Connect(function()
				shift = math.max(shift, (area.AbsolutePosition - at).Magnitude, (area.AbsoluteSize - extent).Magnitude)
			end)
			virtual:SendMousePosition(point)
			virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, true)
			t.settle(2)
			for index = 1, 12 do
				virtual:SendMousePosition(point + Vector2.new(0, index * 5))
				t.settle(1)
			end
			t.settle(10)
			t.check(
				tostring(size) .. " drag started",
				string.find(t.find(stage, "DropStatus").Text, "Holding") ~= nil,
				t.find(stage, "DropStatus").Text
			)
			virtual:SendMouseButton(point + Vector2.new(0, 60), Enum.UserInputType.MouseButton1, false)
			t.settle(45)
			connection:Disconnect()
			t.check(tostring(size) .. " status changes keep world framing still", shift <= 1, shift)
			t.cleanup()
		end
	end,
})

return cases
