--!strict

local Extended = require(game:GetService("ReplicatedStorage").Shared.Extended)
local E = require(script.Parent.ExtendedKit)
local Kit = require(script.Parent.Kit)
local function mount(playerGui: PlayerGui)
	local api = Extended.client()
	local state = api.get()
	local modal, scroll = E.panel(playerGui, "Track Vote")
	local timer = E.label(scroll, "Waiting for vote")
	local choices: { TextButton } = {}
	for index, name in state.tracks do
		local card = Kit.card()
		card.Parent = scroll
		Kit.list(Enum.FillDirection.Vertical, 8).Parent = card
		E.label(card, name)
		local descriptions = { "Coastal corners / 3 laps", "Snowy climbs / 2 laps", "Dunes and straights / 3 laps" }
		E.label(card, descriptions[index])
		choices[index] = E.button(card, "Vote", function()
			api.request("vote", index)
		end)
	end
	local winner = E.label(scroll, "")
	local function render()
		local remaining = math.max(0, math.ceil(state.endsAt - api.now()))
		timer.Text = if state.endsAt == 0 then "Waiting for vote" else ("Voting ends in %d"):format(remaining)
		for index, choice in choices do
			choice.Text = ("%d votes%s"):format(
				state.votes[index],
				if state.vote == index then " / Your vote" else " / Vote"
			)
			choice.BackgroundColor3 = if state.vote == index then Kit.colors.success else Kit.colors.secondary
			choice.Interactable = true
		end
		winner.Text = if state.winner == "" then "" else "Winner: " .. state.winner
	end
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
	local _ = modal
	render()
end
return { mount = mount }
