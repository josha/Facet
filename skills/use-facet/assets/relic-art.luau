--!strict
local Facet = require(game.ReplicatedStorage.Packages.Facet)

return function(
	runtime: Facet.Runtime,
	world: WorldModel,
	chosen: Facet.ReadOnlyValue<string>,
	sunColor: Color3,
	tideColor: Color3
): nil
	local C = Facet.Compose
	local Host = Facet.host(runtime)
	local function art(sun: boolean): Model
		local sculpture = Host.Model(if sun then "SunPrism" else "TideLens") {}
		local metal = Color3.fromRGB(70, 67, 58)
		local brass = Color3.fromRGB(172, 143, 86)
		local inlay = Color3.fromRGB(228, 215, 172)
		local function piece(name: string, size: Vector3, at: Vector3, color: Color3, shape: Enum.PartType?): Part
			return Host.Part(name) {
				Parent = C.static(sculpture),
				Anchored = true,
				CanCollide = false,
				Size = size,
				Position = at,
				Color = color,
				Shape = shape or Enum.PartType.Block,
				Material = Enum.Material.Metal,
			}
		end
		if sun then
			local amber = sunColor
			local body = piece("Crystal", Vector3.new(1.3, 2.3, 1.25), Vector3.new(0, 0.25, 0), amber)
			body.Material, body.Transparency = Enum.Material.Glass, 0.12
			for _, direction in { -1, 1 } do
				Host.WedgePart("Crown" .. tostring(direction)) {
					Parent = C.static(sculpture),
					Anchored = true,
					CanCollide = false,
					Size = Vector3.new(1.3, 0.7, 0.625),
					Position = Vector3.new(0, 1.75, direction * 0.3125),
					Orientation = Vector3.new(0, if direction < 0 then 180 else 0, 0),
					Color = amber,
					Material = Enum.Material.Glass,
					Transparency = 0.12,
				}
				piece(
					"Cradle" .. tostring(direction),
					Vector3.new(0.28, 1.7, 1.7),
					Vector3.new(direction * 0.95, -0.65, 0),
					brass
				)
				piece(
					"Inlay" .. tostring(direction),
					Vector3.new(0.12, 1.45, 0.08),
					Vector3.new(direction * 0.4, 0.2, 0.67),
					inlay
				)
			end
			piece("CradleFoot", Vector3.new(2.7, 0.3, 2), Vector3.new(0, -1.6, 0), metal)
			piece("CradleBridge", Vector3.new(2.2, 0.28, 0.3), Vector3.new(0, -0.8, 0.85), brass)
		else
			local bezel =
				piece("Bezel", Vector3.new(0.35, 3.05, 3.05), Vector3.new(0, 0, -0.12), brass, Enum.PartType.Cylinder)
			bezel.Orientation = Vector3.new(0, 90, 0)
			local lens =
				piece("Lens", Vector3.new(2.65, 2.65, 0.45), Vector3.new(0, 0, 0.14), tideColor, Enum.PartType.Ball)
			lens.Material, lens.Transparency = Enum.Material.Glass, 0.16
			local sheen = piece("LensReflection", Vector3.new(0.12, 1.2, 0.08), Vector3.new(0.48, 0.28, 0.4), inlay)
			sheen.Orientation = Vector3.new(0, 0, -28)
			for _, direction in { -1, 1 } do
				piece(
					"Fork" .. tostring(direction),
					Vector3.new(0.22, 1.35, 0.4),
					Vector3.new(direction * 1.2, -1.2, 0),
					metal
				)
				piece(
					"Index" .. tostring(direction),
					Vector3.new(0.12, 0.3, 0.12),
					Vector3.new(direction * 0.98, 1.05, 0.1),
					inlay
				)
			end
			local hinge =
				piece("Hinge", Vector3.new(0.5, 0.55, 0.55), Vector3.new(0, -1.4, 0), brass, Enum.PartType.Cylinder)
			hinge.Orientation = Vector3.new(0, 90, 0)
			piece("Stand", Vector3.new(2.8, 0.28, 1.5), Vector3.new(0, -1.95, 0), metal)
		end
		return sculpture
	end
	Host.Model "RelicArt" {
		Parent = C.static(world),
		C.show(function(use: Facet.Use)
			return use(chosen) == "sun"
		end, function()
			return art(true)
		end, function()
			return art(false)
		end),
	}
	return nil
end
