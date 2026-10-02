--!strict

type Host = {
	Part: (string) -> ({ [string]: any }) -> Part,
	Model: (string) -> ({ Instance }) -> Model,
	PointLight: ({ [string]: any }) -> PointLight,
	ProximityPrompt: ({ [string]: any }) -> ProximityPrompt,
}
local world = {}
world.colors = {
	sage = Color3.fromRGB(121, 159, 137),
	clay = Color3.fromRGB(201, 125, 99),
	cream = Color3.fromRGB(232, 221, 190),
	midnight = Color3.fromRGB(64, 82, 108),
}
function world.position(index: number): Vector3
	return Vector3.new(((index - 1) % 3 - 1) * 7, 0.28, if index <= 3 then -4 else 4)
end
function world.furniture(Host: Host, item: any, at: CFrame, assets: Instance?): Model
	local template = if assets then assets:FindFirstChild(item.kind) else nil
	if template and template:IsA("Model") then
		local model = template:Clone()
		local _, original = model:GetBoundingBox()
		local factor = if item.kind == "shelf"
			then 4.8 / original.Y
			elseif item.kind == "lamp" then 4.6 / original.Y
			else (if item.kind == "sofa" then 5.8 else 4.8) / original.X
		model:ScaleTo(model:GetScale() * factor)
		local bounds, size = model:GetBoundingBox()
		model.WorldPivot = bounds
		model:PivotTo(at * CFrame.new(0, size.Y / 2, 0))
		for _, piece in model:GetDescendants() do
			if piece:IsA("MeshPart") then
				local surface = piece:FindFirstChildWhichIsA("SurfaceAppearance")
				if surface then
					surface.Color = world.colors[item.palette] or world.colors.sage
				end
			end
		end
		return model
	end
	local tint = world.colors[item.palette] or world.colors.sage
	local wood, soft = Color3.fromRGB(144, 107, 73), Color3.fromRGB(245, 233, 209)
	local function part(name: string, size: Vector3, offset: Vector3, color: Color3, shape: Enum.PartType?): Part
		return Host.Part(name) {
			Anchored = true,
			Size = size,
			CFrame = at * CFrame.new(offset),
			Color = color,
			Material = if color == wood
				then Enum.Material.Wood
				elseif item.kind == "rug" then Enum.Material.Fabric
				else Enum.Material.SmoothPlastic,
			Shape = shape or Enum.PartType.Block,
			TopSurface = Enum.SurfaceType.Smooth,
			BottomSurface = Enum.SurfaceType.Smooth,
		}
	end
	local pieces: { Instance } = {}
	if item.kind == "sofa" then
		table.insert(pieces, part("Base", Vector3.new(5.5, 0.7, 2.8), Vector3.new(0, 0.8, 0), wood))
		table.insert(pieces, part("Cushion", Vector3.new(5.1, 0.65, 2.6), Vector3.new(0, 1.45, 0), tint))
		table.insert(pieces, part("Back", Vector3.new(5.5, 2.2, 0.5), Vector3.new(0, 2, 1.3), tint))
		for _, x in { -2.5, 2.5 } do
			table.insert(pieces, part("Arm", Vector3.new(0.5, 1.4, 2.8), Vector3.new(x, 1.8, 0), tint))
		end
	elseif item.kind == "table" then
		table.insert(pieces, part("Top", Vector3.new(4.5, 0.4, 3), Vector3.new(0, 2.1, 0), wood))
		for _, x in { -1.8, 1.8 } do
			for _, z in { -1, 1 } do
				table.insert(pieces, part("Leg", Vector3.new(0.3, 2, 0.3), Vector3.new(x, 1, z), tint))
			end
		end
		table.insert(pieces, part("Bowl", Vector3.new(1, 0.3, 1), Vector3.new(0, 2.45, 0), soft, Enum.PartType.Ball))
	elseif item.kind == "lamp" then
		table.insert(pieces, part("Base", Vector3.new(1.5, 0.2, 1.5), Vector3.new(0, 0.2, 0), wood))
		table.insert(pieces, part("Stem", Vector3.new(0.2, 3.5, 0.2), Vector3.new(0, 1.85, 0), wood))
		local shade = part("Shade", Vector3.new(2, 2, 2), Vector3.new(0, 4, 0), tint, Enum.PartType.Ball)
		Host.PointLight { Color = soft, Brightness = 1.2, Range = 14 }.Parent = shade
		table.insert(pieces, shade)
	elseif item.kind == "plant" then
		table.insert(pieces, part("Pot", Vector3.new(1.8, 1.5, 1.8), Vector3.new(0, 0.9, 0), tint))
		table.insert(pieces, part("Stem", Vector3.new(0.2, 2.4, 0.2), Vector3.new(0, 2, 0), wood))
		for index = 1, 5 do
			local angle = index * math.pi * 2 / 5
			table.insert(
				pieces,
				part(
					"Leaf",
					Vector3.new(1.3, 0.45, 1.8),
					Vector3.new(math.cos(angle) * 0.7, 2.3 + index * 0.15, math.sin(angle) * 0.7),
					Color3.fromRGB(68, 116, 77),
					Enum.PartType.Ball
				)
			)
		end
	elseif item.kind == "shelf" then
		for _, y in { 0.4, 2, 3.6 } do
			table.insert(pieces, part("Shelf", Vector3.new(4, 0.2, 1.5), Vector3.new(0, y, 0), wood))
		end
		for _, x in { -1.9, 1.9 } do
			table.insert(pieces, part("Side", Vector3.new(0.2, 4, 1.5), Vector3.new(x, 2, 0), tint))
		end
		for index = 1, 6 do
			table.insert(
				pieces,
				part(
					"Book",
					Vector3.new(0.35, 1.1, 0.8),
					Vector3.new(-1.3 + index * 0.4, 2.65, 0),
					if index % 2 == 0 then soft else tint
				)
			)
		end
	else
		table.insert(pieces, part("Rug", Vector3.new(5.5, 0.12, 4), Vector3.new(0, 0.12, 0), tint))
		table.insert(pieces, part("Stripe", Vector3.new(5.3, 0.04, 0.35), Vector3.new(0, 0.2, 0), soft))
	end
	return Host.Model(item.kind)(pieces)
end
function world.room(Host: Host, owner: Player, origin: Vector3): (Model, { Part }, Part)
	local wood = Color3.fromRGB(182, 147, 107)
	local function part(name: string, size: Vector3, position: Vector3, color: Color3): Part
		return Host.Part(name) {
			Anchored = true,
			Size = size,
			Position = origin + position,
			Color = color,
			Material = if name == "Floor"
				then Enum.Material.WoodPlanks
				elseif name == "GardenPath" then Enum.Material.Slate
				else Enum.Material.Plaster,
			TopSurface = Enum.SurfaceType.Smooth,
			BottomSurface = Enum.SurfaceType.Smooth,
		}
	end
	local children: { Instance } = {
		part("Floor", Vector3.new(27, 0.4, 23), Vector3.new(0, 0, 0), wood),
		part("BackWall", Vector3.new(27, 9, 0.5), Vector3.new(0, 4.5, 11.5), Color3.fromRGB(229, 222, 203)),
		part("LeftWall", Vector3.new(0.5, 9, 23), Vector3.new(-13.5, 4.5, 0), Color3.fromRGB(223, 216, 199)),
		part("GardenPath", Vector3.new(6, 0.2, 22), Vector3.new(0, -0.3, -22), Color3.fromRGB(221, 211, 188)),
	}
	local board = part("HomeBoard", Vector3.new(7, 3.4, 0.15), Vector3.new(0, 5.5, 11.1), Color3.fromRGB(54, 80, 70))
	table.insert(children, board)
	local ivory = Color3.fromRGB(239, 234, 221)
	for _, x in { -13.2, 13.2 } do
		table.insert(children, part("Skirting", Vector3.new(0.25, 0.5, 23), Vector3.new(x, 0.5, 0), ivory))
	end
	table.insert(children, part("BackSkirting", Vector3.new(27, 0.5, 0.25), Vector3.new(0, 0.5, 11.15), ivory))
	for _, z in { -11, 0, 11 } do
		table.insert(children, part("WindowPost", Vector3.new(0.4, 9, 0.4), Vector3.new(13.5, 4.5, z), wood))
	end
	for _, y in { 0.5, 4.5, 8.8 } do
		table.insert(children, part("WindowRail", Vector3.new(0.4, 0.35, 23), Vector3.new(13.5, y, 0), wood))
	end
	local glass =
		part("PictureWindow", Vector3.new(0.12, 8, 22), Vector3.new(13.5, 4.6, 0), Color3.fromRGB(203, 224, 229))
	glass.Material, glass.Transparency, glass.CanCollide = Enum.Material.Glass, 0.82, false
	table.insert(children, glass)
	for _, x in { -9, 9 } do
		table.insert(children, part("EntryColumn", Vector3.new(0.5, 9, 0.5), Vector3.new(x, 4.5, -11.4), wood))
	end
	table.insert(children, part("EntryBeam", Vector3.new(27, 0.6, 0.6), Vector3.new(0, 9, -11.4), wood))
	for index = 1, 4 do
		table.insert(
			children,
			part("SteppingStone", Vector3.new(5, 0.12, 2.5), Vector3.new(0, -0.05, -13 - index * 4), ivory)
		)
	end
	local slots = {}
	for index = 1, 6 do
		local marker =
			part("Place" .. index, Vector3.new(6, 0.08, 6), world.position(index), Color3.fromRGB(214, 202, 175))
		marker.Transparency = 0.92
		marker.CanCollide = false
		marker:SetAttribute("FacetHomeSlot", index)
		Host.ProximityPrompt {
			ActionText = "Choose this place",
			ObjectText = "Room place " .. index,
			MaxActivationDistance = 8,
			RequiresLineOfSight = false,
		}.Parent =
			marker
		table.insert(slots, marker)
		table.insert(children, marker)
	end
	for _, x in { -17, 17 } do
		for _, z in { -15, 14 } do
			table.insert(
				children,
				part("TreeTrunk", Vector3.new(1, 5, 1), Vector3.new(x, 2, z), Color3.fromRGB(119, 95, 66))
			)
			local crown = part("TreeCrown", Vector3.new(7, 7, 7), Vector3.new(x, 6.5, z), Color3.fromRGB(109, 142, 89))
			crown.Shape = Enum.PartType.Ball
			table.insert(children, crown)
		end
	end
	local room = Host.Model("Home_" .. owner.UserId)(children)
	room:SetAttribute("OwnerUserId", owner.UserId)
	return room, slots, board
end
return world
