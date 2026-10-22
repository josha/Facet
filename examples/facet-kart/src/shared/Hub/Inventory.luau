--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Items = require(script.Parent.Items)

export type Slot = Items.Slot
export type Rarity = Items.Rarity
export type Definition = Items.Definition

export type State = {
	owned: { string },
	equipped: { [Slot]: string },
}

export type Failure = "not_owned" | "unknown_item" | "empty_slot"

export type Result = {
	ok: boolean,
	reason: Failure?,
	state: State,
}

export type Client = {
	definitions: { Definition },
	slots: { Slot },
	getState: () -> State,
	equip: (itemId: string) -> Result,
	unequip: (slot: Slot) -> Result,
	onChanged: (callback: (State) -> ()) -> RBXScriptConnection,
}

local function client(): Client
	assert(RunService:IsClient(), "Inventory.client() runs on the client")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local getInventory = remotes:WaitForChild("GetInventory") :: RemoteFunction
	local equip = remotes:WaitForChild("Equip") :: RemoteFunction
	local unequip = remotes:WaitForChild("Unequip") :: RemoteFunction
	local changed = remotes:WaitForChild("InventoryChanged") :: RemoteEvent
	return {
		definitions = Items.definitions,
		slots = Items.slots,
		getState = function(): State
			return getInventory:InvokeServer()
		end,
		equip = function(itemId: string): Result
			return equip:InvokeServer(itemId)
		end,
		unequip = function(slot: Slot): Result
			return unequip:InvokeServer(slot)
		end,
		onChanged = function(callback: (State) -> ()): RBXScriptConnection
			return changed.OnClientEvent:Connect(callback)
		end,
	}
end

return {
	client = client,
	definitions = Items.definitions,
	byId = Items.byId,
	slots = Items.slots,
}
