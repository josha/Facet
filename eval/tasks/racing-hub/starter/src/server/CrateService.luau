--!strict

local Players = game:GetService("Players")
local Ledger = require(script.Parent.Ledger)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Crates = require(ReplicatedStorage.Shared.Hub.Crates)

type State = Crates.State
type Card = Crates.Card

export type Entry = { crate: string, ok: boolean, reason: Crates.Failure?, cards: { string }, at: number }

type Profile = {
	wallet: Ledger.Wallet,
	collection: { [string]: number },
	opened: number,
	busy: boolean,
	journal: { Entry },
}

local SERVER_DELAY = 0.4
local RARITIES: { Crates.Rarity } = { "Common", "Rare", "Epic", "Legendary" }

local profiles: { [Player]: Profile } = {}
local changed = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CrateStateChanged") :: RemoteEvent

local byRarity: { [string]: { Card } } = {}
for _, card in Crates.cards do
	byRarity[card.rarity] = byRarity[card.rarity] or {}
	table.insert(byRarity[card.rarity], card)
end

local function profileOf(player: Player): Profile
	local profile = profiles[player]
	if profile == nil then
		local created: Profile =
			{ wallet = Ledger.wallet(player), collection = {}, opened = 0, busy = false, journal = {} }
		profiles[player] = created
		return created
	end
	return profile
end

local function snapshot(profile: Profile): State
	return { gems = profile.wallet.Gems, collection = table.clone(profile.collection) }
end

local function publish(player: Player)
	changed:FireClient(player, snapshot(profileOf(player)))
end

local function chance(odds: Crates.Odds, rarity: string): number
	return if rarity == "Common"
		then odds.Common
		elseif rarity == "Rare" then odds.Rare
		elseif rarity == "Epic" then odds.Epic
		else odds.Legendary
end

local function crateOf(id: string): Crates.Crate?
	for _, crate in Crates.crates do
		if crate.id == id then
			return crate
		end
	end
	return nil
end

local function draw(crate: Crates.Crate, random: Random): { Card }
	local result: { Card } = {}
	for _ = 1, crate.cards do
		local roll = random:NextNumber() * 100
		local chosen: Crates.Rarity = "Common"
		local sum = 0
		for _, rarity in RARITIES do
			sum += chance(crate.odds, rarity)
			if roll < sum then
				chosen = rarity :: Crates.Rarity
				break
			end
		end
		local pool = byRarity[chosen]
		table.insert(result, table.clone(pool[random:NextInteger(1, #pool)]))
	end
	return result
end

local function getState(player: Player): State
	return snapshot(profileOf(player))
end

local function open(player: Player, crateId: unknown): Crates.OpenResult
	local profile = profileOf(player)
	local id = if type(crateId) == "string" then crateId else ""
	local function refuse(reason: Crates.Failure): Crates.OpenResult
		table.insert(profile.journal, { crate = id, ok = false, reason = reason, cards = {}, at = os.clock() })
		return { ok = false, crate = id, reason = reason, cards = {}, state = snapshot(profile) }
	end
	local crate = crateOf(id)
	if crate == nil then
		return refuse("unknown_crate")
	end
	if profile.busy then
		return refuse("busy")
	end
	local free = id == "starter" and Ledger.progress(player).crates > 0
	if not free and profile.wallet.Gems < (crate :: Crates.Crate).price then
		return refuse("insufficient_funds")
	end
	profile.busy = true
	task.wait(SERVER_DELAY)
	profile.opened += 1
	local cards = draw(crate :: Crates.Crate, Random.new(1000 + profile.opened))
	if not free or not Ledger.consumeCrate(player) then
		profile.wallet.Gems -= (crate :: Crates.Crate).price
	end
	local names: { string } = {}
	for _, card in cards do
		profile.collection[card.id] = (profile.collection[card.id] or 0) + 1
		table.insert(names, card.id)
	end
	profile.busy = false
	table.insert(profile.journal, { crate = id, ok = true, reason = nil, cards = names, at = os.clock() })
	publish(player)
	return { ok = true, crate = id, reason = nil, cards = cards, state = snapshot(profile) }
end

local function grant(player: Player, gems: number)
	local profile = profileOf(player)
	profile.wallet.Gems = math.max(0, profile.wallet.Gems + gems)
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
	open = open,
	grant = grant,
	journal = journal,
}
