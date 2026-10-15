--!strict

local Players = game:GetService("Players")
local Ledger = require(script.Parent.Ledger)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyRewards = require(ReplicatedStorage.Shared.Hub.DailyRewards)

type State = DailyRewards.State
type Reward = DailyRewards.Reward

export type Entry = { kind: string, day: number, ok: boolean, reason: string?, at: number }

type Profile = {
	day: number,
	claimedToday: boolean,
	nextClaimAt: number,
	restarted: boolean,
	wallet: { Coins: number, Gems: number },
	items: { [string]: number },
	busy: boolean,
	journal: { Entry },
}

local TRACK: { DailyRewards.Day } = {
	{ day = 1, reward = { kind = "Coins", name = "Coins", amount = 100 } },
	{ day = 2, reward = { kind = "Coins", name = "Coins", amount = 150 } },
	{ day = 3, reward = { kind = "Gems", name = "Gems", amount = 5 } },
	{ day = 4, reward = { kind = "Coins", name = "Coins", amount = 300 } },
	{ day = 5, reward = { kind = "Gems", name = "Gems", amount = 10 } },
	{ day = 6, reward = { kind = "Item", name = "Speed Potion", amount = 3 } },
	{ day = 7, reward = { kind = "Item", name = "Legendary Crate", amount = 1 } },
}

local COOLDOWN = 6 * 3600
local SERVER_DELAY = 0.3

local profiles: { [Player]: Profile } = {}
local changed = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RewardsStateChanged") :: RemoteEvent

local function profileOf(player: Player): Profile
	local profile = profiles[player]
	if profile == nil then
		local created: Profile = {
			day = 3,
			claimedToday = false,
			nextClaimAt = 0,
			restarted = false,
			wallet = Ledger.wallet(player),
			items = {},
			busy = false,
			journal = {},
		}
		profiles[player] = created
		return created
	end
	return profile
end

local function snapshot(profile: Profile): State
	local track: { DailyRewards.Day } = {}
	for _, entry in TRACK do
		table.insert(track, { day = entry.day, reward = table.clone(entry.reward) })
	end
	return {
		track = track,
		day = profile.day,
		claimedToday = profile.claimedToday,
		nextClaimAt = profile.nextClaimAt,
		restarted = profile.restarted,
		wallet = { Coins = profile.wallet.Coins, Gems = profile.wallet.Gems },
		items = table.clone(profile.items),
	}
end

local function publish(player: Player)
	changed:FireClient(player, snapshot(profileOf(player)))
end

local function getState(player: Player): State
	return snapshot(profileOf(player))
end

local function claim(player: Player): DailyRewards.ClaimResult
	local profile = profileOf(player)
	if profile.busy then
		return { ok = false, reason = "busy", reward = nil, state = snapshot(profile) }
	end
	if profile.claimedToday then
		table.insert(
			profile.journal,
			{ kind = "claim", day = profile.day, ok = false, reason = "already_claimed", at = os.clock() }
		)
		return { ok = false, reason = "already_claimed", reward = nil, state = snapshot(profile) }
	end
	profile.busy = true
	task.wait(SERVER_DELAY)
	local reward = TRACK[profile.day].reward
	if reward.kind == "Coins" then
		profile.wallet.Coins += reward.amount
	elseif reward.kind == "Gems" then
		profile.wallet.Gems += reward.amount
	else
		profile.items[reward.name] = (profile.items[reward.name] or 0) + reward.amount
	end
	profile.claimedToday = true
	profile.restarted = false
	profile.nextClaimAt = workspace:GetServerTimeNow() + COOLDOWN
	profile.busy = false
	table.insert(profile.journal, { kind = "claim", day = profile.day, ok = true, reason = nil, at = os.clock() })
	publish(player)
	return { ok = true, reason = nil, reward = table.clone(reward), state = snapshot(profile) }
end

local function advance(player: Player)
	local profile = profileOf(player)
	profile.day = if profile.claimedToday then profile.day % #TRACK + 1 else profile.day
	profile.claimedToday = false
	profile.nextClaimAt = 0
	profile.restarted = false
	table.insert(profile.journal, { kind = "advance", day = profile.day, ok = true, reason = nil, at = os.clock() })
	publish(player)
end

local function miss(player: Player)
	local profile = profileOf(player)
	profile.day = 1
	profile.claimedToday = false
	profile.nextClaimAt = 0
	profile.restarted = true
	table.insert(profile.journal, { kind = "miss", day = 1, ok = true, reason = nil, at = os.clock() })
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
	claim = claim,
	advance = advance,
	miss = miss,
	journal = journal,
}
