--!strict

local inputs = script.Parent.Parent.KartInput
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Settings = require(ReplicatedStorage.Shared.Hub.Settings)
local Kit = require(script.Parent.Kit)

export type Context = {
	player: Player,
	playerGui: PlayerGui,
	settings: Settings.Client,
}

type Slider = { track: TextButton, set: (value: number) -> (), get: () -> number }

local STEP = 5

local function mount(context: Context)
	local api = context.settings
	local values = api.get()
	local editing: { [string]: boolean } = {}
	local queued: Settings.Patch = {}
	local pendingCount = 0
	local flushing = false

	local screen = Kit.screen(context.playerGui, "SettingsInterface")
	Kit.scale(screen)
	local hud = Kit.hud(screen)
	local openButton = Kit.button("Settings", "primary")
	openButton.Name = "OpenSettings"
	openButton.Parent = hud

	local modal = Kit.modal(screen, "SettingsPanel", "Settings", Vector2.new(700, 680))
	modal.hides(openButton)
	local scroller = Kit.scroller()
	scroller.Parent = modal.body
	Kit.list(Enum.FillDirection.Vertical, Kit.space.medium).Parent = scroller
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local function section(title: string)
		local heading = Kit.label(title, Kit.size.heading, Kit.colors.primary, true)
		heading.LayoutOrder = nextOrder()
		heading.Parent = scroller
	end

	local function row(height: number): Frame
		local frame = Kit.create("Frame", {
			BackgroundColor3 = Kit.colors.card,
			Size = UDim2.new(1, 0, 0, height),
			LayoutOrder = nextOrder(),
			Parent = scroller,
		}, { Kit.corner(12), Kit.padding(Kit.space.medium) }) :: Frame
		return frame
	end

	local function flush()
		if flushing then
			return
		end
		flushing = true
		task.spawn(function()
			while pendingCount > 0 do
				local patch = queued
				queued = {}
				pendingCount = 0
				local ok, result = pcall(api.save, patch)
				if ok and result.ok then
					values = result.values
				end
			end
			flushing = false
		end)
	end

	local function save(field: string, value: unknown)
		if field == "musicVolume" and type(value) == "number" then
			queued.musicVolume = value
		elseif field == "effectsVolume" and type(value) == "number" then
			queued.effectsVolume = value
		elseif field == "showDamageNumbers" and type(value) == "boolean" then
			queued.showDamageNumbers = value
		elseif field == "cameraShake" and type(value) == "boolean" then
			queued.cameraShake = value
		elseif field == "graphics" and (value == "Low" or value == "Medium" or value == "High") then
			queued.graphics = if value == "Low" then "Low" elseif value == "Medium" then "Medium" else "High"
		else
			return
		end
		pendingCount += 1
		flush()
	end

	local function volumeOf(field: string): number
		return if field == "musicVolume" then values.musicVolume else values.effectsVolume
	end

	local function flagOf(field: string): boolean
		return if field == "showDamageNumbers" then values.showDamageNumbers else values.cameraShake
	end

	local function setFlag(field: string, value: boolean)
		if field == "showDamageNumbers" then
			values.showDamageNumbers = value
		else
			values.cameraShake = value
		end
	end

	local sliders: { [string]: Slider } = {}

	local function slider(title: string, field: string): Slider
		local frame = row(96)
		local name = Kit.label(title, Kit.size.body, Kit.colors.text, true)
		name.AutomaticSize = Enum.AutomaticSize.None
		name.Size = UDim2.new(1, -80, 0, 28)
		name.Parent = frame
		local readout = Kit.label("", Kit.size.body, Kit.colors.text, true)
		readout.Name = "Value"
		readout.AutomaticSize = Enum.AutomaticSize.None
		readout.AnchorPoint = Vector2.new(1, 0)
		readout.Position = UDim2.fromScale(1, 0)
		readout.Size = UDim2.fromOffset(72, 28)
		readout.TextXAlignment = Enum.TextXAlignment.Right
		readout.Parent = frame
		local track = Kit.create("TextButton", {
			Name = "Track",
			Text = "",
			AutoButtonColor = false,
			Selectable = true,
			BackgroundColor3 = Kit.colors.secondary,
			Position = UDim2.fromOffset(0, 36),
			Size = UDim2.new(1, 0, 0, 44),
			Parent = frame,
		}, { Kit.corner(22) }) :: TextButton
		local fill = Kit.create("Frame", {
			Name = "Fill",
			BackgroundColor3 = Kit.colors.primary,
			Size = UDim2.fromScale(0.5, 1),
			Parent = track,
		}, { Kit.corner(22) }) :: Frame
		local thumb = Kit.create("Frame", {
			Name = "Thumb",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Kit.colors.text,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(48, 48),
			Parent = track,
		}, { Kit.corner(24) }) :: Frame
		local current = 0
		local function show(value: number)
			current = math.clamp(math.floor(value + 0.5), 0, 100)
			fill.Size = UDim2.fromScale(current / 100, 1)
			thumb.Position = UDim2.fromScale(current / 100, 0.5)
			readout.Text = ("%d%%"):format(current)
		end
		local function fromX(x: number)
			local left = track.AbsolutePosition.X
			local width = math.max(1, track.AbsoluteSize.X)
			show((x - left) / width * 100)
		end
		local dragging: InputObject? = nil
		track.InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging = input
				editing[field] = true
				fromX(input.Position.X)
			end
		end)
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if dragging == nil then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			then
				fromX(input.Position.X)
			end
		end)
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if dragging == nil then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging = nil
				editing[field] = nil
				save(field, current)
			end
		end)
		local inputContext = inputs:FindFirstChild(field) :: InputContext
		local decrease = inputContext:FindFirstChild("Decrease") :: InputAction
		local increase = inputContext:FindFirstChild("Increase") :: InputAction
		decrease.Pressed:Connect(function()
			show(current - STEP)
			save(field, current)
		end)
		increase.Pressed:Connect(function()
			show(current + STEP)
			save(field, current)
		end)
		track.SelectionGained:Connect(function()
			inputContext.Enabled = true
		end)
		track.SelectionLost:Connect(function()
			inputContext.Enabled = false
		end)
		local made: Slider = {
			track = track,
			set = show,
			get = function(): number
				return current
			end,
		}
		sliders[field] = made
		return made
	end

	local toggles: { [string]: TextButton } = {}
	local function toggle(title: string, field: "showDamageNumbers" | "cameraShake")
		local frame = row(72)
		local name = Kit.label(title, Kit.size.body, Kit.colors.text, true)
		name.AutomaticSize = Enum.AutomaticSize.None
		name.Size = UDim2.new(1, -110, 1, 0)
		name.Parent = frame
		local switch = Kit.button("Off", "secondary")
		switch.Name = "Switch"
		switch.AnchorPoint = Vector2.new(1, 0.5)
		switch.Position = UDim2.fromScale(1, 0.5)
		switch.Size = UDim2.fromOffset(96, 48)
		switch.Parent = frame
		switch.Activated:Connect(function()
			local value = not flagOf(field)
			setFlag(field, value)
			switch.Text = if value then "On" else "Off"
			switch.BackgroundColor3 = if value then Kit.colors.success else Kit.colors.secondary
			save(field, value)
		end)
		toggles[field] = switch
	end

	local presetButtons: { [string]: TextButton } = {}
	local function graphics()
		local frame = row(72)
		Kit.list(Enum.FillDirection.Horizontal, Kit.space.small).Parent = frame
		for index, preset in api.presets do
			local choice = Kit.button(preset, "secondary")
			choice.LayoutOrder = index
			choice.Size = UDim2.new(1 / #api.presets, -6, 1, 0)
			choice.Parent = frame
			choice.Activated:Connect(function()
				values.graphics = preset :: Settings.Preset
				for name, other in presetButtons do
					other.BackgroundColor3 = if name == preset then Kit.colors.primary else Kit.colors.secondary
					other.TextColor3 = if name == preset then Kit.colors.primaryText else Kit.colors.secondaryText
				end
				save("graphics", preset)
			end)
			presetButtons[preset] = choice
		end
	end

	section("Audio")
	slider("Music", "musicVolume")
	slider("Sound Effects", "effectsVolume")
	section("Gameplay")
	toggle("Damage Numbers", "showDamageNumbers")
	toggle("Camera Shake", "cameraShake")
	section("Graphics")
	graphics()
	section("Controls")
	local header = row(40)
	header.BackgroundTransparency = 1
	Kit.list(Enum.FillDirection.Horizontal, 0).Parent = header
	for index, words in { "Action", "Keyboard", "Gamepad" } do
		local cell = Kit.label(words, Kit.size.small, Kit.colors.muted, true)
		cell.AutomaticSize = Enum.AutomaticSize.None
		cell.Size = UDim2.new(1 / 3, 0, 1, 0)
		cell.LayoutOrder = index
		cell.Parent = header
	end
	for _, bind in api.keybinds do
		local line = row(48)
		Kit.list(Enum.FillDirection.Horizontal, 0).Parent = line
		for index, words in { bind.action, bind.keyboard, bind.gamepad } do
			local cell = Kit.label(words, Kit.size.body, Kit.colors.text, index == 1)
			cell.AutomaticSize = Enum.AutomaticSize.None
			cell.Size = UDim2.new(1 / 3, 0, 1, 0)
			cell.LayoutOrder = index
			cell.Parent = line
		end
	end

	local function render()
		for field, made in sliders do
			if not editing[field] then
				made.set(volumeOf(field))
			end
		end
		for field, switch in toggles do
			local value = flagOf(field)
			switch.Text = if value then "On" else "Off"
			switch.BackgroundColor3 = if value then Kit.colors.success else Kit.colors.secondary
		end
		for name, choice in presetButtons do
			choice.BackgroundColor3 = if name == values.graphics then Kit.colors.primary else Kit.colors.secondary
			choice.TextColor3 = if name == values.graphics then Kit.colors.primaryText else Kit.colors.secondaryText
		end
	end

	openButton.Activated:Connect(function()
		values = api.get()
		render()
		modal.setOpen(true, sliders.musicVolume.track)
	end)
	modal.onClosed(function()
		flush()
		if GuiService.SelectedObject ~= nil and GuiService.SelectedObject:IsDescendantOf(modal.panel) then
			GuiService.SelectedObject = nil
		end
	end)
	api.onChanged(function(next: Settings.Values)
		values = next
		render()
	end)
	render()
end

return {
	mount = mount,
}
