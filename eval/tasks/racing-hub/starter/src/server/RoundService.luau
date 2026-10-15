--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ledger = require(script.Parent.Ledger)
local RaceService = require(script.Parent.RaceService)
local Round = require(ReplicatedStorage.Shared.Hub.Round)

type State = Round.State
type Fighter = Round.Fighter
type Phase = Round.Phase

local function duration(phase: Phase): number
	return if phase == "Round" then 90 elseif phase == "Results" then 10 else 20
end
local BOTS: { { name: string, team: Round.Team } } = {
	{ name = "Nova", team = "Red" },
	{ name = "Pip", team = "Red" },
	{ name = "Rook", team = "Red" },
	{ name = "Zed", team = "Blue" },
	{ name = "Ivy", team = "Blue" },
	{ name = "Bolt", team = "Blue" },
	{ name = "Moss", team = "Blue" },
}
local WIN_REWARD = 50
local LOSS_REWARD = 20

local changed = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoundStateChanged") :: RemoteEvent
local event = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoundEvent") :: RemoteEvent

local state: State = {
	round = 1,
	phase = "Intermission",
	endsAt = workspace:GetServerTimeNow() + duration("Intermission"),
	fighters = {},
	winner = nil,
	rewards = nil,
}
local automatic = true
local raceComplete = false
local log: { Round.Event } = {}

for _, bot in BOTS do
	table.insert(state.fighters, { name = bot.name, team = bot.team, eliminated = false, eliminations = 0 })
end

local function snapshot(): State
	local fighters: { Fighter } = {}
	for _, fighter in state.fighters do
		table.insert(fighters, table.clone(fighter))
	end
	return {
		round = state.round,
		phase = state.phase,
		endsAt = state.endsAt,
		fighters = fighters,
		winner = state.winner,
		rewards = if state.rewards ~= nil then table.clone(state.rewards) else nil,
	}
end

local function publish()
	changed:FireAllClients(snapshot())
end

local function find(name: string): Fighter?
	for _, fighter in state.fighters do
		if fighter.name == name then
			return fighter
		end
	end
	return nil
end

local function alive(team: Round.Team): number
	local count = 0
	for _, fighter in state.fighters do
		if fighter.team == team and not fighter.eliminated then
			count += 1
		end
	end
	return count
end

local function enter(phase: Phase, seconds: number?, winner: (Round.Team | "Draw")?)
	state.phase = phase
	state.endsAt = workspace:GetServerTimeNow() + (seconds or duration(phase))
	if phase == "Round" then
		for _, fighter in state.fighters do
			fighter.eliminated = false
			fighter.eliminations = 0
		end
		state.winner = nil
		state.rewards = nil
		raceComplete = false
		RaceService.start(state.fighters, not automatic, function()
			raceComplete = true
		end)
	elseif phase == "Results" then
		local red, blue = alive("Red"), alive("Blue")
		state.winner = winner
			or (
				if automatic
					then RaceService.winner()
					elseif red > blue then "Red"
					elseif blue > red then "Blue"
					else "Draw"
			)
		RaceService.stop()
		state.rewards = {
			Red = if state.winner == "Red" then WIN_REWARD else LOSS_REWARD,
			Blue = if state.winner == "Blue" then WIN_REWARD else LOSS_REWARD,
		}
		for _, player in Players:GetPlayers() do
			Ledger.reward(player, state.round, (state.rewards :: { Red: number, Blue: number }).Red)
		end
	elseif phase == "Intermission" then
		RaceService.stop()
		state.round += 1
		state.winner = nil
		state.rewards = nil
	end
	publish()
end

local function eliminate(victim: string, lap: string): boolean
	local target = find(victim)
	if automatic or target == nil or target.eliminated or state.phase ~= "Round" then
		return false
	end
	target.eliminated = true
	RaceService.markOut(victim)
	local entry: Round.Event = { kind = "elimination", victim = victim, by = lap, at = workspace:GetServerTimeNow() }
	table.insert(log, entry)
	event:FireAllClients(entry)
	publish()
	if not automatic and (alive("Red") == 0 or alive("Blue") == 0) then
		enter("Results")
	end
	return true
end

local function join(player: Player)
	if find(player.Name) == nil then
		local fighter: Fighter = { name = player.Name, team = "Red", eliminated = false, eliminations = 0 }
		table.insert(state.fighters, 1, fighter)
		publish()
	end
end

local function leave(player: Player)
	for index, fighter in state.fighters do
		if fighter.name == player.Name then
			table.remove(state.fighters, index)
			publish()
			return
		end
	end
end

local function tick()
	local now = workspace:GetServerTimeNow()
	if state.phase ~= "Intermission" and now >= state.endsAt then
		if state.phase == "Round" then
			enter("Results")
		else
			enter("Intermission")
		end
		return
	end
	if automatic and state.phase == "Round" then
		local updated = false
		for _, fighter in state.fighters do
			local laps = RaceService.laps(fighter.name)
			if fighter.eliminations ~= laps then
				fighter.eliminations = laps
				updated = true
			end
		end
		if updated then
			publish()
		end
		if raceComplete then
			enter("Results")
		end
	end
end

local function start()
	Players.PlayerAdded:Connect(join)
	Players.PlayerRemoving:Connect(leave)
	for _, player in Players:GetPlayers() do
		join(player)
	end
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
	enter = enter,
	eliminate = eliminate,
	setLaps = function(name: string, laps: number)
		assert(not automatic, "lap fixtures require manual mode")
		local fighter = find(name)
		assert(fighter, "unknown racer")
		fighter.eliminations = math.clamp(math.floor(laps), 0, 3)
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
