--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Hub = require(ReplicatedStorage.Shared.Hub)
export type Context = Hub.Context
local function mount(context: Context)
	local _ = context
end
return { mount = mount }
