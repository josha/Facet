--!strict

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

export type Style = "primary" | "secondary" | "success" | "danger" | "ghost"

export type Modal = {
	scrim: TextButton,
	backdrop: Frame,
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
	panel = Color3.fromRGB(15, 20, 38),
	card = Color3.fromRGB(28, 35, 58),
	cardRaised = Color3.fromRGB(48, 56, 74),
	text = Color3.fromRGB(244, 246, 250),
	muted = Color3.fromRGB(184, 192, 210),
	primary = Color3.fromRGB(70, 235, 255),
	primaryText = Color3.fromRGB(5, 24, 32),
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
	return UserInputService.PreferredInput == Enum.PreferredInput.Gamepad
end

function Kit.focus(target: GuiObject?)
	if target ~= nil and Kit.usesGamepad() and target.Selectable and target.Interactable then
		local ancestor: Instance? = target
		while ancestor and not ancestor:IsA("PlayerGui") do
			if ancestor:IsA("GuiObject") and not ancestor.Visible then
				return
			end
			if ancestor:IsA("ScreenGui") and not ancestor.Enabled then
				return
			end
			ancestor = ancestor.Parent
		end
		if ancestor == nil then
			return
		end
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
		Selectable = true,
		Size = UDim2.new(1, 0, 0, 48),
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, { Kit.corner(10), Kit.padding(Kit.space.small) }) :: TextButton
end

function Kit.badge(button: TextButton, text: string): TextLabel
	local badge = Kit.label(text, Kit.size.small, Kit.colors.primaryText, true)
	badge.AutomaticSize = Enum.AutomaticSize.None
	badge.AnchorPoint = Vector2.new(1, 0.5)
	badge.Position = UDim2.new(1, -4, 0.5, 0)
	badge.Size = UDim2.fromOffset(64, 24)
	badge.BackgroundTransparency = 0
	badge.BackgroundColor3 = Kit.colors.primary
	badge.TextXAlignment = Enum.TextXAlignment.Center
	badge.ZIndex = 3
	Kit.corner(12).Parent = badge
	badge.Parent = button
	return badge
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
		Selectable = true,
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
	local scrimScreen = Kit.create("ScreenGui", {
		Name = name .. "Backdrop",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.None,
		ClipToDeviceSafeArea = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1,
		Parent = screen.Parent,
	}) :: ScreenGui
	local panelScreen = Kit.create("ScreenGui", {
		Name = name .. "Content",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 2,
		Parent = screen.Parent,
	}) :: ScreenGui
	Kit.scale(panelScreen)
	local backdrop = Kit.create("Frame", {
		Name = name .. "Dim",
		BackgroundColor3 = Kit.colors.scrim,
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = scrimScreen,
	}) :: Frame
	local scrim = Kit.create("TextButton", {
		Name = name .. "Scrim",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		Interactable = not Kit.isTenFoot() and not UserInputService.TouchEnabled,
		BackgroundColor3 = Kit.colors.scrim,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 10,
		Parent = panelScreen,
	}) :: TextButton
	local panel = Kit.create("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.94, 0.9),
		BackgroundColor3 = Kit.colors.panel,
		Visible = false,
		ZIndex = 11,
		Parent = panelScreen,
	}, {
		Kit.corner(16),
		Kit.padding(Kit.space.large),
		Kit.create("UISizeConstraint", { MaxSize = limit, MinSize = Vector2.new(280, 240) }),
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
		backdrop = backdrop,
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
			backdrop.Visible = value
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
local backContext = script.Parent.Parent.KartInput.Back
local panels: { [string]: Modal } = {}
local backs: { [Modal]: () -> () } = {}
type Controls = { Enable: (Controls) -> (), Disable: (Controls) -> () }
local controls: Controls? = nil
local function modalControls()
	backContext.Enabled = #stack > 0
	if not UserInputService.TouchEnabled then
		return
	end
	if controls == nil then
		local scripts = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts")
		local module =
			require(scripts:WaitForChild("PlayerModule") :: ModuleScript) :: { GetControls: (unknown) -> Controls }
		controls = module:GetControls()
	end
	local active = controls :: Controls
	if #stack > 0 then
		active:Disable()
	else
		active:Enable()
	end
end
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
	local topbar = Kit.create("ScreenGui", {
		Name = "HubActions",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = screen.Parent,
	}) :: ScreenGui
	local frame = Kit.create("Frame", {
		BackgroundTransparency = 1,
		Visible = false,
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(0, 0),
		Parent = topbar,
	}) :: Frame
	local body = Kit.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = frame,
	}) :: Frame
	Kit.list(Enum.FillDirection.Horizontal, Kit.space.small, Enum.HorizontalAlignment.Right).Parent = body
	body.SelectionGroup = true
	local function resize()
		local scale = if Kit.isTenFoot() then 1.25 else 1
		local band = GuiService.TopbarInset.Height
		local diameter = (
			if band > 0
				then math.round(band * (if GuiService:IsTenFootInterface() then 0.5 else 0.75))
				else Kit.size.body + Kit.space.medium * 2
		)
		local labelHeight = Kit.size.body * scale * 1.5
		local width = 0
		local actions: { TextButton } = {}
		for _, row in body:GetChildren() do
			if row:IsA("Frame") and row.Name == "HudAction" then
				local control = row:FindFirstChildWhichIsA("TextButton")
				local caption = if control then control:FindFirstChild("ActionLabel") else nil
				if control and caption and caption:IsA("TextLabel") then
					local cellWidth =
						math.max(diameter, Kit.size.body * scale * (if caption.Text == "Garage" then 3.25 else 2.5))
					local captionHeight = if string.find(caption.Text, " ") then labelHeight * 2 else labelHeight
					caption.TextSize = Kit.size.body * scale
					row.Size = UDim2.fromOffset(cellWidth, diameter + captionHeight)
					control.Position = UDim2.fromOffset((cellWidth - diameter) / 2, 0)
					control.Size = UDim2.fromOffset(diameter, diameter)
					caption.Position = UDim2.fromOffset((diameter - cellWidth) / 2, diameter + Kit.space.small / 2)
					caption.Size = UDim2.fromOffset(cellWidth, captionHeight)
					if row.Visible then
						width += cellWidth + Kit.space.small
						table.insert(actions, control)
					end
				end
			end
		end
		table.sort(actions, function(a: TextButton, b: TextButton)
			return (a.Parent :: Frame).LayoutOrder < (b.Parent :: Frame).LayoutOrder
		end)
		for index, control in actions do
			control.NextSelectionLeft = actions[index - 1]
			control.NextSelectionRight = actions[index + 1]
		end
		frame.Position = UDim2.new(1, 0, 0, band - Kit.space.small / 4 - diameter)
		frame.Size =
			UDim2.fromOffset(math.max(0, width - Kit.space.small), diameter + labelHeight + Kit.space.small / 2)
		frame.Visible = screen:GetAttribute("ModalOpen") ~= true
	end
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	screen:GetAttributeChangedSignal("ModalOpen"):Connect(resize)
	game:GetService("RunService").PreRender:Connect(resize)
	resize()
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
			local overflow = stack[#stack]
			if overflow ~= nil and overflow.title.Text == "More" then
				overflow.setOpen(false)
			end
			previous = GuiService.SelectedObject
			local top = stack[#stack]
			if top ~= nil then
				top.panel.Visible = false
				top.scrim.Visible = false
				top.backdrop.Visible = false
			end
			table.insert(stack, modal)
			if sharedScreen then
				sharedScreen:SetAttribute("ModalOpen", true)
			end
			modal.panel.ZIndex = 10 + #stack * 2
			modal.scrim.ZIndex = modal.panel.ZIndex - 1
			(modal.backdrop.Parent :: ScreenGui).DisplayOrder = #stack * 2 - 1
			(modal.panel.Parent :: ScreenGui).DisplayOrder = #stack * 2
			original(true, focus)
			modalControls()
		else
			local index = table.find(stack, modal)
			if index ~= nil then
				table.remove(stack, index)
			end
			if sharedScreen then
				sharedScreen:SetAttribute("ModalOpen", #stack > 0)
			end
			original(false)
			modalControls()
			local top = stack[#stack]
			if top ~= nil then
				top.panel.Visible = true
				top.scrim.Visible = true
				top.backdrop.Visible = true
			end
			Kit.focus(previous)
			if GuiService.SelectedObject == nil and top ~= nil then
				Kit.focus(top.close)
			end
		end
	end
	modal.panel.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	modal.panel.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	modal.panel.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	modal.panel.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	return modal
end
backContext.Close.Pressed:Connect(function()
	local top = stack[#stack]
	if top == nil then
		return
	end
	local back = backs[top]
	if back ~= nil then
		back()
	else
		top.setOpen(false)
	end
end)
return Kit
