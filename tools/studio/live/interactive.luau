--!strict

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Verify = (require :: any)(game.ReplicatedStorage:WaitForChild("FacetVerify"):WaitForChild("core"))

return function(live: any, suite: string, options: { [string]: any }): any
	local function settle(frames: number?)
		for _ = 1, frames or 8 do
			RunService.RenderStepped:Wait()
		end
	end
	local function centre(node: GuiObject): Vector2
		return node.AbsolutePosition + node.AbsoluteSize / 2
	end
	local function pointer(t: any): any
		local virtual = (UserInputService :: any):CreateVirtualInput()
		local inset = GuiService:GetGuiInset()
		if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
			local shield = Instance.new("ScreenGui")
			shield.DisplayOrder, shield.IgnoreGuiInset = 10000, true
			local pad = Instance.new("TextButton")
			pad.Size, pad.BackgroundTransparency, pad.Text = UDim2.fromScale(1, 1), 1, ""
			pad.Parent = shield
			shield.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
			local seen: Vector3?
			local watch = UserInputService.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.Touch then
					seen = input.Position
				end
			end)
			settle(2)
			local probe = workspace.CurrentCamera.ViewportSize / 2 + inset
			virtual:SendMousePosition(probe)
			virtual:SendMouseButton(probe, Enum.UserInputType.MouseButton1, true)
			settle(2)
			virtual:SendMouseButton(probe, Enum.UserInputType.MouseButton1, false)
			settle(2)
			watch:Disconnect()
			shield:Destroy()
			assert(seen, "touch calibration did not receive native Touch input")
			local observed = seen :: Vector3
			inset = probe - Vector2.new(observed.X, observed.Y)
			t.note("touch calibration inset", inset)
		end
		local io: any = {}
		function io.move(at: Vector2)
			virtual:SendMousePosition(at + inset)
			settle(2)
		end
		function io.down(at: Vector2)
			io.move(at)
			virtual:SendMouseButton(at + inset, Enum.UserInputType.MouseButton1, true)
			settle(3)
		end
		function io.up(at: Vector2)
			virtual:SendMouseButton(at + inset, Enum.UserInputType.MouseButton1, false)
			settle(6)
		end
		function io.heldDrag(from: Vector2, to: Vector2)
			io.down(from)
			for index = 1, 16 do
				virtual:SendMousePosition(from:Lerp(to, index / 16) + inset)
				settle(1)
			end
			settle(3)
		end
		function io.drag(from: Vector2, to: Vector2, pause: number?)
			io.heldDrag(from, to)
			settle(pause or 1)
			io.up(to)
		end
		function io.click(at: Vector2)
			io.down(at)
			io.up(at)
		end
		function io.hold(key: Enum.KeyCode, frames: number)
			virtual:SendKey(true, key, false)
			settle(frames)
			virtual:SendKey(false, key, false)
			settle(12)
		end
		function io.shiftReturn()
			virtual:SendKey(true, Enum.KeyCode.LeftShift, false)
			virtual:SendKey(true, Enum.KeyCode.Return, false)
			settle(3)
			virtual:SendKey(false, Enum.KeyCode.Return, false)
			virtual:SendKey(false, Enum.KeyCode.LeftShift, false)
			settle(12)
		end
		return io
	end
	local function press(t: any, names: { string })
		local result = HttpService:JSONDecode(live.press(names))
		for _, name in names do
			if string.sub(name, 1, 4) == "DPad" or string.sub(name, 1, 6) == "Button" then
				t.check(
					"native gamepad input delivered " .. name,
					table.find(result.input, "Gamepad1:" .. name) ~= nil,
					result.input
				)
			end
		end
	end
	local function point(values: any, name: string): Vector2
		local at = assert(values[name], "missing native point " .. name)
		return Vector2.new(at[1], at[2])
	end
	local drivers: { [string]: (any, any, any) -> () } = {}
	drivers["gallery-keyboard-reaches-demos"] = function(t)
		press(t, { "Down", "Down" })
		live.step("afterDownDown")
		press(t, { "Return" })
		live.step("afterReturn")
		press(t, { "Return" })
		live.step("afterReturnAgain")
	end
	drivers["held-arrow-repeats-and-stops"] = function(_, _, io)
		io.hold(Enum.KeyCode.Down, 150)
		live.step("afterHold")
	end
	drivers["form-controls-traverse-in-document-order"] = function(t)
		local keys = {}
		for _ = 1, 20 do
			table.insert(keys, "Down")
		end
		press(t, keys)
		live.step("afterWalk")
	end
	drivers["return-activates-the-selected-row"] = function(t)
		press(t, { "Return" })
		live.step("afterReturn")
	end
	drivers["open-tray-steps-sideways"] = function(t)
		press(t, { "Right", "Right" })
		live.step("afterRight")
	end
	drivers["tab-key-traversal"] = function(t)
		press(t, { "Tab" })
		live.step("afterTab")
	end
	drivers["range-slider-drag"] = function(_, _, io)
		local points = shared.FacetLiveSession.record.notes.points
		io.drag(point(points, "gapLower"), point(points, "gapPast"))
		live.step("dragGap")
		io.drag(point(points, "pileUpper"), point(points, "pileLeft"))
		live.step("dragPile")
	end
	drivers["color-plane-drag"] = function(_, _, io)
		local points = shared.FacetLiveSession.record.notes.points
		io.heldDrag(point(points, "down"), point(points, "to"))
		live.step("hold")
		io.up(point(points, "to"))
		live.step("release")
		io.click(point(points, "corner"))
		live.step("corner")
	end
	drivers["underline-hover"] = function(_, _, io)
		local points = shared.FacetLiveSession.record.notes.points
		io.move(point(points, "hover"))
		live.step("hover")
		io.move(point(points, "away"))
		live.step("away")
	end
	drivers["skinned-part-press-state"] = function(_, _, io)
		local points = shared.FacetLiveSession.record.notes.points
		io.down(point(points, "toggle"))
		live.step("pressToggle")
		io.up(point(points, "toggle"))
		live.step("releaseToggle")
		io.down(point(points, "stepper"))
		live.step("pressStepper")
		io.up(point(points, "stepper"))
		live.step("releaseStepper")
	end
	drivers["return-and-space-activate-once"] = function(t)
		press(t, { "Return" })
		live.step("afterReturn")
		press(t, { "Space" })
		live.step("afterSpace")
		press(t, { "Return", "Space" })
		live.step("afterDisabled")
	end
	drivers["skinned-part-hover-state"] = function(_, value, io)
		io.move(centre(value.parts.Indicator))
		live.step("hoverIndicator")
		io.move(centre(value.parts.Stepper))
		live.step("hoverStepper")
		io.move(centre(value.parts.Thumb))
		live.step("hoverThumb")
	end
	drivers["shift-return-opens-row-menu"] = function(t, value, io)
		io.shiftReturn()
		live.step("afterShiftReturn")
		io.click(Vector2.new(800, 600))
		press(t, { "Return" })
		live.step("afterReturn")
	end
	drivers["touch-drag-scrolls-reorderable-list"] = function(t, value, io)
		local cell = t.find(value.list, "Cell3")
		local from = centre(cell)
		io.drag(from, from - Vector2.new(0, 160))
		live.step("afterDrag")
	end
	drivers["mail-swipe-and-tap"] = function(t, value, io)
		local row = t.find(value.stage, "Row_m1")
		local from = row.AbsolutePosition + Vector2.new(row.AbsoluteSize.X * 0.8, row.AbsoluteSize.Y / 2)
		io.drag(from, from - Vector2.new(row.AbsoluteSize.X * 0.4, 0), 20)
		live.step("afterSwipe")
		local fifth = t.find(value.stage, "Row_m5")
		local parent = fifth.Parent
		while parent do
			if parent:IsA("ScrollingFrame") then
				local below = fifth.AbsolutePosition.Y
					+ fifth.AbsoluteSize.Y
					- parent.AbsolutePosition.Y
					- parent.AbsoluteWindowSize.Y
				if below > 0 then
					parent.CanvasPosition += Vector2.new(0, below)
				end
			end
			parent = parent.Parent
		end
		settle(12)
		io.click(centre(fifth))
		live.step("afterTap")
	end
	drivers["list-keyboard-and-dpad"] = function(t)
		press(t, { "Down" })
		live.step("afterDown")
		press(t, { "DPadDown" })
		live.step("afterDpad")
		press(t, { "DPadDown", "DPadDown", "DPadDown", "DPadDown", "DPadDown", "DPadDown" })
		live.step("afterPast")
	end
	drivers["scroll-into-view-by-gamepad"] = function(t)
		press(t, { "DPadDown", "DPadDown", "DPadDown", "DPadDown", "DPadDown", "DPadDown" })
		live.step("afterDpad")
	end
	drivers["sidebar-dpad-to-collections"] = function(t)
		press(t, { "DPadDown" })
		live.step("afterDown")
	end
	drivers["power-off-traversal"] = function(t)
		press(t, { "DPadDown", "DPadDown", "DPadDown", "DPadDown", "DPadDown", "DPadDown" })
		live.step("afterDpad")
		press(t, { "Tab", "Tab", "Tab", "Tab", "Tab", "Tab" })
		live.step("afterTab")
	end
	drivers["sheet-traps-and-orders-selection"] = function(t)
		press(t, { "Down", "Down", "Down", "Down", "Down", "Down" })
		live.step("afterDown")
		press(t, { "Left", "Right", "Up", "Down", "Left", "Right", "Up", "Down" })
		live.step("afterAll")
		press(t, { "ButtonB" })
		live.step("afterBack")
	end
	drivers["alert-selection-stays-inside"] = function(t)
		press(t, { "Down", "Down", "Down", "Down" })
		live.step("afterDown")
		press(t, { "Up", "Up", "Up", "Up" })
		live.step("afterUp")
		press(t, { "ButtonA" })
		live.step("afterActivate")
	end
	drivers["confirm-dialog-left-right"] = function(t)
		press(t, { "Return" })
		live.step("afterOpen")
		press(t, { "Right" })
		live.step("afterRight")
		press(t, { "Left" })
		live.step("afterLeft")
		press(t, { "ButtonB" })
		live.step("afterBack")
	end
	local gamepad = {
		["list-keyboard-and-dpad"] = true,
		["scroll-into-view-by-gamepad"] = true,
		["sidebar-dpad-to-collections"] = true,
		["power-off-traversal"] = true,
		["sheet-traps-and-orders-selection"] = true,
		["alert-selection-stays-inside"] = true,
		["confirm-dialog-left-right"] = true,
	}
	local capabilities = { "roblox-client", "input-pointer" }
	if options.device == "keep" and UserInputService.GamepadEnabled then
		table.insert(capabilities, "input-gamepad")
	end
	local reports = {}
	if suite == "haptics_pair" then
		live.release()
		table.insert(reports, Verify.decode(live.report("haptics_setup", { device = options.device or "none" })))
		local fixture =
			assert(Players.LocalPlayer.PlayerGui:FindFirstChild("FacetLive"), "haptics fixture did not mount")
		local io = pointer({ note = function() end })
		for _, name in { "Press", "Release", "Selection", "Custom" } do
			local button = assert(fixture:FindFirstChild(name, true), "missing haptics button " .. name) :: GuiObject
			local parent = button.Parent
			while parent do
				if parent:IsA("ScrollingFrame") then
					local below = button.AbsolutePosition.Y
						+ button.AbsoluteSize.Y
						- parent.AbsolutePosition.Y
						- parent.AbsoluteWindowSize.Y
					if below > 0 then
						parent.CanvasPosition += Vector2.new(0, below)
					end
				end
				parent = parent.Parent
			end
			settle(12)
			io.click(centre(button))
		end
		table.insert(reports, Verify.decode(live.report("haptics_verify", { device = "keep" })))
		live.release()
		return Verify.merge(reports, "roblox-studio", { suite = suite, inputMode = "continuous-native" })
	end
	local unavailable = Verify.createHarness({ source = suite, now = os.clock, prefixIds = false })
	local selected = 0
	for _, case in live.cases(suite) do
		if not case.setup or (options.only and not string.find(case.id, options.only, 1, true)) then
			continue
		end
		selected += 1
		local required = if case.id == "tray-grows-with-text-size"
			then "input-native-settings"
			elseif gamepad[case.id] then "input-gamepad"
			else nil
		if required and not table.find(capabilities, required) then
			unavailable:case(case.id, {
				id = case.id,
				requires = { required },
				run = function()
					error("missing input capability", 0)
				end,
			})
			continue
		end
		local touch = case.id == "touch-drag-scrolls-reorderable-list" or case.id == "mail-swipe-and-tap"
		if options.device ~= "keep" then
			local simulator = game:GetService("StudioDeviceSimulatorService") :: any
			if touch then
				simulator:SetDeviceAsync("iphone_14")
				simulator:SetOrientationAsync(Enum.ScreenOrientation.Portrait)
			else
				simulator:StopSimulationAsync()
			end
			settle(60)
		end
		local began, problem = pcall(live.begin, suite, case.id)
		if not began then
			table.insert(
				reports,
				Verify.decode(HttpService:JSONDecode(live.case(suite, case.id, function()
					error(problem, 0)
				end)))
			)
			continue
		end
		local session = shared.FacetLiveSession
		local ran, errorMessage = xpcall(function()
			local driver = assert(drivers[case.id], "no native input driver for " .. case.id)
			driver(session.t, session.value, pointer(session.t))
		end, debug.traceback)
		if not ran then
			session.t.check("native input driver completed", false, errorMessage)
		end
		table.insert(reports, Verify.decode(HttpService:JSONDecode(live.finish())))
	end
	assert(selected > 0, "no interactive cases matched the selection")
	table.insert(
		reports,
		unavailable:run({ executor = "roblox-studio", capabilities = capabilities, environment = { suite = suite } })
	)
	return Verify.merge(
		reports,
		"roblox-studio",
		{ suite = suite, device = options.device or "none", inputMode = "interactive-native" }
	)
end
