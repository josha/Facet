--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local player = Players.LocalPlayer
local holding = false
local charge = 0
local boost = 0
local speed = 0
local previous = false
local savedType = Enum.CameraType.Custom
local savedSubject: (BasePart | Humanoid)? = nil
local savedFov = 70

local function drift(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
	holding = state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change
	return Enum.ContextActionResult.Sink
end

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
			local target = seat.ThrottleFloat * (if boost > 0 then 66 else 46)
			speed += (target - speed) * math.min(1, dt * 3)
			if
				player:GetAttribute("RaceAutopilot") ~= true
				and drive
				and drive:IsA("LinearVelocity")
				and turn
				and turn:IsA("AngularVelocity")
			then
				local forward = root.CFrame.LookVector
				local velocity = forward * speed
				if drifting then
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
		ContextActionService:BindAction("KartDrift", drift, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonX)
		RunService:BindToRenderStep("KartDrive", Enum.RenderPriority.Camera.Value + 1, render)
	else
		ContextActionService:UnbindAction("KartDrift")
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
