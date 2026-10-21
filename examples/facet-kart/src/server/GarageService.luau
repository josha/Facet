--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ledger = require(script.Parent.Ledger)
local Garage = require(ReplicatedStorage.Shared.Hub.Garage)

type State = Garage.State
type Result = Garage.Result

export type Entry = { kind: string, vehicle: string?, ok: boolean, reason: Garage.Failure?, at: number }

type Profile = {
	favorites: { [string]: boolean },
	spawned: string?,
	busy: boolean,
	journal: { Entry },
}

local profiles: { [Player]: Profile } = {}
local changed = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GarageStateChanged") :: RemoteEvent

local known: { [string]: boolean } = {}
for _, vehicle in Garage.vehicles do
	known[vehicle.id] = true
end

local function profileOf(player: Player): Profile
	local profile = profiles[player]
	if profile == nil then
		local created: Profile = { favorites = { summit_kart = true }, spawned = nil, busy = false, journal = {} }
		profiles[player] = created
		return created
	end
	return profile
end

local function snapshot(profile: Profile): State
	return { favorites = table.clone(profile.favorites), spawned = profile.spawned }
end

local function publish(player: Player)
	changed:FireClient(player, snapshot(profileOf(player)))
end

local function answer(profile: Profile, kind: string, vehicle: string?, reason: Garage.Failure?): Result
	table.insert(
		profile.journal,
		{ kind = kind, vehicle = vehicle, ok = reason == nil, reason = reason, at = os.clock() }
	)
	return { ok = reason == nil, reason = reason, state = snapshot(profile) }
end

local function getState(player: Player): State
	return snapshot(profileOf(player))
end

local function spawnVehicle(player: Player, vehicleId: unknown): Result
	local profile = profileOf(player)
	local id = if type(vehicleId) == "string" then vehicleId else ""
	if not known[id] then
		return answer(profile, "spawn", id, "unknown_vehicle")
	end
	if profile.busy then
		return answer(profile, "spawn", id, "busy")
	end
	if profile.spawned ~= nil then
		return answer(profile, "spawn", id, "already_spawned")
	end
	profile.busy = true
	task.wait(0.4)
	profile.spawned = id
	Ledger.setKart(player, id)
	profile.busy = false
	publish(player)
	return answer(profile, "spawn", id, nil)
end

local function exitVehicle(player: Player): Result
	local profile = profileOf(player)
	if profile.spawned == nil then
		return answer(profile, "exit", nil, "nothing_spawned")
	end
	local id = profile.spawned
	profile.spawned = nil
	publish(player)
	return answer(profile, "exit", id, nil)
end

local function setFavorite(player: Player, vehicleId: unknown, favorite: unknown): Result
	local profile = profileOf(player)
	local id = if type(vehicleId) == "string" then vehicleId else ""
	if not known[id] then
		return answer(profile, "favorite", id, "unknown_vehicle")
	end
	if favorite == true then
		profile.favorites[id] = true
	else
		profile.favorites[id] = nil
	end
	publish(player)
	return answer(profile, "favorite", id, nil)
end

local function journal(player: Player): { Entry }
	return table.clone(profileOf(player).journal)
end

Players.PlayerRemoving:Connect(function(player)
	profiles[player] = nil
end)

return {
	getState = getState,
	spawn = spawnVehicle,
	exit = exitVehicle,
	setFavorite = setFavorite,
	journal = journal,
}
