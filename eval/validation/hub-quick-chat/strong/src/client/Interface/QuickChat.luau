--!strict

local CAS = game:GetService("ContextActionService")
local Extended = require(game:GetService("ReplicatedStorage").Shared.Extended)
local Kit = require(script.Parent.Kit)
local E = require(script.Parent.ExtendedKit)
local function mount(playerGui: PlayerGui)
	local api = Extended.client()
	local state = api.get()
	local modal, scroll = E.panel(playerGui, "Quick Chat")
	local wheel =
		Kit.create("Frame", { Size = UDim2.new(1, 0, 0, 360), BackgroundTransparency = 1, Parent = scroll }) :: Frame
	local choices: { TextButton } = {}
	local toast = E.label(Kit.screen(playerGui, "Chat"), "")
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.Position = UDim2.new(0.5, 0, 1, -16)
	toast.Size = UDim2.new(0.6, 0, 0, 48)
	toast.AutomaticSize = Enum.AutomaticSize.None
	toast.BackgroundTransparency = 0
	toast.BackgroundColor3 = Kit.colors.card
	toast.Visible = false
	for index, message in Extended.messages do
		local choice = E.button(wheel, message, function()
			local result = api.request("chat", message)
			state = result.state
			if result.ok then
				toast.Text = message
				toast.Visible = true
				task.delay(3, function()
					toast.Visible = false
				end)
				modal.setOpen(false)
			end
		end)
		choice.AnchorPoint = Vector2.new(0.5, 0.5)
		choice.Size = UDim2.fromOffset(80, 52)
		choice.TextWrapped = true
		choices[index] = choice
	end
	local function layout()
		local radius = math.max(70, math.min(130, wheel.AbsoluteSize.X / 2 - 44))
		for index, choice in choices do
			local angle = -math.pi / 2 + (index - 1) * math.pi / 4
			choice.Position = UDim2.new(0.5, math.cos(angle) * radius, 0, 180 + math.sin(angle) * 130)
		end
	end
	wheel:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	local cooldown = E.label(scroll, "Ready")
	local function render()
		local remaining = math.max(0, math.ceil(state.readyAt - api.now()))
		cooldown.Text = if remaining > 0 then ("Cooldown %ds"):format(remaining) else "Ready"
		for _, choice in choices do
			choice.Interactable = remaining == 0
		end
	end
	CAS:BindActionAtPriority("QuickChatWheel", function(_: string, input: Enum.UserInputState): Enum.ContextActionResult
		if input == Enum.UserInputState.Begin then
			modal.setOpen(not modal.isOpen(), choices[1])
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
	api.onChanged(function(next)
		state = next
		render()
	end)
	task.spawn(function()
		while playerGui.Parent ~= nil do
			render()
			task.wait(0.2)
		end
	end)
	layout()
	render()
end
return { mount = mount }
