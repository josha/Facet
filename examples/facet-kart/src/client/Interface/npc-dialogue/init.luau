--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Hub = require(ReplicatedStorage.Shared.Hub)
local Dialogue = require(ReplicatedStorage.Shared.Hub.Dialogue)
local Kit = require(script.Parent.Kit)
local function mount(context: Hub.Context)
	local api = context.dialogue
	local state = api.getState()
	local screen = Kit.screen(context.playerGui, "Dialogue")
	local talk = Kit.button("Talk to Mechanic", "primary")
	talk.Parent = Kit.hud(screen)
	local modal = Kit.modal(screen, "Mechanic", "Mechanic")
	local scroll = Kit.scroller()
	scroll.Parent = modal.body
	Kit.list(Enum.FillDirection.Vertical, 8).Parent = scroll
	local line = Kit.label("", 20)
	line.Parent = scroll
	local choices = Kit.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = scroll,
	}, { Kit.list(Enum.FillDirection.Vertical, 8) }) :: Frame
	local shown: string? = nil
	local pending = false
	local render: () -> ()
	local function act(call: () -> Dialogue.Result)
		if pending then
			return
		end
		pending = true
		local result = call()
		pending = false
		state = result.state
		render()
	end
	modal.onClosed(function()
		if state.node ~= nil then
			act(api.leave)
		end
	end)
	render = function()
		talk.Visible = state.nearby ~= nil and state.node == nil
		local node = state.node
		if node == nil then
			shown = nil
			modal.setOpen(false)
			return
		end
		modal.title.Text = node.speaker
		modal.close.Text = if node.ended then "Close" else "Leave"
		if shown ~= node.id then
			shown = node.id
			line.Text = node.text
			for _, child in choices:GetChildren() do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
			local first: GuiObject? = nil
			for _, choice in node.choices do
				local option = Kit.button(choice.text)
				option.Parent = choices
				option.Activated:Connect(function()
					act(function()
						return api.choose(choice.id)
					end)
				end)
				first = first or option
			end
			modal.setOpen(true, first)
			Kit.focus(first or modal.close)
		end
	end
	talk.Activated:Connect(function()
		act(api.talk)
	end)
	api.onStateChanged(function(next)
		state = next
		render()
	end)
	render()
end
return { mount = mount }
