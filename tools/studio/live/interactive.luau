--!strict

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Verify = (require :: any)(game.ReplicatedStorage:WaitForChild("FacetVerify"):WaitForChild("core"))

return function(live: any, suite: string, options: { [string]: any }): any
	local automaticReport = nil
	if options.complete and suite ~= "haptics_pair" then
		local ids = {}
		local hasInteractive = false
		for _, case in live.cases(suite) do
			if case.run then
				table.insert(ids, case.id)
			end
			hasInteractive = hasInteractive or case.setup ~= nil
		end
		if #ids > 0 then
			local selected = table.clone(options)
			selected.ids = ids
			automaticReport = Verify.decode(live.report(suite, selected))
		end
		if not hasInteractive then
			return assert(automaticReport, "the live suite registers no cases")
		end
	end
	if not options.registerOnly and suite ~= "haptics_pair" then
		local interactive = false
		for _, case in live.cases(suite) do
			if case.setup and (not options.only or string.find(case.id, options.only, 1, true)) then
				interactive = true
				break
			end
		end
		if not interactive then
			return live.report(suite, options)
		end
	end
	local function settle(frames: number?)
		for _ = 1, frames or 8 do
			RunService.RenderStepped:Wait()
		end
	end
	if not options.registerOnly and options.device ~= "keep" then
		local simulator = game:GetService("StudioDeviceSimulatorService")
		if options.device == nil or options.device == "none" then
			simulator:StopSimulationAsync()
		else
			simulator:SetDeviceAsync(options.device)
		end
		settle(60)
	end
	local keyboardInput = UserInputService.KeyboardEnabled
		and UserInputService.PreferredInput ~= Enum.PreferredInput.Gamepad
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
		local function screenPoint(at: Vector2): Vector2
			local pixel = at + inset
			return Vector2.new(math.floor(pixel.X + 0.5), math.floor(pixel.Y + 0.5))
		end
		local held = false
		local last: Vector2? = nil
		local function moveTo(at: Vector2)
			virtual:SendMousePosition(screenPoint(at))
			last = at
		end
		local io: any = {}
		function io.move(at: Vector2)
			moveTo(at)
			settle(2)
		end
		function io.down(at: Vector2)
			io.move(at)
			virtual:SendMouseButton(screenPoint(at), Enum.UserInputType.MouseButton1, true)
			held = true
			settle(3)
		end
		function io.up(at: Vector2)
			virtual:SendMouseButton(screenPoint(at), Enum.UserInputType.MouseButton1, false)
			held = false
			settle(6)
		end
		function io.heldDrag(from: Vector2, to: Vector2)
			io.down(from)
			for index = 1, 16 do
				moveTo(from:Lerp(to, index / 16))
				settle(1)
			end
			settle(3)
		end
		function io.cleanup()
			if held and last then
				io.up(last)
			end
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
				virtual:SendMouseButton(screenPoint(at), Enum.UserInputType.MouseButton1, true, count)
				settle(1)
				virtual:SendMouseButton(screenPoint(at), Enum.UserInputType.MouseButton1, false, count)
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
		local hold = if frames == nil and (table.find(names, "ButtonR2") or table.find(names, "ButtonL2"))
			then 30
			else frames
		local result = HttpService:JSONDecode(live.press(names, hold))
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
	drivers["tray-keys-and-hover"] = function(t, value, io)
		press(t, { "Right" })
		live.step("afterRight")
		press(t, { "Return" })
		live.step("afterReturn")
		io.move(centre(assert(value.tray:FindFirstChild("flag"))))
		live.step("afterHover")
	end
	drivers["header-sort-keys"] = function(t)
		for _, action in
			{
				{ "Return", "afterReturn" },
				{ "Return", "afterReturnAgain" },
				{ "Right", "afterRight" },
				{ "Return", "afterReturnLaps" },
				{ "Down", "afterDown" },
				{ "Up", "afterUp" },
			}
		do
			press(t, { action[1] })
			live.step(action[2])
		end
	end
	drivers["left-reaches-this-rows-minus"] = function(t)
		press(t, { "Left" })
		live.step("afterLeft")
		press(t, { "Return" })
		live.step("afterReturn")
	end
	drivers["collapsed-column-leaves-the-ring"] = function(t)
		press(t, { "Tab", "Tab", "Tab", "Tab", "Tab", "Tab", "Tab", "Tab" })
		live.step("afterWalk")
		press(t, { "Return" })
		live.step("afterReturn")
	end
	drivers["return-toggles-multi-selection"] = function(t)
		for _, action in
			{
				{ "Return", "afterReturn" },
				{ "Down", "afterDown" },
				{ "Return", "afterReturnTwo" },
				{ "Return", "afterReturnThree" },
			}
		do
			press(t, { action[1] })
			live.step(action[2])
		end
	end
	drivers["horizontal-list-keys"] = function(t)
		press(t, { "Right" })
		live.step("afterRight")
		press(t, { "Return" })
		live.step("afterReturn")
	end
	drivers["drag-across-rows-after-page-scroll"] = function(_, value, io)
		local start = Vector2.new(value.start[1], value.start[2]) - GuiService:GetGuiInset()
		io.down(start)
		io.move(start + Vector2.new(0, math.floor(value.height)))
		local finish = start + Vector2.new(0, math.floor(value.height * 2.2))
		io.move(finish)
		io.up(finish)
		live.step("afterDrag")
	end
	drivers["segment-fill-follows-track"] = function()
		live.step("capture")
	end
	drivers["navigation-back-pointer"] = function(_, value, io)
		io.move(centre(value.back))
		live.step("hovered")
		io.click(centre(value.back))
		live.step("clicked")
	end
	drivers["path-clipped-in-scroll"] = function()
		live.step("scrolled")
	end
	drivers["files-linked-input"] = function(t, value, io)
		local api = workspace:WaitForChild("FacetShowcaseAPI") :: BindableFunction
		api:Invoke("device", "desktop")
		settle(20)
		local detail = value.root:FindFirstChild("Detail")
		if detail == nil or not detail.Visible then
			local menu = assert(t.find(value.layer, "ViewOptions"))
			io.click(centre(menu:FindFirstChild("Trigger", true) or menu))
			settle(8)
			local panel = assert(t.find(Players.LocalPlayer.PlayerGui, "MenuPanel"))
			io.click(centre(assert(t.find(panel, "linked"))))
			settle(20)
		end
		live.step("wide")
		GuiService.SelectedObject = value.root.Resize
		press(t, { "Period", "Period" })
		live.step("resized")
		local function firstStop(root: Instance): GuiObject
			for _, node in root:GetDescendants() do
				if node:IsA("GuiObject") and node.Selectable and t.visible(node) then
					return node
				end
			end
			error("split pane has no selection stop")
		end
		GuiService.SelectedObject = firstStop(value.root.Sidebar)
		settle(4)
		GuiService.SelectedObject = firstStop(value.root.Detail)
		settle(4)
		t.note(
			"pane crossing",
			"Native SelectedObject changes from sidebar to detail; resize and Back use native input."
		)
		live.step("divider")
		api:Invoke("device", "phone")
		settle(20)
		if not value.root.Detail.Visible then
			io.click(centre(assert(value.root.NavigationBar:FindFirstChild("ShowDetail"))))
			settle(12)
		end
		live.step("compact")
		io.click(centre(assert(t.find(value.root.NavigationBar, "Back"))))
		settle(12)
		live.step("back")
		api:Invoke("device", "automatic")
	end
	drivers["files-nested-touch-handoff"] = function(t, value, io)
		(workspace:WaitForChild("FacetShowcaseAPI") :: BindableFunction):Invoke("device", "phone")
		settle(30)
		local function swipe(direction: number)
			local window = assert(t.clipped(value.inner), "file list has no visible touch area")
			local start = Vector2.new(window.x + window.w / 2, window.y + window.h / 2)
			local finish = start + Vector2.new(0, direction * math.min(120, window.h / 3))
			io.heldDrag(start, finish)
			io.up(finish)
		end
		live.step("top")
		swipe(1)
		live.step("upstream")
		live.step("bottom")
		swipe(-1)
		live.step("downstream")
	end
	drivers["chrome-strips-dpad"] = function(t)
		for _, action in
			{
				{ "Up", "afterUp" },
				{ "Right", "afterRight" },
				{ "Left", "afterLeft" },
				{ "Down", "afterDown" },
				{ "Down", "afterDown2" },
				{ "Down", "afterDown3" },
				{ "Right", "afterRight2" },
			}
		do
			press(t, { action[1] })
			live.step(action[2])
		end
	end
	drivers["form-controls-reach-by-arrows"] = function(t)
		for _ = 1, 30 do
			press(t, { "Down" })
		end
		live.step("afterDowns")
	end
	drivers["slider-between-controls-by-arrows"] = function(t)
		press(t, { "Down" })
		live.step("afterDown")
		press(t, { "Up" })
		live.step("afterUp")
		press(t, { "Down" })
		live.step("afterVolumeDown")
	end
	for _, width in { 390, 1920 } do
		drivers["hud-dpad-reaches-actions-" .. width] = function(t, value)
			press(t, { if value.vertical then "Up" else "Left" })
			live.step("afterWalk")
			press(t, { "Return" })
			live.step("afterOpen")
			press(t, { "Return" })
			live.step("afterPick")
		end
	end
	drivers["recipe-rail-tab-scrolls-tail"] = function(t)
		press(t, { "Right" })
		live.step("afterRight")
		for _ = 1, 40 do
			press(t, { "Down" })
		end
		live.step("afterWalk")
		for _ = 1, 40 do
			press(t, { "Down" })
		end
		live.step("afterAccordion")
	end
	drivers["showcase-rail-tail-inside-clips"] = function(t)
		for _, action in
			{
				{ "Return", "afterReturnActions" },
				{ "Return", "afterReturnRecipes" },
				{ "Right", "afterRight" },
				{ "Return", "afterReturnChip" },
			}
		do
			press(t, { action[1] })
			live.step(action[2])
		end
	end
	drivers["inner-tabs-widen-to-engine-words"] = function(t)
		press(t, { "Return" })
		live.step("afterReturn")
	end
	drivers["dense-menu-and-picker-rows"] = function(_, value, io)
		live.step("pointer")
		io.click(centre(assert(value.panel:FindFirstChild("b", true))))
		live.step("clicked")
		live.step("touch")
		live.step("gamepad")
		live.step("desktop")
		io.click(point(value, "trigger") - GuiService:GetGuiInset())
		live.step("picker")
		live.step("pickertouch")
	end
	drivers["sheet-adaptive"] = function()
		live.step("phone")
		live.step("narrow")
	end
	drivers["selection-mark-hover"] = function(_, value, io)
		io.move(centre(value.chip))
		live.step("hovered")
	end
	drivers["underline-live"] = function(_, value, io)
		live.step("rest")
		io.move(centre(value.more))
		live.step("hovered")
		io.move(Vector2.new(20, 500))
		live.step("left")
		live.step("selected")
	end
	drivers["inverse-paint"] = function(_, value, io)
		local dark, light = centre(value.buttons.Dark), centre(value.buttons.Light)
		io.move(dark)
		live.step("darkhover")
		io.down(dark)
		live.step("darkpress")
		io.up(dark)
		io.move(light)
		live.step("lighthover")
		io.down(light)
		live.step("lightpress")
		io.up(light)
	end
	drivers["xsmall-rung"] = function(_, value, io)
		io.click(point(value, "Tiny") - GuiService:GetGuiInset())
		live.step("button")
		io.click(point(value, "TinyChip") - GuiService:GetGuiInset())
		live.step("chip")
	end
	drivers["pagination-neighbours-arrive-and-land"] = function(t)
		press(t, { "Down" })
		live.step("afterDown")
	end
	drivers["card-hover-reveals-inside-the-envelope"] = function(_, _, io)
		io.move(point(shared.FacetLiveSession.record.notes, "hover point"))
		live.step("afterHover")
	end
	drivers["card-keys-enter-and-stay-inside"] = function(t)
		for _, action in
			{
				{ "ButtonA", "afterReturn" },
				{ "DPadRight", "afterRight" },
				{ "DPadRight", "afterRightAgain" },
				{ "DPadDown", "afterDown" },
				{ "ButtonB", "afterBack" },
			}
		do
			press(t, { action[1] })
			live.step(action[2])
		end
		press(t, { "ButtonA", "DPadRight", "ButtonY" })
		live.step("afterMenuY")
		press(t, { "ButtonB" })
		live.step("afterMenuBack")
	end
	drivers["menu-lands-on-selected-and-walks-bounded"] = function(t)
		for _ = 1, 11 do
			press(t, { "Down" })
		end
		live.step("afterDown")
	end
	drivers["choices-vote-row-inside-the-page"] = function(t)
		press(t, { "Return" })
		live.step("afterReturn")
	end
	drivers["badge-seal-sits-on-the-corner"] = function(_, _, io)
		local notes = shared.FacetLiveSession.record.notes
		io.click(point(notes, "Inbox seal point"))
		live.step("afterInbox")
		io.click(point(notes, "Alerts seal point"))
		live.step("afterAlerts")
	end
	local clickCases: { [string]: { string } } = {
		["fields-control-size"] = { "click", "afterClick" },
		["pickers-avatar-row-press"] = { "avatar", "afterClick" },
		["plain-checkbox-row-tap"] = { "click", "click" },
	}
	for id, action in clickCases do
		drivers[id] = function(_, _, io)
			io.click(point(shared.FacetLiveSession.record.notes, action[1]))
			live.step(action[2])
		end
	end
	drivers["fields-visible-lines"] = function(_, _, io)
		io.text("x")
		live.step("afterType")
	end
	drivers["fields-select-on-focus"] = function(_, _, io)
		for _, action in { { "clickAll", "afterAll" }, { "clickEnd", "afterEnd" }, { "clickNone", "afterNone" } } do
			io.click(point(shared.FacetLiveSession.record.notes, action[1]))
			live.step(action[2])
		end
	end
	drivers["number-step-buttons"] = function(t)
		press(t, { "Right" })
		live.step("afterRight")
		press(t, { "Right" })
		live.step("afterRightAgain")
	end
	drivers["slider-landing-live"] = function(t)
		press(t, { "Up" })
		live.step("afterUp")
		press(t, { "Up" })
		live.step("afterSecondUp")
	end
	drivers["slider-rotation-live"] = function(_, _, io)
		for _, action in
			{
				{ "click0", "afterTurn0" },
				{ "click135", "afterTurn135" },
				{ "click270", "afterTurn270Scrolled" },
			}
		do
			io.click(point(shared.FacetLiveSession.record.notes, action[1]))
			live.step(action[2])
		end
	end
	drivers["slider-thumb-auto-live"] = function(_, _, io)
		io.move(point(shared.FacetLiveSession.record.notes, "hover"))
		live.step("afterHover")
		io.move(point(shared.FacetLiveSession.record.notes, "away"))
		live.step("afterLeave")
	end
	drivers["dtp-icon-toggle"] = function(_, _, io)
		for _, step in { "afterOpen", "afterClose", "afterReopen" } do
			io.click(point(shared.FacetLiveSession.record.notes, "icon"))
			live.step(step)
		end
	end
	drivers["dtp-native-navigation"] = function(t)
		for _, action in
			{
				{ "Up", "afterUpWalk" },
				{ "Down", "afterDownWalk" },
				{ "Down", "afterDraftDown" },
				{ "Down", "afterInlineDown" },
			}
		do
			press(t, { action[1], action[1], action[1] })
			live.step(action[2])
		end
	end
	drivers["dtp-menu-centred"] = function(t)
		press(t, { "Return" })
		live.step("afterReturn")
	end
	drivers["chip-edit-live"] = function(t)
		press(t, { "Delete" })
		live.step("afterDelete")
	end
	drivers["color-grid-wraps-two-dimensions"] = function(t)
		press(t, { "DPadDown" })
		live.step("afterDown")
		press(t, { "DPadRight" })
		live.step("afterRight")
	end
	for _, id in { "dtp-ten-foot-pad-open-and-back", "color-ten-foot-pad-open-and-back" } do
		drivers[id] = function(t)
			press(t, { "ButtonA" })
			live.step("afterOpen")
			press(t, { "ButtonB" })
			live.step("afterBack")
		end
	end
	drivers["color-ten-foot-center"] = function(t)
		for _ = 1, 8 do
			press(t, { "DPadDown" })
		end
		live.step("afterDown")
		for _ = 1, 8 do
			press(t, { "StickUp" })
		end
		live.step("afterUp")
	end
	drivers["dialog-body-pad-scrolls-then-moves"] = function(t)
		press(t, { "DPadDown" })
		live.step("afterDown")
		for _ = 1, 15 do
			press(t, { "DPadDown" })
		end
		live.step("afterDownMany")
	end
	drivers["menu-real-pad-opens-and-closes"] = function(t)
		for _ = 1, 2 do
			press(t, { "ButtonA" })
			live.step("opened")
			press(t, { "ButtonB" })
			live.step("closed")
		end
	end
	drivers["popover-real-pad-and-trigger-click"] = function(t, value, io)
		press(t, { "ButtonA" })
		live.step("opened")
		press(t, { "ButtonB" })
		live.step("cancelled")
		live.step("reopen")
		io.click(centre(value.trigger))
		live.step("clicked")
	end
	local shortRooms: { [string]: string } =
		{ ["dialog-short-room-pad-walk"] = "Leave", ["sheet-short-room-pad-walk"] = "Join" }
	for id, _last in shortRooms do
		drivers[id] = function(t, value)
			local last: GuiObject? = nil
			for _, node in value.panel:GetDescendants() do
				if node:IsA("GuiButton") and (last == nil or node.AbsolutePosition.Y > last.AbsolutePosition.Y) then
					last = node
				end
			end
			for _ = 1, 40 do
				if GuiService.SelectedObject == last then
					break
				end
				press(t, { "DPadDown" })
			end
			live.step("walked")
		end
	end
	drivers["changed-controls-board"] = function(t, value, io)
		io.pointerAction(centre(t.find(value.stage, "ReviewScroll")), { Wheel = -40 })
		live.step("held")
	end
	drivers["radial-menu-board"] = function(t, value, io)
		io.click(centre(t.find(value.stage, "N")))
		live.step("held")
	end
	for _, width in { 390, 1280 } do
		drivers["hud-settings-nonmodal-" .. width] = function(_, value, io)
			io.click(centre(value.trigger))
			settle(30)
			live.step("afterOpen")
			io.click(centre(value.outside))
			settle(30)
			live.step("afterOutside")
			io.click(centre(value.close))
			settle(30)
			live.step("afterClose")
		end
	end
	drivers["held-button-destruction-cancels"] = function(_, value, io)
		local at = centre(value.button)
		io.down(at)
		live.step("whileHeld")
		io.up(at)
		live.step("afterRelease")
	end
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
	drivers["drag-moves-a-layer-below-its-siblings"] = function(_, _, io)
		local points = shared.FacetLiveSession.record.notes.points
		io.drag(point(points, "first"), point(points, "below"))
		live.step("drag")
	end
	drivers["resize-handle-drag-sets-the-layer-width"] = function(_, _, io)
		local points = shared.FacetLiveSession.record.notes.points
		io.drag(point(points, "east"), point(points, "past"))
		live.step("drag")
	drivers["held-tile-opens-its-slot-and-settles-on-drop"] = function(_, _, io)
		local points = shared.FacetLiveSession.record.notes.points
		io.heldDrag(point(points, "from"), point(points, "to"))
		live.step("held")
		io.up(point(points, "to"))
		live.step("dropped")
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
		local distance = math.min(160, from.Y - value.list.AbsolutePosition.Y - 8)
		t.note("native scroll drag", { from = from, to = from - Vector2.new(0, distance) })
		io.drag(from, from - Vector2.new(0, distance))
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
	drivers["sidebar-dpad-to-collections"] = function(t, value)
		press(t, { if value.across then "DPadRight" else "DPadDown" })
		live.step(if value.across then "afterRight" else "afterDown")
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
	drivers["reserved-slots-pointer-recall"] = function(_, value, io)
		io.drag(centre(value.source), centre(value.target))
		live.step("afterStage")
		local slot: GuiObject = value.stage
		for _, child in value.stage:GetDescendants() do
			if child:IsA("GuiObject") and child:GetAttribute("FacetReservedKey") == "A" then
				slot = child
			end
		end
		io.drag(centre(value.target), centre(slot))
		live.step("afterRecall")
		live.step("afterRelease")
	end
	drivers["collection-immediate-touch-transfer"] = function(_, value, io)
		local from, to = centre(value.source), centre(value.target)
		io.down(from)
		io.move(from + Vector2.new(8, 0))
		live.step("afterEightPixels")
		for index = 1, 16 do
			io.move((from + Vector2.new(8, 0)):Lerp(to, index / 16))
		end
		live.step("whileDragging")
		io.up(to)
		live.step("afterDrop")
	end
	drivers["travel-recycled-destination"] = function(_, value)
		value.destination:set(assert(value.targets[1]))
		settle(2)
		value.replace()
		settle(120)
		live.step("afterReplace")
		value.remove()
		settle(120)
		live.step("afterRemove")
	end
	for _, id in { "zoom-capture-camera", "zoom-collection-capture-camera" } do
		drivers[id] = function(_, value, io)
			local at = centre(value.tile)
			io.heldDrag(at, at + Vector2.new(20, 20))
			settle(120)
			live.step("whileLifted")
			io.up(at + Vector2.new(20, 20))
			settle(120)
			live.step("afterRelease")
		end
	end
	drivers["shuffle-pointer"] = function(t, value, io)
		local button = assert(value.row.Parent:FindFirstChild("Shuffle", true))
		local activated = 0
		local watch = button.Activated:Connect(function()
			activated += 1
		end)
		t.note("shuffle button", t.rect(button))
		io.click(centre(button))
		settle(240)
		t.note("shuffle activations", activated)
		live.step("afterShuffle")
		io.click(centre(button))
		settle(8)
		io.click(centre(button))
		settle(240)
		live.step("afterInterrupt")
		watch:Disconnect()
	end
	drivers["shuffle-gamepad"] = function(t, value)
		GuiService.SelectedObject = assert(value.row.Parent:FindFirstChild("Shuffle", true))
		press(t, { "ButtonA" })
		settle(240)
		live.step("afterShuffle")
		press(t, { "ButtonA" })
		settle(8)
		press(t, { "ButtonA" })
		settle(240)
		live.step("afterInterrupt")
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
		io.controlWheel(at, 1)
		live.step("afterFocusZoom")
		io.doubleClick(at)
		settle(60)
		live.step("afterDoubleTap")
		io.controlWheel(at, 2)
		live.step("afterWheelZoom")
		io.pointerAction(at, { Wheel = 2 })
		live.step("afterWheelPan")
		io.drag(at, at - Vector2.new(0, 40))
		live.step("afterMousePan")
		local contact = centre(value.tile)
		io.heldDrag(contact, contact + Vector2.new(20, 20))
		live.step("afterChildDrag")
		io.up(contact + Vector2.new(20, 20))
	end
	do
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
	drivers["board-command-gamepad"] = function(t, value)
		GuiService.SelectedObject = value.first
		press(t, { "ButtonX" })
		live.step("afterPlace")
		press(t, { "DPadRight" })
		press(t, { "ButtonY" })
		live.step("afterRecall")
	end
	drivers["reward-gamepad"] = function(t, value)
		local root = assert(value.target.Parent)
		local play = assert(root:FindFirstChild("Play", true))
		local finish = assert(root:FindFirstChild("Finish", true))
		GuiService.SelectedObject = play
		press(t, { "ButtonA" })
		settle(180)
		live.step("afterReward")
		GuiService.SelectedObject = play
		press(t, { "ButtonA" })
		GuiService.SelectedObject = finish
		press(t, { "ButtonA" })
		settle(60)
		live.step("afterFinish")
	end
	drivers["tray-grows-with-text-size"] = function()
		assert(type(options.changeNativeTextSize) == "function", "native text-size setting requires an external driver")
		options.changeNativeTextSize()
		settle(60)
		live.step("afterChange")
	end
	local gamepad: { [string]: boolean } = {
		["color-grid-wraps-two-dimensions"] = true,
		["dialog-body-pad-scrolls-then-moves"] = true,
		["menu-real-pad-opens-and-closes"] = true,
		["popover-real-pad-and-trigger-click"] = true,
		["dialog-short-room-pad-walk"] = true,
		["sheet-short-room-pad-walk"] = true,
		["dtp-ten-foot-pad-open-and-back"] = true,
		["color-ten-foot-pad-open-and-back"] = true,
		["color-ten-foot-center"] = true,
		["card-keys-enter-and-stay-inside"] = true,
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
	local requirements: { [string]: string } = {
		["fields-visible-lines"] = "input-keyboard",
		["number-step-buttons"] = "input-keyboard",
		["slider-landing-live"] = "input-keyboard",
		["files-linked-input"] = "input-keyboard",
		["files-nested-touch-handoff"] = "input-native-touch",
		["dtp-native-navigation"] = "input-keyboard",
		["dtp-menu-centred"] = "input-keyboard",
		["chip-edit-live"] = "input-keyboard",
		["pagination-neighbours-arrive-and-land"] = "input-keyboard",
		["menu-lands-on-selected-and-walks-bounded"] = "input-keyboard",
		["choices-vote-row-inside-the-page"] = "input-keyboard",
		["collection-immediate-touch-transfer"] = "input-native-touch",
		["tray-grows-with-text-size"] = "input-native-settings",
		["text-edit-carries-gamepad-connect"] = "input-native-controller-connect",
		["radial-hot-switch-keeps-open"] = "input-native-controller-connect",
		["input-fact-follows-device"] = "input-native-controller-connect",
	}
	local keyboardCases: { string } = {
		"board-typing-pointer-and-text-entry",
		"return-and-space-activate-once",
		"shift-return-opens-row-menu",
		"tray-keys-and-hover",
		"header-sort-keys",
		"left-reaches-this-rows-minus",
		"collapsed-column-leaves-the-ring",
		"return-toggles-multi-selection",
		"horizontal-list-keys",
		"chrome-strips-dpad",
		"form-controls-reach-by-arrows",
		"slider-between-controls-by-arrows",
		"hud-dpad-reaches-actions-390",
		"hud-dpad-reaches-actions-1920",
		"recipe-rail-tab-scrolls-tail",
		"showcase-rail-tail-inside-clips",
		"inner-tabs-widen-to-engine-words",
	}
	for _, id in keyboardCases do
		requirements[id] = "input-keyboard"
	end
	requirements["touch-drag-scrolls-reorderable-list"] = "input-native-touch"
	requirements["mail-swipe-and-tap"] = "input-native-touch"
	requirements["slider-rotation-live"] = "input-mouse"
	requirements["zoom-pointer"] = "input-mouse"
	requirements["zoom-collection-capture-camera"] = "input-mouse"
	drivers["text-edit-carries-gamepad-connect"] = function()
		options.connectGamepad()
		live.step("afterConnect")
		options.disconnectGamepad()
	end
	drivers["radial-hot-switch-keeps-open"] = function()
		options.connectGamepad()
		live.step("afterPlug")
		options.disconnectGamepad()
		live.step("afterUnplug")
	end
	drivers["input-fact-follows-device"] = function()
		options.connectGamepad()
		live.step("afterPlug")
		options.disconnectGamepad()
	end
	drivers["hover-arrives-with-a-mouse"] = function()
		game:GetService("StudioDeviceSimulatorService"):StopSimulationAsync()
		settle(60)
		live.step("afterDesktop")
	end
	for id in gamepad do
		requirements[id] = "input-gamepad"
	end
	if options.registerOnly then
		return { drivers = drivers, requirements = requirements, pointer = pointer }
	end
	local capabilities = { "roblox-client", "input-pointer" }
	if UserInputService.MouseEnabled then
		table.insert(capabilities, "input-mouse")
	end
	if type(options.changeNativeTextSize) == "function" then
		table.insert(capabilities, "input-native-settings")
	end
	if type(options.connectGamepad) == "function" and type(options.disconnectGamepad) == "function" then
		table.insert(capabilities, "input-native-controller-connect")
	end
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		table.insert(capabilities, "input-native-touch")
	end
	if keyboardInput then
		table.insert(capabilities, "input-keyboard")
	end
	if options.device == "keep" and UserInputService.GamepadEnabled then
		table.insert(capabilities, "input-gamepad")
	end
	local reports = {}
	if automaticReport then
		table.insert(reports, automaticReport)
	end
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
		local required = requirements[case.id]
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
		local touch = case.id == "touch-drag-scrolls-reorderable-list"
			or case.id == "mail-swipe-and-tap"
			or case.id == "collection-immediate-touch-transfer"
			or case.id == "files-nested-touch-handoff"
		if options.device ~= "keep" then
			local simulator = game:GetService("StudioDeviceSimulatorService") :: any
			if touch then
				simulator:SetDeviceAsync("iphone_14")
				simulator:SetOrientationAsync(Enum.ScreenOrientation.Portrait)
			elseif options.device == nil or options.device == "none" then
				simulator:StopSimulationAsync()
			else
				simulator:SetDeviceAsync(options.device)
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
		if required == "input-keyboard" then
			live.press({ "LeftShift" })
		end
		local began, problem = pcall(live.begin, suite, case.id, options)
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
		local cleanInput: (() -> ())? = nil
		local ran, errorMessage = xpcall(function()
			local driver = assert(drivers[case.id], "no native input driver for " .. case.id)
			local io = pointer(session.t)
			cleanInput = io.cleanup
			driver(session.t, session.value, io)
		end, debug.traceback)
		if cleanInput then
			local released, releaseError = pcall(function(): unknown
				assert(cleanInput)()
				return nil
			end)
			session.t.check("native input released after driver", released, releaseError)
		end
		if not ran then
			session.t.check("native input driver completed", false, errorMessage)
		end
		table.insert(reports, Verify.decode(HttpService:JSONDecode(live.finish())))
	end
	if selected == 0 then
		return Verify.decode(live.report(suite, options))
	end
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
