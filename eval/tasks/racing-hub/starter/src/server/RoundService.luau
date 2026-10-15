--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ledger = require(script.Parent.Ledger)
local RaceService = require(script.Parent.RaceService)
local Round = require(ReplicatedStorage.Shared.Hub.Round)
local Rules = require(ReplicatedStorage.Shared.RaceRules)

type State = Round.State
type Racer = Round.Racer
type Phase = Round.Phase

local changed = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoundStateChanged") :: RemoteEvent
local event = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoundEvent") :: RemoteEvent
local function newRacer(name: string, position: number): Racer
	return {
		name = name,
		position = position,
		lap = 1,
		lapCount = 3,
		completedLaps = 0,
		bestLap = nil,
		gap = 0,
		finished = false,
		eliminated = false,
	}
end
local state: State = {
	round = 1,
	phase = "Intermission",
	endsAt = workspace:GetServerTimeNow() + 20,
	racers = {},
	mode = "race",
	rewards = nil,
}
for index, name in { "Nova", "Pip", "Rook", "Zed", "Ivy", "Bolt", "Moss" } do
	table.insert(state.racers, newRacer(name, index))
end
local automatic = true
local raceComplete = false
local knockoutLap = 0
local log: { Round.Event } = {}
local function snapshot(): State
	local copy = table.clone(state)
	copy.racers = {}
	for _, racer in state.racers do
		table.insert(copy.racers, table.clone(racer))
	end
	copy.rewards = if state.rewards then table.clone(state.rewards) else nil
	return copy
end
local function publish()
	changed:FireAllClients(snapshot())
end
local function find(name: string): Racer?
	for _, racer in state.racers do
		if racer.name == name then
			return racer
		end
	end
	return nil
end
local function rankFixtures()
	table.sort(state.racers, function(a: Racer, b: Racer): boolean
		if a.eliminated ~= b.eliminated then
			return not a.eliminated
		end
		if a.completedLaps ~= b.completedLaps then
			return a.completedLaps > b.completedLaps
		end
		return a.position < b.position
	end)
	for index, racer in state.racers do
		racer.position = index
	end
end
local function enter(phase: Phase, seconds: number?)
	if phase == "Results" and state.phase == "Results" then
		return
	end
	state.phase = phase
	state.endsAt = workspace:GetServerTimeNow()
		+ (seconds or (if phase == "Round" then 90 elseif phase == "Results" then 10 else 20))
	if phase == "Round" then
		table.sort(state.racers, function(a: Racer, b: Racer): boolean
			local aPlayer = Players:FindFirstChild(a.name) ~= nil
			local bPlayer = Players:FindFirstChild(b.name) ~= nil
			if aPlayer ~= bPlayer then
				return aPlayer
			end
			return a.name < b.name
		end)
		for index, racer in state.racers do
			state.racers[index] = newRacer(racer.name, index)
		end
		state.rewards = nil
		table.clear(log)
		raceComplete = false
		knockoutLap = 0
		RaceService.start(state.racers, not automatic, function()
			raceComplete = true
		end)
	elseif phase == "Results" then
		if automatic then
			state.racers = RaceService.standings()
		else
			rankFixtures()
		end
		local rewards: { [string]: number } = {}
		state.rewards = rewards
		for _, racer in state.racers do
			rewards[racer.name] = math.max(20, 55 - racer.position * 5)
		end
		for _, player in Players:GetPlayers() do
			Ledger.reward(player, state.round, rewards[player.Name] or 20)
		end
		RaceService.stop()
	elseif phase == "Intermission" then
		RaceService.stop()
		state.round += 1
		state.rewards = nil
	end
	publish()
end
local function eliminate(victim: string, lap: string): boolean
	local target = find(victim)
	local completed = tonumber(string.match(lap, "%d+")) or 0
	if automatic or target == nil or target.eliminated or state.phase ~= "Round" or completed < 1 then
		return false
	end
	target.completedLaps = math.max(target.completedLaps, completed)
	target.lap = math.min(3, completed + 1)
	target.eliminated = true
	RaceService.markOut(victim)
	local entry: Round.Event =
		{ kind = "elimination", victim = victim, by = "lap " .. tostring(completed), at = workspace:GetServerTimeNow() }
	table.insert(log, entry)
	event:FireAllClients(entry)
	rankFixtures()
	publish()
	return true
end
local function tick()
	if state.phase ~= "Intermission" and workspace:GetServerTimeNow() >= state.endsAt then
		enter(if state.phase == "Round" then "Results" else "Intermission")
		return
	end
	if automatic and state.phase == "Round" then
		local nextStandings = RaceService.standings()
		if state.mode == "lap-knockout" then
			local victim, lap = Rules.lapKnockout(nextStandings, knockoutLap)
			knockoutLap = lap
			if victim then
				RaceService.markOut(victim)
				local entry: Round.Event = {
					kind = "elimination",
					victim = victim,
					by = "lap " .. tostring(lap),
					at = workspace:GetServerTimeNow(),
				}
				table.insert(log, entry)
				event:FireAllClients(entry)
			end
		end
		state.racers = RaceService.standings()
		publish()
		if raceComplete then
			enter("Results")
		end
	end
end
return {
	start = function()
		local function join(player: Player)
			if find(player.Name) == nil then
				for _, racer in state.racers do
					racer.position += 1
				end
				table.insert(state.racers, 1, newRacer(player.Name, 1))
				publish()
			end
		end
		Players.PlayerAdded:Connect(join)
		Players.PlayerRemoving:Connect(function(player: Player)
			for index, racer in state.racers do
				if racer.name == player.Name then
					table.remove(state.racers, index)
					break
				end
			end
			publish()
		end)
		for _, player in Players:GetPlayers() do
			join(player)
		end
		task.spawn(function()
			while true do
				tick()
				task.wait(0.25)
			end
		end)
	end,
	snapshot = snapshot,
	enter = enter,
	eliminate = eliminate,
	setLaps = function(name: string, laps: number)
		assert(not automatic, "lap fixtures require manual mode")
		local racer = find(name)
		assert(racer, "unknown racer")
		racer.completedLaps = math.clamp(math.floor(laps), 0, 3)
		racer.lap = math.min(3, racer.completedLaps + 1)
		racer.finished = racer.completedLaps == 3
		rankFixtures()
		publish()
	end,
	setMode = function(mode: Round.Mode)
		state.mode = mode
	end,
	setPositions = function(names: { string })
		assert(not automatic, "position fixtures require manual mode")
		local ordered: { Racer } = {}
		local seen: { [string]: boolean } = {}
		for _, name in names do
			local racer = find(name)
			assert(racer and not seen[name], "unknown or repeated racer")
			seen[name] = true
			table.insert(ordered, racer)
		end
		for _, racer in state.racers do
			if not seen[racer.name] then
				table.insert(ordered, racer)
			end
		end
		for position, racer in ordered do
			racer.position = position
		end
		state.racers = ordered
		publish()
	end,
	setAutomatic = function(value: boolean)
		automatic = value
		RaceService.setManual(not value)
	end,
	events = function(): { Round.Event }
		return table.clone(log)
	end,
}
