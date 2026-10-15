--!strict

local Lighting = game:GetService("Lighting")
local Track = require(game:GetService("ReplicatedStorage").Shared.RaceTrack)

local World = {}

function World.build()
	local folder = Instance.new("Folder")
	folder.Name = "SunfieldCircuit"
	folder.Parent = workspace
	local count = 0
	local function part(name: string, size: Vector3, frame: CFrame, color: Color3, material: Enum.Material?): Part
		local object = Instance.new("Part")
		object.Name = name
		object.Size = size
		object.CFrame = frame
		object.Color = color
		object.Material = material or Enum.Material.SmoothPlastic
		object.Anchored = true
		object.TopSurface = Enum.SurfaceType.Smooth
		object.BottomSurface = Enum.SurfaceType.Smooth
		object.Parent = folder
		count += 1
		return object
	end
	local green = Color3.fromRGB(113, 192, 100)
	local cream = Color3.fromRGB(255, 235, 172)
	local coral = Color3.fromRGB(244, 99, 75)
	local teal = Color3.fromRGB(46, 178, 180)
	part("Meadow", Vector3.new(440, 2, 440), CFrame.new(0, -1, -155), green, Enum.Material.Grass)
	part("Plaza", Vector3.new(100, 1, 72), CFrame.new(0, 0.5, 0), cream, Enum.Material.Concrete)
	part("GridWalk", Vector3.new(18, 1, 72), CFrame.new(0, 0.5, -70), cream)
	for index = 0, Track.segments - 1 do
		local a, b = Track.point(index / Track.segments), Track.point((index + 1) / Track.segments)
		local frame = CFrame.lookAt((a + b) / 2, b)
		local length = (a - b).Magnitude + 0.6
		part(
			"Asphalt",
			Vector3.new(Track.width, 1, length),
			frame * CFrame.new(0, -1, 0),
			Color3.fromRGB(57, 67, 80),
			Enum.Material.Asphalt
		)
		for _, side in { -1, 1 } do
			part(
				"Curb",
				Vector3.new(2, 0.5, length),
				frame * CFrame.new(side * 14, -0.5, 0),
				if index % 2 == 0 then coral else cream
			)
			part(
				"Barrier",
				Vector3.new(1.5, 3, length),
				frame * CFrame.new(side * 17, 0.5, 0),
				if index % 4 < 2 then teal else cream
			)
		end
	end
	for index = 0, Track.checkpoints - 1 do
		local checkpoint = part(
			"Checkpoint",
			Vector3.new(30, 12, 1),
			Track.frame(index / Track.checkpoints) * CFrame.new(0, 5, 0),
			teal
		)
		checkpoint.Transparency = 1
		checkpoint.CanCollide = false
		checkpoint.CanTouch = false
		checkpoint:SetAttribute("Index", index)
	end
	for _, side in { -1, 1 } do
		part("GantryPost", Vector3.new(2, 15, 2), Track.frame(0, side * 16) * CFrame.new(0, 6, 0), teal)
	end
	part("FinishGantry", Vector3.new(34, 4, 2), Track.frame(0) * CFrame.new(0, 13, 0), cream)
	for index = 0, 11 do
		part(
			"FinishTile",
			Vector3.new(2, 0.1, 3),
			Track.frame(0, index * 2 - 11) * CFrame.new(0, -0.44, 0),
			if index % 2 == 0 then cream else Color3.fromRGB(40, 50, 65)
		)
	end
	local function stall(name: string, x: number, z: number, color: Color3, width: number)
		part(name, Vector3.new(width, 10, 3), CFrame.new(x, 6, z), color)
		part(name .. "Roof", Vector3.new(width + 4, 2, 16), CFrame.new(x, 12, z + 4), cream)
		for _, side in { -1, 1 } do
			part(name .. "Pillar", Vector3.new(1, 10, 1), CFrame.new(x + side * (width / 2), 6, z + 10), color)
		end
		part(name .. "Counter", Vector3.new(width - 2, 3, 4), CFrame.new(x, 2.5, z + 7), color)
	end
	stall("Garage", -32, 15, teal, 25)
	stall("ShopStall", 0, 23, coral, 16)
	stall("MechanicStand", 26, -7, teal, 14)
	stall("CrateArea", 36, 22, coral, 15)
	for index = 1, 6 do
		part(
			"SupplyCrate",
			Vector3.new(4, 4, 4),
			CFrame.new(28 + (index % 3) * 5, 3 + (index // 4) * 4, 29),
			cream,
			Enum.Material.WoodPlanks
		)
	end
	for _, side in { -1, 1 } do
		part("QueueGate", Vector3.new(3, 10, 3), CFrame.new(side * 12, 6, -30), coral)
	end
	part("QueueArch", Vector3.new(27, 3, 3), CFrame.new(0, 12, -30), teal)
	local random = Random.new(Track.seed)
	for index = 1, 24 do
		local frame = Track.frame(index / 24, if index % 2 == 0 then 32 else -35)
		local height = random:NextNumber(9, 15)
		part(
			"TreeTrunk",
			Vector3.new(2, height, 2),
			frame * CFrame.new(0, height / 2, 0),
			Color3.fromRGB(143, 100, 65),
			Enum.Material.Wood
		)
		local crown = part(
			"TreeCrown",
			Vector3.new(10, 10, 10),
			frame * CFrame.new(0, height, 0),
			if index % 2 == 0 then teal else Color3.fromRGB(65, 151, 99)
		)
		crown.Shape = Enum.PartType.Ball
	end
	local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
	if spawn then
		spawn.CFrame = CFrame.lookAt(Vector3.new(0, 2, 0), Vector3.new(0, 2, -100))
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.Neutral = true
	end
	Lighting.ClockTime = 12
	Lighting.Brightness = 2.5
	Lighting.Ambient = Color3.fromRGB(165, 178, 198)
	Lighting.OutdoorAmbient = Color3.fromRGB(180, 190, 210)
	folder:SetAttribute("StaticParts", count)
	assert(count == 511, "update the racing world part budget")
end

return World
