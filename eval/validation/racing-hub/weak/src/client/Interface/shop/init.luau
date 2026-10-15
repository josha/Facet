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
	local actions: { [string]: TextButton } = {}
	for _, item in api.catalog do
		local card = Kit.card()
		card.Parent = list
		Kit.list(Enum.FillDirection.Vertical, 8).Parent = card
		Kit.label(item.name, 20, nil, true).Parent = card
		Kit.label(item.description, 16).Parent = card
		Kit.label(tostring(item.price) .. " " .. item.currency).Parent = card
		local action = Kit.button("Buy", "primary")
		action.Parent = card
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
	api.onStateChanged(function(_next) end)
	render()
end
return { mount = mount }
