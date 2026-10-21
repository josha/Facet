--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Catalog = require(script.Parent.Catalog)

export type Currency = Catalog.Currency
export type Category = Catalog.Category
export type Item = Catalog.Item

export type Wallet = { Coins: number, Gems: number }

export type State = {
	wallet: Wallet,
	owned: { [string]: boolean },
}

export type Failure = "insufficient_funds" | "already_owned" | "unknown_item" | "busy"

export type PurchaseResult = {
	ok: boolean,
	item: string,
	reason: Failure?,
	state: State,
}

export type Client = {
	catalog: { Item },
	categories: { Category },
	getState: () -> State,
	purchase: (itemId: string) -> PurchaseResult,
	onStateChanged: (callback: (State) -> ()) -> RBXScriptConnection,
}

local function client(): Client
	assert(RunService:IsClient(), "Shop.client() runs on the client")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local getState = remotes:WaitForChild("GetShopState") :: RemoteFunction
	local purchase = remotes:WaitForChild("Purchase") :: RemoteFunction
	local changed = remotes:WaitForChild("ShopStateChanged") :: RemoteEvent
	return {
		catalog = Catalog.items,
		categories = Catalog.categories,
		getState = function(): State
			return getState:InvokeServer()
		end,
		purchase = function(itemId: string): PurchaseResult
			return purchase:InvokeServer(itemId)
		end,
		onStateChanged = function(callback: (State) -> ()): RBXScriptConnection
			return changed.OnClientEvent:Connect(callback)
		end,
	}
end

return {
	client = client,
	catalog = Catalog.items,
	byId = Catalog.byId,
	categories = Catalog.categories,
}
