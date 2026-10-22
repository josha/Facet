--!strict

local Players = game:GetService("Players")
local Ledger = require(script.Parent.Ledger)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Hub.Economy)

type State = Economy.State
type Result = Economy.Result

export type Entry = { kind: string, ok: boolean, reason: Economy.Failure?, at: number }

type Profile = {
	wallet: Ledger.Wallet,

	earned: number,
	boostEndsAt: number?,
	boosts: number,
	quests: { Economy.Quest },
	offer: Economy.Offer,
	journal: { Entry },
}

local BASE_INCOME = 5
local BOOST_PRICE = 10
local BOOST_SECONDS = 30
local ZONE_GOAL = 5000
local OFFER_SECONDS = 25 * 60

local changed = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("EconomyStateChanged") :: RemoteEvent
local profiles: { [Player]: Profile } = {}
local paused = false

local function profileOf(player: Player): Profile
	local profile = profiles[player]
	if profile == nil then
		local created: Profile = {
			wallet = Ledger.wallet(player),

			earned = 1180,
			boostEndsAt = nil,
			boosts = 0,
			quests = {
				{
					id = "earn_small",
					title = "Earn 1,200 Coins",
					goal = 1200,
					progress = 0,
					reward = 5,
					claimed = false,
				},
				{
					id = "earn_big",
					title = "Earn 10,000 Coins",
					goal = 10000,
					progress = 0,
					reward = 25,
					claimed = false,
				},
				{ id = "boost", title = "Buy a 2x Coins boost", goal = 1, progress = 0, reward = 10, claimed = false },
			},
			offer = {
				name = "Starter Offer",
				coins = 5000,
				price = 99,
				endsAt = workspace:GetServerTimeNow() + OFFER_SECONDS,
				bought = false,
			},
			journal = {},
		}
		profiles[player] = created
		return created
	end
	return profile
end

local function boosted(profile: Profile): boolean
	return profile.boostEndsAt ~= nil and (profile.boostEndsAt :: number) > workspace:GetServerTimeNow()
end

local function refresh(profile: Profile)
	for _, quest in profile.quests do
		if quest.id == "boost" then
			quest.progress = math.min(quest.goal, profile.boosts)
		else
			quest.progress = math.min(quest.goal, profile.earned)
		end
	end
	if not boosted(profile) then
		profile.boostEndsAt = nil
	end
end

local function snapshot(profile: Profile): State
	refresh(profile)
	local quests: { Economy.Quest } = {}
	for _, quest in profile.quests do
		table.insert(quests, table.clone(quest))
	end
	return {
		coins = profile.wallet.Coins,
		gems = profile.wallet.Gems,
		perSecond = if boosted(profile) then BASE_INCOME * 2 else BASE_INCOME,
		boostEndsAt = profile.boostEndsAt,
		boostPrice = BOOST_PRICE,
		zone = 2,
		zoneProgress = math.min(ZONE_GOAL, profile.earned),
		zoneGoal = ZONE_GOAL,
		quests = quests,
		offer = table.clone(profile.offer),
	}
end

local function publish(player: Player)
	changed:FireClient(player, snapshot(profileOf(player)))
end

local function answer(profile: Profile, kind: string, reason: Economy.Failure?): Result
	table.insert(profile.journal, { kind = kind, ok = reason == nil, reason = reason, at = os.clock() })
	return { ok = reason == nil, reason = reason, state = snapshot(profile) }
end

local function earn(profile: Profile, amount: number)
	profile.wallet.Coins += amount
	profile.earned += amount
end

local function buyBoost(player: Player): Result
	local profile = profileOf(player)
	if boosted(profile) then
		return answer(profile, "boost", "already_active")
	end
	if profile.wallet.Gems < BOOST_PRICE then
		return answer(profile, "boost", "insufficient_funds")
	end
	profile.wallet.Gems -= BOOST_PRICE
	profile.boosts += 1
	profile.boostEndsAt = workspace:GetServerTimeNow() + BOOST_SECONDS
	publish(player)
	return answer(profile, "boost", nil)
end

local function claimQuest(player: Player, questId: unknown): Result
	local profile = profileOf(player)
	refresh(profile)
	for _, quest in profile.quests do
		if quest.id == questId then
			if quest.claimed then
				return answer(profile, "quest", "already_claimed")
			end
			if quest.progress < quest.goal then
				return answer(profile, "quest", "not_complete")
			end
			quest.claimed = true
			profile.wallet.Gems += quest.reward
			publish(player)
			return answer(profile, "quest", nil)
		end
	end
	return answer(profile, "quest", "unknown_quest")
end

local function buyOffer(player: Player): Result
	local profile = profileOf(player)
	local offer = profile.offer
	if offer.bought then
		return answer(profile, "offer", "already_bought")
	end
	if workspace:GetServerTimeNow() >= offer.endsAt then
		return answer(profile, "offer", "expired")
	end
	if profile.wallet.Gems < offer.price then
		return answer(profile, "offer", "insufficient_funds")
	end
	profile.wallet.Gems -= offer.price
	offer.bought = true
	earn(profile, offer.coins)
	publish(player)
	return answer(profile, "offer", nil)
end

local function start()
	task.spawn(function()
		while true do
			task.wait(1)
			if not paused then
				for player, profile in profiles do
					earn(profile, if boosted(profile) then BASE_INCOME * 2 else BASE_INCOME)
					publish(player)
				end
			end
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		profileOf(player)
	end)
	for _, player in Players:GetPlayers() do
		profileOf(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		profiles[player] = nil
	end)
end

return {
	start = start,
	getState = function(player: Player): State
		return snapshot(profileOf(player))
	end,
	buyBoost = buyBoost,
	claimQuest = claimQuest,
	buyOffer = buyOffer,
	setPaused = function(value: boolean)
		paused = value
	end,
	grant = function(player: Player, coins: number, gems: number)
		local profile = profileOf(player)
		earn(profile, coins)
		profile.wallet.Gems += gems
		publish(player)
	end,
	journal = function(player: Player): { Entry }
		return table.clone(profileOf(player).journal)
	end,
}
