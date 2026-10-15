--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Hub = require(ReplicatedStorage.Shared.Hub)

local function mount(context: Hub.Context)
	require(script.HubPanels).mount(context)
	require(script.shop).mount(context)
	require(script.inventory).mount(context)
	require(script.settings).mount(context)
	require(script.codes).mount(context)
	require(script["daily-rewards"]).mount(context)
	require(script["npc-dialogue"]).mount(context)
	require(script["pack-opening"]).mount(context)
	require(script["round-hud"]).mount(context)
	require(script.Livery).mount(context.playerGui)
	require(script.TrackVote).mount(context.playerGui)
	require(script.QuickChat).mount(context.playerGui)
	require(script.Upgrades).mount(context.playerGui)
	require(script.Party).mount(context.playerGui)
	require(script.Tutorial).mount(context.playerGui)
end

return { mount = mount }
