--!strict

local Extended = require(game:GetService("ReplicatedStorage").Shared.Extended)
local Kit = require(script.Parent.Kit)
local E = require(script.Parent.ExtendedKit)
local function mount(playerGui: PlayerGui)
	local api = Extended.client()
	local state = api.get()
	local _, scroll = E.panel(playerGui, "Party")
	local strip = E.label(scroll, "Party: You")
	local search = Kit.input("Search friends")
	search.Parent = scroll
	E.button(scroll, "Clear", function()
		search.Text = ""
	end)
	local rows = Kit.create("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		Parent = scroll,
	})
	Kit.list(Enum.FillDirection.Vertical, 8).Parent = rows
	local function render()
		strip.Text = "Party: " .. table.concat(state.party, ", ")
		for _, child in rows:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local count = 0
		for _, friend in state.friends do
			if string.find(string.lower(friend.name), string.lower(search.Text), 1, true) ~= nil then
				count += 1
				local card = Kit.card()
				card.Parent = rows
				Kit.list(Enum.FillDirection.Vertical, 8).Parent = card
				E.label(card, friend.name .. " / " .. friend.presence)
				local invite = E.button(card, friend.invite, function()
					api.request("invite", friend.name)
				end)
				invite.Interactable = friend.presence ~= "Offline" and friend.invite == "Invite"
			end
		end
		if count == 0 then
			E.label(rows, "No friends match")
		end
	end
	search:GetPropertyChangedSignal("Text"):Connect(render)
	api.onChanged(function(next)
		state = next
		render()
	end)
	render()
end
return { mount = mount }
