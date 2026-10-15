--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type Reward = {
	kind: "Coins" | "Gems" | "Item",
	name: string,
	amount: number,
}

export type Day = { day: number, reward: Reward }

export type State = {
	track: { Day },
	day: number,
	claimedToday: boolean,
	nextClaimAt: number,
	restarted: boolean,
	wallet: { Coins: number, Gems: number },
	items: { [string]: number },
}

export type Failure = "already_claimed" | "busy"

export type ClaimResult = {
	ok: boolean,
	reason: Failure?,
	reward: Reward?,
	state: State,
}

export type Client = {
	getState: () -> State,
	claim: () -> ClaimResult,
	serverNow: () -> number,
	onStateChanged: (callback: (State) -> ()) -> RBXScriptConnection,
}

local function client(): Client
	assert(RunService:IsClient(), "DailyRewards.client() runs on the client")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local getState = remotes:WaitForChild("GetRewardsState") :: RemoteFunction
	local claim = remotes:WaitForChild("ClaimReward") :: RemoteFunction
	local changed = remotes:WaitForChild("RewardsStateChanged") :: RemoteEvent
	return {
		getState = function(): State
			return getState:InvokeServer()
		end,
		claim = function(): ClaimResult
			return claim:InvokeServer()
		end,
		serverNow = function(): number
			return workspace:GetServerTimeNow()
		end,
		onStateChanged = function(callback: (State) -> ()): RBXScriptConnection
			return changed.OnClientEvent:Connect(callback)
		end,
	}
end

return {
	client = client,
}
