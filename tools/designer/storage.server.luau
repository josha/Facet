--!strict

local storage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")
local json = game:GetService("HttpService")
local storeOk, store = pcall(function()
	return game:GetService("DataStoreService"):GetDataStore("FacetDesign.Library.v1")
end)
players.CharacterAutoLoads = false
local policy = require(storage.FacetDesignModules.saved_library)
local remote = Instance.new("RemoteFunction")
remote.Name = "FacetDesignStorage"
remote.Parent = storage
local sessions: { [Player]: any } = {}

remote.OnServerInvoke = function(player: Player, operation: any, payload: any): any
	local session = sessions[player]
	if not session then
		session = { busy = false, loaded = false, revision = 0, nextWrite = 0 }
		sessions[player] = session
	end
	if session.busy then
		return { ok = false, message = "Storage is busy. Try Save again shortly" }
	end
	session.busy = true
	local ok, result = pcall(function()
		assert(storeOk, "Publish this experience to enable saved designs")
		local key = "User_" .. tostring(player.UserId)
		if operation == "load" then
			assert(not session.loaded, "Your library is already loaded")
			local value = store:GetAsync(key)
			local clean = policy.validate(if value then value.library else {})
			session.revision = if value then value.revision else 0
			session.loaded = true
			return { ok = true, library = clean }
		end
		assert(operation == "save", "Unknown storage request")
		assert(session.loaded, "Saved designs could not be loaded. Rejoin before saving")
		assert(os.clock() >= session.nextWrite, "Please wait a moment before saving again")
		session.nextWrite = os.clock() + 6
		local clean = policy.validate(payload)
		assert(#json:JSONEncode(clean) <= 900000, "The saved library is too large")
		local result = store:UpdateAsync(key, function(previous)
			return policy.replace(previous, session.revision, clean), { player.UserId }
		end)
		session.revision = result.revision
		return { ok = true }
	end)
	session.busy = false
	if ok then
		return result
	end
	local conflict = string.find(tostring(result), "another session", 1, true) ~= nil
	return {
		ok = false,
		retryable = not conflict,
		message = if conflict
			then "Your library changed in another session. Rejoin to load it"
			else "Cloud storage is unavailable",
	}
end

players.PlayerRemoving:Connect(function(player)
	sessions[player] = nil
end)
