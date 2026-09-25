--!strict
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local storage = game:GetService("ReplicatedStorage")

local cases = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local function interactive(
	id: string,
	contracts: { string },
	setup: (any) -> any,
	steps: { [string]: (any, any) -> () },
	keepGallery: boolean?
)
	table.insert(cases, { id = id, contracts = contracts, setup = setup, steps = steps, keepGallery = keepGallery })
end

local PAD: { [string]: Enum.KeyCode } = {
	ButtonA = Enum.KeyCode.Nine,
	ButtonB = Enum.KeyCode.Zero,
	ButtonX = Enum.KeyCode.Eight,
	ButtonY = Enum.KeyCode.Seven,
	DPadDown = Enum.KeyCode.Three,
	DPadLeft = Enum.KeyCode.Two,
	DPadRight = Enum.KeyCode.Four,
	ButtonL1 = Enum.KeyCode.R,
	ButtonR1 = Enum.KeyCode.O,
	ButtonL2 = Enum.KeyCode.E,
	ButtonSelect = Enum.KeyCode.Q,
	StickUp = Enum.KeyCode.W,
	StickDown = Enum.KeyCode.S,
	StickLeft = Enum.KeyCode.A,
	StickRight = Enum.KeyCode.D,
	RightStickUp = Enum.KeyCode.I,
	RightStickDown = Enum.KeyCode.K,
	RightStickLeft = Enum.KeyCode.J,
	RightStickRight = Enum.KeyCode.L,
}

local function gamepadWatch(): () -> { string }
	local seen = {}
	local connection = UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Gamepad1 then
			table.insert(seen, input.KeyCode.Name)
		end
	end)
	return function()
		connection:Disconnect()
		return seen
	end
end

local function device(t: any): any
	local virtual = (UserInputService :: any):CreateVirtualInput()
	t.check("virtual input is available", virtual ~= nil)
	local inset = GuiService:GetGuiInset()
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		local shield = Instance.new("ScreenGui")
		shield.DisplayOrder = 10000
		shield.IgnoreGuiInset = true
		local pad = Instance.new("TextButton")
		pad.Size = UDim2.fromScale(1, 1)
		pad.BackgroundTransparency = 1
		pad.Text = ""
		pad.Parent = shield
		shield.Parent = Players.LocalPlayer.PlayerGui
		t.settle(2)
		local seen: Vector3? = nil
		local watch = UserInputService.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				seen = input.Position
			end
		end)
		local probe = workspace.CurrentCamera.ViewportSize / 2 + inset
		virtual:SendMousePosition(probe)
		virtual:SendMouseButton(probe, Enum.UserInputType.MouseButton1, true)
		t.settle(2)
		virtual:SendMouseButton(probe, Enum.UserInputType.MouseButton1, false)
		t.settle(2)
		watch:Disconnect()
		shield:Destroy()
		if seen then
			inset = probe - Vector2.new(seen.X, seen.Y)
		end
		t.note("touch calibration inset", inset)
	end
	local io = { virtual = virtual, inset = inset }
	function io.move(at: Vector2)
		virtual:SendMousePosition(at + inset)
		t.settle(1)
	end
	function io.down(at: Vector2)
		virtual:SendMousePosition(at + inset)
		virtual:SendMouseButton(at + inset, Enum.UserInputType.MouseButton1, true)
		t.settle(1)
	end
	function io.up(at: Vector2)
		virtual:SendMouseButton(at + inset, Enum.UserInputType.MouseButton1, false)
		t.settle(1)
	end
	function io.drag(from: Vector2, to: Vector2, steps: number?, hold: number?)
		local count = steps or 12
		virtual:SendMousePosition(from + inset)
		t.settle(2)
		virtual:SendMouseButton(from + inset, Enum.UserInputType.MouseButton1, true)
		t.settle(hold or 2)
		for index = 1, count do
			virtual:SendMousePosition(from:Lerp(to, index / count) + inset)
			t.settle(1)
		end
		virtual:SendMouseButton(to + inset, Enum.UserInputType.MouseButton1, false)
		t.settle(4)
	end
	function io.click(at: Vector2)
		virtual:SendMousePosition(at + inset)
		t.settle(2)
		virtual:SendMouseButton(at + inset, Enum.UserInputType.MouseButton1, true)
		t.settle(2)
		virtual:SendMouseButton(at + inset, Enum.UserInputType.MouseButton1, false)
		t.settle(4)
	end
	function io.press(key: Enum.KeyCode, down: boolean)
		virtual:SendKey(down, key, false)
		t.settle(1)
	end
	function io.key(key: Enum.KeyCode)
		virtual:SendKey(true, key, false)
		t.settle(2)
		virtual:SendKey(false, key, false)
		t.settle(4)
	end
	function io.pad(button: string)
		local key = PAD[button]
		assert(key, "no emulator key for " .. button)
		virtual:SendKey(true, key, false)
		t.settle(3)
		virtual:SendKey(false, key, false)
		t.settle(5)
	end
	function io.warm()
		virtual:SendKey(true, PAD.ButtonL2, false)
		t.settle(3)
		virtual:SendKey(false, PAD.ButtonL2, false)
		t.settle(8)
		local previous = GuiService.SelectedObject
		local shield = Instance.new("ScreenGui")
		shield.DisplayOrder = 10000
		local pad = Instance.new("TextButton")
		pad.Size = UDim2.fromOffset(40, 40)
		pad.BackgroundTransparency = 1
		pad.Text = ""
		pad.Parent = shield
		shield.Parent = Players.LocalPlayer.PlayerGui
		t.settle(2)
		GuiService.SelectedObject = pad
		t.settle(2)
		virtual:SendKey(true, PAD.ButtonA, false)
		t.settle(3)
		virtual:SendKey(false, PAD.ButtonA, false)
		t.settle(4)
		shield:Destroy()
		GuiService.SelectedObject = previous
		t.settle(2)
	end
	function io.padHold(button: string, down: boolean)
		virtual:SendKey(down, PAD[button], false)
		t.settle(1)
	end
	function io.text(value: string)
		virtual:SendTextInput(value)
		t.settle(2)
	end
	function io.wheel(at: Vector2, up: boolean)
		virtual:SendMousePosition(at + inset)
		virtual:SendPointerAction(at + inset, if up then Enum.PointerAction.WheelUp else Enum.PointerAction.WheelDown)
		t.settle(4)
	end
	return io
end

local function centre(node: GuiObject): Vector2
	return node.AbsolutePosition + node.AbsoluteSize / 2
end

local function selectedName(): string
	local selected = GuiService.SelectedObject
	return if selected then selected.Name else "nil"
end

local function textBox(root: Instance?): TextBox?
	if root == nil then
		return nil
	end
	if root:IsA("TextBox") then
		return root
	end
	return root:FindFirstChildWhichIsA("TextBox", true)
end

local function visibleNamed(t: any, root: Instance, name: string): any
	for _, node in root:GetDescendants() do
		if node.Name == name and node:IsA("GuiObject") and t.visible(node) then
			return node
		end
	end
	return nil
end

local function hits(at: Vector2): { GuiObject }
	return (Players.LocalPlayer.PlayerGui :: any):GetGuiObjectsAtPosition(at.X, at.Y)
end

local function example(t: any, name: string, patch: ((any) -> ())?, size: Vector2?): (any, any)
	local built
	local stage = t.mount(function(UI, Host, Compose, env)
		local ctx = t.context(UI, Host, Compose, env)
		if patch then
			patch(ctx)
		end
		built = (require :: any)(storage:WaitForChild("FacetExamples"):WaitForChild(name)).build(ctx)
		return if type(built) == "function" then built() else built.screen()
	end, { frames = 20, size = size })
	return stage, built
end

local function scenario(t: any, name: string, patch: ((any) -> ())?, size: Vector2?): (any, any)
	local built
	local stage = t.mount(function(UI, Host, Compose, env)
		local ctx = t.context(UI, Host, Compose, env)
		if patch then
			patch(ctx)
		end
		built = t.scenario(name).build(ctx)
		return if type(built) == "function" then built() else built.screen()
	end, { frames = 20, size = size })
	return stage, built
end

local function touch(t: any)
	t.device({ device = "iphone_14", input = Enum.PreferredInput.Touch, restore = "xbox" })
	for _ = 1, 180 do
		if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
			break
		end
		t.settle(1)
	end
	t.settle(10)
end

local function temperatureField(t: any): (any, any, TextBox?)
	local stage, built = example(t, "01_temperature_converter")
	local field = textBox(t.find(stage, "Fahrenheit"))
	t.check("the Fahrenheit TextBox mounts", field ~= nil)
	return stage, built, field
end

add("temperature-pointer-enters-edit", { "apps2-30" }, function(t)
	local io = device(t)
	local _, built, field = temperatureField(t)
	if not field then
		return
	end
	t.check("the field starts unfocused", not field:IsFocused())
	io.click(centre(field))
	t.check("a mouse click focuses the field for editing", field:IsFocused())
	io.text("212")
	t.settle(4)
	t.check("typed text reaches the value", built.fahrenheitText() == "212", built.fahrenheitText())
	t.check("the live preview follows", built.liveCelsius() == 100, built.liveCelsius())
	t.check("nothing is committed while editing", built.celsius() == nil, built.celsius())
	io.key(Enum.KeyCode.Return)
	t.check("Return commits the conversion", built.celsius() == 100, built.celsius())
	t.check("Return ends the edit", not field:IsFocused())
end)

add("temperature-touch-enters-edit", { "apps2-30" }, function(t)
	touch(t)
	t.check("the emulator reports touch", UserInputService.PreferredInput == Enum.PreferredInput.Touch)
	local io = device(t)
	local kinds = {}
	local watch = UserInputService.InputBegan:Connect(function(input)
		table.insert(kinds, input.UserInputType.Name)
	end)
	local _, built, field = temperatureField(t)
	if not field then
		watch:Disconnect()
		return
	end
	io.click(centre(field))
	watch:Disconnect()
	t.note("input kinds", kinds)
	t.check("the tap arrives as touch", table.find(kinds, "Touch") ~= nil, kinds)
	t.check("a touch tap focuses the field for editing", field:IsFocused())
	io.text("32")
	t.settle(2)
	field:ReleaseFocus()
	t.settle(4)
	t.check("focus loss commits", built.celsius() == 0, built.celsius())
end)

add("temperature-return-enters-edit", { "apps2-30" }, function(t)
	local io = device(t)
	for _, key in { Enum.KeyCode.Return } do
		local _, built, field = temperatureField(t)
		if not field then
			return
		end
		GuiService.SelectedObject = field
		t.settle(3)
		t.check(`{key.Name}: the field is the selected object`, GuiService.SelectedObject == field, selectedName())
		io.key(key)
		t.settle(4)
		t.check(`{key.Name} on the selected field enters editing`, field:IsFocused())
		io.text("5")
		t.settle(2)
		t.check(`{key.Name}: typing edits the value`, built.fahrenheitText() == "5", built.fahrenheitText())
		field:ReleaseFocus()
		GuiService.SelectedObject = nil
		t.cleanup()
	end
end)

add("confirm-dialog-keyboard-to-cancel", { "apps2-45" }, function(t)
	local io = device(t)
	local stage, built = example(t, "04_confirm_dialog")
	local gui = stage:FindFirstAncestorWhichIsA("LayerCollector")
	local delete = t.find(stage, "Delete")
	GuiService.SelectedObject = delete
	t.settle(3)
	t.check("Delete is selected", GuiService.SelectedObject == delete, selectedName())
	io.key(Enum.KeyCode.Return)
	t.settle(40)
	local cancel, confirm = visibleNamed(t, gui, "Cancel"), visibleNamed(t, gui, "Confirm")
	t.check("Return on Delete opens the dialog", cancel ~= nil and confirm ~= nil)
	t.check("the selection lands on Cancel, the safe default", selectedName() == "Cancel", selectedName())
	io.key(Enum.KeyCode.Right)
	t.check("Right moves to Confirm", selectedName() == "Confirm", selectedName())
	io.key(Enum.KeyCode.Left)
	t.check("Left returns to Cancel", selectedName() == "Cancel", selectedName())
	io.key(Enum.KeyCode.Up)
	io.key(Enum.KeyCode.Up)
	local inside = GuiService.SelectedObject ~= nil
		and cancel ~= nil
		and GuiService.SelectedObject:IsDescendantOf(cancel:FindFirstAncestorWhichIsA("LayerCollector") or gui)
	t.check(
		"Up cannot leave the dialog",
		selectedName() == "Cancel" or selectedName() == "Confirm",
		{ selectedName(), inside }
	)
	GuiService.SelectedObject = cancel
	t.settle(2)
	io.key(Enum.KeyCode.Return)
	t.settle(40)
	t.check("Return on Cancel reports a cancel", built.result() == "cancelled", built.result())
	t.check("the save is kept", built.hasSave() == true)
	t.check("the dialog is dismissed", visibleNamed(t, gui, "Confirm") == nil)
	t.note("selection after dismissal", selectedName())
	t.check("selection returns to Delete", selectedName() == "Delete", selectedName())
	GuiService.SelectedObject = nil
end)

add("pad-with-animation-a", { "apps2-52" }, function(t)
	local io = device(t)
	local stage, built = scenario(t, "with_animation")
	local animate = t.find(stage, "Animate")
	t.check("the Animate button mounts", animate ~= nil)
	if not animate then
		return
	end
	io.warm()
	local stop = gamepadWatch()
	GuiService.SelectedObject = animate
	t.settle(2)
	io.pad("ButtonA")
	t.check("gamepad A on the selected button animates once", built.report().runs == 1, built.report())
	io.pad("ButtonA")
	t.check("a second gamepad A animates once more", built.report().runs == 2, built.report())
	t.note("gamepad events", stop())
	GuiService.SelectedObject = nil
end)

add("with-animation-four-inputs", { "apps2-52" }, function(t)
	local io = device(t)
	local function world(): (any, any, any)
		local stage, built = scenario(t, "with_animation")
		local animate = t.find(stage, "Animate")
		t.check("the Animate button mounts", animate ~= nil)
		return stage, built, animate
	end
	local stage, built, animate = world()
	io.click(centre(animate))
	t.check("mouse click animates once", built.report().runs == 1, built.report())
	GuiService.SelectedObject = animate
	t.settle(2)
	io.key(Enum.KeyCode.Return)
	t.check("Return on the selected button animates once more", built.report().runs == 2, built.report())
	local reduced = t.find(stage, "Reduced")
	local target = textBox(reduced) or reduced
	local button = if reduced and reduced:IsA("GuiButton")
		then reduced
		else reduced and reduced:FindFirstChildWhichIsA("GuiButton", true)
	GuiService.SelectedObject = button
	t.settle(2)
	io.key(Enum.KeyCode.Return)
	t.check(
		"Return reaches the reduced-motion toggle",
		built.report().reduced == true,
		{ built.report(), target and target.Name }
	)
	GuiService.SelectedObject = nil
	t.cleanup()
	touch(t)
	local io2 = device(t)
	local _, touched, pad = world()
	io2.click(centre(pad))
	t.check("a touch tap animates once", touched.report().runs == 1, touched.report())
end)

add("settings-sheet-stays-over-demo", { "apps2-94" }, function(t)
	local io = device(t)
	local stage, context = t.gallery({ demo = "all-controls" })
	t.settle(10)
	local gui = stage:FindFirstAncestorWhichIsA("LayerCollector")
	local settings = visibleNamed(t, gui, "Settings") or visibleNamed(t, gui, "CompactSettings")
	t.check("the Settings chrome button is visible", settings ~= nil)
	if not settings then
		return
	end
	local button = if settings:IsA("GuiButton") then settings else settings:FindFirstChildWhichIsA("GuiButton", true)
	io.click(centre(button))
	t.settle(40)
	local function panel(): (any, any)
		local modal = visibleNamed(t, gui, "Modal")
		if not modal then
			return nil, nil
		end
		local best
		for _, child in modal:GetChildren() do
			if child:IsA("GuiObject") and child.Name ~= "DismissOutside" and t.visible(child) then
				if
					not best
					or child.AbsoluteSize.X * child.AbsoluteSize.Y > best.AbsoluteSize.X * best.AbsoluteSize.Y
				then
					best = child
				end
			end
		end
		return modal, best
	end
	local modal, sheet = panel()
	t.check("a click opens the settings sheet", modal ~= nil and sheet ~= nil)
	if not (modal and sheet) then
		return
	end
	local function title(root: Instance): boolean
		for _, node in root:GetDescendants() do
			if node:IsA("TextLabel") and node.ContentText == "Gallery settings" then
				return true
			end
		end
		return false
	end
	t.check("the sheet shows the Gallery settings title", title(sheet))
	local function onTop(label: string, node: any)
		local box = t.clipped(node) or t.rect(node)
		local at = Vector2.new(box.x + box.w / 2, box.y + math.min(box.h / 2, 40))
		local list = hits(at)
		local names = {}
		for index = 1, math.min(6, #list) do
			names[index] = list[index]:GetFullName()
		end
		t.note(label, names)
		local top = list[1]
		t.check(label, top ~= nil and (top == node or top:IsDescendantOf(node)), top and top:GetFullName())
		local stageAt, modalAt = nil, nil
		for index, hit in list do
			if not modalAt and hit:IsDescendantOf(modal) then
				modalAt = index
			end
			if not stageAt and hit:IsDescendantOf(stage) then
				stageAt = index
			end
		end
		t.check(
			label .. ": the demo is beneath the sheet",
			modalAt ~= nil and (stageAt == nil or modalAt < stageAt),
			{ modalAt, stageAt }
		)
	end
	onTop("the sheet is the topmost object when it opens", sheet)
	local shown = {}
	for _ = 1, 6 do
		table.insert(shown, context.dispatch("next", 1).current)
		t.settle(30)
	end
	t.note("demos swapped under the sheet", shown)
	t.check("six different demos were shown", #shown == 6 and shown[1] ~= shown[6], shown)
	local modal2, sheet2 = panel()
	t.check("the same sheet is still open after six demo swaps", modal2 == modal and sheet2 == sheet)
	if sheet2 then
		t.check("the sheet still shows its title", title(sheet2))
		onTop("the sheet is still the topmost object over the new demo", sheet2)
		local count = 0
		for _, node in gui:GetDescendants() do
			if node.Name == "Modal" and node:IsA("GuiObject") and t.visible(node) then
				count += 1
			end
		end
		t.check("there is exactly one open modal layer", count == 1, count)
	end
end)

add("pad-confirm-dialog-to-cancel", { "apps2-45" }, function(t)
	local io = device(t)
	local stage, built = example(t, "04_confirm_dialog")
	local gui = stage:FindFirstAncestorWhichIsA("LayerCollector")
	local delete = t.find(stage, "Delete")
	io.warm()
	local stop = gamepadWatch()
	GuiService.SelectedObject = delete
	t.settle(3)
	io.pad("ButtonA")
	t.settle(40)
	t.check("gamepad A on Delete opens the dialog", visibleNamed(t, gui, "Confirm") ~= nil)
	local panel = visibleNamed(t, gui, "AlertPanel") or visibleNamed(t, gui, "Card")
	if panel then
		t.stable(panel, 10)
	end
	t.settle(30)
	t.check("the selection lands on Cancel", selectedName() == "Cancel", selectedName())
	io.pad("DPadRight")
	t.check("DPadRight moves to Confirm", selectedName() == "Confirm", selectedName())
	io.pad("DPadLeft")
	t.check("DPadLeft returns to Cancel", selectedName() == "Cancel", selectedName())
	io.pad("StickUp")
	t.settle(10)
	t.check(
		"the stick up cannot leave the dialog",
		selectedName() == "Cancel" or selectedName() == "Confirm",
		selectedName()
	)
	GuiService.SelectedObject = visibleNamed(t, gui, "Cancel")
	t.settle(2)
	io.pad("ButtonA")
	t.settle(40)
	t.check("gamepad A on Cancel reports a cancel", built.result() == "cancelled", built.result())
	t.check("the save is kept", built.hasSave() == true)
	t.check("the dialog is dismissed", visibleNamed(t, gui, "Confirm") == nil)
	t.check("the selection returns to Delete", selectedName() == "Delete", selectedName())
	built.restore()
	t.settle(4)
	GuiService.SelectedObject = t.find(stage, "Delete")
	t.settle(2)
	io.pad("ButtonA")
	t.settle(40)
	t.check("gamepad A reopens the dialog", visibleNamed(t, gui, "Confirm") ~= nil)
	io.pad("ButtonB")
	t.settle(40)
	t.check("gamepad B dismisses the dialog", visibleNamed(t, gui, "Confirm") == nil)
	t.check("gamepad B deletes nothing", built.hasSave() == true)
	t.check("gamepad B returns the selection to Delete", selectedName() == "Delete", selectedName())
	local seen = stop()
	t.note("gamepad events", seen)
	t.check(
		"the presses arrived as Gamepad1 input",
		table.find(seen, "ButtonA") ~= nil
			and table.find(seen, "DPadRight") ~= nil
			and table.find(seen, "ButtonB") ~= nil,
		seen
	)
	GuiService.SelectedObject = nil
end)

local function chromeBar(t: any): (any, any, any)
	local pressed = {}
	local stage = t.mount(function(UI, Host)
		return Host.Frame "Root" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			UI.HStack "Bar" {
				UI.Button "Left" {
					label = "Left",
					onActivate = function()
						table.insert(pressed, "Left")
					end,
				},
				UI.Button "Right" {
					label = "Right",
					onActivate = function()
						table.insert(pressed, "Right")
					end,
				},
			},
			Host.Frame "Content" {
				Position = UDim2.fromOffset(0, 200),
				Size = UDim2.fromOffset(300, 100),
				BackgroundTransparency = 1,
				UI.Button "A" {
					label = "Content A",
					onActivate = function()
						table.insert(pressed, "A")
					end,
				},
			},
		}
	end, { frames = 12 })
	local left, a = t.find(stage, "Left"), t.find(stage, "A")
	t.check("the chrome and content buttons mount", left ~= nil and a ~= nil)
	local leftButton = left and (if left:IsA("GuiButton") then left else left:FindFirstChildWhichIsA("GuiButton", true))
	local aButton = a and (if a:IsA("GuiButton") then a else a:FindFirstChildWhichIsA("GuiButton", true))
	return pressed, leftButton, aButton
end

add("chrome-press-activates-once", { "apps-152" }, function(t)
	local io = device(t)
	local pressed, leftButton, aButton = chromeBar(t)
	if not (leftButton and aButton) then
		return
	end
	GuiService.SelectedObject = leftButton
	t.settle(2)
	io.key(Enum.KeyCode.Return)
	t.check("Return on the chrome button runs its handler once", #pressed == 1 and pressed[1] == "Left", pressed)
	table.clear(pressed)
	GuiService.SelectedObject = aButton
	t.settle(2)
	io.key(Enum.KeyCode.Return)
	t.check("Return on the content button runs the content handler once", #pressed == 1 and pressed[1] == "A", pressed)
	table.clear(pressed)
	GuiService.SelectedObject = nil
	t.settle(2)
	io.click(centre(leftButton))
	t.check("a click on the chrome button runs its handler once", #pressed == 1 and pressed[1] == "Left", pressed)
end)

add("pad-chrome-press-activates-once", { "apps-152" }, function(t)
	local io = device(t)
	local pressed, leftButton, aButton = chromeBar(t)
	if not (leftButton and aButton) then
		return
	end
	io.warm()
	local stop = gamepadWatch()
	GuiService.SelectedObject = leftButton
	t.settle(2)
	io.pad("ButtonA")
	t.check("gamepad A on the chrome button runs its handler once", #pressed == 1 and pressed[1] == "Left", pressed)
	table.clear(pressed)
	GuiService.SelectedObject = aButton
	t.settle(2)
	io.pad("ButtonA")
	t.check(
		"gamepad A on the content button runs the content handler once",
		#pressed == 1 and pressed[1] == "A",
		pressed
	)
	t.note("gamepad events", stop())
	GuiService.SelectedObject = nil
end)

local function fieldForm(t: any): (any, any)
	local value = { commits = {}, changes = {} }
	local stage = t.mount(function(UI, Host, Compose)
		value.text = Compose.cell("seed")
		return UI.VStack "Form" {
			gap = "s",
			UI.TextInput "Name" {
				value = value.text,
				onChange = function(text)
					table.insert(value.changes, text)
					value.text:set(text)
				end,
				onCommit = function(text, reason)
					table.insert(value.commits, { text, reason })
				end,
			},
			UI.Button "Next" { label = "Next" },
		}
	end, { frames = 12 })
	value.field = textBox(t.find(stage, "Name"))
	value.next = t.find(stage, "Next")
	t.check("the field and the next button mount", value.field ~= nil and value.next ~= nil)
	return stage, value
end

add("text-input-return-enters-once", { "inputs-181" }, function(t)
	local io = device(t)
	local _, value = fieldForm(t)
	local field = value.field
	if not field then
		return
	end
	GuiService.SelectedObject = field
	t.settle(3)
	io.key(Enum.KeyCode.Return)
	t.settle(10)
	t.check("Return on the selected field enters editing", field:IsFocused())
	t.check("the entering Return commits nothing", #value.commits == 0, value.commits)
	t.check("the entering Return changes nothing", #value.changes == 0, value.changes)
	t.settle(20)
	t.check("the field is still editing twenty frames later", field:IsFocused())
	io.key(Enum.KeyCode.Return)
	t.settle(6)
	t.note("second Return commits", value.commits)
	t.check("a second Return is the native submit: exactly one commit", #value.commits == 1, value.commits)
	t.check("the submit keeps the value", value.text:peek() == "seed", value.text:peek())
	t.check("the second Return does not re-enter editing", not field:IsFocused())
	GuiService.SelectedObject = nil
end)

add("text-input-owns-arrows", { "apps-169" }, function(t)
	local io = device(t)
	local _, value = fieldForm(t)
	local field = value.field
	if not field then
		return
	end
	GuiService.SelectedObject = field
	t.settle(3)
	io.key(Enum.KeyCode.Down)
	t.check(
		"before editing, Down moves the selection off the field",
		GuiService.SelectedObject ~= field,
		selectedName()
	)
	GuiService.SelectedObject = field
	t.settle(3)
	io.key(Enum.KeyCode.Return)
	t.check("Return enters editing", field:IsFocused())
	for _, key in { Enum.KeyCode.Down, Enum.KeyCode.Up, Enum.KeyCode.Left, Enum.KeyCode.Right } do
		io.key(key)
		t.check(
			`{key.Name} while editing leaves the selection on the field`,
			GuiService.SelectedObject == field,
			selectedName()
		)
		t.check(`{key.Name} while editing keeps the edit open`, field:IsFocused())
	end
	io.text("x")
	t.settle(2)
	t.check("typing still reaches the field after the arrows", string.find(field.Text, "x", 1, true) ~= nil, field.Text)
	field:ReleaseFocus()
	GuiService.SelectedObject = nil
end)

interactive("text-edit-carries-gamepad-connect", { "inputs-137" }, function(t)
	touch(t)
	local io = device(t)
	local _, value = fieldForm(t)
	value.events = {}
	value.connections = {
		UserInputService.GamepadConnected:Connect(function(gamepad)
			table.insert(value.events, "connected " .. gamepad.Name)
		end),
		UserInputService.GamepadDisconnected:Connect(function(gamepad)
			table.insert(value.events, "disconnected " .. gamepad.Name)
		end),
	}
	local field = value.field
	if field then
		io.click(centre(field))
		t.check("a touch tap starts editing", field:IsFocused())
		field.CursorPosition = #field.Text + 1
		io.text("hi")
		t.settle(4)
		t.check("typing reaches the value", value.text:peek() == "seedhi", value.text:peek())
		t.check("no gamepad is enabled before the arrival", not UserInputService.GamepadEnabled)
	end
	return value
end, {
	afterConnect = function(t, value)
		t.settle(10)
		t.note("device events", value.events)
		t.check(
			"the Controller Emulator connected Gamepad1 mid-edit",
			table.find(value.events, "connected Gamepad1") ~= nil,
			value.events
		)
		t.check("the engine now reports a gamepad", UserInputService.GamepadEnabled)
		t.check("the edit carries across the gamepad arrival", value.field:IsFocused())
		t.check("the text is intact", value.text:peek() == "seedhi", value.text:peek())
		t.check("nothing was committed", #value.commits == 0, value.commits)
		for _, connection in value.connections do
			connection:Disconnect()
		end
		value.field:ReleaseFocus()
	end,
})

add("pad-text-edit-commits-on-dock", { "inputs-137" }, function(t)
	touch(t)
	local io = device(t)
	local _, value = fieldForm(t)
	local field = value.field
	if not field then
		return
	end
	io.click(centre(field))
	t.check("a touch tap starts editing", field:IsFocused())
	field.CursorPosition = #field.Text + 1
	io.text("hi")
	t.settle(4)
	t.check("the typed text is in the value", value.text:peek() == "seedhi", value.text:peek())
	local simulator = game:GetService("StudioDeviceSimulatorService") :: any
	simulator:SetDeviceAsync("xbox")
	t.settle(40)
	t.note("after dock", {
		preferred = UserInputService.PreferredInput,
		touch = UserInputService.TouchEnabled,
		focused = field:IsFocused(),
		commits = value.commits,
	})
	t.check("docking to a console ends the edit", not field:IsFocused())
	t.check("the edit ended through exactly one commit", #value.commits == 1, value.commits)
	t.check(
		"the commit reports focus loss",
		value.commits[1] ~= nil and value.commits[1][2] == "focusLost",
		value.commits
	)
	t.check("the value keeps the last accepted text", value.text:peek() == "seedhi", value.text:peek())
	local pad = device(t)
	pad.warm()
	GuiService.SelectedObject = field
	t.settle(3)
	pad.pad("DPadDown")
	t.check(
		"navigation resumes after the edit ends: DPadDown leaves the field",
		GuiService.SelectedObject ~= field and GuiService.SelectedObject ~= nil,
		selectedName()
	)
	GuiService.SelectedObject = nil
end)

local COMPASS =
	{ { "N", "chevron.up" }, { "E", "chevron.trailing" }, { "S", "chevron.down" }, { "W", "chevron.leading" } }

local function radial(t: any, options: { [string]: any }?): { [string]: any }
	local config = options or {}
	local value: { [string]: any } = { fired = {} }
	local stage = t.mount(function(UI, Host, Compose)
		value.open = Compose.cell(false)
		local items = {}
		for _, entry in COMPASS do
			table.insert(items, {
				id = entry[1],
				slot = entry[1],
				label = if config.iconOnly then nil else entry[1],
				icon = entry[2],
				completion = "stay",
				onSelect = function()
					table.insert(value.fired, entry[1])
				end,
			})
		end
		return UI.RadialMenu "Quick" { isPresented = value.open, items = items, preset = config.preset }
	end, {
		size = (config.size or Vector2.new(800, 600)) / (config.scale or 1),
		theme = config.theme,
		frames = 20,
	})
	if config.scale then
		local scale = Instance.new("UIScale")
		scale.Name = "ViewingDistance"
		scale.Scale = config.scale
		scale.Parent = stage
		t.settle(4)
	end
	value.stage = stage
	value.gui = stage:FindFirstAncestorWhichIsA("LayerCollector")
	value.open:set(true)
	t.settle(60)
	value.panel = visibleNamed(t, value.gui, "RadialPanel")
	t.check("the radial menu presents", value.panel ~= nil)
	if value.panel then
		t.stable(value.panel, 6)
	end
	value.sectors = {}
	for _, entry in COMPASS do
		local slot = value.panel and value.panel:FindFirstChild("SectorSlot/" .. entry[1])
		local sector = slot and slot:FindFirstChild("Sector-" .. entry[1])
		local button = sector and sector:FindFirstChild(entry[1])
		value.sectors[entry[1]] =
			{ slot = slot, sector = sector, button = button, paint = sector and sector:FindFirstChild("Paint") }
	end
	return value
end

local function layoutWatch(root: Instance): () -> number
	local count = 0
	local connections = {}
	for _, node in root:GetDescendants() do
		if node:IsA("GuiObject") then
			table.insert(
				connections,
				node:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
					count += 1
				end)
			)
			table.insert(
				connections,
				node:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
					count += 1
				end)
			)
		end
	end
	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		return count
	end
end

add("pad-radial-held-dpad-steps-once", { "apps2-183" }, function(t)
	local io = device(t)
	local menu = radial(t)
	local north, east = menu.sectors.N.button, menu.sectors.E.button
	if not (north and east) then
		t.check("the compass buttons mount", false)
		return
	end
	io.warm()
	GuiService.SelectedObject = north
	t.settle(4)
	local visited = {}
	local watch = GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		table.insert(visited, selectedName())
	end)
	io.padHold("DPadDown", true)
	t.settle(4)
	local landed = selectedName()
	local stopLayout = layoutWatch(menu.panel)
	table.clear(visited)
	t.settle(60)
	local layoutChanges = stopLayout()
	local held = table.clone(visited)
	io.padHold("DPadDown", false)
	t.settle(4)
	watch:Disconnect()
	t.note("held d-pad", { landed = landed, during = held, layoutChanges = layoutChanges })
	t.check("the first DPadDown step leaves North", landed ~= "N" and landed ~= "nil", landed)
	t.check("there is still a stop below the one it landed on", landed ~= "S", landed)
	t.note("engine repeat stops during the hold", held)
	local inside = true
	for _, name in held do
		if not (menu.sectors[name] or name == "Center") then
			inside = false
		end
	end
	t.check("any engine repeat during the hold stays on the ring's own stops", inside, held)
	t.check("the held d-pad changes no ring geometry across 60 frames", layoutChanges == 0, layoutChanges)
	t.check("holding the d-pad fires no item", #menu.fired == 0, menu.fired)
	GuiService.SelectedObject = nil
end)

add("pad-radial-held-stick-rests", { "apps2-183" }, function(t)
	local io = device(t)
	local menu = radial(t)
	local south = menu.sectors.S.button
	if not south then
		t.check("the compass buttons mount", false)
		return
	end
	io.warm()
	GuiService.SelectedObject = south
	t.settle(4)
	local visited = {}
	local watch = GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		table.insert(visited, selectedName())
	end)
	io.padHold("StickUp", true)
	t.settle(12)
	local aimed = selectedName()
	table.clear(visited)
	local stopLayout = layoutWatch(menu.panel)
	t.settle(60)
	local layoutChanges = stopLayout()
	local held = table.clone(visited)
	io.padHold("StickUp", false)
	t.settle(6)
	watch:Disconnect()
	t.note("held stick", { aimed = aimed, during = held, layoutChanges = layoutChanges, afterRelease = selectedName() })
	t.check("the stick aim leaves South for a ring stop", aimed ~= "nil" and aimed ~= "S", aimed)
	t.check("there is still a stop above the one it landed on", aimed ~= "N", aimed)
	t.check("a held, unchanged stick moves the selection no further across 60 frames", #held == 0, held)
	t.check("a held, unchanged stick changes no ring geometry across 60 frames", layoutChanges == 0, layoutChanges)
	t.check("the menu is still open", t.visible(menu.panel))
	t.check("holding the stick fires no item", #menu.fired == 0, menu.fired)
	io.pad("DPadDown")
	t.check(
		"after release the d-pad steps the ring again",
		selectedName() ~= aimed and selectedName() ~= "nil",
		{ aimed, selectedName() }
	)
	GuiService.SelectedObject = nil
end)

local function union(a: any, b: any): any
	local x, y = math.min(a.x, b.x), math.min(a.y, b.y)
	local r, bottom = math.max(a.r, b.r), math.max(a.b, b.b)
	return { x = x, y = y, r = r, b = bottom, w = r - x, h = bottom - y }
end

add("radial-icons-centred-on-paint", { "apps2-198" }, function(t)
	for _, entry in t.themes do
		for _, scale in { 1, 1.5 } do
			for _, iconOnly in { false, true } do
				local where = `{entry.name} x{scale}{if iconOnly then " icon-only" else ""}`
				local menu =
					radial(t, { theme = entry.package, scale = if scale ~= 1 then scale else nil, iconOnly = iconOnly })
				for id, parts in menu.sectors do
					local button, paint = parts.button, parts.paint
					if not (button and paint) then
						t.check(`{where} {id} sector mounts`, false)
						continue
					end
					local icon = button:FindFirstChild("LeadingIcon", true)
					local title = button:FindFirstChild("Title", true)
					t.check(
						`{where} {id} has an image icon`,
						icon ~= nil and icon:IsA("ImageLabel") and icon.Image ~= ""
					)
					if not icon then
						continue
					end
					local b, i = t.rect(button), t.rect(icon)
					t.near(`{where} {id} icon is square`, i.w, i.h, 0.5)
					local metric = icon:GetStyled("Size").X.Offset
					t.near(`{where} {id} icon paints at the theme icon size`, i.w, metric * scale, 0.75)
					t.check(
						`{where} {id} icon is a usable square of at least {12 * scale} px`,
						i.w >= 12 * scale - 0.5,
						i.w
					)
					local content = if title and title.ContentText ~= "" then union(i, t.rect(title)) else i
					t.near(`{where} {id} content centred horizontally`, content.x + content.w / 2, b.x + b.w / 2, 1.5)
					t.near(`{where} {id} icon centred vertically`, i.y + i.h / 2, b.y + b.h / 2, 1.5)
					t.inside(`{where} {id} icon inside its button`, icon, button, 0.5)
					t.inside(`{where} {id} button on its painted surface`, button, paint, 1)
					if title and title.ContentText ~= "" then
						t.check(`{where} {id} label fits`, t.fits(title), { title.TextBounds, title.AbsoluteSize })
						t.near(
							`{where} {id} label centred vertically with the icon`,
							title.AbsolutePosition.Y + title.AbsoluteSize.Y / 2,
							i.y + i.h / 2,
							1.5
						)
					end
				end
				t.cleanup()
			end
		end
	end
end)

add("pad-radial-selection-on-paint", { "apps2-198" }, function(t)
	local io = device(t)
	local menu = radial(t)
	io.warm()
	GuiService.SelectedObject = menu.sectors.N.button
	t.settle(4)
	local seen = {}
	for _, key in { "DPadRight", "DPadDown", "DPadLeft", "StickUp" } do
		if key == "StickUp" then
			io.padHold(key, true)
			t.settle(8)
			io.padHold(key, false)
			t.settle(6)
		else
			io.pad(key)
		end
		local selected = GuiService.SelectedObject
		local parts = selected and menu.sectors[selected.Name]
		seen[key] = selectedName()
		t.check(`{key} selects a ring button`, parts ~= nil and parts.button == selected, selectedName())
		if parts and parts.paint then
			t.inside(
				`{key} the selection ring's target {selected.Name} sits on its painted surface`,
				selected,
				parts.paint,
				1
			)
			t.check(
				`{key} the selected button keeps the engine selection ring`,
				selected.Selectable and selected.SelectionImageObject == nil,
				selected.SelectionImageObject
			)
		end
	end
	t.note("selection walk", seen)
	GuiService.SelectedObject = nil
end)

interactive("radial-hot-switch-keeps-open", { "apps2-211" }, function(t)
	pcall(function()
		(game:GetService("StudioDeviceSimulatorService") :: any):StopSimulationAsync()
	end)
	t.settle(40)
	local io = device(t)
	local menu = radial(t)
	menu.io = io
	menu.open:set(false)
	t.settle(40)
	local launcher = t.find(menu.stage, "Launcher")
	t.check("the launcher mounts", launcher ~= nil)
	if launcher then
		io.click(centre(launcher))
		t.settle(40)
	end
	menu.panel = visibleNamed(t, menu.gui, "RadialPanel")
	t.check("a mouse click opens the ring", menu.panel ~= nil and menu.open:peek() == true)
	t.check(
		"the engine reports keyboard and mouse",
		UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse,
		UserInputService.PreferredInput
	)
	t.check("no gamepad is connected yet", not UserInputService.GamepadEnabled)
	return menu
end, {
	afterPlug = function(t, menu)
		t.settle(10)
		t.check("the Controller Emulator connected a gamepad", UserInputService.GamepadEnabled)
		menu.io.warm()
		t.settle(20)
		t.check(
			"a gamepad press flips the engine to gamepad",
			UserInputService.PreferredInput == Enum.PreferredInput.Gamepad,
			UserInputService.PreferredInput
		)
		t.check("the ring stays open across the flip to gamepad", menu.open:peek() == true and t.visible(menu.panel))
		menu.io.pad("DPadRight")
		t.check("the pad steers the ring that the mouse opened", menu.sectors[selectedName()] ~= nil, selectedName())
	end,
	afterUnplug = function(t, menu)
		t.settle(20)
		t.note(
			"after unplug",
			{ preferred = UserInputService.PreferredInput, gamepad = UserInputService.GamepadEnabled }
		)
		t.check("the gamepad is gone", not UserInputService.GamepadEnabled)
		t.check(
			"the engine leaves gamepad",
			UserInputService.PreferredInput ~= Enum.PreferredInput.Gamepad,
			UserInputService.PreferredInput
		)
		t.check("the ring stays open across the flip back", menu.open:peek() == true and t.visible(menu.panel))
		t.check("no item fired during the switches", #menu.fired == 0, menu.fired)
		GuiService.SelectedObject = nil
	end,
})

local function monitors(t: any, size: Vector2?, app: string): any
	local folder = storage:WaitForChild("VirtualMonitors")
	local screens = (require :: any)(folder:WaitForChild("screens"))
	local theme = (require :: any)(folder:WaitForChild("theme"))
	local modelModule = (require :: any)(folder:WaitForChild("model"))
	local package = theme.create(t.Facet, app)
	local value: any = {}
	value.stage = t.mount(function(_, _, Compose, env)
		local model = modelModule.new(Compose)
		Compose.cleanup(model.dispose)
		value.model = model
		local actions = { model = model, spatial = false, theme = package, reducedMotion = Compose.cell(true) }
		local views = screens.create(t.Facet, env.runtime, actions)
		model.selectedTab:set(app)
		return views[app]()
	end, { size = size, theme = package, palette = theme.paletteName("sage", true), frames = 30 })
	t.settle(20)
	return value
end

local function tableProbe(t: any): (any, any)
	local stage = t.mount(function(UI, _, Compose)
		return UI.Table "Scores" {
			from = { { id = "a", name = "Alpha" }, { id = "b", name = "Bravo" } },
			key = "id",
			widths = Compose.cell({}),
			Size = UDim2.fromOffset(400, 200),
			columns = {
				{ id = "name", label = "Name", width = 160, minWidth = 60, maxWidth = 300 },
			},
		}
	end, { size = Vector2.new(600, 400), frames = 20 })
	return t.find(stage, "Header"), t.find(stage, "Resize")
end

local function readTable(t: any, where: string, header: any, handle: any, height: number, grip: number)
	t.check(`{where}: the table header mounts`, header ~= nil)
	if header then
		t.near(`{where}: the table header is {height} px`, header.AbsoluteSize.Y, height, 0.5)
	end
	if handle then
		t.near(`{where}: the column resize grip is {grip} px wide`, handle.AbsoluteSize.X, grip, 0.5)
	else
		t.check(`{where}: the column resize grip mounts`, false)
	end
end

add("touch-vm-tap-leaves-no-ring", { "apps2-280" }, function(t)
	touch(t)
	local io = device(t)
	local value = monitors(t, nil, "Discover")
	local card
	for _, node in value.stage:GetDescendants() do
		if
			node:IsA("GuiButton")
			and t.visible(node)
			and string.find(node:GetFullName(), "Games", 1, true)
			and t.clipped(node)
		then
			card = node
			break
		end
	end
	t.check("a feed card is on screen", card ~= nil)
	if not card then
		return
	end
	GuiService.SelectedObject = nil
	t.settle(2)
	local box = t.clipped(card)
	io.click(Vector2.new(box.x + box.w / 2, box.y + box.h / 2))
	t.settle(20)
	t.note("after the tap", { selected = selectedName(), preferred = UserInputService.PreferredInput })
	t.check(
		"the engine reports touch",
		UserInputService.PreferredInput == Enum.PreferredInput.Touch,
		UserInputService.PreferredInput
	)
	t.check(
		"a touch tap selects nothing, so no selection ring is drawn",
		GuiService.SelectedObject == nil,
		selectedName()
	)
end)

interactive("input-fact-follows-device", { "apps2-280", "inputs-141" }, function(t)
	local simulator = game:GetService("StudioDeviceSimulatorService") :: any
	pcall(function()
		simulator:StopSimulationAsync()
	end)
	t.settle(40)
	local value: any = { io = device(t), simulator = simulator }
	t.check("a desktop without a pad has no gamepad", not UserInputService.GamepadEnabled)
	t.check(
		"a desktop without a pad prefers keyboard and mouse",
		UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse,
		UserInputService.PreferredInput
	)
	for _ = 1, 3 do
		value.io.click(Vector2.new(300, 300))
	end
	t.check(
		"pointer use keeps keyboard and mouse",
		UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse,
		UserInputService.PreferredInput
	)
	local header, handle = tableProbe(t)
	readTable(t, "desktop", header, handle, 40, 12)
	t.cleanup()
	return value
end, {
	afterPlug = function(t, value)
		t.settle(20)
		t.check("the Controller Emulator connected a gamepad", UserInputService.GamepadEnabled)
		value.io.warm()
		t.check(
			"a pad press makes the pad primary",
			UserInputService.PreferredInput == Enum.PreferredInput.Gamepad,
			UserInputService.PreferredInput
		)
		for index = 1, 10 do
			value.io.move(Vector2.new(200 + index * 7, 300))
		end
		t.settle(10)
		t.check(
			"mouse movement does not take the pad's primacy",
			UserInputService.PreferredInput == Enum.PreferredInput.Gamepad,
			UserInputService.PreferredInput
		)
		local header, handle = tableProbe(t)
		readTable(t, "desktop with a pad", header, handle, 44, 12)
		t.cleanup()
		value.simulator:SetDeviceAsync("xbox")
		t.settle(40)
		t.check("a console has no pointer", not UserInputService.MouseEnabled and not UserInputService.TouchEnabled)
		t.check(
			"a console prefers the pad",
			UserInputService.PreferredInput == Enum.PreferredInput.Gamepad,
			UserInputService.PreferredInput
		)
		local io = device(t)
		io.click(Vector2.new(300, 300))
		t.check(
			"a console stays on the pad whatever else arrives",
			UserInputService.PreferredInput == Enum.PreferredInput.Gamepad,
			UserInputService.PreferredInput
		)
		header, handle = tableProbe(t)
		readTable(t, "console", header, handle, 44, 12)
		t.cleanup()
		value.simulator:SetDeviceAsync("iphone_14")
		t.settle(60)
		t.check(
			"a phone prefers touch",
			UserInputService.PreferredInput == Enum.PreferredInput.Touch,
			UserInputService.PreferredInput
		)
		header, handle = tableProbe(t)
		readTable(t, "phone", header, handle, 44, 44)
		t.cleanup()
		value.simulator:SetDeviceAsync("xbox")
		t.settle(30)
	end,
})

add("pad-vm-navigation-selects", { "apps2-280" }, function(t)
	local io = device(t)
	local value = monitors(t, Vector2.new(1280, 720), "Discover")
	io.warm()
	GuiService.SelectedObject = nil
	t.settle(4)
	io.pad("DPadDown")
	t.settle(6)
	local first = GuiService.SelectedObject
	t.note("first selection", first and first:GetFullName())
	t.check(
		"with nothing selected, one DPadDown shows the selection on a Discover control",
		first ~= nil and first:IsDescendantOf(value.stage),
		first and first:GetFullName()
	)
	io.pad("DPadDown")
	t.check(
		"the next DPadDown moves it",
		GuiService.SelectedObject ~= nil and GuiService.SelectedObject ~= first,
		selectedName()
	)
	GuiService.SelectedObject = nil
end)

add("pad-temperature-a-enters-edit", { "apps2-30" }, function(t)
	local io = device(t)
	local _, built, field = temperatureField(t)
	if not field then
		return
	end
	io.warm()
	local stop = gamepadWatch()
	GuiService.SelectedObject = field
	t.settle(3)
	io.pad("ButtonA")
	t.check("gamepad A on the selected field enters editing", field:IsFocused())
	io.text("5")
	t.settle(2)
	t.check("typing edits the value", built.fahrenheitText() == "5", built.fahrenheitText())
	local seen = stop()
	t.note("gamepad events", seen)
	t.check("the press arrived as Gamepad1 ButtonA", table.find(seen, "ButtonA") ~= nil, seen)
	t.check("nothing is committed while editing", built.celsius() == nil, built.celsius())
	field:ReleaseFocus()
	t.settle(4)
	GuiService.SelectedObject = nil
end)

local function contexts(): { InputContext }
	local out = {}
	for _, node in Players.LocalPlayer.PlayerGui:GetDescendants() do
		if node:IsA("InputContext") then
			table.insert(out, node)
		end
	end
	return out
end

add("native-context-arbitration", { "inputs-97" }, function(t)
	local io = device(t)
	local value: any = { high = 0, low = 0, highReleased = 0 }
	local stage = t.mount(function(_, Host, Compose)
		value.highOn = Compose.cell(true)
		return Host.Frame "Root" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Host.InputContext "High" {
				Priority = 3000,
				Sink = true,
				Enabled = value.highOn,
				Host.InputAction "Hit" {
					Type = Enum.InputActionType.Bool,
					Pressed = function()
						value.high += 1
					end,
					Released = function()
						value.highReleased += 1
					end,
					Host.InputBinding({ KeyCode = Enum.KeyCode.X }),
				},
			},
			Host.InputContext "Low" {
				Priority = 1000,
				Sink = false,
				Host.InputAction "Hit" {
					Type = Enum.InputActionType.Bool,
					Pressed = function()
						value.low += 1
					end,
					Host.InputBinding({ KeyCode = Enum.KeyCode.X }),
				},
			},
		}
	end, { frames = 10 })
	local high, low = t.find(stage, "High"), t.find(stage, "Low")
	t.check("both native contexts mount", high ~= nil and low ~= nil)
	if not (high and low) then
		return
	end
	io.key(Enum.KeyCode.X)
	t.check(
		"the higher sink context takes the key and the lower does not",
		value.high == 1 and value.low == 0,
		{ value.high, value.low }
	)
	value.highOn:set(false)
	t.settle(3)
	io.key(Enum.KeyCode.X)
	t.check(
		"disabling the high context releases the key to the lower one",
		value.high == 1 and value.low == 1,
		{ value.high, value.low }
	)
	io.press(Enum.KeyCode.X, true)
	io.press(Enum.KeyCode.X, true)
	io.press(Enum.KeyCode.X, false)
	t.settle(3)
	t.check("a repeated identical key-down presses once", value.low == 2, value.low)
	value.highOn:set(true)
	t.settle(3)
	local lowAction = low:FindFirstChild("Hit") :: any
	lowAction:Fire(true)
	lowAction:Fire(false)
	t.settle(3)
	t.check(
		"a scripted Fire reaches the lower action even under the sink",
		value.low == 3 and value.high == 1,
		{ value.high, value.low }
	)
	local highAction = high:FindFirstChild("Hit") :: any
	io.press(Enum.KeyCode.X, true)
	t.settle(3)
	t.check("the held key holds the high action's Bool state", highAction:GetState() == true, highAction:GetState())
	value.highOn:set(false)
	t.settle(4)
	t.check("disabling the context resets its held Bool state", highAction:GetState() == false, highAction:GetState())
	t.note("releases after disable", value.highReleased)
	io.press(Enum.KeyCode.X, false)
	t.settle(3)
	low:Destroy()
	t.settle(2)
	local ok = pcall(function()
		io.key(Enum.KeyCode.X)
	end)
	t.check("a key for a destroyed context raises nothing", ok)
	t.check("a destroyed context delivers nothing", value.low == 3, value.low)
	local fired = pcall(function()
		lowAction:Fire(true)
		lowAction:Fire(false)
	end)
	t.note("scripted fire on a destroyed context", { ok = fired, low = value.low })
end)

local function shortcutPair(t: any): any
	local value: any = { plain = 0, shifted = 0 }
	t.mount(function(UI)
		return UI.VStack "Pair" {
			UI.Button "Plain" {
				label = "Plain K",
				shortcut = { keyCode = "K" },
				onActivate = function()
					value.plain += 1
				end,
			},
			UI.Button "Shifted" {
				label = "Shift K",
				shortcut = { keyCode = "K", modifiers = { shift = true } },
				onActivate = function()
					value.shifted += 1
				end,
			},
		}
	end, { frames = 12 })
	return value
end

add("modifier-shortcuts-and-key-up", { "inputs-100" }, function(t)
	local io = device(t)
	local value = shortcutPair(t)
	GuiService.SelectedObject = nil
	io.key(Enum.KeyCode.K)
	t.check(
		"plain K fires the plain shortcut only",
		value.plain == 1 and value.shifted == 0,
		{ value.plain, value.shifted }
	)
	io.press(Enum.KeyCode.LeftShift, true)
	io.key(Enum.KeyCode.K)
	io.press(Enum.KeyCode.LeftShift, false)
	t.settle(3)
	t.check(
		"Shift+K fires the shifted shortcut and preempts the plain one",
		value.shifted == 1 and value.plain == 1,
		{ value.plain, value.shifted }
	)
	io.key(Enum.KeyCode.K)
	t.check(
		"plain K works normally after a shifted press",
		value.plain == 2 and value.shifted == 1,
		{ value.plain, value.shifted }
	)
	io.press(Enum.KeyCode.RightShift, true)
	io.key(Enum.KeyCode.K)
	io.press(Enum.KeyCode.RightShift, false)
	t.settle(3)
	t.check(
		"the right Shift sibling fires the same shortcut",
		value.shifted == 2 and value.plain == 2,
		{ value.plain, value.shifted }
	)
	io.press(Enum.KeyCode.K, true)
	io.press(Enum.KeyCode.LeftShift, true)
	io.press(Enum.KeyCode.K, false)
	io.press(Enum.KeyCode.LeftShift, false)
	t.settle(3)
	io.key(Enum.KeyCode.K)
	t.check(
		"tapping Shift while plain K is held does not steal its key-up",
		value.plain == 4 and value.shifted == 2,
		{ value.plain, value.shifted }
	)
	io.press(Enum.KeyCode.LeftShift, true)
	io.press(Enum.KeyCode.K, true)
	io.press(Enum.KeyCode.LeftShift, false)
	io.press(Enum.KeyCode.K, false)
	t.settle(3)
	io.press(Enum.KeyCode.LeftShift, true)
	io.key(Enum.KeyCode.K)
	io.press(Enum.KeyCode.LeftShift, false)
	t.settle(3)
	t.check(
		"a chord whose Shift released first leaves no stuck state: the next chord fires",
		value.shifted == 4,
		{ value.plain, value.shifted }
	)
	io.press(Enum.KeyCode.LeftShift, true)
	t.settle(2)
	io.press(Enum.KeyCode.LeftShift, false)
	t.settle(2)
	io.key(Enum.KeyCode.K)
	t.check(
		"after an interrupted Shift the engine holds no modifier: plain K fires",
		value.plain == 5,
		{ value.plain, value.shifted }
	)
end)

add("editing-sinks-lower-navigation", { "inputs-145" }, function(t)
	local io = device(t)
	local moved = 0
	local _, value = fieldForm(t)
	local extra = t.mount(function(_, Host)
		return Host.InputContext "CharacterControls" {
			Priority = 1000,
			Sink = false,
			Host.InputAction "Move" {
				Type = Enum.InputActionType.Bool,
				Pressed = function()
					moved += 1
				end,
				Host.InputBinding({ KeyCode = Enum.KeyCode.Down }),
			},
		}
	end, { frames = 6 })
	t.check("the character context mounts", extra ~= nil)
	local field = value.field
	if not field then
		return
	end
	GuiService.SelectedObject = nil
	t.settle(2)
	io.key(Enum.KeyCode.Down)
	t.check("with nothing editing, Down reaches the lower gameplay context", moved == 1, moved)
	GuiService.SelectedObject = field
	t.settle(3)
	io.key(Enum.KeyCode.Return)
	t.check("Return enters editing", field:IsFocused())
	io.key(Enum.KeyCode.Down)
	io.key(Enum.KeyCode.Down)
	t.check("while editing, Down never reaches the lower context", moved == 1, moved)
	t.check("the selection stays on the field", GuiService.SelectedObject == field, selectedName())
	io.key(Enum.KeyCode.Return)
	t.check("Return ends the edit", not field:IsFocused())
	GuiService.SelectedObject = nil
	t.settle(3)
	io.key(Enum.KeyCode.Down)
	t.check("after the edit, Down reaches the lower context again", moved == 2, moved)
end)

add("actions-released-with-their-owner", { "mech3-36" }, function(t)
	local io = device(t)
	local baseline = #contexts()
	local fired = 0
	t.mount(function(UI)
		return UI.VStack "Owned" {
			UI.Button "Save" {
				label = "Save",
				shortcut = { keyCode = "K" },
				onActivate = function()
					fired += 1
				end,
			},
			UI.Button "Close" { label = "Close", dialogAction = "cancel" },
			UI.TextInput "Name" { value = "seed", onChange = function() end },
		}
	end, { frames = 12 })
	local mounted = #contexts()
	t.note("contexts", { baseline = baseline, mounted = mounted })
	t.check("the mounted controls own native input contexts", mounted > baseline, { baseline, mounted })
	io.key(Enum.KeyCode.K)
	t.check("the shortcut fires while mounted", fired == 1, fired)
	t.cleanup()
	t.settle(4)
	t.check(
		"unmounting destroys every context the controls created",
		#contexts() == baseline,
		{ baseline, #contexts() }
	)
	local ok = pcall(function()
		io.key(Enum.KeyCode.K)
	end)
	t.check("a key after teardown raises nothing", ok)
	t.check("a disposed control delivers nothing", fired == 1, fired)
end)

add("one-action-many-devices", { "mech3-40" }, function(t)
	local io = device(t)
	local fired = 0
	local stage = t.mount(function(UI)
		return UI.Button "Close" {
			label = "Close",
			shortcut = { keyCode = "K" },
			dialogAction = "cancel",
			onActivate = function()
				fired += 1
			end,
		}
	end, { frames = 12 })
	local action
	for _, context in contexts() do
		if context:IsDescendantOf(stage:FindFirstAncestorWhichIsA("LayerCollector")) then
			local found = context:FindFirstChild("Shortcut")
			if found then
				action = found
			end
		end
	end
	t.check("the button owns one Shortcut InputAction", action ~= nil)
	if not action then
		return
	end
	local keys = {}
	for _, binding in action:GetChildren() do
		if binding:IsA("InputBinding") then
			table.insert(keys, binding.KeyCode.Name)
		end
	end
	t.note("bindings", keys)
	t.check(
		"one action carries a keyboard and a gamepad binding",
		table.find(keys, "K") ~= nil and table.find(keys, "ButtonB") ~= nil,
		keys
	)
	io.key(Enum.KeyCode.K)
	t.check("the keyboard binding fires the action", fired == 1, fired)
	local button = t.find(stage, "Close")
	io.click(centre(button))
	t.check("a pointer press on the same control fires it", fired == 2, fired)
end)

add("pad-one-action-many-devices", { "mech3-40" }, function(t)
	local io = device(t)
	local fired = 0
	t.mount(function(UI)
		return UI.Button "Close" {
			label = "Close",
			shortcut = { keyCode = "K" },
			dialogAction = "cancel",
			onActivate = function()
				fired += 1
			end,
		}
	end, { frames = 12 })
	io.warm()
	GuiService.SelectedObject = nil
	t.settle(2)
	local stop = gamepadWatch()
	io.pad("ButtonB")
	t.note("gamepad events", stop())
	t.check("Gamepad1 ButtonB fires the same action", fired == 1, fired)
end)

add("touch-one-action-many-devices", { "mech3-40" }, function(t)
	touch(t)
	local io = device(t)
	local fired = 0
	local stage = t.mount(function(UI, Host)
		return Host.Frame "Holder" {
			Position = UDim2.fromOffset(40, 240),
			Size = UDim2.fromOffset(200, 100),
			BackgroundTransparency = 1,
			UI.Button "Close" {
				label = "Close",
				shortcut = { keyCode = "K" },
				dialogAction = "cancel",
				onActivate = function()
					fired += 1
				end,
			},
		}
	end, { frames = 12 })
	io.click(centre(t.find(stage, "Close")))
	t.check("a touch tap fires the same control once", fired == 1, fired)
end)

local function hoverProbe(t: any, value: any): any
	return t.mount(function(UI, Host)
		return Host.Frame "Holder" {
			Position = UDim2.fromOffset(40, 240),
			Size = UDim2.fromOffset(300, 200),
			BackgroundTransparency = 1,
			UI.VStack "Column" {
				UI.Button "Go" {
					label = "Go",
					help = "Starts the race",
					onActivate = function()
						value.activated += 1
					end,
				},
				UI.Text "Caption" { text = "A caption" },
			},
		}
	end, { frames = 12 })
end

local function guiStates(node: GuiObject): { string }
	local seen = {}
	node:GetPropertyChangedSignal("GuiState"):Connect(function()
		table.insert(seen, node.GuiState.Name)
	end)
	return seen
end

local function fill(node: any): string
	return `{node:GetStyled("BackgroundColor3")}|{node:GetStyled("BackgroundTransparency")}`
end

local function paint(node: any): string
	return `{node:GetStyled("TextColor3")}|{node:GetStyled("BackgroundColor3")}|{node:GetStyled(
		"BackgroundTransparency"
	)}|{node:GetStyled("TextTransparency")}`
end

add("hover-follows-the-pointer", { "inputs-133", "paint-102" }, function(t)
	local io = device(t)
	local value = { activated = 0 }
	local stage = hoverProbe(t, value)
	local go, caption = t.find(stage, "Go"), t.find(stage, "Caption")
	t.check("the button and caption mount", go ~= nil and caption ~= nil)
	if not (go and caption) then
		return
	end
	io.move(Vector2.new(5, 5))
	t.settle(10)
	local rest = fill(go)
	io.move(centre(go))
	io.move(centre(go) + Vector2.new(2, 0))
	t.settle(10)
	t.check(
		"a resting mouse puts the button in the engine Hover state",
		go.GuiState == Enum.GuiState.Hover,
		go.GuiState
	)
	local hovered = fill(go)
	t.note("rest and hover fills", { rest = rest, hover = hovered })
	t.check("the hover StyleRule paints a fill distinct from rest", hovered ~= rest, { rest, hovered })
	io.move(Vector2.new(5, 5))
	t.settle(10)
	local calm = paint(caption)
	io.move(centre(caption))
	io.move(centre(caption) + Vector2.new(2, 0))
	t.settle(10)
	t.note("caption state under the mouse", caption.GuiState)
	t.check(
		"a non-interactive caption paints nothing different under the mouse",
		paint(caption) == calm,
		{ calm, paint(caption) }
	)
	io.move(Vector2.new(5, 5))
	t.settle(10)
	t.check(
		"leaving returns the button to rest",
		go.GuiState == Enum.GuiState.Idle and fill(go) == rest,
		{ go.GuiState, fill(go) }
	)
	io.click(centre(go))
	t.check("a click activates the button once", value.activated == 1, value.activated)
end)

add("touch-never-hovers", { "inputs-133", "paint-102" }, function(t)
	touch(t)
	local io = device(t)
	local value = { activated = 0 }
	local stage = hoverProbe(t, value)
	local go = t.find(stage, "Go")
	if not go then
		t.check("the button mounts", false)
		return
	end
	t.settle(10)
	local rest = fill(go)
	local states = guiStates(go)
	io.click(centre(go))
	t.settle(40)
	t.note("touch states", states)
	t.check("a touch tap never puts the button in the Hover state", table.find(states, "Hover") == nil, states)
	t.check(
		"the tap still activates the button: nothing essential is behind hover",
		value.activated == 1,
		value.activated
	)
	t.check("the button settles back to its rest fill", fill(go) == rest, { fill(go), rest })
	local gui = stage:FindFirstAncestorWhichIsA("LayerCollector")
	t.check("no help panel shows on touch", visibleNamed(t, gui, "HelpText") == nil)
end)

interactive("hover-arrives-with-a-mouse", { "inputs-133" }, function(t)
	touch(t)
	local value: any = { activated = 0 }
	value.stage = hoverProbe(t, value)
	value.go = t.find(value.stage, "Go")
	t.check("the button mounts on the phone", value.go ~= nil)
	return value
end, {
	afterDesktop = function(t, value)
		t.settle(20)
		t.check("the device now has a mouse", UserInputService.MouseEnabled)
		local io = device(t)
		io.move(Vector2.new(5, 5))
		t.settle(6)
		local rest = fill(value.go)
		io.move(centre(value.go))
		io.move(centre(value.go) + Vector2.new(2, 0))
		t.settle(10)
		t.check(
			"the button mounted under touch hovers when a mouse joins",
			value.go.GuiState == Enum.GuiState.Hover,
			value.go.GuiState
		)
		t.check("and paints its hover fill", fill(value.go) ~= rest, { rest, fill(value.go) })
	end,
})

add("help-leaves-with-its-surface", { "inputs-94" }, function(t)
	local io = device(t)
	local open
	local stage = t.mount(function(UI, _, Compose)
		open = Compose.cell(true)
		return UI.Sheet "Editor" {
			isPresented = open,
			detent = Compose.cell("medium"),
			title = "Editor",
			content = function()
				return UI.Button "Post" { label = "Post", help = "Posts this avatar" }
			end,
		}
	end, { frames = 30 })
	local gui = stage:FindFirstAncestorWhichIsA("LayerCollector")
	local post = visibleNamed(t, gui, "Post")
	t.check("the sheet shows its Post button", post ~= nil)
	if not post then
		return
	end
	io.move(centre(post))
	io.move(centre(post) + Vector2.new(1, 0))
	t.settle(50)
	local text = visibleNamed(t, gui, "HelpText")
	t.check(
		"resting the mouse shows the help",
		text ~= nil and text.ContentText == "Posts this avatar",
		text and text.ContentText
	)
	open:set(false)
	t.settle(40)
	t.check("dismissing the surface takes its help with it", visibleNamed(t, gui, "HelpText") == nil)
	t.check("and its button", visibleNamed(t, gui, "Post") == nil)
end)

local function sliderProbe(t: any): (any, any)
	local value
	local stage = t.mount(function(UI, Host, Compose)
		value = Compose.cell(0)
		return Host.Frame "Holder" {
			Position = UDim2.fromOffset(40, 300),
			Size = UDim2.fromOffset(300, 80),
			BackgroundTransparency = 1,
			UI.Slider "Vol" { value = value, min = 0, max = 100, Size = UDim2.fromOffset(300, 44) },
		}
	end, { frames = 12 })
	return stage, value
end

local function sliderDrag(t: any, io: any, stage: any, value: any, where: string)
	local track = t.find(stage, "Track")
	t.check(`{where}: the track mounts`, track ~= nil)
	if not track then
		return
	end
	local r = t.rect(track)
	local y = r.y + r.h / 2
	io.drag(Vector2.new(r.x + 1, y), Vector2.new(r.x + r.w / 2, y), 16)
	t.settle(10)
	t.note(`{where} value`, value:peek())
	t.near(`{where}: a drag to the middle of the track sets the middle value`, value:peek(), 50, 3)
end

add("slider-mouse-drag", { "inputs-223" }, function(t)
	local io = device(t)
	local stage, value = sliderProbe(t)
	sliderDrag(t, io, stage, value, "mouse")
end)

add("touch-slider-drag", { "inputs-223" }, function(t)
	touch(t)
	local io = device(t)
	local stage, value = sliderProbe(t)
	sliderDrag(t, io, stage, value, "touch")
end)

add("pad-table-row-a-selects", { "inputs-05" }, function(t)
	local io = device(t)
	local selection
	local stage = t.mount(function(UI, _, Compose)
		selection = Compose.cell({})
		return UI.Table "Scores" {
			from = { { id = "a", name = "Alpha" }, { id = "b", name = "Bravo" }, { id = "c", name = "Charlie" } },
			key = "id",
			selection = selection,
			selectionMode = "multi",
			Size = UDim2.fromOffset(400, 240),
			columns = { { id = "name", label = "Name" } },
		}
	end, { size = Vector2.new(600, 400), frames = 20 })
	local rows = {}
	for _, node in stage:GetDescendants() do
		if
			node:IsA("GuiButton")
			and node.Selectable
			and t.visible(node)
			and string.find(node:GetFullName(), "Body", 1, true)
		then
			table.insert(rows, node)
		end
	end
	table.sort(rows, function(a, b)
		return a.AbsolutePosition.Y < b.AbsolutePosition.Y
	end)
	t.check("the table rows are selection stops", #rows >= 3, #rows)
	if #rows < 2 then
		return
	end
	io.warm()
	local stop = gamepadWatch()
	GuiService.SelectedObject = rows[1]
	t.settle(3)
	io.pad("ButtonA")
	t.check("gamepad A on the first row selects it", selection:peek().a == true, selection:peek())
	io.pad("DPadDown")
	t.check("DPadDown moves to the next row", GuiService.SelectedObject ~= rows[1], selectedName())
	io.pad("ButtonA")
	t.check(
		"gamepad A adds the second row",
		selection:peek().a == true and selection:peek().b == true,
		selection:peek()
	)
	io.pad("ButtonA")
	t.check("gamepad A again removes it", selection:peek().b ~= true, selection:peek())
	t.note("gamepad events", stop())
	GuiService.SelectedObject = nil
end)

return cases
