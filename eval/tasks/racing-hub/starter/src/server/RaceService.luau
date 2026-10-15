--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Track = require(game:GetService("ReplicatedStorage").Shared.RaceTrack)
local Rules = require(game:GetService("ReplicatedStorage").Shared.RaceRules)
local Round = require(game:GetService("ReplicatedStorage").Shared.Hub.Round)
local Kart = require(script.Parent.Kart)

type Racer = {
	name: string,
	team: Round.Team,
	kart: Kart.Kart,
	player: Player?,
	progress: number,
	startProgress: number,
	checkpoint: number,
	lap: number,
	finish: number,
	speed: number,
	lane: number,
	out: boolean,
}
local racers: { Racer } = {}
local ordered: { Racer } = {}
local names: { string } = {}
local active = false
local manual = false
local elapsed = 0
local accumulator = 0
local measuredSeconds = 0
local measuredSteps = 0
local measuredCost = 0
local measuredMax = 0
local reseatAt = 0
local complete: () -> () = function() end
local palette = {
	Color3.fromRGB(255, 190, 65),
	Color3.fromRGB(240, 90, 95),
	Color3.fromRGB(73, 180, 225),
	Color3.fromRGB(178, 112, 225),
	Color3.fromRGB(80, 210, 145),
	Color3.fromRGB(255, 145, 70),
	Color3.fromRGB(238, 120, 190),
	Color3.fromRGB(235, 225, 110),
}

local function markOut(name: string)
	for _, racer in racers do
		if racer.name == name then
			racer.out = true
			for _, object in racer.kart.model:GetDescendants() do
				if object:IsA("BasePart") then
					object.Anchored = true
				end
			end
			return
		end
	end
end

local function stop()
	active = false
	for _, racer in racers do
		local player = racer.player
		if player then
			player:SetAttribute("Racing", false)
			local character = player.Character
			local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
			if humanoid then
				humanoid.Sit = false
				humanoid.Jump = false
			end
		end
		racer.kart.model:Destroy()
		if player and player.Character then
			player.Character:PivotTo(CFrame.lookAt(Vector3.new(0, 5, 0), Vector3.new(0, 5, -100)))
			local root = player.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
	table.clear(racers)
	table.clear(ordered)
end

local function start(fighters: { Round.Fighter }, scenario: boolean, onComplete: () -> ())
	stop()
	manual = scenario
	complete = onComplete
	elapsed = 0
	accumulator = 0
	reseatAt = 0
	table.clear(names)
	for index, fighter in fighters do
		local player = Players:FindFirstChild(fighter.name)
		local driver = if player and player:IsA("Player") then player else nil
		local lane = if index % 2 == 0 then -5 else 5
		local progress = 0.05 - math.floor((index - 1) / 2) * 0.012
		local kart = Kart.create(
			fighter.name .. "Kart",
			palette[(index - 1) % #palette + 1],
			Track.frame(progress, lane),
			driver == nil or manual
		)
		local racer: Racer = {
			name = fighter.name,
			team = fighter.team,
			kart = kart,
			player = driver,
			progress = progress,
			startProgress = progress,
			checkpoint = 0,
			lap = 0,
			finish = math.huge,
			speed = 0.047 + index * 0.0007,
			lane = lane,
			out = false,
		}
		table.insert(racers, racer)
		table.insert(ordered, racer)
		if driver then
			driver:SetAttribute("Racing", true)
			driver:SetAttribute("RaceAutopilot", manual)
			local character = driver.Character
			local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
			if humanoid then
				if character then
					character:PivotTo(kart.seat.CFrame * CFrame.new(0, 2, 0))
				end
				kart.seat:Sit(humanoid)
			end
			if not manual and kart.model.PrimaryPart then
				kart.model.PrimaryPart:SetNetworkOwner(driver)
			end
			local progressData = require(script.Parent.Ledger).progress(driver)
			kart.model:SetAttribute("KartId", progressData.kart)
			kart.model:SetAttribute("DriverId", progressData.driver)
		end
	end
	for index, racer in ordered do
		names[index] = if racer.player then "You" else racer.name
	end
	active = true
end

RunService.Heartbeat:Connect(function(dt: number)
	if not active then
		return
	end
	accumulator += dt
	if accumulator < 1 / 30 then
		return
	end
	debug.profilebegin("SunfieldRaceStep")
	local stepStarted = os.clock()
	measuredSeconds += accumulator
	elapsed += accumulator
	accumulator = 0
	local reseat = elapsed >= reseatAt
	if reseat then
		reseatAt = elapsed + 0.5
	end
	local finished = 0
	for _, racer in racers do
		if racer.out then
			finished += 1
			continue
		end
		if reseat and racer.player then
			local character = racer.player.Character
			local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
			if humanoid and humanoid.SeatPart ~= racer.kart.seat then
				if character then
					character:PivotTo(racer.kart.seat.CFrame * CFrame.new(0, 2, 0))
				end
				racer.kart.seat:Sit(humanoid)
			end
		end
		if racer.player == nil or manual then
			racer.progress = math.min(Track.laps, elapsed * racer.speed + racer.startProgress)
			local lap = math.floor(racer.progress)
			racer.lap = lap
			racer.checkpoint = math.floor(racer.progress % 1 * Track.checkpoints)
			racer.kart.model:PivotTo(Track.frame(racer.progress % 1, racer.lane) * CFrame.new(0, 1, 0))
		else
			local root = racer.kart.model.PrimaryPart
			if root then
				local t = Track.progress(root.Position)
				local onRoad = (root.Position - Track.point(t)).Magnitude < Track.width / 2 + 5
				Rules.advance(racer, t, onRoad, Track.checkpoints)
				root:SetAttribute("Lap", math.min(Track.laps, racer.lap + 1))
				root:SetAttribute("Checkpoint", racer.checkpoint)
				root:SetAttribute("RaceProgress", racer.progress)
				if root.Position.Y < -10 or (root.Position - Track.point(t)).Magnitude > 60 then
					racer.kart.model:PivotTo(
						Track.frame(racer.checkpoint / Track.checkpoints, racer.lane) * CFrame.new(0, 3, 0)
					)
					root.AssemblyLinearVelocity = Vector3.zero
				end
			end
		end
		if racer.progress >= Track.laps and racer.finish == math.huge then
			racer.finish = if racer.player == nil or manual
				then (Track.laps - racer.startProgress) / racer.speed
				else elapsed
		end
		if racer.finish ~= math.huge then
			finished += 1
		end
	end
	table.sort(ordered, Rules.ahead)
	for index, racer in ordered do
		names[index] = if racer.player then "You" else racer.name
	end
	if not manual and finished == #racers then
		complete()
	end
	local cost = os.clock() - stepStarted
	measuredCost += cost
	measuredMax = math.max(measuredMax, cost)
	measuredSteps += 1
	if measuredSeconds >= 1 then
		workspace:SetAttribute("RaceStepMeanUs", measuredCost / measuredSteps * 1e6)
		workspace:SetAttribute("RaceStepMaxUs", measuredMax * 1e6)
		workspace:SetAttribute("RaceStepHz", measuredSteps / measuredSeconds)
		measuredSeconds, measuredSteps, measuredCost, measuredMax = 0, 0, 0, 0
	end
	debug.profileend()
end)

return {
	start = start,
	stop = stop,
	positions = function(): { string }
		return names
	end,
	winner = function(): Round.Team | "Draw"
		return if ordered[1] then ordered[1].team else "Draw"
	end,
	setManual = function(value: boolean)
		manual = value
	end,
	markOut = markOut,
	laps = function(name: string): number
		for _, racer in racers do
			if racer.name == name then
				return racer.lap
			end
		end
		return 0
	end,
}
