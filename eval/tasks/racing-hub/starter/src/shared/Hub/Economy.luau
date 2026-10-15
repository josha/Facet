--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type Quest = {
	id: string,
	title: string,
	goal: number,
	progress: number,
	reward: number,
	claimed: boolean,
}

export type Offer = {
	name: string,
	coins: number,
	price: number,
	endsAt: number,
	bought: boolean,
}

export type State = {
	coins: number,
	gems: number,
	perSecond: number,
	boostEndsAt: number?,
	boostPrice: number,
	zone: number,
	zoneProgress: number,
	zoneGoal: number,
	quests: { Quest },
	offer: Offer,
}

export type Failure =
	"insufficient_funds"
	| "already_active"
	| "not_complete"
	| "already_claimed"
	| "expired"
	| "already_bought"
	| "unknown_quest"

export type Result = { ok: boolean, reason: Failure?, state: State }

export type Client = {
	getState: () -> State,
	buyBoost: () -> Result,
	claimQuest: (questId: string) -> Result,
	buyOffer: () -> Result,
	serverNow: () -> number,
	onStateChanged: (callback: (State) -> ()) -> RBXScriptConnection,
}

local function client(): Client
	assert(RunService:IsClient(), "Economy.client() runs on the client")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local getState = remotes:WaitForChild("GetEconomyState") :: RemoteFunction
	local buyBoost = remotes:WaitForChild("BuyBoost") :: RemoteFunction
	local claimQuest = remotes:WaitForChild("ClaimQuest") :: RemoteFunction
	local buyOffer = remotes:WaitForChild("BuyOffer") :: RemoteFunction
	local changed = remotes:WaitForChild("EconomyStateChanged") :: RemoteEvent
	return {
		getState = function(): State
			return getState:InvokeServer()
		end,
		buyBoost = function(): Result
			return buyBoost:InvokeServer()
		end,
		claimQuest = function(questId: string): Result
			return claimQuest:InvokeServer(questId)
		end,
		buyOffer = function(): Result
			return buyOffer:InvokeServer()
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
