--!strict

local Players = game:GetService("Players")
local Ledger = require(script.Parent.Ledger)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Codes = require(ReplicatedStorage.Shared.Hub.Codes)

type State = Codes.State
type Reward = Codes.Reward
type RedeemResult = Codes.RedeemResult

export type Entry = { code: string, ok: boolean, reason: Codes.Failure?, at: number }

type Definition = { rewards: { Reward }, expired: boolean }

type Profile = {
	wallet: { Coins: number, Gems: number },
	items: { [string]: number },
	redeemed: { string },
	failures: { number },
	busy: boolean,
	journal: { Entry },
}

local CATALOG: { [string]: Definition } = {
	WELCOME = {
		rewards = {
			{ kind = "Currency", name = "Coins", amount = 500 },
			{ kind = "Currency", name = "Gems", amount = 10 },
		},
		expired = false,
	},
	SPEEDY = {
		rewards = { { kind = "Item", name = "Speed Potion", amount = 2 } },
		expired = false,
	},
	LUCKY7 = {
		rewards = {
			{ kind = "Item", name = "Lucky Charm", amount = 1 },
			{ kind = "Currency", name = "Coins", amount = 77 },
		},
		expired = false,
	},
	SUMMER24 = {
		rewards = { { kind = "Currency", name = "Gems", amount = 50 } },
		expired = true,
	},
}

local FAILURE_LIMIT = 5
local FAILURE_WINDOW = 30
local SERVER_DELAY = 0.4

local profiles: { [Player]: Profile } = {}
local changed = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CodesStateChanged") :: RemoteEvent

local function profileOf(player: Player): Profile
	local profile = profiles[player]
	if profile == nil then
		local created: Profile = {
			wallet = Ledger.wallet(player),
			items = {},
			redeemed = {},
			failures = {},
			busy = false,
			journal = {},
		}
		profiles[player] = created
		return created
	end
	return profile
end

local function snapshot(profile: Profile): State
	return {
		wallet = { Coins = profile.wallet.Coins, Gems = profile.wallet.Gems },
		items = table.clone(profile.items),
		redeemed = table.clone(profile.redeemed),
	}
end

local function publish(player: Player)
	changed:FireClient(player, snapshot(profileOf(player)))
end

local function normalize(raw: unknown): string
	if type(raw) ~= "string" then
		return ""
	end
	local trimmed = string.match(raw, "^%s*(.-)%s*$") or ""
	return string.upper(string.sub(trimmed, 1, 40))
end

local function getState(player: Player): State
	return snapshot(profileOf(player))
end

local function redeem(player: Player, raw: unknown): RedeemResult
	local profile = profileOf(player)
	local code = normalize(raw)
	local now = os.clock()
	local function refuse(reason: Codes.Failure, retryIn: number?): RedeemResult
		table.insert(profile.journal, { code = code, ok = false, reason = reason, at = now })
		return { ok = false, code = code, reason = reason, retryIn = retryIn, rewards = {}, state = snapshot(profile) }
	end
	local recent: { number } = {}
	for _, at in profile.failures do
		if now - at < FAILURE_WINDOW then
			table.insert(recent, at)
		end
	end
	profile.failures = recent
	if #recent >= FAILURE_LIMIT then
		return refuse("rate_limited", math.max(1, math.ceil(FAILURE_WINDOW - (now - recent[1]))))
	end
	if code == "" then
		return refuse("empty")
	end
	if profile.busy then
		return refuse("busy")
	end
	local definition = CATALOG[code]
	if definition == nil then
		table.insert(profile.failures, now)
		return refuse("invalid")
	end
	if definition.expired then
		table.insert(profile.failures, now)
		return refuse("expired")
	end
	if table.find(profile.redeemed, code) ~= nil then
		return refuse("already_redeemed")
	end
	profile.busy = true
	task.wait(SERVER_DELAY)
	for _, reward in definition.rewards do
		if reward.kind == "Currency" then
			if reward.name == "Gems" then
				profile.wallet.Gems += reward.amount
			else
				profile.wallet.Coins += reward.amount
			end
		else
			profile.items[reward.name] = (profile.items[reward.name] or 0) + reward.amount
		end
	end
	table.insert(profile.redeemed, code)
	profile.busy = false
	table.insert(profile.journal, { code = code, ok = true, reason = nil, at = os.clock() })
	publish(player)
	return {
		ok = true,
		code = code,
		reason = nil,
		retryIn = nil,
		rewards = table.clone(definition.rewards),
		state = snapshot(profile),
	}
end

local function journal(player: Player): { Entry }
	return table.clone(profileOf(player).journal)
end

Players.PlayerRemoving:Connect(function(player)
	profiles[player] = nil
end)

return {
	getState = getState,
	redeem = redeem,
	journal = journal,
}
