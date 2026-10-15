--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type Phase = "Intermission" | "Round" | "Results"

export type Team = "Red" | "Blue"

export type Fighter = {
	name: string,
	team: Team,
	eliminated: boolean,
	eliminations: number,
}

export type State = {
	round: number,
	phase: Phase,
	endsAt: number,
	fighters: { Fighter },
	winner: (Team | "Draw")?,
	rewards: { Red: number, Blue: number }?,
}

export type Event = {
	kind: "elimination",
	victim: string,
	by: string,
	at: number,
}

export type Client = {
	localName: string,
	getState: () -> State,
	serverNow: () -> number,
	onStateChanged: (callback: (State) -> ()) -> RBXScriptConnection,
	onEvent: (callback: (Event) -> ()) -> RBXScriptConnection,
}

local function client(): Client
	assert(RunService:IsClient(), "Round.client() runs on the client")
	local Players = game:GetService("Players")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local getState = remotes:WaitForChild("GetRoundState") :: RemoteFunction
	local changed = remotes:WaitForChild("RoundStateChanged") :: RemoteEvent
	local event = remotes:WaitForChild("RoundEvent") :: RemoteEvent
	return {
		localName = (Players.LocalPlayer :: Player).Name,
		getState = function(): State
			return getState:InvokeServer()
		end,
		serverNow = function(): number
			return workspace:GetServerTimeNow()
		end,
		onStateChanged = function(callback: (State) -> ()): RBXScriptConnection
			return changed.OnClientEvent:Connect(callback)
		end,
		onEvent = function(callback: (Event) -> ()): RBXScriptConnection
			return event.OnClientEvent:Connect(callback)
		end,
	}
end

return {
	client = client,
}
