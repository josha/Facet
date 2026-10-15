--!strict

local Players = game:GetService("Players")
local Ledger = require(script.Parent.Ledger)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Drivers = require(ReplicatedStorage.Shared.Hub.Drivers)

type State = Drivers.State
type Result = Drivers.Result

export type Entry = { kind: string, driver: string, ok: boolean, reason: Drivers.Failure?, at: number }

type Profile = {
	wallet: Ledger.Wallet,
	owned: { [string]: boolean },
	rented: { [string]: number },
	equipped: string?,
	busy: boolean,
	journal: { Entry },
}

local profiles: { [Player]: Profile } = {}
local changed = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DriverStateChanged") :: RemoteEvent

local byId: { [string]: Drivers.Driver } = {}
for _, driver in Drivers.drivers do
	byId[driver.id] = driver
end

local function profileOf(player: Player): Profile
	local profile = profiles[player]
	if profile == nil then
		local created: Profile = {
			wallet = Ledger.wallet(player),
			owned = { haru = true },
			rented = {},
			equipped = "haru",
			busy = false,
			journal = {},
		}
		profiles[player] = created
		return created
	end
	return profile
end

local function prune(profile: Profile)
	local now = workspace:GetServerTimeNow()
	for id, expires in profile.rented do
		if expires <= now then
			profile.rented[id] = nil
			if profile.equipped == id then
				profile.equipped = nil
			end
		end
	end
end

local function snapshot(profile: Profile): State
	prune(profile)
	return {
		coins = profile.wallet.Coins,
		owned = table.clone(profile.owned),
		rented = table.clone(profile.rented),
		equipped = profile.equipped,
	}
end

local function publish(player: Player)
	changed:FireClient(player, snapshot(profileOf(player)))
end

local function answer(profile: Profile, kind: string, id: string, reason: Drivers.Failure?): Result
	table.insert(profile.journal, { kind = kind, driver = id, ok = reason == nil, reason = reason, at = os.clock() })
	return { ok = reason == nil, reason = reason, state = snapshot(profile) }
end

local function pay(player: Player, raw: unknown, kind: "buy" | "rent"): Result
	local profile = profileOf(player)
	local id = if type(raw) == "string" then raw else ""
	local driver = byId[id]
	if driver == nil then
		return answer(profile, kind, id, "unknown_driver")
	end
	if profile.busy then
		return answer(profile, kind, id, "busy")
	end
	if profile.owned[id] then
		return answer(profile, kind, id, "already_owned")
	end
	local cost = if kind == "buy" then driver.price else driver.rentPrice
	if profile.wallet.Coins < cost then
		return answer(profile, kind, id, "insufficient_funds")
	end
	profile.busy = true
	task.wait(0.4)
	profile.wallet.Coins -= cost
	if kind == "buy" then
		profile.owned[id] = true
		profile.rented[id] = nil
	else
		profile.rented[id] = workspace:GetServerTimeNow() + Drivers.rentSeconds
	end
	profile.busy = false
	publish(player)
	return answer(profile, kind, id, nil)
end

local function equip(player: Player, raw: unknown): Result
	local profile = profileOf(player)
	local id = if type(raw) == "string" then raw else ""
	prune(profile)
	if byId[id] == nil then
		return answer(profile, "equip", id, "unknown_driver")
	end
	if not profile.owned[id] and profile.rented[id] == nil then
		return answer(profile, "equip", id, "not_available")
	end
	profile.equipped = id
	Ledger.setDriver(player, id)
	publish(player)
	return answer(profile, "equip", id, nil)
end

local function getState(player: Player): State
	return snapshot(profileOf(player))
end

local function grant(player: Player, coins: number)
	local profile = profileOf(player)
	profile.wallet.Coins = math.max(0, profile.wallet.Coins + coins)
	publish(player)
end

local function journal(player: Player): { Entry }
	return table.clone(profileOf(player).journal)
end

Players.PlayerRemoving:Connect(function(player)
	profiles[player] = nil
end)

return {
	getState = getState,
	buy = function(player: Player, id: unknown): Result
		return pay(player, id, "buy")
	end,
	rent = function(player: Player, id: unknown): Result
		return pay(player, id, "rent")
	end,
	equip = equip,
	grant = grant,
	journal = journal,
}
