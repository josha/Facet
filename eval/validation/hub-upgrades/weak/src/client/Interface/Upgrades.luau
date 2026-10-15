--!strict

local Extended = require(game:GetService("ReplicatedStorage").Shared.Extended)
local Garage = require(game:GetService("ReplicatedStorage").Shared.Hub.Garage)
local Kit = require(script.Parent.Kit)
local E = require(script.Parent.ExtendedKit)
local function mount(playerGui: PlayerGui)
	local api = Extended.client()
	local state = api.get()
	local modal, scroll, opener = E.panel(playerGui, "Upgrades")
	local chosen = "rookie_kart"
	local confirm = Kit.modal(Kit.screen(playerGui, "Upgrades"), "UpgradeConfirm", "Confirm")
	local confirmBody = Kit.scroller()
	confirmBody.Parent = confirm.body
	Kit.list(Enum.FillDirection.Vertical, 8).Parent = confirmBody
	local question = E.label(confirmBody, "")
	local pending = 0
	local render: () -> ()
	E.button(confirmBody, "Confirm", function()
		if pending > 0 then
			local index = pending
			pending = 0
			local result = api.request("upgrade", { kart = chosen, stat = index })
			state = result.state
		end
		confirm.setOpen(false)
		render()
	end)
	E.button(confirmBody, "Cancel", function()
		pending = 0
		confirm.setOpen(false)
	end)
	render = function()
		for _, child in scroll:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		E.label(scroll, ("%d Coins / %d Gems"):format(state.wallet.Coins, state.wallet.Gems))
		for _, kart in Garage.vehicles do
			E.button(scroll, kart.name, function()
				chosen = kart.id
				render()
			end)
		end
		E.label(scroll, "Selected: " .. chosen)
		local levels = state.levels[chosen] or { 0, 0, 0 }
		for index, name in Extended.stats do
			local level = levels[index]
			E.label(scroll, ("%s Level %d / 3 / %d%%"):format(name, level, 40 + level * 20))
			local bar = Kit.create(
				"Frame",
				{ Size = UDim2.new(1, 0, 0, 16), BackgroundColor3 = Kit.colors.secondary, Parent = scroll }
			)
			Kit.create(
				"Frame",
				{ Size = UDim2.fromScale(0.4 + level * 0.2, 1), BackgroundColor3 = Kit.colors.primary, Parent = bar }
			)
			local coins, gems = 100 * (level + 1), 5 * (level + 1)
			E.label(scroll, ("%d Coins + %d Gems"):format(coins, gems))
			local buy = E.button(scroll, "Upgrade " .. name, function()
				pending = index
				question.Text = ("Upgrade %s for %d Coins + %d Gems?"):format(name, coins, gems)
				confirm.setOpen(true)
			end)
			buy.Interactable = level < 3 and state.wallet.Coins >= coins and true
			if not buy.Interactable then
				E.label(scroll, if level == 3 then "Maximum level" else "Not enough Coins or Gems")
			end
		end
	end
	api.onChanged(function(next)
		state = next
		if modal.isOpen() and not confirm.isOpen() then
			render()
		end
	end)
	opener.Activated:Connect(function()
		state = api.get()
		render()
	end)
	render()
end
return { mount = mount }
