--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type ModeId = "solo" | "duo"

export type Mode = { id: ModeId, name: string, players: number, description: string }

export type Phase = "Lobby" | "Queue" | "Countdown" | "Starting"

export type State = {
	phase: Phase,
	mode: ModeId?,
	players: number,
	needed: number,
	countdownEndsAt: number?,
}

export type Failure = "already_queued" | "not_queued" | "unknown_mode" | "starting"

export type Result = { ok: boolean, reason: Failure?, state: State }

export type Client = {
	modes: { Mode },
	getState: () -> State,
	join: (modeId: ModeId) -> Result,
	leave: () -> Result,
	serverNow: () -> number,
	onStateChanged: (callback: (State) -> ()) -> RBXScriptConnection,
}

local modes: { Mode } = {
	{ id = "solo", name = "Solo", players = 4, description = "Every player for themselves." },
	{ id = "duo", name = "Duo", players = 6, description = "Team up in pairs." },
}

local function client(): Client
	assert(RunService:IsClient(), "Lobby.client() runs on the client")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local getState = remotes:WaitForChild("GetLobbyState") :: RemoteFunction
	local join = remotes:WaitForChild("JoinQueue") :: RemoteFunction
	local leave = remotes:WaitForChild("LeaveQueue") :: RemoteFunction
	local changed = remotes:WaitForChild("LobbyStateChanged") :: RemoteEvent
	return {
		modes = modes,
		getState = function(): State
			return getState:InvokeServer()
		end,
		join = function(modeId: ModeId): Result
			return join:InvokeServer(modeId)
		end,
		leave = function(): Result
			return leave:InvokeServer()
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
	modes = modes,
}
