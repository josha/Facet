--!strict
type Context = {
	find: (Instance, string) -> Instance,
	check: (string, boolean) -> (),
	note: (string, unknown) -> (),
	settle: (number) -> (),
}
local GuiService = game:GetService("GuiService")
local function pointer(t: Context, playerGui: Instance)
	local input = game:GetService("UserInputService")
	local virtual = input:CreateVirtualInput()
	local inset = GuiService:GetGuiInset()
	if input.TouchEnabled and not input.MouseEnabled then
		local shield = Instance.new("ScreenGui")
		shield.DisplayOrder, shield.IgnoreGuiInset = 10000, true
		local pad = Instance.new("TextButton")
		pad.Size, pad.BackgroundTransparency, pad.Text = UDim2.fromScale(1, 1), 1, ""
		pad.Parent, shield.Parent = shield, playerGui
		t.settle(2)
		local seen: Vector3? = nil
		local connection = input.InputBegan:Connect(function(event)
			if event.UserInputType == Enum.UserInputType.Touch then
				seen = event.Position
			end
		end)
		local probe = assert(workspace.CurrentCamera).ViewportSize / 2 + inset
		virtual:SendMousePosition(probe)
		virtual:SendMouseButton(probe, Enum.UserInputType.MouseButton1, true)
		t.settle(2)
		virtual:SendMouseButton(probe, Enum.UserInputType.MouseButton1, false)
		t.settle(2)
		connection:Disconnect()
		shield:Destroy()
		local observed = assert(seen, "Touch calibration needs a native Touch event")
		inset = probe - Vector2.new(observed.X, observed.Y)
	end
	return virtual, inset
end
return {
	{
		id = "catalog-current",
		contracts = {},
		keepGallery = false,
		run = function(t: Context)
			local api = assert(workspace:WaitForChild("FacetLabAPI", 20))
			local sweep = api:FindFirstChild("mountSweep") :: BindableFunction
			local rows = game:GetService("HttpService"):JSONDecode(sweep:Invoke())
			local count = 0
			for id, row in rows do
				count += 1
				t.check(id .. " mounts without refusals", row.open == true and row.refusals == 0)
			end
			t.note("catalog pages", count)
			local open = api:FindFirstChild("open") :: BindableFunction
			local configure = api:FindFirstChild("configure") :: BindableFunction
			local report = api:FindFirstChild("report") :: BindableFunction
			for _, variant in
				{
					{ "CollapsibleView", "+outside dismissal disabled" },
					{ "ZoomView", "captureCamera=true" },
					{ "ZoomView", "collectionCapture=true" },
					{ "Travel", "recycle=true" },
					{ "Travel", "shuffle=true" },
					{ "sequence", "pulse=true" },
				}
			do
				open:Invoke(variant[1])
				local result = game:GetService("HttpService"):JSONDecode(configure:Invoke(variant[2]))
				t.settle(10)
				local state = game:GetService("HttpService"):JSONDecode(report:Invoke())
				t.note(table.concat(variant, " "), { result = result, errors = state.errors })
				t.check(
					table.concat(variant, " ") .. " uses the current API",
					result.ok == true and next(state.errors) == nil
				)
			end
		end,
	},
	{
		id = "recent-layout-bindings",
		contracts = { "UI.Button", "UI.Composition", "UI.Region", "UI.Popover" },
		keepGallery = false,
		run = function(t: Context)
			local api = workspace:WaitForChild("FacetLabAPI", 20)
			assert(api, "Lab starts")
			local open = api:FindFirstChild("open") :: BindableFunction
			local configure = api:FindFirstChild("configure") :: BindableFunction
			local report = api:FindFirstChild("report") :: BindableFunction
			local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
			local virtual, inset = pointer(t, playerGui)
			local function press(button: GuiObject)
				local ancestor = button.Parent
				while ancestor do
					if ancestor:IsA("ScrollingFrame") then
						local offset = button.AbsolutePosition
							+ button.AbsoluteSize / 2
							- ancestor.AbsolutePosition
							- ancestor.AbsoluteWindowSize / 2
						ancestor.CanvasPosition += offset
						t.settle(3)
					end
					ancestor = ancestor.Parent
				end
				local point = button.AbsolutePosition + button.AbsoluteSize / 2 + inset
				virtual:SendMousePosition(point)
				virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, true)
				t.settle(2)
				virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, false)
				t.settle(30)
			end
			for _, state in { "reactive width (tap to change)", "reactive width with subtitle" } do
				open:Invoke("Button")
				configure:Invoke("-reactive width (tap to change)")
				configure:Invoke("-reactive width with subtitle")
				configure:Invoke("+" .. state)
				t.settle(30)
				local playground = t.find(t.find(playerGui, "Page_Button"), "Playground")
				local button = t.find(playground, "Live"):FindFirstChildWhichIsA("GuiButton", true)
				assert(button)
				for _, width in { 140, 220, 0, 140 } do
					t.check(state .. " width " .. width, button.Size.X.Offset == width)
					t.check(
						state .. " native sizing " .. width,
						button.AutomaticSize == (if width == 0 then Enum.AutomaticSize.XY else Enum.AutomaticSize.Y)
					)
					for _, node in button:GetDescendants() do
						if node:IsA("TextLabel") and node.Text ~= "" then
							t.check(state .. " caption fits " .. width .. " " .. node.Name, node.TextFits)
						end
					end
					press(button)
				end
			end
			t.note("Button report", game:GetService("HttpService"):JSONDecode(report:Invoke()))
			open:Invoke("Composition")
			configure:Invoke("topbar=true")
			t.settle(45)
			local strip = playerGui:FindFirstChild("CompositionTopbar")
			assert(strip, "real top bar mounts")
			press(t.find(strip, "StripSettingsButton") :: GuiObject)
			local state = game:GetService("HttpService"):JSONDecode(report:Invoke())
			t.check("strip trigger commands the presentation cell", state.values.stripSettingsOpen == "true")
			local overlays = t.find(playerGui, "PreviewOverlays")
			local popup = t.find(overlays, "Popup")
			t.check("popup is outside the top bar", not popup:IsDescendantOf(strip))
			press(t.find(popup, "CloseCommand") :: GuiObject)
			state = game:GetService("HttpService"):JSONDecode(report:Invoke())
			t.check("Close commands the presentation cell", state.values.stripSettingsOpen == "false")
			t.note("Lab report", state)
			t.check("Lab has no refusals", state.totalErrors == 0)
		end,
	},
	{
		id = "world-image-drop",
		contracts = { "UI.draggable", "UI.dropTarget" },
		keepGallery = false,
		run = function(t: Context)
			local player = game:GetService("Players").LocalPlayer
			local playerGui = player:WaitForChild("PlayerGui")
			local api = workspace:WaitForChild("FacetLabAPI", 20)
			assert(api, "Lab starts")
			local open = api:FindFirstChild("open") :: BindableFunction
			open:Invoke("Button")
			local top = api:FindFirstChild("top") :: BindableFunction
			top:Invoke("drag-drop")
			t.settle(90)
			local virtual, inset = pointer(t, playerGui)
			local function click(node: GuiObject)
				local at = node.AbsolutePosition + node.AbsoluteSize / 2 + inset
				virtual:SendMousePosition(at)
				virtual:SendMouseButton(at, Enum.UserInputType.MouseButton1, true)
				t.settle(2)
				virtual:SendMouseButton(at, Enum.UserInputType.MouseButton1, false)
				t.settle(30)
			end
			for _, offset in { 0, 1.8, -1.8 } do
				local source = t.find(playerGui, "Assetportrait") :: GuiObject
				local area = t.find(playerGui, "WorldDropArea") :: GuiObject
				t.note("world area", {
					at = tostring(area.AbsolutePosition),
					size = tostring(area.AbsoluteSize),
					source = tostring(source.AbsolutePosition),
				})
				local canvas = workspace:FindFirstChild("ImageCanvas", true)
				assert(canvas and canvas:IsA("BasePart"), "Canvas mounts")
				local camera = assert(workspace.CurrentCamera)
				local projected, visible = camera:WorldToScreenPoint(canvas.Position + Vector3.new(0, offset, 0.05))
				local destination = Vector2.new(projected.X, projected.Y)
				t.check("canvas target is on screen " .. offset, visible)
				local point = source.AbsolutePosition + source.AbsoluteSize / 2 + inset
				virtual:SendMousePosition(point)
				virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, true)
				t.settle(2)
				for step = 1, 30 do
					projected = camera:WorldToScreenPoint(canvas.Position + Vector3.new(0, offset, 0.05))
					destination = Vector2.new(projected.X, projected.Y)
					virtual:SendMousePosition(point:Lerp(destination + inset, step / 30))
					t.settle(1)
				end
				t.settle(10)
				projected = camera:WorldToScreenPoint(canvas.Position + Vector3.new(0, offset, 0.05))
				destination = Vector2.new(projected.X, projected.Y)
				virtual:SendMousePosition(destination + inset)
				t.settle(2)
				virtual:SendMouseButton(destination + inset, Enum.UserInputType.MouseButton1, false)
				t.settle(30)
				local decal = canvas:FindFirstChildWhichIsA("Decal")
				t.check(
					"portrait applies at canvas offset " .. offset,
					decal ~= nil and decal.Texture == "rbxassetid://75342910516929"
				)
				local messages = {}
				for _, node in t.find(playerGui, "WorldStatus"):GetDescendants() do
					if node:IsA("TextLabel") then
						table.insert(messages, node.Text)
					end
				end
				t.note("drop status " .. offset, messages)
				click(t.find(playerGui, "UndoAppearance") :: GuiObject)
				t.check("undo clears image " .. offset, decal ~= nil and decal.Texture == "")
			end
		end,
	},
}
