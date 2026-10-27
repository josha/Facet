--!strict
local Facet = require(game.ReplicatedStorage.Packages.Facet)

return function(runtime: Facet.Runtime, world: WorldModel, chosen: Facet.ReadOnlyValue<string>): nil
	local C, Host = Facet.Compose, Facet.host(runtime)
	local leaf, stem = Color3.fromRGB(95, 143, 73), Color3.fromRGB(52, 95, 56)
	local wood, metal = Color3.fromRGB(169, 118, 66), Color3.fromRGB(111, 143, 143)
	local function art(id: string): Model
		local model = Host.Model "Supply" {}
		local function part(name: string, size: Vector3, at: Vector3, color: Color3, shape: Enum.PartType?): Part
			return Host.Part(name) {
				Parent = C.static(model),
				Anchored = true,
				CanCollide = false,
				Size = size,
				Position = at,
				Color = color,
				Shape = shape or Enum.PartType.Block,
				Material = Enum.Material.SmoothPlastic,
			}
		end
		local function rod(name: string, a: Vector3, b: Vector3, width: number, color: Color3)
			local node = part(name, Vector3.new(width, width, (b - a).Magnitude), (a + b) / 2, color)
			node.CFrame = CFrame.lookAt((a + b) / 2, b)
		end
		local function plant(kind: string, at: Vector3, scale: number)
			if kind == "willow" then
				rod("Trunk", at, at + Vector3.new(0, 2.8, 0) * scale, 0.18 * scale, wood)
				for side = -1, 1, 2 do
					rod(
						"Branch",
						at + Vector3.new(0, 1.8, 0) * scale,
						at + Vector3.new(side, 2.6, 0) * scale,
						0.12 * scale,
						wood
					)
					part(
						"WillowCrown",
						Vector3.new(1.4, 1.7, 1.2) * scale,
						at + Vector3.new(side * 0.65, 2.6, 0) * scale,
						leaf,
						Enum.PartType.Ball
					)
				end
			else
				for i = -2, 2 do
					local base = at + Vector3.new(i * 0.13, 0, 0)
					local tip = base
						+ Vector3.new(
								i * 0.23,
								(if kind == "reed" then 2.4 else 1.6) - math.abs(i) * 0.18,
								i * 0.08
							)
							* scale
					rod(
						"Leaf",
						base,
						tip,
						(if kind == "sedge" then 0.16 else 0.09) * scale,
						if kind == "sedge" then Color3.fromRGB(155, 165, 63) else stem
					)
					if kind == "reed" then
						part("SeedHead", Vector3.new(0.18, 0.5, 0.18) * scale, tip, Color3.fromRGB(132, 93, 55))
					elseif kind == "iris" and i % 2 == 0 then
						for petal = 0, 2 do
							local angle = petal * math.pi * 2 / 3
							part(
								"IrisPetal",
								Vector3.new(0.48, 0.18, 0.4) * scale,
								tip + Vector3.new(math.cos(angle) * 0.22, 0, math.sin(angle) * 0.22) * scale,
								Color3.fromRGB(108, 103, 187),
								Enum.PartType.Ball
							)
						end
						part(
							"FlowerHeart",
							Vector3.new(0.14, 0.15, 0.14),
							tip,
							Color3.fromRGB(236, 198, 76),
							Enum.PartType.Ball
						)
					end
				end
			end
		end
		if id == "reed" or id == "willow" or id == "sedge" or id == "iris" then
			part("RootPlug", Vector3.new(1.25, 0.55, 1.05), Vector3.new(0, -1.35, 0), Color3.fromRGB(101, 77, 51))
			plant(id, Vector3.new(0, -1.1, 0), 1)
		elseif id == "net" or id == "rake" or id == "spade" then
			rod("Handle", Vector3.new(0, -1.9, 0), Vector3.new(0, 0.9, 0), 0.16, wood)
			if id == "net" then
				for i = 0, 11 do
					local a, b = i * math.pi / 6, (i + 1) * math.pi / 6
					rod(
						"Hoop",
						Vector3.new(math.cos(a) * 0.85, 1.35 + math.sin(a) * 0.85, 0),
						Vector3.new(math.cos(b) * 0.85, 1.35 + math.sin(b) * 0.85, 0),
						0.09,
						metal
					)
				end
				for i = -2, 2 do
					local d, edge = i * 0.24, math.sqrt(0.64 - (i * 0.24) ^ 2)
					rod("Mesh", Vector3.new(d, 1.35 - edge, 0), Vector3.new(d, 1.35 + edge, 0), 0.025, metal)
					rod("Mesh", Vector3.new(-edge, 1.35 + d, 0), Vector3.new(edge, 1.35 + d, 0), 0.025, metal)
				end
			elseif id == "rake" then
				part("RakeHead", Vector3.new(2.1, 0.16, 0.18), Vector3.new(0, 1.05, 0), metal)
				for i = -3, 3 do
					part("Tooth", Vector3.new(0.09, 0.6, 0.12), Vector3.new(i * 0.3, 1.4, 0), metal)
				end
			else
				part("SpadeBlade", Vector3.new(0.85, 1, 0.16), Vector3.new(0, 1.35, 0), metal)
				part("Grip", Vector3.new(0.65, 0.16, 0.2), Vector3.new(0, -1.9, 0), stem)
			end
		elseif id == "meter" then
			part("Meter", Vector3.new(1.2, 1.7, 0.55), Vector3.new(0, 0.5, 0), Color3.fromRGB(233, 181, 68))
			part("Readout", Vector3.new(0.85, 0.65, 0.08), Vector3.new(0, 0.85, 0.32), Color3.fromRGB(35, 70, 65))
			part("DisplayMark", Vector3.new(0.5, 0.08, 0.06), Vector3.new(0, 0.85, 0.38), Color3.fromRGB(170, 220, 166))
			rod("Probe", Vector3.new(0, -0.3, 0), Vector3.new(0, -1.8, 0), 0.18, metal)
		elseif id == "stones" then
			for i = 1, 5 do
				part(
					"RiverStone",
					Vector3.new(1.2, 0.65, 1),
					Vector3.new((i % 3 - 1) * 0.8, -1 + math.floor(i / 3) * 0.4, (i % 2 - 0.5) * 0.9),
					Color3.fromRGB(133 + i * 8, 145 + i * 6, 136 + i * 5),
					Enum.PartType.Ball
				)
			end
		elseif id == "clay" or id == "log" then
			local color = if id == "clay" then Color3.fromRGB(186, 112, 74) else Color3.fromRGB(119, 88, 55)
			for i = 0, 9 do
				local angle = i * math.pi / 5
				part(
					"HollowWall",
					Vector3.new(0.46, 0.46, 2.4),
					Vector3.new(math.cos(angle) * 0.72, math.sin(angle) * 0.72 - 0.45, 0),
					color,
					if id == "log" then Enum.PartType.Block else Enum.PartType.Ball
				)
			end
			if id == "log" then
				rod("Branch", Vector3.new(0.5, 0, 0.3), Vector3.new(1.3, 0.7, 0.3), 0.3, wood)
			end
		elseif id == "raft" then
			part("FloatingBed", Vector3.new(3.2, 0.4, 2.4), Vector3.new(0, -1, 0), wood)
			part("GrassBed", Vector3.new(2.9, 0.15, 2.1), Vector3.new(0, -0.72, 0), leaf)
			plant("reed", Vector3.new(-0.8, -0.6, -0.5), 0.6)
			for i = 0, 7 do
				local angle = i * math.pi / 4
				part(
					"Nest",
					Vector3.new(0.5, 0.18, 0.3),
					Vector3.new(0.65 + math.cos(angle) * 0.45, -0.5, math.sin(angle) * 0.45),
					wood
				)
			end
		else
			part("SupplyCrate", Vector3.new(2, 1.5, 1.5), Vector3.zero, wood)
		end
		return model
	end
	Host.Model "SupplyArt" {
		Parent = C.static(world),
		C.keyed({
			from = function(use: Facet.Use): { string }
				return { use(chosen) }
			end,
			key = function(id: string): string
				return id
			end,
			render = function(current: Facet.ReadOnlyValue<string>): Model
				return art(current:peek())
			end,
		}),
	}
	return nil
end
