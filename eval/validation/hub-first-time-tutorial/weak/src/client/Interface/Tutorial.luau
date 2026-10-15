--!strict

local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local CAS = game:GetService("ContextActionService")
local Extended = require(game:GetService("ReplicatedStorage").Shared.Extended)
local Kit = require(script.Parent.Kit)
local E = require(script.Parent.ExtendedKit)
local function mount(playerGui: PlayerGui)
	local api = Extended.client()
	local hub = Kit.screen(playerGui, "Tutorial")
	local overlay = Instance.new("ScreenGui")
	overlay.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	overlay.DisplayOrder = 30
	overlay.ResetOnSpawn = false
	overlay.Parent = playerGui
	local card = Kit.card()
	card.Size = UDim2.fromOffset(320, 200)
	card.AutomaticSize = Enum.AutomaticSize.None
	card.Visible = false
	card.Parent = overlay
	Kit.list(Enum.FillDirection.Vertical, 8).Parent = card
	local heading = E.label(card, "")
	local copy = E.label(card, "")
	local actions = Kit.create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48), Parent = card })
	Kit.list(Enum.FillDirection.Horizontal, 8).Parent = actions
	local step = 1
	local previous: GuiObject? = nil
	local opener: TextButton
	local targets = { "Garage", "Shop", "Play" }
	local names = { "Dock", "Shop", "Race queue" }
	local descriptions = {
		"Use the dock to prepare your kart. Try Garage.",
		"Shop has parts and prices. You can open it now.",
		"Play opens the race queue. Choose your mode.",
	}
	local function target(): TextButton?
		for _, object in hub:GetDescendants() do
			if object:IsA("TextButton") and object.Text == targets[step] and object.Visible then
				return object
			end
		end
		return nil
	end
	local function render()
		heading.Text = ("Step %d of 3: %s"):format(step, names[step])
		copy.Text = descriptions[step]
	end
	local function finish()
		card.Visible = false
		api.request("tutorial")
		Kit.focus(previous or opener)
	end
	local back = E.button(actions, "Back", function()
		step = step
		render()
	end)
	local next = E.button(actions, "Next", function()
		if step == 3 then
			finish()
		else
			step += 1
			render()
		end
	end)
	local skip = E.button(actions, "Skip", finish)
	for _, button in { back, next, skip } do
		button.Size = UDim2.new(1 / 3, -6, 0, 48)
	end
	opener = E.button(Kit.hud(hub), "Tutorial", function()
		previous = GuiService.SelectedObject
		step = 1
		render()
		card.Visible = true
		Kit.focus(next)
	end)
	local pointer = Kit.create("Frame", {
		BackgroundColor3 = Kit.colors.primary,
		Size = UDim2.fromOffset(12, 12),
		Rotation = 45,
		Visible = false,
		Parent = overlay,
	}) :: Frame
	RunService.RenderStepped:Connect(function()
		pointer.Visible = card.Visible
		if not card.Visible then
			return
		end
		back.Interactable = step > 1
		local anchor = target()
		if anchor == nil then
			pointer.Visible = false
			return
		end
		local width = math.min(320, overlay.AbsoluteSize.X - 24)
		local position = anchor.AbsolutePosition
		local size = anchor.AbsoluteSize
		local ancestor = anchor.Parent
		while ancestor ~= nil and ancestor ~= hub do
			if ancestor:IsA("ScrollingFrame") then
				local top = ancestor.AbsolutePosition.Y
				local bottom = top + ancestor.AbsoluteWindowSize.Y
				if position.Y < top then
					ancestor.CanvasPosition += Vector2.new(0, position.Y - top)
				elseif position.Y + size.Y > bottom then
					ancestor.CanvasPosition += Vector2.new(0, position.Y + size.Y - bottom)
				end
			end
			ancestor = ancestor.Parent
		end
		local x = math.clamp(position.X, 12, math.max(12, overlay.AbsoluteSize.X - width - 12))
		local y = if position.Y > 224 then position.Y - 212 else position.Y + size.Y + 12
		card.Size = UDim2.fromOffset(width, 200)
		card.Position = UDim2.fromOffset(x, math.clamp(y, 12, math.max(12, overlay.AbsoluteSize.Y - 212)))
		pointer.Position = UDim2.fromOffset(position.X + size.X / 2 - 6, position.Y + size.Y - 6)
	end)
	CAS:BindActionAtPriority("TutorialBack", function(_: string, state: Enum.UserInputState): Enum.ContextActionResult
		if not card.Visible then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then
			if step > 1 then
				step -= 1
				render()
			else
				finish()
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 1, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
end
return { mount = mount }
