--!strict

export type Kart = { model: Model, seat: VehicleSeat }
local Kart = {}
local PhysicsService = game:GetService("PhysicsService")
for _, group in { "RaceBody", "RaceWheel" } do
	if not PhysicsService:IsCollisionGroupRegistered(group) then
		PhysicsService:RegisterCollisionGroup(group)
	end
end
PhysicsService:CollisionGroupSetCollidable("RaceBody", "RaceWheel", false)

function Kart.create(name: string, color: Color3, frame: CFrame, kinematic: boolean): Kart
	local model = Instance.new("Model")
	model.Name = name
	local function part(label: string, size: Vector3, offset: CFrame, tint: Color3): Part
		local object = Instance.new("Part")
		object.Name = label
		object.Size = size
		object.CFrame = frame * offset
		object.Color = tint
		if workspace:GetAttribute("WorldTheme") == "scifi" then
			object.Material = if label == "Nose" or label == "Spoiler" then Enum.Material.Neon else Enum.Material.Metal
			if label == "Chassis" then
				object.Color = Color3.fromRGB(30, 38, 58)
			end
		end
		object.Anchored = kinematic
		object.CanCollide = label == "Chassis" or (not kinematic and label == "Wheel")
		object.CollisionGroup = if label == "Wheel" then "RaceWheel" else "RaceBody"
		object.TopSurface = Enum.SurfaceType.Smooth
		object.BottomSurface = Enum.SurfaceType.Smooth
		object.Parent = model
		return object
	end
	local body = part("Chassis", Vector3.new(7.6, 0.7, 7), CFrame.new(0, 1, 0), color)
	body.RootPriority = 127
	body.CustomPhysicalProperties = PhysicalProperties.new(1, 0.15, 0, 100, 100)
	model.PrimaryPart = body
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.7, 2)
	seat.CFrame = frame * CFrame.new(0, 1.8, 0.6)
	seat.Color = Color3.fromRGB(42, 49, 64)
	seat.Anchored = kinematic
	seat.CanCollide = false
	seat.HeadsUpDisplay = not kinematic
	seat.Parent = model
	local function weld(object: BasePart)
		local joint = Instance.new("WeldConstraint")
		joint.Part0 = body
		joint.Part1 = object
		joint.Parent = object
	end
	weld(seat)
	weld(part("Nose", Vector3.new(3, 1, 2), CFrame.new(0, 1.8, -2.4), color))
	weld(part("Spoiler", Vector3.new(6, 0.4, 1), CFrame.new(0, 2.4, 3), color))
	for _, x in { -3.2, 3.2 } do
		for _, z in { -2, 2 } do
			local wheel = part("Wheel", Vector3.new(1.2, 2, 2), CFrame.new(x, 0.5, z), Color3.fromRGB(34, 40, 53))
			wheel.Shape = Enum.PartType.Cylinder
			wheel.CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.15, 0, 100, 100)
			if kinematic then
				weld(wheel)
			else
				local axle = Instance.new("Attachment")
				axle.Position = Vector3.new(x, -0.5, z)
				axle.Parent = body
				local hub = Instance.new("Attachment")
				hub.Parent = wheel
				local hinge = Instance.new("HingeConstraint")
				hinge.Attachment0 = axle
				hinge.Attachment1 = hub
				hinge.Parent = body
			end
		end
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "DriveAttachment"
	attachment.Parent = body
	local drive = Instance.new("LinearVelocity")
	drive.Name = "Drive"
	drive.Attachment0 = attachment
	drive.RelativeTo = Enum.ActuatorRelativeTo.World
	drive.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	drive.PrimaryTangentAxis = Vector3.xAxis
	drive.SecondaryTangentAxis = Vector3.zAxis
	drive.MaxForce = 18000
	drive.Enabled = not kinematic
	drive.Parent = body
	local turn = Instance.new("AngularVelocity")
	turn.Name = "Turn"
	turn.Attachment0 = attachment
	turn.RelativeTo = Enum.ActuatorRelativeTo.World
	turn.MaxTorque = 12000
	turn.Enabled = not kinematic
	turn.Parent = body
	local uprightAxis = Instance.new("Attachment")
	uprightAxis.Axis = Vector3.yAxis
	uprightAxis.SecondaryAxis = Vector3.xAxis
	uprightAxis.Parent = body
	local upright = Instance.new("AlignOrientation")
	upright.Attachment0 = uprightAxis
	upright.Mode = Enum.OrientationAlignmentMode.OneAttachment
	upright.AlignType = Enum.AlignType.PrimaryAxisParallel
	upright.CFrame = CFrame.Angles(0, 0, math.pi / 2)
	upright.MaxTorque = 100000
	upright.Responsiveness = 15
	upright.Enabled = not kinematic
	upright.Parent = body
	model.Parent = workspace
	return { model = model, seat = seat }
end

return Kart
