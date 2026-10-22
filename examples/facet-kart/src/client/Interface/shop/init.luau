--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shop = require(ReplicatedStorage.Shared.Hub.Shop)
local Kit = require(script.Parent.Kit)
export type Context = { player: Player, playerGui: PlayerGui, shop: Shop.Client }
local function mount(context: Context)
	local api = context.shop
	local state = api.getState()
	local screen = Kit.screen(context.playerGui, "Shop")
	local modal = Kit.modal(screen, "Shop", "Shop")
	local dock = Kit.hud(screen)
	local opener = Kit.button("Shop", "primary")
	opener.LayoutOrder = -1
	opener.Parent = dock
	opener.Activated:Connect(function()
		modal.setOpen(true)
	end)
	local list = Kit.scroller()
	list.Parent = modal.body
	Kit.list(Enum.FillDirection.Vertical, 8).Parent = list
	local balance = Kit.label("")
	balance.Parent = list
	local codes = Kit.button("Codes")
	codes.Parent = list
	codes.Activated:Connect(function()
		Kit.openPanel("Codes")
	end)
	local feedback, say = Kit.message(list)
	local _ = feedback
	balance.Parent = modal.body
	balance.LayoutOrder = 1
	feedback.Parent = modal.body
	feedback.LayoutOrder = 2
	list.LayoutOrder = 3
	list.Size = UDim2.new(1, 0, 0, 0)
	Kit.list(Enum.FillDirection.Vertical, 8).Parent = modal.body
	Kit.create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = list })
	local actions: { [string]: TextButton } = {}
	for _, item in api.catalog do
		local card = Kit.card()
		card.Parent = list
		Kit.list(Enum.FillDirection.Vertical, 8).Parent = card
		local row = Kit.create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			Parent = card,
		}) :: Frame
		local rowLayout = Kit.list(Enum.FillDirection.Horizontal, 8) :: UIListLayout
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rowLayout.Parent = row
		local info = Kit.create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -118, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = row,
		}, { Kit.list(Enum.FillDirection.Vertical, 4) }) :: Frame
		Kit.label(item.name, 20, nil, true).Parent = info
		Kit.label(tostring(item.price) .. " " .. item.currency).Parent = info
		local description = Kit.label(item.description, 16)
		description.LayoutOrder = 2
		description.Parent = card
		local action = Kit.button("Buy", "primary")
		action.Size = UDim2.fromOffset(110, 48)
		action.Parent = row
		actions[item.id] = action
		action.Activated:Connect(function()
			local result = api.purchase(item.id)
			state = result.state
			if result.ok then
				say("You bought " .. item.name, "success")
			elseif result.reason == "insufficient_funds" then
				say("Not enough " .. item.currency)
			else
				say(result.reason or "Try again")
			end
		end)
	end
	local function render()
		balance.Text = Kit.number(state.wallet.Coins) .. " Coins • " .. Kit.number(state.wallet.Gems) .. " Gems"
		for id, action in actions do
			action.Text = if state.owned[id] then "Owned" else "Buy"
			action.Interactable = not state.owned[id]
		end
	end
	api.onStateChanged(function(next)
		state = next
		render()
	end)
	render()
end
return { mount = mount }
