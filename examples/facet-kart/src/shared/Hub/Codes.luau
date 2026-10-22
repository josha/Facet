--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type Currency = "Coins" | "Gems"

export type Reward = {
	kind: "Currency" | "Item",
	name: string,
	amount: number,
}

export type State = {
	wallet: { Coins: number, Gems: number },
	items: { [string]: number },
	redeemed: { string },
}

export type Failure = "empty" | "invalid" | "expired" | "already_redeemed" | "rate_limited" | "busy"

export type RedeemResult = {
	ok: boolean,
	code: string,
	reason: Failure?,
	retryIn: number?,
	rewards: { Reward },
	state: State,
}

export type Client = {
	getState: () -> State,
	redeem: (code: string) -> RedeemResult,
	onStateChanged: (callback: (State) -> ()) -> RBXScriptConnection,
}

local function client(): Client
	assert(RunService:IsClient(), "Codes.client() runs on the client")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local getState = remotes:WaitForChild("GetCodesState") :: RemoteFunction
	local redeem = remotes:WaitForChild("RedeemCode") :: RemoteFunction
	local changed = remotes:WaitForChild("CodesStateChanged") :: RemoteEvent
	return {
		getState = function(): State
			return getState:InvokeServer()
		end,
		redeem = function(code: string): RedeemResult
			return redeem:InvokeServer(code)
		end,
		onStateChanged = function(callback: (State) -> ()): RBXScriptConnection
			return changed.OnClientEvent:Connect(callback)
		end,
	}
end

return {
	client = client,
}
