--!strict

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

export type Style = "primary" | "secondary" | "success" | "danger" | "ghost"

export type Modal = {
	scrim: TextButton,
	panel: Frame,
	header: Frame,
	title: TextLabel,
	body: Frame,
	close: TextButton,
	isOpen: () -> boolean,
	setOpen: (open: boolean, focus: GuiObject?) -> (),
	onClosed: (callback: () -> ()) -> (),
	hides: (object: GuiObject) -> (),
}

local Kit = {}

Kit.colors = {
	scrim = Color3.fromRGB(6, 8, 14),
	panel = Color3.fromRGB(22, 26, 36),
	card = Color3.fromRGB(36, 42, 56),
	cardRaised = Color3.fromRGB(48, 56, 74),
	text = Color3.fromRGB(244, 246, 250),
	muted = Color3.fromRGB(184, 192, 210),
	primary = Color3.fromRGB(255, 196, 64),
	primaryText = Color3.fromRGB(26, 20, 4),
	secondary = Color3.fromRGB(58, 66, 86),
	secondaryText = Color3.fromRGB(244, 246, 250),
	success = Color3.fromRGB(34, 110, 70),
	successText = Color3.fromRGB(240, 255, 246),
	danger = Color3.fromRGB(176, 40, 48),
	dangerText = Color3.fromRGB(255, 255, 255),
	info = Color3.fromRGB(28, 80, 140),
	infoText = Color3.fromRGB(240, 246, 255),
	rarity = {
		Common = Color3.fromRGB(150, 158, 172),
		Rare = Color3.fromRGB(90, 155, 240),
		Epic = Color3.fromRGB(190, 120, 245),
		Legendary = Color3.fromRGB(240, 170, 40),
	} :: { [string]: Color3 },
}

Kit.font = Font.fromEnum(Enum.Font.BuilderSans)
Kit.bold = Font.new(Kit.font.Family, Enum.FontWeight.Bold)

Kit.size = { title = 26, heading = 20, body = 18, small = 16 }
Kit.space = { small = 8, medium = 12, large = 16 }

function Kit.create(className: string, properties: { [string]: unknown }, children: { Instance }?): Instance
	local instance = Instance.new(className)
	local writable = (instance :: unknown) :: { [string]: unknown }
	for key, value in properties do
		if key ~= "Parent" then
			writable[key] = value
		end
	end
	if children ~= nil then
		for _, child in children do
			child.Parent = instance
		end
	end
	if properties.Parent ~= nil then
		instance.Parent = properties.Parent :: Instance
	end
	return instance
end

function Kit.corner(radius: number): Instance
	return Kit.create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

function Kit.padding(all: number): Instance
	return Kit.create("UIPadding", {
		PaddingLeft = UDim.new(0, all),
		PaddingRight = UDim.new(0, all),
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
	})
end

function Kit.list(direction: Enum.FillDirection, gap: number, horizontal: Enum.HorizontalAlignment?): Instance
	return Kit.create("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = horizontal or Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
	})
end

function Kit.isTenFoot(): boolean
	return GuiService:IsTenFootInterface() or (UserInputService.GamepadEnabled and not UserInputService.TouchEnabled)
end

function Kit.usesGamepad(): boolean
	if Kit.isTenFoot() then
		return true
	end
	local last = UserInputService:GetLastInputType()
	return last == Enum.UserInputType.Gamepad1
end

function Kit.focus(target: GuiObject?)
	if false and target ~= nil and Kit.usesGamepad() then
		GuiService.SelectedObject = target
	end
end

function Kit.label(text: string, size: number?, color: Color3?, bold: boolean?): TextLabel
	return Kit.create("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size or Kit.size.body,
		TextColor3 = color or Kit.colors.text,
		FontFace = if bold then Kit.bold else Kit.font,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
	}) :: TextLabel
end

function Kit.button(text: string, style: Style?): TextButton
	local chosen: Style = style or "secondary"
	local fill = if chosen == "primary"
		then Kit.colors.primary
		elseif chosen == "success" then Kit.colors.success
		elseif chosen == "danger" then Kit.colors.danger
		elseif chosen == "ghost" then Kit.colors.card
		else Kit.colors.secondary
	local ink = if chosen == "primary"
		then Kit.colors.primaryText
		elseif chosen == "success" then Kit.colors.successText
		elseif chosen == "danger" then Kit.colors.dangerText
		else Kit.colors.secondaryText
	return Kit.create("TextButton", {
		Text = text,
		TextSize = Kit.size.body,
		FontFace = Kit.bold,
		TextColor3 = ink,
		BackgroundColor3 = fill,
		AutoButtonColor = true,
		Selectable = false,
		Size = UDim2.new(1, 0, 0, 48),
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, { Kit.corner(10), Kit.padding(Kit.space.small) }) :: TextButton
end

function Kit.input(placeholder: string): TextBox
	return Kit.create("TextBox", {
		Text = "",
		PlaceholderText = placeholder,
		PlaceholderColor3 = Kit.colors.muted,
		ClearTextOnFocus = false,
		TextSize = Kit.size.body,
		FontFace = Kit.font,
		TextColor3 = Kit.colors.text,
		BackgroundColor3 = Kit.colors.card,
		TextXAlignment = Enum.TextXAlignment.Left,
		Selectable = false,
		Size = UDim2.new(1, 0, 0, 48),
	}, {
		Kit.corner(10),
		Kit.padding(Kit.space.medium),
		Kit.create("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Kit.colors.muted,
			Thickness = 1,
		}),
	}) :: TextBox
end

function Kit.card(): Frame
	return Kit.create("Frame", {
		BackgroundColor3 = Kit.colors.card,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, { Kit.corner(12), Kit.padding(Kit.space.medium) }) :: Frame
end

function Kit.scroller(): ScrollingFrame
	return Kit.create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Kit.colors.muted,
		Selectable = false,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	}) :: ScrollingFrame
end

function Kit.screen(playerGui: PlayerGui, name: string): ScreenGui
	return Kit.create("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		Parent = playerGui,
	}) :: ScreenGui
end

function Kit.scale(screen: ScreenGui): UIScale
	local scale = Kit.create("UIScale", { Parent = screen }) :: UIScale
	local function update()
		local size = screen.AbsoluteSize
		local short = math.min(size.X, size.Y)
		if Kit.isTenFoot() then
			scale.Scale = 1.25
		else
			scale.Scale = 1
		end
	end
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	update()
	return scale
end

function Kit.hud(screen: ScreenGui): Frame
	return Kit.create("Frame", {
		Name = "Hud",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Kit.space.large, 0, Kit.space.large),
		Size = UDim2.fromOffset(150, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = screen,
	}, { Kit.list(Enum.FillDirection.Vertical, Kit.space.small, Enum.HorizontalAlignment.Right) }) :: Frame
end

function Kit.modal(screen: ScreenGui, name: string, title: string, maxSize: Vector2?): Modal
	local limit = maxSize or Vector2.new(760, 620)
	local scrim = Kit.create("TextButton", {
		Name = name .. "Scrim",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		Interactable = not Kit.isTenFoot(),
		BackgroundColor3 = Kit.colors.scrim,
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 10,
		Parent = screen,
	}) :: TextButton
	local panel = Kit.create("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.94, 0.9),
		BackgroundColor3 = Kit.colors.panel,
		Visible = false,
		ZIndex = 11,
		Parent = screen,
	}, {
		Kit.corner(16),
		Kit.padding(Kit.space.large),
		Kit.create("UISizeConstraint", { MaxSize = limit, MinSize = Vector2.new(720, 620) }),
		Kit.create("UIStroke", { Color = Kit.colors.cardRaised, Thickness = 1 }),
	}) :: Frame
	local header = Kit.create("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 48),
		ZIndex = 11,
		Parent = panel,
	}) :: Frame
	local titleLabel = Kit.label(title, Kit.size.title, Kit.colors.text, true)
	titleLabel.Name = "Title"
	titleLabel.AutomaticSize = Enum.AutomaticSize.None
	titleLabel.Size = UDim2.new(1, -120, 1, 0)
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.TextWrapped = false
	titleLabel.Parent = header
	local close = Kit.button("Close", "secondary")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Size = UDim2.fromOffset(110, 48)
	close.Parent = header
	local body = Kit.create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 48 + Kit.space.medium),
		Size = UDim2.new(1, 0, 1, -(48 + Kit.space.medium)),
		ClipsDescendants = false,
		Parent = panel,
	}) :: Frame
	local open = false
	local closedCallbacks: { () -> () } = {}
	local covered: { GuiObject } = {}
	local previous: GuiObject? = nil
	local modal: Modal
	modal = {
		scrim = scrim,
		panel = panel,
		header = header,
		title = titleLabel,
		body = body,
		close = close,
		isOpen = function(): boolean
			return open
		end,
		setOpen = function(value: boolean, focus: GuiObject?)
			if value == open then
				return
			end
			open = value
			scrim.Visible = value
			panel.Visible = value
			for _, object in covered do
				object.Visible = not value
			end
			if value then
				previous = GuiService.SelectedObject
				Kit.focus(focus or close)
			else
				if GuiService.SelectedObject ~= nil and GuiService.SelectedObject:IsDescendantOf(panel) then
					GuiService.SelectedObject = nil
					Kit.focus(previous)
				end
				for _, callback in closedCallbacks do
					callback()
				end
			end
		end,
		onClosed = function(callback: () -> ())
			table.insert(closedCallbacks, callback)
		end,
		hides = function(object: GuiObject)
			table.insert(covered, object)
			object.Visible = not open
		end,
	}
	close.Activated:Connect(function()
		modal.setOpen(false)
	end)
	scrim.Activated:Connect(function()
		modal.setOpen(false)
	end)
	panel.SelectionGroup = true
	return modal
end

function Kit.number(amount: number): string
	local text = tostring(math.floor(amount))
	while true do
		local replaced, count = string.gsub(text, "^(-?%d+)(%d%d%d)", "%1,%2")
		text = replaced
		if count == 0 then
			break
		end
	end
	return text
end

function Kit.short(amount: number): string
	local absolute = math.abs(amount)
	local sizes = { 1e9, 1e6, 1e3 }
	local suffixes = { "B", "M", "K" }
	for index, size in sizes do
		if absolute >= size then
			local value = math.floor(amount / size * 100) / 100
			local text = string.format("%.2f", value)
			text = string.gsub(text, "%.?0+$", "")
			return text .. suffixes[index]
		end
	end
	return Kit.number(amount)
end

function Kit.clock(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	local hours = total // 3600
	local minutes = (total % 3600) // 60
	local rest = total % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, rest)
	end
	return string.format("%d:%02d", minutes, rest)
end

function Kit.message(parent: Instance): (TextLabel, (text: string?, style: Style?) -> ())
	local note = Kit.label("", Kit.size.body, Kit.colors.text, true)
	note.Name = "Message"
	note.Visible = false
	note.BackgroundTransparency = 0
	note.BackgroundColor3 = Kit.colors.danger
	note.TextXAlignment = Enum.TextXAlignment.Center
	note.Parent = parent
	Kit.corner(10).Parent = note
	Kit.padding(Kit.space.medium).Parent = note
	local function show(text: string?, style: Style?)
		if text == nil then
			note.Visible = false
			return
		end
		note.Text = text
		note.BackgroundColor3 = if style == "success" then Kit.colors.success else Kit.colors.danger
		note.TextColor3 = if style == "success" then Kit.colors.successText else Kit.colors.dangerText
		note.Visible = true
	end
	return note, show
end

local baseScreen = Kit.screen
local baseScale = Kit.scale
local baseModal = Kit.modal
local sharedScreen: ScreenGui? = nil
local sharedScale: UIScale? = nil
local dock: Frame? = nil
local stack: { Modal } = {}
local panels: { [string]: Modal } = {}
local backs: { [Modal]: () -> () } = {}
function Kit.bindBack(modal: Modal, action: () -> ())
	backs[modal] = action
end
function Kit.openPanel(title: string)
	local panel = panels[title]
	if panel ~= nil then
		panel.setOpen(true)
	end
end
function Kit.screen(playerGui: PlayerGui, name: string): ScreenGui
	if name == "RoundInterface" then
		local roundScreen = baseScreen(playerGui, name)
		roundScreen.DisplayOrder = -1
		return roundScreen
	end
	if sharedScreen == nil then
		sharedScreen = baseScreen(playerGui, "RacingHub")
	end
	return sharedScreen :: ScreenGui
end
function Kit.scale(screen: ScreenGui): UIScale
	if screen ~= sharedScreen then
		return baseScale(screen)
	end
	if sharedScale == nil then
		sharedScale = baseScale(screen)
	end
	return sharedScale :: UIScale
end
function Kit.hud(screen: ScreenGui): Frame
	if dock ~= nil then
		return dock :: Frame
	end
	task.spawn(function()
		local playerGui = screen.Parent
		if playerGui == nil then
			return
		end
		local touch = playerGui:WaitForChild("TouchGui", 10)
		local controls = if touch then touch:WaitForChild("TouchControlFrame", 10) else nil
		local jump = if controls then controls:WaitForChild("JumpButton", 10) else nil
		if jump == nil or not jump:IsA("GuiObject") then
			return
		end
		local overlay = Instance.new("ScreenGui")
		overlay.ScreenInsets = Enum.ScreenInsets.None
		overlay.DisplayOrder = 50
		overlay.Parent = screen.Parent
		local action = Kit.button("Quick action")
		action.Parent = overlay
		game:GetService("RunService").RenderStepped:Connect(function()
			action.Position = UDim2.fromOffset(jump.AbsolutePosition.X, jump.AbsolutePosition.Y)
			action.Size = UDim2.fromOffset(jump.AbsoluteSize.X, jump.AbsoluteSize.Y)
			action.Visible = jump.Visible
		end)
	end)
	local frame = Kit.create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 96),
		Size = UDim2.new(0, 156, 1, -112),
		Parent = screen,
	}) :: Frame
	local scroll = Kit.scroller()
	scroll.Parent = frame
	local body = Kit.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = scroll,
	}, { Kit.list(Enum.FillDirection.Vertical, 8) }) :: Frame
	dock = body
	return body
end
function Kit.modal(screen: ScreenGui, name: string, title: string, maxSize: Vector2?): Modal
	local modal = baseModal(screen, name, title, maxSize)
	panels[title] = modal
	local original = modal.setOpen
	local previous: GuiObject? = nil
	modal.hides = function(_object: GuiObject) end
	modal.setOpen = function(open: boolean, focus: GuiObject?)
		if open == modal.isOpen() then
			return
		end
		if open then
			previous = GuiService.SelectedObject
			local top = stack[#stack]
			if top ~= nil then
				top.panel.Visible = false
				top.scrim.Visible = false
			end
			table.insert(stack, modal)
			modal.panel.ZIndex = 10 + #stack * 2
			modal.scrim.ZIndex = modal.panel.ZIndex - 1
			original(true, focus)
		else
			local index = table.find(stack, modal)
			if index ~= nil then
				table.remove(stack, index)
			end
			original(false)
			local top = stack[#stack]
			if top ~= nil then
				top.panel.Visible = true
				top.scrim.Visible = true
			end
			Kit.focus(previous)
		end
	end
	modal.panel.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	modal.panel.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	modal.panel.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	modal.panel.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	return modal
end
game:GetService("ContextActionService")
	:BindActionAtPriority("HubBack", function(_: string, state: Enum.UserInputState): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin and #stack > 0 then
			local top = stack[#stack]
			local back = backs[top]
			if back ~= nil then
				back()
			else
				top.setOpen(false)
			end
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
return Kit
