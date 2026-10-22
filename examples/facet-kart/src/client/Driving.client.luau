--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Track = require(game:GetService("ReplicatedStorage").Shared.RaceTrack)
type Rival = { model: Model, visual: Model?, samples: { Vector3 }, progress: number?, lane: number? }
local rivals: { Rival } = {}
local function watch(object: Instance)
	if object:IsA("Model") then
		table.insert(rivals, { model = object, samples = {} })
	end
end
for _, object in workspace:GetChildren() do
	watch(object)
end
workspace.ChildAdded:Connect(watch)
RunService:BindToRenderStep("RaceRivals", Enum.RenderPriority.Camera.Value - 1, function(dt: number)
	local clock = workspace:GetServerTimeNow()
	for index = #rivals, 1, -1 do
		local rival = rivals[index]
		local model = rival.model
		if model.Parent == nil then
			if rival.visual then
				rival.visual:Destroy()
			end
			table.remove(rivals, index)
			continue
		end
		local motion = model:GetAttribute("Motion")
		local epoch = model:GetAttribute("RaceEpoch")
		if typeof(motion) ~= "Vector3" or type(epoch) ~= "number" then
			continue
		end
		local now = clock - epoch
		local visual = rival.visual
		if not visual then
			local created = model:Clone() :: Model
			created.Name = "RivalVisual"
			created:SetAttribute("Motion", nil)
			for _, object in created:GetDescendants() do
				if object:IsA("BasePart") then
					object.CanCollide = false
					object.CanTouch = false
					object.CanQuery = false
				elseif object:IsA("Weld") and object.Name == "SeatWeld" then
					object:Destroy()
				end
			end
			rival.visual = created
			visual = created
			for _, object in model:GetDescendants() do
				if object:IsA("BasePart") then
					object.LocalTransparencyModifier = 1
				end
			end
			created.Parent = workspace.CurrentCamera
		end
		assert(visual)
		local samples = rival.samples
		if samples[#samples] ~= motion then
			table.insert(samples, motion)
		end
		while #samples > 2 do
			table.remove(samples, 1)
		end
		local before = samples[1]
		motion = samples[2] or before
		local span = motion.Z - before.Z
		local alpha = if span > 0 then math.clamp((now - before.Z) / span, 0, 1 + 0.1 / span) else 1
		local stopped = model:GetAttribute("StoppedProgress")
		local progress = if type(stopped) == "number" then stopped else before.X + (motion.X - before.X) * alpha
		local lane = math.clamp(before.Y + (motion.Y - before.Y) * alpha, -8.25, 8.25)
		local predicting = span > 0 and now < motion.Z + 0.1 and type(stopped) ~= "number"
		local pace = if predicting then (motion.X - before.X) / span else 0
		local lateral = if predicting then (motion.Y - before.Y) / span else 0
		local blend = 1 - math.exp(-dt * 20)
		local advanced = (rival.progress or progress) + pace * dt
		local shifted = (rival.lane or lane) + lateral * dt
		local visualProgress = advanced + (progress - advanced) * blend
		local visualLane = math.clamp(shifted + (lane - shifted) * blend, -8.25, 8.25)
		rival.progress = visualProgress
		rival.lane = visualLane
		local rendered = visual :: Model
		rendered:PivotTo(Track.frame(visualProgress, visualLane) * CFrame.new(0, 1, 0))
	end
end)
local driftContext = script.Parent.KartInput.Drift
local player = Players.LocalPlayer
local holding = false
local charge = 0
local boost = 0
local speed = 0
local previous = false
local savedType = Enum.CameraType.Custom
local savedSubject: (BasePart | Humanoid)? = nil
local savedFov = 70

driftContext.Hold.Pressed:Connect(function()
	holding = true
end)
driftContext.Hold.Released:Connect(function()
	holding = false
end)

local function render(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local seat = if humanoid then humanoid.SeatPart else nil
	local racing = player:GetAttribute("Racing") == true and seat ~= nil and seat:IsA("VehicleSeat")
	if racing and seat and seat:IsA("VehicleSeat") then
		if not previous then
			savedType = camera.CameraType
			savedSubject = camera.CameraSubject
			savedFov = camera.FieldOfView
		end
		local root = seat.AssemblyRootPart
		if root then
			local drive = root:FindFirstChild("Drive")
			local turn = root:FindFirstChild("Turn")
			local drifting = holding or math.abs(seat.SteerFloat) > 0.8
			if drifting and math.abs(speed) > 12 then
				charge = math.min(1.5, charge + dt)
			elseif charge > 0 then
				if charge >= 0.35 then
					boost = 1.2
				end
				charge = 0
			end
			boost = math.max(0, boost - dt)
			local bumpUntil = root:GetAttribute("BumpUntil")
			local bumped = type(bumpUntil) == "number" and workspace:GetServerTimeNow() < bumpUntil
			local target = seat.ThrottleFloat * (if bumped then 20 elseif boost > 0 then 66 else 46)
			if bumped then
				speed = math.clamp(speed, -20, 20)
			end
			speed += (target - speed) * math.min(1, dt * 3)
			if
				player:GetAttribute("RaceAutopilot") ~= true
				and drive
				and drive:IsA("LinearVelocity")
				and turn
				and turn:IsA("AngularVelocity")
			then
				local t = Track.progress(root.Position)
				if root.Position.Y < -10 or (root.Position - Track.point(t)).Magnitude > 60 then
					local checkpoint = root:GetAttribute("Checkpoint")
					local progress = if type(checkpoint) == "number" then checkpoint / Track.checkpoints else 0
					local model = seat.Parent
					if model and model:IsA("Model") then
						model:PivotTo(Track.frame(progress) * CFrame.new(0, 3, 0))
					end
					root.AssemblyLinearVelocity = Vector3.zero
				end
				local forward = root.CFrame.LookVector
				local velocity = forward * speed
				drive.MaxForce = if bumped then root.AssemblyMass * 25 else 18000
				if bumped then
					velocity = velocity:Lerp(root.AssemblyLinearVelocity, 0.65)
				elseif drifting then
					velocity = velocity:Lerp(root.AssemblyLinearVelocity, 0.25)
				end
				drive.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
				turn.AngularVelocity = Vector3.new(
					0,
					-seat.SteerFloat * math.clamp(speed / 22, -1, 1) * (if drifting then 2.2 else 1.6),
					0
				)
			end
			camera.CameraType = Enum.CameraType.Scriptable
			local position = root.Position
			local desired = CFrame.lookAt(
				position - root.CFrame.LookVector * 19 + Vector3.new(0, 10, 0),
				position + root.CFrame.LookVector * 12 + Vector3.new(0, 2, 0)
			)
			camera.CFrame = if previous then camera.CFrame:Lerp(desired, 1 - math.exp(-dt * 9)) else desired
			camera.FieldOfView = if boost > 0 then 78 else 70
		end
	elseif previous then
		camera.CameraType = savedType
		camera.CameraSubject = if humanoid then humanoid else savedSubject
		camera.FieldOfView = savedFov
	end
	previous = racing
end

local function phase()
	local racing = player:GetAttribute("Racing") == true
	if racing then
		driftContext.Enabled = true
		RunService:BindToRenderStep("KartDrive", Enum.RenderPriority.Camera.Value, render)
	else
		driftContext.Enabled = false
		RunService:UnbindFromRenderStep("KartDrive")
		local camera = workspace.CurrentCamera
		if previous and camera then
			camera.CameraType = savedType
			local character = player.Character
			local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
			camera.CameraSubject = if humanoid then humanoid else savedSubject
			camera.FieldOfView = savedFov
		end
		previous = false
		holding = false
		charge = 0
		boost = 0
		speed = 0
	end
end
player:GetAttributeChangedSignal("Racing"):Connect(phase)
phase()
