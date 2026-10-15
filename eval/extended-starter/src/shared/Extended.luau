--!strict

export type Livery = { body: number, accent: number, shade: number, decal: string }
export type Friend = { name: string, presence: string, invite: string }
export type State = {
	livery: Livery,
	tracks: { string },
	votes: { number },
	vote: number,
	endsAt: number,
	winner: string,
	chat: string,
	chatCount: number,
	readyAt: number,
	levels: { [string]: { number } },
	wallet: { Coins: number, Gems: number },
	friends: { Friend },
	party: { string },
	tutorialDone: boolean,
}
export type Result = { ok: boolean, reason: string?, state: State }
export type Client = {
	get: () -> State,
	request: (action: string, value: unknown?) -> Result,
	onChanged: ((State) -> ()) -> RBXScriptConnection,
	now: () -> number,
}
local messages = { "Hello!", "Good luck!", "Nice race!", "Thanks!", "Follow me!", "Ready!", "Sorry!", "Well played!" }
local decals = { "None", "Stripes", "Flames", "Stars", "Checks", "Lightning" }
local function client(): Client
	local folder = game:GetService("ReplicatedStorage"):WaitForChild("ExtendedRemotes")
	local request = folder:WaitForChild("Request") :: RemoteFunction
	local changed = folder:WaitForChild("Changed") :: RemoteEvent
	return {
		get = function(): State
			return request:InvokeServer("get").state
		end,
		request = function(action: string, value: unknown?): Result
			return request:InvokeServer(action, value)
		end,
		onChanged = function(callback: (State) -> ()): RBXScriptConnection
			return changed.OnClientEvent:Connect(callback)
		end,
		now = function(): number
			return workspace:GetServerTimeNow()
		end,
	}
end
return { client = client, messages = messages, decals = decals, stats = { "Speed", "Handling", "Boost" } }
