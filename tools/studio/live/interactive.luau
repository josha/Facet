--!strict

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Verify = (require :: any)(game.ReplicatedStorage:WaitForChild("FacetVerify"):WaitForChild("core"))

return function(live: any, suite: string, options: { [string]: any }): any
	local keyboardInput = UserInputService.KeyboardEnabled
		and UserInputService.PreferredInput ~= Enum.PreferredInput.Gamepad
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
		function io.text(value: string)
			virtual:SendTextInput(value)
			settle(12)
		end
		function io.doubleClick(at: Vector2)
			io.move(at)
			for count = 0, 1 do
				virtual:SendMouseButton(at + inset, Enum.UserInputType.MouseButton1, true, count)
				settle(1)
				virtual:SendMouseButton(at + inset, Enum.UserInputType.MouseButton1, false, count)
				settle(1)
			end
		end
		function io.pointerAction(at: Vector2, action: { Wheel: number?, Pan: Vector2?, Pinch: number? })
			io.move(at)
			virtual:SendPointerAction(at + inset, action)
			settle(30)
		end
		function io.controlWheel(at: Vector2, wheel: number)
			virtual:SendKey(true, Enum.KeyCode.LeftControl, false)
			io.pointerAction(at, { Wheel = wheel })
			virtual:SendKey(false, Enum.KeyCode.LeftControl, false)
			settle(30)
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
	local function press(t: any, names: { string }, frames: number?)
		local result = HttpService:JSONDecode(live.press(names, frames))
		for _, name in names do
			if string.sub(name, 1, 5) == "Stick" then
				local delivered = false
				for _, entry in result.input do
					local stick = if string.sub(name, 1, 6) == "Stick2" then "Thumbstick2" else "Thumbstick1"
					delivered = delivered or string.find(entry, "Gamepad1:" .. stick .. ":", 1, true) ~= nil
				end
				t.check("native gamepad stick input delivered " .. name, delivered, result.input)
			elseif string.sub(name, 1, 4) == "DPad" or string.sub(name, 1, 6) == "Button" then
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
		press(t, { "DPadDown" })
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
	drivers["power-off-traversal"] = function(t, value)
		press(t, { "DPadDown", "DPadDown", "DPadDown", "DPadDown", "DPadDown", "DPadDown" })
		live.step("afterDpad")
		if not keyboardInput then
			t.note(
				"unsupported keyboard phase",
				"Controller Emulator consumes Tab; power-off-traversal-tab requires native keyboard input"
			)
			value.connection:Disconnect()
			GuiService.SelectedObject = nil
			return
		end
		press(t, { "Tab", "Tab", "Tab", "Tab", "Tab", "Tab" })
		live.step("afterTab")
	end
	drivers["sheet-traps-and-orders-selection"] = function(t)
		t.note("up input", "StickUp delivers native Gamepad1 Thumbstick1; VirtualInput rejects the emulator DPadUp key")
		press(t, { "DPadDown", "DPadDown", "DPadDown", "DPadDown", "DPadDown", "DPadDown" })
		live.step("afterDown")
		press(t, { "DPadLeft", "DPadRight", "StickUp", "DPadDown", "DPadLeft", "DPadRight", "StickUp", "DPadDown" })
		live.step("afterAll")
		press(t, { "ButtonB" })
		live.step("afterBack")
	end
	drivers["alert-selection-stays-inside"] = function(t)
		t.note("up input", "StickUp delivers native Gamepad1 Thumbstick1; VirtualInput rejects the emulator DPadUp key")
		press(t, { "DPadDown", "DPadDown", "DPadDown", "DPadDown" })
		live.step("afterDown")
		press(t, { "StickUp", "StickUp", "StickUp", "StickUp" })
		live.step("afterUp")
		press(t, { "ButtonA" })
		live.step("afterActivate")
	end
	drivers["confirm-dialog-left-right"] = function(t, value)
		GuiService.SelectedObject = assert(value.stage:FindFirstChild("Delete", true)) :: GuiObject
		settle(2)
		press(t, { "ButtonA" })
		live.step("afterOpen")
		press(t, { "DPadRight" })
		live.step("afterRight")
		press(t, { "DPadLeft" })
		live.step("afterLeft")
		press(t, { "ButtonB" })
		live.step("afterBack")
	end
	drivers["vote-pad-reaches-and-proposes"] = function(t)
		press(t, { "DPadRight" })
		live.step("afterRight")
		press(t, { "ButtonA" })
		live.step("afterReturn")
	end
	drivers["radial-list-scrolls-selection-into-view"] = function(t)
		for _ = 1, 12 do
			press(t, { "DPadDown" })
		end
		live.step("afterDown")
	end
	drivers["category-strip-dpad-keeps-page"] = function(t)
		press(t, { "DPadRight" })
		live.step("afterBasicsRight")
		press(t, { "DPadRight" })
		live.step("afterInputsRight")
	end
	drivers["grabber-activation-cycles-detents"] = function(t)
		press(t, { "ButtonA" })
		live.step("afterFirst")
		press(t, { "DPadLeft" })
		live.step("afterLower")
		press(t, { "DPadLeft" })
		live.step("afterShortest")
		for _, step in { "afterGrow", "afterLargest", "afterClose" } do
			press(t, { "ButtonA" })
			live.step(step)
		end
	end
	drivers["hover-slot-reflow"] = function(_, value, io)
		local source = centre(value.source)
		local node = assert(value.stage:FindFirstChild("B", true)) :: GuiObject
		local slot = node.AbsolutePosition + node.AbsoluteSize * Vector2.new(0.25, 0.5)
		io.heldDrag(source, slot)
		live.step("whileHovering")
		io.move(source)
		live.step("afterLeave")
		io.up(source)
	end
	drivers["pointer-contact-scroll-and-travel"] = function(_, value, io)
		local source, target = centre(value.source), centre(value.target)
		io.click(source)
		live.step("afterTap")
		io.heldDrag(source, target)
		live.step("whileDragging")
		io.up(target)
		live.step("afterDrop")
	end
	drivers["keyboard-gamepad-place-and-cancel"] = function(t, _, io)
		if keyboardInput then
			io.hold(Enum.KeyCode.Return, 3)
			live.step("afterPickUp")
			io.hold(Enum.KeyCode.Down, 3)
			live.step("afterTarget")
			io.hold(Enum.KeyCode.Return, 3)
			live.step("afterPlace")
			io.hold(Enum.KeyCode.Return, 3)
			press(t, { "ButtonB" })
			live.step("afterCancel")
		else
			press(t, { "ButtonA" })
			live.step("afterPickUp")
			press(t, { "DPadDown" })
			live.step("afterTarget")
			press(t, { "ButtonA" })
			live.step("afterPlace")
			press(t, { "ButtonA" })
			press(t, { "ButtonB" })
			live.step("afterCancel")
		end
	end
	drivers["travel-pointer"] = function(_, value, io)
		local stage = assert(value.source.Parent)
		io.click(centre(assert(stage:FindFirstChild("Send", true))))
		settle(120)
		live.step("afterSend")
		io.click(centre(assert(stage:FindFirstChild("Return", true))))
		settle(120)
		live.step("afterReverse")
	end
	drivers["zoom-pointer"] = function(_, value, io)
		local at = value.view.AbsolutePosition + Vector2.new(value.view.AbsoluteSize.X - 80, 80)
		io.pointerAction(at, { Pinch = 0.5 })
		live.step("afterPinch")
		io.doubleClick(at)
		settle(60)
		live.step("afterDoubleTap")
		io.controlWheel(at, 2)
		live.step("afterWheelZoom")
		io.pointerAction(at, { Wheel = 2 })
		live.step("afterWheelPan")
		io.drag(at, at + Vector2.new(0, 40))
		live.step("afterMousePan")
		local contact = centre(value.tile)
		io.heldDrag(contact, contact + Vector2.new(20, 20))
		live.step("afterChildDrag")
		io.up(contact + Vector2.new(20, 20))
	end
	if options.device == "keep" and UserInputService.GamepadEnabled then
		local travelDrivers = require(game.ReplicatedStorage.FacetLive.zoom_travel_drivers)(
			live.step,
			press,
			settle,
			function(node)
				GuiService.SelectedObject = node
			end
		)
		for id, driver in travelDrivers do
			drivers[id] = driver
		end
	end
	drivers["board-typing-pointer-and-text-entry"] = function(t, value, io)
		local received: { string } = {}
		local connection = UserInputService.InputBegan:Connect(function(event)
			table.insert(received, event.KeyCode.Name)
		end)
		t.note(
			"initial command state",
			{ key = value.scope.current:peek(), enabled = value.scope.actions.Letter.Enabled }
		)
		io.hold(Enum.KeyCode.A, 3)
		t.note("placement counts", { value.counts() })
		live.step("afterPlace")
		io.click(centre(value.chat))
		io.hold(Enum.KeyCode.A, 3)
		io.text("A")
		t.note(
			"text entry state",
			{ focused = UserInputService:GetFocusedTextBox() == value.chat, text = value.chat.Text }
		)
		live.step("afterChat")
		io.hold(Enum.KeyCode.Backspace, 3)
		t.note("recall counts", { value.counts() })
		t.note("native keys received", received)
		connection:Disconnect()
		live.step("afterRecall")
	end
	drivers["reward-pointer"] = function(_, value, io)
		local root = assert(value.target.Parent)
		local play = assert(root:FindFirstChild("Play", true)) :: GuiObject
		local finish = assert(root:FindFirstChild("Finish", true)) :: GuiObject
		io.click(centre(play))
		settle(180)
		live.step("afterReward")
		io.click(centre(play))
		io.click(centre(finish))
		settle(60)
		live.step("afterFinish")
	end
	local gamepad = {
		["shuffle-gamepad"] = true,
		["board-command-gamepad"] = true,
		["reward-gamepad"] = true,
		["keyboard-gamepad-place-and-cancel"] = true,
		["zoom-gamepad"] = true,
		["travel-gamepad"] = true,
		["vote-pad-reaches-and-proposes"] = true,
		["radial-list-scrolls-selection-into-view"] = true,
		["category-strip-dpad-keeps-page"] = true,
		["grabber-activation-cycles-detents"] = true,
		["list-keyboard-and-dpad"] = true,
		["scroll-into-view-by-gamepad"] = true,
		["sidebar-dpad-to-collections"] = true,
		["power-off-traversal"] = true,
		["sheet-traps-and-orders-selection"] = true,
		["alert-selection-stays-inside"] = true,
		["confirm-dialog-left-right"] = true,
	}
	local capabilities = { "roblox-client", "input-pointer" }
	if keyboardInput then
		table.insert(capabilities, "input-keyboard")
	end
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
		if case.id == "power-off-traversal" and not table.find(capabilities, "input-keyboard") then
			unavailable:case("power-off-traversal-tab", {
				id = "power-off-traversal-tab",
				requires = { "input-keyboard" },
				run = function()
					error("Controller Emulator consumes Tab; run the keyboard phase outside console emulation", 0)
				end,
			})
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
