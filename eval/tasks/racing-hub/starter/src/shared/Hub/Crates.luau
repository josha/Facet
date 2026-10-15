--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"

export type Card = { id: string, name: string, rarity: Rarity }

export type Odds = { Common: number, Rare: number, Epic: number, Legendary: number }

export type Crate = { id: string, name: string, price: number, cards: number, odds: Odds }

export type State = {
	gems: number,
	collection: { [string]: number },
}

export type Failure = "insufficient_funds" | "unknown_crate" | "busy"

export type OpenResult = {
	ok: boolean,
	crate: string,
	reason: Failure?,
	cards: { Card },
	state: State,
}

export type Client = {
	crates: { Crate },
	cards: { Card },
	getState: () -> State,
	open: (crateId: string) -> OpenResult,
	onStateChanged: (callback: (State) -> ()) -> RBXScriptConnection,
}

local crates: { Crate } = {
	{
		id = "starter",
		name = "Starter Crate",
		price = 50,
		cards = 3,
		odds = { Common = 70, Rare = 25, Epic = 5, Legendary = 0 },
	},
	{
		id = "veteran",
		name = "Veteran Crate",
		price = 120,
		cards = 4,
		odds = { Common = 45, Rare = 35, Epic = 17, Legendary = 3 },
	},
	{
		id = "legend",
		name = "Legend Crate",
		price = 300,
		cards = 5,
		odds = { Common = 20, Rare = 40, Epic = 30, Legendary = 10 },
	},
}

local cards: { Card } = {
	{ id = "pebble_golem", name = "Pebble Golem", rarity = "Common" },
	{ id = "moss_sprite", name = "Moss Sprite", rarity = "Common" },
	{ id = "dune_beetle", name = "Dune Beetle", rarity = "Common" },
	{ id = "river_otter", name = "River Otter", rarity = "Common" },
	{ id = "frost_fox", name = "Frost Fox", rarity = "Rare" },
	{ id = "ember_hawk", name = "Ember Hawk", rarity = "Rare" },
	{ id = "tide_serpent", name = "Tide Serpent", rarity = "Rare" },
	{ id = "storm_lion", name = "Storm Lion", rarity = "Epic" },
	{ id = "crystal_stag", name = "Crystal Stag", rarity = "Epic" },
	{ id = "sun_dragon", name = "Sun Dragon", rarity = "Legendary" },
	{ id = "moon_whale", name = "Moon Whale", rarity = "Legendary" },
}

local function client(): Client
	assert(RunService:IsClient(), "Crates.client() runs on the client")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local getState = remotes:WaitForChild("GetCrateState") :: RemoteFunction
	local open = remotes:WaitForChild("OpenCrate") :: RemoteFunction
	local changed = remotes:WaitForChild("CrateStateChanged") :: RemoteEvent
	return {
		crates = crates,
		cards = cards,
		getState = function(): State
			return getState:InvokeServer()
		end,
		open = function(crateId: string): OpenResult
			return open:InvokeServer(crateId)
		end,
		onStateChanged = function(callback: (State) -> ()): RBXScriptConnection
			return changed.OnClientEvent:Connect(callback)
		end,
	}
end

return {
	client = client,
	crates = crates,
	cards = cards,
}
