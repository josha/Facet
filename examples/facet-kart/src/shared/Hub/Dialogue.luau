--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type Choice = { id: string, text: string }

export type Node = {
	id: string,
	speaker: string,
	text: string,
	choices: { Choice },
	ended: boolean,
}

export type State = {
	nearby: string?,
	node: Node?,
	coins: number,
	questAccepted: boolean,
}

export type Failure = "not_nearby" | "no_conversation" | "unknown_choice" | "busy"

export type Result = {
	ok: boolean,
	reason: Failure?,
	state: State,
}

export type Client = {
	getState: () -> State,
	talk: () -> Result,
	choose: (choiceId: string) -> Result,
	leave: () -> Result,
	onStateChanged: (callback: (State) -> ()) -> RBXScriptConnection,
}

local function client(): Client
	assert(RunService:IsClient(), "Dialogue.client() runs on the client")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local getState = remotes:WaitForChild("GetDialogueState") :: RemoteFunction
	local talk = remotes:WaitForChild("Talk") :: RemoteFunction
	local choose = remotes:WaitForChild("Choose") :: RemoteFunction
	local leave = remotes:WaitForChild("Leave") :: RemoteFunction
	local changed = remotes:WaitForChild("DialogueStateChanged") :: RemoteEvent
	return {
		getState = function(): State
			return getState:InvokeServer()
		end,
		talk = function(): Result
			return talk:InvokeServer()
		end,
		choose = function(choiceId: string): Result
			return choose:InvokeServer(choiceId)
		end,
		leave = function(): Result
			return leave:InvokeServer()
		end,
		onStateChanged = function(callback: (State) -> ()): RBXScriptConnection
			return changed.OnClientEvent:Connect(callback)
		end,
	}
end

return {
	client = client,
}
