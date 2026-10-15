--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ledger = require(script.Parent.Ledger)
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
local SCRIPT: { { victim: string, by: string } } = {
	{ victim = "Moss", by = "Nova" },
	{ victim = "Pip", by = "Ivy" },
	{ victim = "Bolt", by = "Rook" },
	{ victim = "Rook", by = "Zed" },
	{ victim = "Ivy", by = "Nova" },
}
local AUTO_INTERVAL = 9
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
local scripted = 1
local lastAuto = 0
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
		scripted = 1
		lastAuto = os.clock()
	elseif phase == "Results" then
		local red, blue = alive("Red"), alive("Blue")
		state.winner = winner or (if red > blue then "Red" elseif blue > red then "Blue" else "Draw")
		state.rewards = {
			Red = if state.winner == "Red" then WIN_REWARD else LOSS_REWARD,
			Blue = if state.winner == "Blue" then WIN_REWARD else LOSS_REWARD,
		}
		for _, player in Players:GetPlayers() do
			Ledger.reward(player, state.round, (state.rewards :: { Red: number, Blue: number }).Red)
		end
	elseif phase == "Intermission" then
		state.round += 1
		state.winner = nil
		state.rewards = nil
	end
	publish()
end

local function eliminate(victim: string, by: string): boolean
	local target = find(victim)
	if target == nil or target.eliminated or state.phase ~= "Round" then
		return false
	end
	target.eliminated = true
	local attacker = find(by)
	if attacker ~= nil then
		attacker.eliminations += 1
	end
	local entry: Round.Event = { kind = "elimination", victim = victim, by = by, at = workspace:GetServerTimeNow() }
	table.insert(log, entry)
	event:FireAllClients(entry)
	publish()
	if alive("Red") == 0 or alive("Blue") == 0 then
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
	if automatic and state.phase == "Round" and os.clock() - lastAuto >= AUTO_INTERVAL then
		lastAuto = os.clock()
		local step = SCRIPT[scripted]
		if step ~= nil then
			scripted += 1
			eliminate(step.victim, step.by)
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
	setAutomatic = function(value: boolean)
		automatic = value
	end,
	events = function(): { Round.Event }
		return table.clone(log)
	end,
}
