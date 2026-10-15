--!strict

local Verify = require("../tools/vendor/verify/src/core")
local Lute = require("../tools/vendor/verify/src/lute")
local Engine = require("./lib/native_engine")
local Rules = require("../eval/tasks/racing-hub/starter/src/shared/RaceRules")
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
					Shared = loader.reference("eval/tasks/racing-hub/starter/src/shared"),
					WaitForChild = function()
						return remotes
					end,
				}
		end,
	}
	local service = loader.require("eval/tasks/racing-hub/starter/src/server/RoundService") :: RoundService
	service.start()
	service.setAutomatic(false)
	return service, function()
		return paid
	end
end

local function world(theme: string): { BasePart }
	local engine = Engine.new()
	local workspace = engine.new("Workspace") :: Workspace
	workspace:SetAttribute("WorldTheme", theme)
	local lighting = engine.new("Lighting")
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
				else { Shared = loader.reference("eval/tasks/racing-hub/starter/src/shared") }
		end,
	}
	local builder = loader.require("eval/tasks/racing-hub/starter/src/server/World") :: { build: () -> () }
	builder.build()
	local parts: { BasePart } = {}
	for _, object in workspace:GetDescendants() do
		if object:IsA("BasePart") then
			table.insert(parts, object)
		end
	end
	return parts
end

local function overlap(a: BasePart, b: BasePart): boolean
	local delta = b.CFrame.Position - a.CFrame.Position
	for _, axis in { a.CFrame.RightVector, a.CFrame.LookVector, b.CFrame.RightVector, b.CFrame.LookVector } do
		local function radius(part: BasePart): number
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
					t:expect(not (coplanar and overlap(road, decoration)))
						:toBeTrueWith(theme .. ": " .. decoration.Name)
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
			loader.require("eval/tasks/racing-hub/starter/src/shared/RaceTrack.luau") :: typeof(require("../eval/tasks/racing-hub/starter/src/shared/RaceTrack"))
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
