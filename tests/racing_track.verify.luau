--!strict

local Verify = require("../tools/vendor/verify/src/core")
local Lute = require("../tools/vendor/verify/src/lute")
local Engine = require("./lib/native_engine")
local Rules = require("../examples/facet-kart/src/shared/RaceRules")
local Opponents = require("../examples/facet-kart/src/shared/Opponents")
type RoundService = {
	start: () -> (),
	setAutomatic: (boolean) -> (),
	enter: (string, number) -> (),
	setLaps: (string, number) -> (),
	setPositions: ({ string }) -> (),
	eliminate: (string, string) -> boolean,
	snapshot: (
	) -> {
		mode: string,
		racers: { { name: string, finished: boolean, completedLaps: number } },
		rewards: { [string]: number }?,
	},
	events: () -> { { by: string } },
}

local function roundFixture(): (RoundService, () -> number)
	local player = { Name = "Driver" }
	local paid = 0
	local signal = { Connect = function(_self: unknown, _callback: unknown) end }
	local players = {
		PlayerAdded = signal,
		PlayerRemoving = signal,
		GetPlayers = function()
			return { player }
		end,
		FindFirstChild = function(_self: unknown, name: string): { Name: string }?
			return if name == player.Name then player else nil
		end,
	}
	local remote = { FireAllClients = function(_self: unknown, _value: unknown) end }
	local remotes = {
		WaitForChild = function()
			return remote
		end,
	}
	local globals: { [string]: unknown } = {
		workspace = {
			GetServerTimeNow = function()
				return 100
			end,
		},
		task = { spawn = function(_callback: unknown) end },
		fixtureRace = {
			start = function() end,
			stop = function() end,
			setManual = function() end,
			markOut = function() end,
		},
		fixtureLedger = {
			reward = function(_player: unknown, _round: number, coins: number)
				paid += coins
			end,
		},
	}
	local loader = Lute.loader.new({
		globals = globals,
		transform = function(path: string, source: string): string
			if string.find(path, "RoundService", 1, true) then
				source = string.gsub(source, "require%(script.Parent.Ledger%)", "fixtureLedger")
				source = string.gsub(source, "require%(script.Parent.RaceService%)", "fixtureRace")
			end
			return source
		end,
	})
	globals.game = {
		GetService = function(_self: unknown, name: string): unknown
			return if name == "Players"
				then players
				else {
					Shared = loader.reference("examples/facet-kart/src/shared"),
					WaitForChild = function()
						return remotes
					end,
				}
		end,
	}
	local service = loader.require("examples/facet-kart/src/server/RoundService") :: RoundService
	service.start()
	service.setAutomatic(false)
	return service, function()
		return paid
	end
end

local function world(theme: string?): ({ BasePart }, Lighting)
	local engine = Engine.new()
	local workspace = engine.new("Workspace") :: Workspace
	if theme then
		workspace:SetAttribute("WorldTheme", theme)
	end
	local lighting = engine.new("Lighting") :: Lighting
	local globals: { [string]: unknown } = {
		Vector3 = Engine.types.Vector3,
		CFrame = Engine.types.CFrame,
		Color3 = Engine.types.Color3,
		Enum = Engine.types.Enum,
		Instance = { new = engine.new },
		workspace = workspace,
		Random = {
			new = function(_seed: number)
				return {
					NextNumber = function(_self: unknown, low: number, high: number): number
						return (low + high) / 2
					end,
				}
			end,
		},
	}
	local loader = Lute.loader.new({ globals = globals })
	globals.game = {
		GetService = function(_self: unknown, name: string): unknown
			return if name == "Lighting"
				then lighting
				else { Shared = loader.reference("examples/facet-kart/src/shared") }
		end,
	}
	local builder = loader.require("examples/facet-kart/src/server/World") :: { build: () -> () }
	builder.build()
	local parts: { BasePart } = {}
	for _, object in workspace:GetDescendants() do
		if object:IsA("BasePart") then
			table.insert(parts, object)
		end
	end
	return parts, lighting
end

type Footprint = { CFrame: CFrame, Size: Vector3 }
local function overlap(a: Footprint, b: Footprint): boolean
	local delta = b.CFrame.Position - a.CFrame.Position
	for _, axis in { a.CFrame.RightVector, a.CFrame.LookVector, b.CFrame.RightVector, b.CFrame.LookVector } do
		local function radius(part: Footprint): number
			return math.abs(axis:Dot(part.CFrame.RightVector)) * part.Size.X / 2
				+ math.abs(axis:Dot(part.CFrame.LookVector)) * part.Size.Z / 2
		end
		if math.abs(delta:Dot(axis)) >= radius(a) + radius(b) - 0.0001 then
			return false
		end
	end
	return true
end

return function(harness: Verify.Harness)
	harness:case("opponents keep swept footprints apart through a seeded full race with a player", function(t)
		local globals: { [string]: unknown } = { Vector3 = Engine.types.Vector3, CFrame = Engine.types.CFrame }
		local loader = Lute.loader.new({ globals = globals })
		local track =
			loader.require("examples/facet-kart/src/shared/RaceTrack") :: typeof(require("../examples/facet-kart/src/shared/RaceTrack"))
		local size = Engine.types.Vector3.new(7.6, 2, 7)
		local reach = 2 * math.sqrt((size.X / 2) ^ 2 + (size.Z / 2) ^ 2)
		for _, seed in { 20261015, 17, 923 } do
			local field: { Opponents.Driver } = {}
			local replay: { Opponents.Driver } = {}
			for index = 1, 8 do
				field[index] = Opponents.create(index, seed)
				replay[index] = Opponents.create(index, seed)
			end
			field[1].controlled = false
			replay[1].controlled = false
			local overtakes = 0
			local changes = 0
			for step = 1, 7200 do
				local previous: { number } = {}
				local earlier: { number } = {}
				for index, driver in field do
					previous[index] = driver.lane
					earlier[index] = driver.progress
				end
				Opponents.stepField(field, Opponents.step, step * Opponents.step)
				Opponents.stepField(replay, Opponents.step, step * Opponents.step)
				local footprints: { Footprint } = {}
				for index, driver in field do
					footprints[index] = { CFrame = track.frame(driver.progress, driver.lane), Size = size }
				end
				for index, driver in field do
					assert(
						math.abs(driver.lane - previous[index]) <= Opponents.laneRate * Opponents.step + 1e-8,
						"lane discontinuity"
					)
					assert(
						driver.progress == replay[index].progress and driver.lane == replay[index].lane,
						"seed replay diverged"
					)
					if driver.lane ~= previous[index] then
						changes += 1
					end
					for otherIndex = index + 1, #field do
						local other = field[otherIndex]
						local a = footprints[index]
						local b = footprints[otherIndex]
						local dx = b.CFrame.Position.X - a.CFrame.Position.X
						local dz = b.CFrame.Position.Z - a.CFrame.Position.Z
						if dx * dx + dz * dz < reach * reach then
							assert(
								not overlap(a, b),
								`footprints overlap seed {seed} step {step}: {index}/{otherIndex}`
							)
						end
						if index > 1 and earlier[index] < earlier[otherIndex] and driver.progress > other.progress then
							overtakes += 1
						end
					end
				end
			end
			for index = 2, #field do
				t:expect(field[index].progress >= 3):toBeTrueWith("opponent completes three laps")
			end
			t:expect(changes > 0):toBe(true)
			t:expect(overtakes > 0):toBe(true)
		end
	end)
	harness:case("opponents brake behind a player when every passing lane is blocked", function(t)
		local field: { Opponents.Driver } = {}
		for index = 1, 3 do
			local blocker = Opponents.create(index, 17)
			blocker.controlled = false
			blocker.progress = 0.15
			table.insert(field, blocker)
		end
		local follower = Opponents.create(4, 17)
		follower.progress = 0.08
		table.insert(field, follower)
		for step = 1, 600 do
			Opponents.stepField(field, Opponents.step, step * Opponents.step)
		end
		t:expect(follower.progress <= 0.15 - Opponents.gap + 1e-8):toBe(true)
		t:expect(follower.speed < 0.0001):toBe(true)
	end)
	harness:case("a turned player reserves its wider footprint across adjacent lanes", function(t)
		local player = Opponents.create(2, 17)
		player.controlled = false
		player.progress = 0.3
		player.halfWidth = 5.5
		local follower = Opponents.create(3, 17)
		follower.progress = 0.2
		for step = 1, 600 do
			Opponents.stepField({ player, follower }, Opponents.step, step * Opponents.step)
		end
		t:expect(follower.progress <= player.progress - Opponents.gap + 1e-8):toBe(true)
		t:expect(follower.speed < 0.0001):toBe(true)
	end)
	harness:case("race fixtures rank individual finishers and pay by position once", function(t)
		local service, paid = roundFixture()
		service.enter("Round", 120)
		t:expect(service.snapshot().mode):toBe("race")
		t:expect(service.eliminate("Driver", "lap 0")):toBe(false)
		service.setLaps("Nova", 3)
		service.setLaps("Driver", 2)
		local state = service.snapshot()
		t:expect(state.racers[1].name):toBe("Nova")
		t:expect(state.racers[1].finished):toBe(true)
		t:expect(state.racers[2].name):toBe("Driver")
		service.enter("Results", 30)
		local rewards = assert(service.snapshot().rewards)
		t:expect(rewards.Nova):toBe(50)
		t:expect(rewards.Driver):toBe(45)
		t:expect(paid()):toBe(45)
		service.enter("Results", 30)
		t:expect(paid()):toBe(45)
		service.enter("Intermission", 30)
		service.enter("Round", 120)
		t:expect(service.snapshot().racers[1].name):toBe("Driver")
		t:expect(service.snapshot().racers[1].completedLaps):toBe(0)
		service.setPositions({ "Moss", "Driver" })
		t:expect(service.snapshot().racers[1].name):toBe("Moss")
		t:expect(service.snapshot().racers[2].name):toBe("Driver")
		t:expect(service.eliminate("Nova", "lap 1")):toBe(true)
		t:expect(service.events()[1].by):toBe("lap 1")
	end)
	harness:case("night world keeps readable materials and a bounded static lighting setup", function(t)
		local parts, lighting = world("scifi")
		local lights = 0
		local towers = 0
		local seams = 0
		for _, part in parts do
			t:expect(part.Anchored):toBe(true)
			t:expect(part.Name == "TreeTrunk" or part.Name == "TreeCrown"):toBe(false)
			if part.Name == "Barrier" or part.Name == "FinishGantry" then
				t:expect(part.Material):toBe(Engine.types.Enum.Material.Metal)
			end
			if part.Name == "BarrierEdge" or part.Name == "GantryTrim" or part.Name == "StartLight" then
				t:expect(part.Material):toBe(Engine.types.Enum.Material.Neon)
				t:expect(part.CanCollide):toBe(false)
			end
			if part.Name == "PlazaSeam" or part.Name == "DeckSeam" then
				seams += 1
			end
			if part.Name == "TowerMast" then
				towers += 1
			end
			for _, child in part:GetChildren() do
				if child:IsA("Light") then
					lights += 1
					t:expect(child.Shadows):toBe(false)
				end
			end
		end
		t:expect(#parts):toBe(511)
		t:expect(lights):toBe(4)
		t:expect(towers):toBe(8)
		t:expect(seams):toBe(12)
		t:expect(lighting.Ambient.R > 0.4 and lighting.OutdoorAmbient.R > 0.5):toBe(true)
		local sky = assert(lighting:FindFirstChildOfClass("Sky"))
		t:expect(sky.CelestialBodiesShown and sky.StarCount >= 3000):toBe(true)
		t:expect(sky.MoonAngularSize > 11):toBe(true)
		t:expect(lighting:FindFirstChildOfClass("Atmosphere") ~= nil):toBe(true)
		t:expect(lighting:FindFirstChildOfClass("BloomEffect") ~= nil):toBe(true)
		t:expect(lighting:FindFirstChildOfClass("ColorCorrectionEffect") ~= nil):toBe(true)
		local bright, daylight = world(nil)
		local trees = 0
		for _, part in bright do
			if part.Name == "TreeCrown" then
				trees += 1
			end
		end
		t:expect(#bright):toBe(511)
		t:expect(trees):toBe(24)
		t:expect(daylight.ClockTime):toBe(12)
		t:expect(daylight:FindFirstChildOfClass("Sky")):toBe(nil)
	end)
	harness:case("world decorations have no overlapping face coplanar with the road in either theme", function(t)
		for _, theme in { "bright", "scifi" } do
			local parts = world(theme)
			t:expect(#parts):toBe(511)
			for _, road in parts do
				if road.Name ~= "Asphalt" then
					continue
				end
				local surface = road.CFrame.Position.Y + road.Size.Y / 2
				for _, decoration in parts do
					if decoration.Name == "Asphalt" or decoration.Transparency == 1 then
						continue
					end
					local coplanar = math.abs(decoration.CFrame.Position.Y - decoration.Size.Y / 2 - surface) < 0.0001
						or math.abs(decoration.CFrame.Position.Y + decoration.Size.Y / 2 - surface) < 0.0001
					t:expect(
						not (
								coplanar
								and overlap(
									{ CFrame = road.CFrame, Size = road.Size },
									{ CFrame = decoration.CFrame, Size = decoration.Size }
								)
							)
					):toBeTrueWith(theme .. ": " .. decoration.Name)
				end
			end
		end
	end)
	harness:case("lap knockout removes the last active racer only once after a completed lap", function(t)
		local racers: { Rules.Racer } = {
			{
				name = "First",
				completedLaps = 0,
				eliminated = false,
				finished = false,
				position = 1,
				lap = 1,
				lapCount = 3,
				gap = 0,
			},
			{
				name = "Last",
				completedLaps = 0,
				eliminated = false,
				finished = false,
				position = 2,
				lap = 1,
				lapCount = 3,
				gap = 0,
			},
		}
		t:expect((Rules.lapKnockout(racers, 0))):toBe(nil)
		racers[1].completedLaps = 1
		local victim, lap = Rules.lapKnockout(racers, 0)
		t:expect(victim):toBe("Last")
		t:expect(lap):toBe(1)
		t:expect((Rules.lapKnockout(racers, lap))):toBe(nil)
		racers[2].eliminated = true
		racers[1].completedLaps = 2
		t:expect((Rules.lapKnockout(racers, lap))):toBe(nil)
	end)
	harness:case("the seeded circuit closes with a continuous tangent and correct progress", function(t)
		local globals: { [string]: unknown } = { Vector3 = Engine.types.Vector3, CFrame = Engine.types.CFrame }
		local loader = Lute.loader.new({ globals = globals })
		local track =
			loader.require("examples/facet-kart/src/shared/RaceTrack.luau") :: typeof(require("../examples/facet-kart/src/shared/RaceTrack"))
		local grid = Opponents.create(1, track.seed)
		t:expect(track.progress(track.frame(grid.progress, grid.lane).Position) < 1 / track.checkpoints):toBe(true)
		t:expect((track.point(0) - track.point(1)).Magnitude < 0.0001):toBe(true)
		local before = (track.point(0) - track.point(-0.0001)).Unit
		local after = (track.point(0.0001) - track.point(0)).Unit
		t:expect(before:Dot(after) > 0.999):toBe(true)
		for index = 0, 79 do
			local progress = index / 80
			t:expect(math.abs(track.progress(track.point(progress)) - progress) < 0.001):toBe(true)
		end
	end)
end
