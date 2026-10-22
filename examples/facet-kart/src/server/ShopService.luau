--!strict

local Players = game:GetService("Players")
local Ledger = require(script.Parent.Ledger)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shop = require(ReplicatedStorage.Shared.Hub.Shop)

type State = Shop.State
type PurchaseResult = Shop.PurchaseResult

export type Entry = { kind: string, item: string?, ok: boolean, reason: string?, at: number }

type Profile = {
	wallet: Shop.Wallet,
	owned: { [string]: boolean },
	busy: boolean,
	journal: { Entry },
}

local STARTING_ITEMS = { "starter_motor" }
local SERVER_DELAY = 0.25

local profiles: { [Player]: Profile } = {}
local changed = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ShopStateChanged") :: RemoteEvent

local function fresh(player: Player): Profile
	local owned: { [string]: boolean } = {}
	for _, id in STARTING_ITEMS do
		owned[id] = true
	end
	return {
		wallet = Ledger.wallet(player),
		owned = owned,
		busy = false,
		journal = {},
	}
end

local function balance(wallet: Shop.Wallet, currency: Shop.Currency): number
	return if currency == "Gems" then wallet.Gems else wallet.Coins
end

local function adjust(wallet: Shop.Wallet, currency: Shop.Currency, delta: number)
	if currency == "Gems" then
		wallet.Gems = math.max(0, wallet.Gems + delta)
	else
		wallet.Coins = math.max(0, wallet.Coins + delta)
	end
end

local function profileOf(player: Player): Profile
	local profile = profiles[player]
	if profile == nil then
		local created = fresh(player)
		profiles[player] = created
		return created
	end
	return profile
end

local function snapshot(profile: Profile): State
	return {
		wallet = { Coins = profile.wallet.Coins, Gems = profile.wallet.Gems },
		owned = table.clone(profile.owned),
	}
end

local function publish(player: Player)
	changed:FireClient(player, snapshot(profileOf(player)))
end

local function record(profile: Profile, entry: Entry)
	table.insert(profile.journal, entry)
end

local function getState(player: Player): State
	return snapshot(profileOf(player))
end

local function purchase(player: Player, itemId: unknown): PurchaseResult
	local profile = profileOf(player)
	local id = if type(itemId) == "string" then itemId else ""
	local function refuse(reason: Shop.Failure): PurchaseResult
		record(profile, { kind = "purchase", item = id, ok = false, reason = reason, at = os.clock() })
		return { ok = false, item = id, reason = reason, state = snapshot(profile) }
	end
	local item = Shop.byId[id]
	if item == nil then
		return refuse("unknown_item")
	end
	if profile.busy then
		return refuse("busy")
	end
	if profile.owned[id] then
		return refuse("already_owned")
	end
	if balance(profile.wallet, item.currency) < item.price then
		return refuse("insufficient_funds")
	end
	profile.busy = true
	task.wait(SERVER_DELAY)
	adjust(profile.wallet, item.currency, -item.price)
	profile.owned[id] = true
	profile.busy = false
	record(profile, { kind = "purchase", item = id, ok = true, reason = nil, at = os.clock() })
	publish(player)
	return { ok = true, item = id, reason = nil, state = snapshot(profile) }
end

local function grant(player: Player, currency: Shop.Currency, amount: number)
	local profile = profileOf(player)
	adjust(profile.wallet, currency, amount)
	record(profile, { kind = "grant", item = currency, ok = true, reason = nil, at = os.clock() })
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
	purchase = purchase,
	grant = grant,
	journal = journal,
	publish = publish,
}
