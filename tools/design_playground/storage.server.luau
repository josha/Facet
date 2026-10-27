--!strict

local storage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")
local Facet = require(storage.Facet)

local LIMIT = 200000
local storeOk, store = pcall(function()
	return game:GetService("DataStoreService"):GetDataStore("ComposeDesign.Screen.v1")
end)
local Design = Facet.design().Design
local library = Facet.design().library({
	UI = {},
})
players.CharacterAutoLoads = false
local remote = Instance.new("RemoteFunction")
remote.Name = "ComposeDesignStorage"
remote.Parent = storage
local nextWrite: { [Player]: number } = {}

remote.OnServerInvoke = function(player: Player, operation: unknown, source: unknown): (boolean, string)
	local ok, result = pcall(function(): string
		assert(storeOk, "Publish this experience to keep saved designs")
		local key = "User_" .. tostring(player.UserId)
		if operation == "load" then
			local saved = store:GetAsync(key)
			return if type(saved) == "string" then saved else ""
		end
		assert(operation == "save" and type(source) == "string", "Unknown storage request")
		assert(#source <= LIMIT, "The design is too large to save")
		assert(os.clock() >= (nextWrite[player] or 0), "Please wait a moment before saving again")
		nextWrite[player] = os.clock() + 6
		Design.parse(source, library)
		store:SetAsync(key, source, { player.UserId })
		return source
	end)
	return ok, if ok then result else tostring(result)
end

players.PlayerRemoving:Connect(function(player)
	nextWrite[player] = nil
end)
