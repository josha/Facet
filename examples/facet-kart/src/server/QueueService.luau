--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lobby = require(ReplicatedStorage.Shared.Hub.Lobby)

type State = Lobby.State
type Result = Lobby.Result

export type Entry = { kind: string, mode: string?, ok: boolean, reason: Lobby.Failure?, at: number }

local COUNTDOWN = 10
local STARTING = 6
local BOT_INTERVAL = 4

local changed = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LobbyStateChanged") :: RemoteEvent

local state: State = { phase = "Lobby", mode = nil, players = 0, needed = 0, countdownEndsAt = nil }
local bots = 0
local automatic = true
local lastBot = 0
local startedAt = 0
local journal: { Entry } = {}

local function snapshot(): State
	return {
		phase = state.phase,
		mode = state.mode,
		players = state.players,
		needed = state.needed,
		countdownEndsAt = state.countdownEndsAt,
	}
end

local function publish()
	changed:FireAllClients(snapshot())
end

local function modeOf(id: unknown): Lobby.Mode?
	for _, mode in Lobby.modes do
		if mode.id == id then
			return mode
		end
	end
	return nil
end

local function recount()
	if state.phase ~= "Queue" and state.phase ~= "Countdown" then
		return
	end
	state.players = math.min(state.needed, 1 + bots)
	if state.players >= state.needed and state.phase == "Queue" then
		state.phase = "Countdown"
		state.countdownEndsAt = workspace:GetServerTimeNow() + COUNTDOWN
	elseif state.players < state.needed and state.phase == "Countdown" then
		state.phase = "Queue"
		state.countdownEndsAt = nil
	end
	publish()
end

local function answer(kind: string, mode: string?, reason: Lobby.Failure?): Result
	table.insert(journal, { kind = kind, mode = mode, ok = reason == nil, reason = reason, at = os.clock() })
	return { ok = reason == nil, reason = reason, state = snapshot() }
end

local function join(_player: Player, modeId: unknown): Result
	local mode = modeOf(modeId)
	if mode == nil then
		return answer("join", tostring(modeId), "unknown_mode")
	end
	if state.phase == "Starting" then
		return answer("join", (mode :: Lobby.Mode).id, "starting")
	end
	if state.phase ~= "Lobby" then
		return answer("join", (mode :: Lobby.Mode).id, "already_queued")
	end
	state.phase = "Queue"
	state.mode = (mode :: Lobby.Mode).id
	state.needed = (mode :: Lobby.Mode).players
	bots = 0
	lastBot = os.clock()
	recount()
	return answer("join", state.mode, nil)
end

local function leave(_player: Player): Result
	if state.phase ~= "Queue" and state.phase ~= "Countdown" then
		return answer("leave", nil, "not_queued")
	end
	state.phase = "Lobby"
	state.mode = nil
	state.players = 0
	state.needed = 0
	state.countdownEndsAt = nil
	bots = 0
	publish()
	return answer("leave", nil, nil)
end

local function addBots(count: number)
	bots = math.max(0, bots + count)
	recount()
end

local function tick()
	local now = workspace:GetServerTimeNow()
	if state.phase == "Queue" and automatic and os.clock() - lastBot >= BOT_INTERVAL then
		lastBot = os.clock()
		addBots(1)
	elseif state.phase == "Countdown" and state.countdownEndsAt ~= nil and now >= state.countdownEndsAt then
		state.phase = "Starting"
		state.countdownEndsAt = nil
		startedAt = os.clock()
		publish()
	elseif state.phase == "Starting" and os.clock() - startedAt >= STARTING then
		state.phase = "Lobby"
		state.mode = nil
		state.players = 0
		state.needed = 0
		bots = 0
		publish()
	end
end

local function start()
	task.spawn(function()
		while true do
			tick()
			task.wait(0.25)
		end
	end)
end

return {
	start = start,
	snapshot = snapshot,
	join = join,
	leave = leave,
	addBots = addBots,
	finishCountdown = function()
		if state.phase == "Countdown" then
			state.countdownEndsAt = workspace:GetServerTimeNow()
		end
	end,
	setAutomatic = function(value: boolean)
		automatic = value
	end,
	journal = function(): { Entry }
		return table.clone(journal)
	end,
}
