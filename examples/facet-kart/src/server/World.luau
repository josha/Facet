--!strict

local Lighting = game:GetService("Lighting")
local Track = require(game:GetService("ReplicatedStorage").Shared.RaceTrack)

local World = {}
local scifi = workspace:GetAttribute("WorldTheme") == "scifi"
local cyan = Color3.fromRGB(65, 211, 235)
local magenta = Color3.fromRGB(192, 100, 187)
local metal = Color3.fromRGB(67, 81, 103)

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
		if scifi then
			object.Material = if material == Enum.Material.Neon
				then Enum.Material.Neon
				elseif material == Enum.Material.Asphalt then Enum.Material.Asphalt
				else Enum.Material.Metal
			if material ~= Enum.Material.Neon then
				object.Color = metal
			end
			object.CastShadow = material ~= Enum.Material.Neon
			if material == Enum.Material.Neon then
				object.CanCollide = false
				object.CanTouch = false
				object.CanQuery = false
			end
		end
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
	part(
		"Meadow",
		Vector3.new(440, 2, 440),
		CFrame.new(0, -1, -155),
		green,
		if scifi then Enum.Material.Metal else Enum.Material.Grass
	)
	local plaza = part(
		"Plaza",
		Vector3.new(100, 1, 72),
		CFrame.new(0, 0.5, 0),
		cream,
		if scifi then Enum.Material.Metal else Enum.Material.Concrete
	)
	if scifi then
		plaza.Color = Color3.fromRGB(91, 106, 130)
		for index = -1, 1 do
			part(
				"PlazaSeam",
				Vector3.new(0.08, 0.05, 70),
				CFrame.new(index * 24, 1.04, 0),
				Color3.fromRGB(49, 112, 135),
				Enum.Material.Neon
			)
			part(
				"PlazaSeam",
				Vector3.new(98, 0.05, 0.08),
				CFrame.new(0, 1.05, index * 18),
				Color3.fromRGB(49, 112, 135),
				Enum.Material.Neon
			)
			part(
				"DeckSeam",
				Vector3.new(430, 0.05, 0.08),
				CFrame.new(0, 0.04, -155 + index * 100),
				Color3.fromRGB(41, 85, 111),
				Enum.Material.Neon
			)
			part(
				"DeckSeam",
				Vector3.new(0.08, 0.05, 430),
				CFrame.new(index * 100, 0.05, -155),
				Color3.fromRGB(41, 85, 111),
				Enum.Material.Neon
			)
		end
	end
	part("GridWalk", Vector3.new(18, 1, 72), CFrame.new(0, 0.5, -70), cream)
	for index = 0, Track.segments - 1 do
		local a, b = Track.point(index / Track.segments), Track.point((index + 1) / Track.segments)
		local frame = CFrame.lookAt((a + b) / 2, b)
		local length = (a - b).Magnitude + 0.6
		local road = part(
			"Asphalt",
			Vector3.new(Track.width, 1, length),
			frame * CFrame.new(0, -1, 0),
			Color3.fromRGB(57, 67, 80),
			Enum.Material.Asphalt
		)
		if scifi then
			road.Color = Color3.fromRGB(46, 56, 76)
		end
		for _, side in { -1, 1 } do
			local curb = part(
				"Curb",
				Vector3.new(2, 0.5, length),
				frame * CFrame.new(side * 14, -0.47, 0),
				if index % 2 == 0 then coral else cream
			)
			if scifi then
				curb.Color = if index % 2 == 0 then Color3.fromRGB(66, 116, 134) else Color3.fromRGB(85, 94, 118)
				if index % 2 == 0 then
					local start = Track.frame(index / Track.segments, side * 17).Position
					local finish = Track.frame((index + 2) / Track.segments, side * 17).Position
					local barrierFrame = CFrame.lookAt((start + finish) / 2, finish)
					local barrierLength = (start - finish).Magnitude + 0.8
					part("Barrier", Vector3.new(1.5, 3, barrierLength), barrierFrame * CFrame.new(0, 0.5, 0), metal)
					part(
						"BarrierEdge",
						Vector3.new(1.6, 0.16, barrierLength),
						barrierFrame * CFrame.new(0, 2.08, 0),
						cyan,
						Enum.Material.Neon
					)
				end
			else
				part(
					"Barrier",
					Vector3.new(1.5, 3, length),
					frame * CFrame.new(side * 17, 0.5, 0),
					if index % 4 < 2 then teal else cream
				)
			end
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
	if scifi then
		for _, side in { -1, 1 } do
			part(
				"GantryTrim",
				Vector3.new(0.18, 15, 2.12),
				Track.frame(0, side * 16) * CFrame.new(0, 6, 0),
				cyan,
				Enum.Material.Neon
			)
		end
		part(
			"GantryTrim",
			Vector3.new(34, 0.18, 2.12),
			Track.frame(0) * CFrame.new(0, 15.1, 0),
			cyan,
			Enum.Material.Neon
		)
		part(
			"StartLight",
			Vector3.new(7, 0.65, 0.3),
			Track.frame(0) * CFrame.new(0, 12.8, 1.2),
			Color3.fromRGB(156, 241, 207),
			Enum.Material.Neon
		)
	end
	for index = 0, 11 do
		local tile = part(
			"FinishTile",
			Vector3.new(2, 0.1, 3),
			Track.frame(0, index * 2 - 11) * CFrame.new(0, -0.42, 0),
			if index % 2 == 0 then cream else Color3.fromRGB(40, 50, 65)
		)
		if scifi then
			tile.Color = if index % 2 == 0 then cyan else Color3.fromRGB(33, 42, 61)
		end
	end
	local function stall(name: string, x: number, z: number, color: Color3, width: number)
		part(name, Vector3.new(width, 10, 3), CFrame.new(x, 6, z), color)
		local roof = part(name .. "Roof", Vector3.new(width + 4, 2, 16), CFrame.new(x, 12, z + 4), cream)
		if scifi and (name == "Garage" or name == "ShopStall") then
			local light = Instance.new("SurfaceLight")
			light.Face = Enum.NormalId.Bottom
			light.Color = cyan
			light.Brightness = 0.8
			light.Range = 20
			light.Angle = 120
			light.Shadows = false
			light.Parent = roof
		end
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
	for index = 1, if scifi then 8 else 24 do
		if scifi then
			local frame = Track.frame(index / 8, if index % 2 == 0 then 32 else -35)
			local height = random:NextNumber(12, 19)
			local accent = if index % 4 == 0 then magenta else cyan
			part("TowerFoot", Vector3.new(7, 1, 7), frame * CFrame.new(0, -1.5, 0), metal)
			part("TowerMast", Vector3.new(2, height, 2), frame * CFrame.new(0, height / 2 - 1, 0), metal)
			part(
				"TowerCore",
				Vector3.new(0.3, height - 2, 2.12),
				frame * CFrame.new(0, height / 2, 0),
				accent,
				Enum.Material.Neon
			)
			local crown = part(
				"TowerBeacon",
				Vector3.new(6, 0.4, 6),
				frame * CFrame.new(0, height, 0) * CFrame.Angles(0, math.pi / 4, 0),
				accent,
				Enum.Material.Neon
			)
			if index == 2 or index == 6 then
				local light = Instance.new("PointLight")
				light.Color = accent
				light.Brightness = 0.7
				light.Range = 28
				light.Shadows = false
				light.Parent = crown
			end
			continue
		end
		local frame = Track.frame(index / 24, if index % 2 == 0 then 32 else -35)
		local height = random:NextNumber(9, 15)
		part(
			"TreeTrunk",
			Vector3.new(2, height, 2),
			frame * CFrame.new(0, height / 2 - 2, 0),
			Color3.fromRGB(143, 100, 65),
			Enum.Material.Wood
		)
		local crown = part(
			"TreeCrown",
			Vector3.new(10, 10, 10),
			frame * CFrame.new(0, height - 2, 0),
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
	if scifi then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.25
		atmosphere.Offset = 0.15
		atmosphere.Color = Color3.fromRGB(112, 137, 191)
		atmosphere.Decay = Color3.fromRGB(65, 51, 103)
		atmosphere.Haze = 1.4
		atmosphere.Glare = 0
		atmosphere.Parent = Lighting
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.25
		bloom.Size = 18
		bloom.Threshold = 1.4
		bloom.Parent = Lighting
		local sky = Instance.new("Sky")
		sky.StarCount = 5000
		sky.CelestialBodiesShown = true
		sky.MoonTextureId = "rbxasset://sky/moon.jpg"
		sky.MoonAngularSize = 22
		sky.Parent = Lighting
		local grade = Instance.new("ColorCorrectionEffect")
		grade.Brightness = 0.03
		grade.Contrast = 0.08
		grade.Saturation = -0.08
		grade.TintColor = Color3.fromRGB(232, 242, 255)
		grade.Parent = Lighting
		Lighting.EnvironmentDiffuseScale = 0.65
		Lighting.EnvironmentSpecularScale = 0.6
	end
	Lighting.ClockTime = if scifi then 20.5 else 12
	Lighting.Brightness = if scifi then 2 else 2.5
	Lighting.Ambient = if scifi then Color3.fromRGB(115, 127, 160) else Color3.fromRGB(165, 178, 198)
	Lighting.OutdoorAmbient = if scifi then Color3.fromRGB(135, 149, 180) else Color3.fromRGB(180, 190, 210)
	folder:SetAttribute("StaticParts", count)
	assert(count == 511, "update the racing world part budget")
end

return World
