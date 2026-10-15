--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Extended = require(ReplicatedStorage.Shared.Extended)
local Garage = require(ReplicatedStorage.Shared.Hub.Garage)
local Ledger = require(script.Parent.Ledger)
local folder = Instance.new("Folder")
folder.Name = "ExtendedRemotes"
local request = Instance.new("RemoteFunction")
request.Name = "Request"
request.Parent = folder
local changed = Instance.new("RemoteEvent")
changed.Name = "Changed"
changed.Parent = folder
folder.Parent = ReplicatedStorage
local states: { [Player]: Extended.State } = {}
local signatures: { [Player]: string } = {}
local function now(): number
	return workspace:GetServerTimeNow()
end
local function initial(player: Player): Extended.State
	return {
		livery = { body = 0, accent = 0.6, shade = 1, decal = "None" },
		tracks = { "Harbor Loop", "Alpine Pass", "Desert Sprint" },
		votes = { 2, 3, 1 },
		vote = 0,
		endsAt = 0,
		winner = "",
		chat = "",
		chatCount = 0,
		readyAt = 0,
		levels = {},
		wallet = Ledger.wallet(player),
		friends = {
			{ name = "Mira", presence = "Online", invite = "Invite" },
			{ name = "Sol", presence = "In race", invite = "Invite" },
			{ name = "Tess", presence = "Offline", invite = "Invite" },
		},
		party = { player.DisplayName },
		tutorialDone = false,
	}
end
local function stateOf(player: Player): Extended.State
	if states[player] == nil then
		states[player] = initial(player)
	end
	return states[player]
end
local function publish(player: Player)
	changed:FireClient(player, stateOf(player))
end
local function validUnit(value: unknown): boolean
	return type(value) == "number" and value == value and value >= 0 and value <= 1
end
request.OnServerInvoke = function(player: Player, action: unknown, value: unknown): Extended.Result
	local state = stateOf(player)
	local ok = false
	local reason = "Invalid request"
	if action == "get" then
		ok = true
	elseif action == "livery" and type(value) == "table" then
		local draft = value :: { [string]: unknown }
		if
			validUnit(draft.body)
			and validUnit(draft.accent)
			and validUnit(draft.shade)
			and type(draft.decal) == "string"
			and table.find(Extended.decals, draft.decal) ~= nil
		then
			state.livery = {
				body = draft.body :: number,
				accent = draft.accent :: number,
				shade = draft.shade :: number,
				decal = draft.decal :: string,
			}
			ok = true
		end
	elseif action == "vote" and type(value) == "number" and value % 1 == 0 and value >= 1 and value <= 3 then
		if state.endsAt > now() and state.winner == "" then
			if state.vote > 0 then
				state.votes[state.vote] -= 1
			end
			state.vote = value
			state.votes[value] += 1
			ok = true
		else
			reason = "Voting closed"
		end
	elseif action == "chat" and type(value) == "string" and table.find(Extended.messages, value) ~= nil then
		if now() >= state.readyAt then
			state.chat = value
			state.chatCount += 1
			state.readyAt = now() + 5
			ok = true
		else
			reason = "Cooldown"
		end
	elseif action == "upgrade" and type(value) == "table" then
		local fields = value :: { [string]: unknown }
		local kart = tostring(fields.kart)
		local index = tonumber(fields.stat) or 0
		local exists = false
		for _, item in Garage.vehicles do
			if item.id == kart then
				exists = true
			end
		end
		if exists and index % 1 == 0 and index >= 1 and index <= 3 then
			local levels = state.levels[kart] or { 0, 0, 0 }
			local level = levels[index]
			local coins, gems = 100 * (level + 1), 5 * (level + 1)
			if level < 3 and state.wallet.Coins >= coins and state.wallet.Gems >= gems then
				state.wallet.Coins -= coins
				state.wallet.Gems -= gems
				levels[index] += 1
				state.levels[kart] = levels
				ok = true
			else
				reason = "Not enough funds or maximum level"
			end
		end
	elseif action == "invite" and type(value) == "string" then
		for _, friend in state.friends do
			if friend.name == value and friend.presence ~= "Offline" and friend.invite == "Invite" then
				friend.invite = "Pending"
				ok = true
				task.delay(2, function()
					local accepted = friend.name == "Mira"
					friend.invite = if accepted then "Accepted" else "Declined"
					if accepted then
						table.insert(state.party, friend.name)
					end
					publish(player)
				end)
			end
		end
	elseif action == "tutorial" then
		state.tutorialDone = true
		ok = true
	end
	if ok then
		publish(player)
	end
	return { ok = ok, reason = if ok then nil else reason, state = state }
end
local admin = Instance.new("BindableFunction")
admin.Name = "ExtendedAdmin"
admin.OnInvoke = function(command: string, fields: { [string]: unknown }?): unknown
	local player = Players:GetPlayers()[1]
	assert(player ~= nil, "no player")
	local state = stateOf(player)
	local options: { [string]: unknown } = fields or {}
	if command == "reset" then
		states[player] = initial(player)
		state = states[player]
	elseif command == "ballot" then
		state.votes = { 2, 3, 1 }
		state.vote = 0
		state.winner = ""
		state.endsAt = now() + (tonumber(options.seconds) or 30)
	elseif command == "votes" then
		state.votes[3] += 8
	elseif command == "finish" then
		state.endsAt = now() - 1
	elseif command ~= "state" then
		error("unknown extended command")
	end
	if state.endsAt > 0 and state.endsAt <= now() and state.winner == "" then
		local best = 1
		for index = 2, 3 do
			if state.votes[index] > state.votes[best] then
				best = index
			end
		end
		state.winner = state.tracks[best]
	end
	publish(player)
	return state
end
admin.Parent = ServerStorage
Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
	signatures[player] = nil
end)
task.spawn(function()
	while true do
		for player, state in states do
			if state.endsAt > 0 and state.endsAt <= now() and state.winner == "" then
				local best = 1
				for index = 2, 3 do
					if state.votes[index] > state.votes[best] then
						best = index
					end
				end
				state.winner = state.tracks[best]
				publish(player)
			end
			local signature = game:GetService("HttpService"):JSONEncode(state)
			if signatures[player] ~= signature then
				signatures[player] = signature
				publish(player)
			end
		end
		task.wait(0.25)
	end
end)
