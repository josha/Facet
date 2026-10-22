--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Hub = require(ReplicatedStorage.Shared.Hub)

local function mount(context: Hub.Context)
	local arrange = require(script.HubPanels).mount(context)
	require(script.shop).mount(context)
	require(script.inventory).mount(context)
	require(script.settings).mount(context)
	require(script.codes).mount(context)
	require(script["daily-rewards"]).mount(context)
	require(script["npc-dialogue"]).mount(context)
	require(script["pack-opening"]).mount(context)
	require(script["round-hud"]).mount(context)
	arrange()
end

return { mount = mount }
