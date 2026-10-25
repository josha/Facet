--!strict
local Players = game:GetService("Players")
local Input = game:GetService("UserInputService")
local Gui = game:GetService("GuiService")
type Live = {
	check: (string, boolean, unknown?) -> (),
	note: (string, unknown) -> (),
	settle: (number) -> (),
	visible: (GuiObject) -> boolean,
	clipped: (GuiObject) -> { x: number, y: number, w: number, h: number }?,
	device: ({ device: string?, orientation: Enum.ScreenOrientation? }) -> Vector2,
}
type Snapshot = { points: number, selected: string, owned: { string }, visible: number, zoom: number, notice: string }
type Report = { ok: boolean, error: string?, panel: string?, demo: Snapshot }
type Virtual = {
	SendMousePosition: (Virtual, Vector2) -> (),
	SendMouseButton: (Virtual, Vector2, Enum.UserInputType, boolean) -> (),
}
local function api(command: string, value: unknown?): Report
	return (assert(workspace:WaitForChild("FacetShowcaseAPI", 10)) :: BindableFunction):Invoke(command, value) :: Report
end
local function stage(): Instance
	return Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("FacetGallery")
end
local function find(name: string): GuiObject
	return assert(stage():FindFirstChild(name, true), name) :: GuiObject
end
local function start(t: Live)
	t.check("Ascent mounts", api("show", "ascent").ok)
	if api("report").panel then
		api("panel", nil)
	end
	t.settle(45)
	local report = api("report")
	t.check("Ascent has no mount error", report.error == nil, report)
end
local function textLayout(t: Live, theme: string)
	for _, node in find("SkillTreeCanvas"):GetChildren() do
		local gem = node:FindFirstChild("Gem")
		if gem then
			local face = assert(gem:FindFirstChild("Face")) :: GuiObject
			local center = face.AbsolutePosition + face.AbsoluteSize / 2
			local scale = face.AbsoluteSize.X / 164
			local name = assert(gem:FindFirstChild("SkillName")) :: TextLabel
			local status = assert(gem:FindFirstChild("SkillStatus")) :: TextLabel
			for _, label in { name, status } do
				for _, corner in { Vector2.zero, Vector2.new(1, 0), Vector2.new(0, 1), Vector2.one } do
					local point = label.AbsolutePosition + label.AbsoluteSize * corner - center
					t.check(
						theme .. " " .. node.Name .. " " .. label.Name .. " has inset hex bounds",
						math.abs(point.Y) <= face.AbsoluteSize.Y / 2 - 7 * scale
							and math.abs(point.X) + math.abs(point.Y) / math.sqrt(3)
								<= face.AbsoluteSize.X / 2 - 7 * scale,
						point
					)
				end
				t.check(theme .. " text fits vertically", label.TextBounds.Y <= label.AbsoluteSize.Y + 1)
			end
			t.check(
				theme .. " text rows have a gap",
				status.AbsolutePosition.Y - name.AbsolutePosition.Y - name.AbsoluteSize.Y >= 7 * scale,
				{ gap = status.AbsolutePosition.Y - name.AbsolutePosition.Y - name.AbsoluteSize.Y, scale = scale }
			)
		end
	end
end
local function pointer(t: Live)
	local virtual = ((Input :: unknown) :: { CreateVirtualInput: (unknown) -> Virtual }):CreateVirtualInput()
	start(t)
	local touch = Input.TouchEnabled and not Input.MouseEnabled
	local delivered, last = 0, Vector2.zero
	local watch = Input.InputBegan:Connect(function(input)
		if input.UserInputType == (if touch then Enum.UserInputType.Touch else Enum.UserInputType.MouseButton1) then
			delivered += 1
			last = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	local offset = Gui:GetGuiInset()
	local function at(position: Vector2, framesAfter: number?)
		virtual:SendMousePosition(position)
		virtual:SendMouseButton(position, Enum.UserInputType.MouseButton1, true)
		t.settle(2)
		virtual:SendMouseButton(position, Enum.UserInputType.MouseButton1, false)
		t.settle(framesAfter or 30)
	end
	local function tap(name: string)
		local node = find(name)
		t.check(name .. " is visible", t.visible(node) and t.clipped(node) ~= nil, node.AbsoluteSize)
		local bounds = assert(t.clipped(node), name .. " is outside the viewport")
		at(Vector2.new(bounds.x + bounds.w / 2, bounds.y + bounds.h / 2) + offset)
	end
	if touch then
		local intended = find("FitTree").AbsolutePosition + find("FitTree").AbsoluteSize / 2
		at(intended + offset)
		offset += intended - last
		if api("report").panel then
			api("panel", nil)
		end
		t.settle(20)
	end
	tap("ResetTree")
	local view = find("SkillMap") :: ScrollingFrame
	if not touch then
		local extent, position = view.CanvasSize, view.CanvasPosition
		tap("Skill_stride")
		tap("Skill_stride")
		t.check("right branch unlocks", table.find(api("report").demo.owned, "stride") ~= nil)
		t.check("branch growth preserves canvas bounds", view.CanvasSize == extent)
		t.check("branch growth preserves view position", (view.CanvasPosition - position).Magnitude < 1)
		tap("ResetTree")
	end
	local before = api("report").demo
	local tile = find("Skill_spark")
	local point = tile.AbsolutePosition + tile.AbsoluteSize / 2 + offset
	local position, scale = view.CanvasPosition, view:GetAttribute("FacetZoom")
	local movement, zoomChanged = 0, false
	local sample = game:GetService("RunService").PreRender:Connect(function()
		movement = math.max(movement, (view.CanvasPosition - position).Magnitude)
		zoomChanged = zoomChanged or view:GetAttribute("FacetZoom") ~= scale
	end)
	at(point, 2)
	local inspected = api("report")
	t.check("first tap inspects without spending", inspected.demo ~= nil and inspected.demo.points == 18, inspected)
	assert(inspected.demo, game:GetService("HttpService"):JSONEncode(inspected))
	at(point)
	sample:Disconnect()
	t.check("rapid tile activation preserves camera scale", not zoomChanged, api("report"))
	t.check("inspection and unlock preserve camera position", movement < 1, movement)
	local purchased = api("report").demo
	t.check(
		"native activation unlocks Spark once",
		purchased.points == before.points - 3 and table.find(purchased.owned, "spark") ~= nil,
		purchased
	)
	t.check("unlock grows the visible tree", purchased.visible > before.visible, purchased)

	if touch then
		for _ = 1, 3 do
			local target = find("Skill_flare")
			local center = view.AbsolutePosition + view.AbsoluteWindowSize / 2
			local delta = center - target.AbsolutePosition - target.AbsoluteSize / 2
			local limit = view.AbsoluteWindowSize * 0.35
			delta = Vector2.new(math.clamp(delta.X, -limit.X, limit.X), math.clamp(delta.Y, -limit.Y, limit.Y))
			local from = center + offset
			virtual:SendMousePosition(from)
			virtual:SendMouseButton(from, Enum.UserInputType.MouseButton1, true)
			for n = 1, 12 do
				virtual:SendMousePosition(from + delta * (n / 12))
				t.settle(1)
			end
			virtual:SendMouseButton(from + delta, Enum.UserInputType.MouseButton1, false)
			t.settle(20)
		end
	end
	tap("Skill_flare")
	t.check("tile inspection does not spend points", api("report").demo.points == purchased.points)
	t.check("tile inspection selects Flare", api("report").demo.selected == "flare", api("report"))
	tap("Skill_flare")
	t.check("second native purchase is accepted", api("report").demo.points == 11, api("report"))
	local zoom = api("report").demo.zoom
	tap("ZoomIn")
	t.check("zoom button changes map scale", api("report").demo.zoom > zoom, api("report"))
	tap("ZoomOut")
	for _ = 1, 4 do
		tap("ZoomIn")
	end
	local pan = view.CanvasPosition
	local point = view.AbsolutePosition + view.AbsoluteSize * Vector2.new(0.65, 0.72) + offset
	virtual:SendMousePosition(point)
	virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, true)
	for n = 1, 12 do
		virtual:SendMousePosition(point + Vector2.new(-n * 8, -n * 8))
		t.settle(1)
	end
	virtual:SendMouseButton(point + Vector2.new(-96, -96), Enum.UserInputType.MouseButton1, false)
	t.settle(15)
	t.check(
		"native drag pans the tree",
		(view.CanvasPosition - pan).Magnitude > 10,
		{ before = pan, after = view.CanvasPosition }
	)
	watch:Disconnect()
	t.check("test receives native input", delivered >= 7, { touch = touch, delivered = delivered })
	for _ = 1, 8 do
		tap("ZoomOut")
	end
	t.check("minimum zoom is exercised", math.abs(api("report").demo.zoom - 0.65) < 0.001)
	for _, theme in { "Neutral", "scifi_hud", "pixel_quest", "fantasy_ornate", "glossy_mobile", "classic_desktop" } do
		t.check(theme .. " applies", api("theme", theme).ok)
		t.settle(24)
		textLayout(t, theme)
		local button = find("UpgradeBenefit")
		t.check(
			theme .. " keeps upgrade details visible",
			t.visible(button) and t.clipped(button) ~= nil,
			button.AbsoluteSize
		)
		t.check(theme .. " preserves progression", api("report").demo.points == 11, api("report"))
	end
	api("theme", "Neutral")
end
local function gamepad(t: Live)
	start(t)
	local load: (Instance) -> { press: ({ string }, number?) -> string } = require
	local live = load(game:GetService("ReplicatedStorage"):WaitForChild("FacetLive"))
	local delivered, analog = 0, false
	local watch = Input.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Gamepad1 then
			delivered += 1
		end
	end)
	local changed = Input.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.Thumbstick1 then
			analog = true
		end
	end)
	Gui.SelectedObject = find("Skill_spark")
	t.settle(20)
	live.press({ "StickUp" })
	t.settle(20)
	t.check("Controller stick reaches next tile", Gui.SelectedObject == find("Skill_flare"), Gui.SelectedObject)
	t.check("navigation never purchases", api("report").demo.points == 18)
	live.press({ "DPadDown" })
	t.settle(15)
	t.check("D-pad returns to Spark", Gui.SelectedObject == find("Skill_spark"), Gui.SelectedObject)
	live.press({ "ButtonA" })
	t.settle(30)
	t.check(
		"gamepad purchase reveals the next frontier",
		api("report").demo.points == 15 and api("report").demo.visible == 9,
		api("report")
	)
	t.check("purchase keeps tile focus", Gui.SelectedObject == find("Skill_spark"), Gui.SelectedObject)
	live.press({ "StickUp", "ButtonA" })
	t.settle(30)
	t.check("gamepad unlocks Flare", api("report").demo.points == 11, api("report"))
	live.press({ "StickUp" })
	t.settle(25)
	t.check("newly revealed node is reachable", Gui.SelectedObject == find("Skill_nova"), Gui.SelectedObject)
	t.check("camera keeps selected node on screen", t.clipped(find("Skill_nova")) ~= nil)
	live.press({ "StickUp" })
	t.settle(15)
	t.check("tree boundary reaches camera tools", Gui.SelectedObject == find("FitTree"), Gui.SelectedObject)
	live.press({ "DPadDown" })
	t.settle(15)
	t.check("camera tools return to the inspected tile", Gui.SelectedObject == find("Skill_nova"), Gui.SelectedObject)
	for _, theme in { "Neutral", "scifi_hud", "classic_desktop" } do
		api("theme", theme)
		t.settle(20)
		local tile = find("Skill_nova")
		textLayout(t, theme)
		local outline = assert(tile.Parent):FindFirstChild("HexFocusOutline", true)
		t.check("selected hex outline survives " .. theme, outline ~= nil and t.visible(outline :: GuiObject))
		t.check("custom focus replaces rectangular glow in " .. theme, tile:FindFirstChild("FacetFocusGlow") == nil)
	end
	watch:Disconnect()
	changed:Disconnect()
	t.check(
		"controller emulator delivers Gamepad1",
		delivered >= 3 and analog,
		{ buttons = delivered, analog = analog }
	)
end
return {
	{
		id = "ascent-portrait-touch-and-themes",
		contracts = {},
		keepGallery = true,
		run = function(t: Live)
			Players.LocalPlayer.PlayerGui.ScreenOrientation = Enum.ScreenOrientation.Portrait
			local simulator = (
				game:GetService("StudioDeviceSimulatorService") :: unknown
			) :: { SetOrientationAsync: (unknown, Enum.ScreenOrientation) -> () }
			t.device({ device = "iphone_14", orientation = Enum.ScreenOrientation.Portrait })
			local size = assert(workspace.CurrentCamera).ViewportSize
			t.check("portrait touch emulator is active", Input.TouchEnabled and size.Y > size.X, size)
			pointer(t)
			for _, orientation in { Enum.ScreenOrientation.LandscapeLeft, Enum.ScreenOrientation.Portrait } do
				Players.LocalPlayer.PlayerGui.ScreenOrientation = orientation
				simulator:SetOrientationAsync(orientation)
				t.settle(30)
				local selected = find("Skill_" .. api("report").demo.selected)
				local bounds = t.clipped(selected)
				t.check(
					"rotation keeps the inspected tile visible",
					bounds ~= nil
						and bounds.w >= selected.AbsoluteSize.X - 1
						and bounds.h >= selected.AbsoluteSize.Y - 1,
					bounds
				)
			end
		end,
	},
	{ id = "ascent-pointer-touch-and-themes", contracts = {}, keepGallery = true, run = pointer },
	{ id = "ascent-gamepad-progression", input = "gamepad", contracts = {}, keepGallery = true, run = gamepad },
}
