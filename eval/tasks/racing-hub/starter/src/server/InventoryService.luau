--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Inventory = require(ReplicatedStorage.Shared.Hub.Inventory)

type State = Inventory.State
type Result = Inventory.Result
type Slot = Inventory.Slot

export type Entry = { kind: string, item: string?, ok: boolean, reason: string?, at: number }

type Profile = {
	owned: { string },
	equipped: { [Slot]: string },
	journal: { Entry },
}

local STARTING_ITEMS = {
	"starter_motor",
	"frost_motor",
	"ember_motor",
	"light_body",
	"steel_body",
	"city_wheels",
	"snow_wheels",
	"spark_trail",
	"galaxy_trail",
}

local profiles: { [Player]: Profile } = {}
local changed = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("InventoryChanged") :: RemoteEvent

local function fresh(): Profile
	return {
		owned = table.clone(STARTING_ITEMS),
		equipped = { Motor = "starter_motor", Body = "light_body", Wheels = "city_wheels" },
		journal = {},
	}
end

local function profileOf(player: Player): Profile
	local profile = profiles[player]
	if profile == nil then
		local created = fresh()
		profiles[player] = created
		return created
	end
	return profile
end

local function snapshot(profile: Profile): State
	return { owned = table.clone(profile.owned), equipped = table.clone(profile.equipped) }
end

local function publish(player: Player)
	changed:FireClient(player, snapshot(profileOf(player)))
end

local function record(profile: Profile, kind: string, item: string?, ok: boolean, reason: string?)
	table.insert(profile.journal, { kind = kind, item = item, ok = ok, reason = reason, at = os.clock() })
end

local function getState(player: Player): State
	return snapshot(profileOf(player))
end

local function equip(player: Player, itemId: unknown): Result
	local profile = profileOf(player)
	local id = if type(itemId) == "string" then itemId else ""
	local definition = Inventory.byId[id]
	if definition == nil then
		record(profile, "equip", id, false, "unknown_item")
		return { ok = false, reason = "unknown_item", state = snapshot(profile) }
	end
	if table.find(profile.owned, id) == nil then
		record(profile, "equip", id, false, "not_owned")
		return { ok = false, reason = "not_owned", state = snapshot(profile) }
	end
	profile.equipped[definition.slot] = id
	record(profile, "equip", id, true, nil)
	publish(player)
	return { ok = true, reason = nil, state = snapshot(profile) }
end

local function unequip(player: Player, slot: unknown): Result
	local profile = profileOf(player)
	local name = if type(slot) == "string" then slot else ""
	if table.find(Inventory.slots, name :: Slot) == nil or profile.equipped[name :: Slot] == nil then
		record(profile, "unequip", name, false, "empty_slot")
		return { ok = false, reason = "empty_slot", state = snapshot(profile) }
	end
	profile.equipped[name :: Slot] = nil
	record(profile, "unequip", name, true, nil)
	publish(player)
	return { ok = true, reason = nil, state = snapshot(profile) }
end

local function give(player: Player, itemId: string): boolean
	local profile = profileOf(player)
	if Inventory.byId[itemId] == nil or table.find(profile.owned, itemId) ~= nil then
		return false
	end
	table.insert(profile.owned, itemId)
	record(profile, "give", itemId, true, nil)
	publish(player)
	return true
end

local function journal(player: Player): { Entry }
	return table.clone(profileOf(player).journal)
end

Players.PlayerRemoving:Connect(function(player)
	profiles[player] = nil
end)

return {
	getState = getState,
	equip = equip,
	unequip = unequip,
	give = give,
	journal = journal,
}
