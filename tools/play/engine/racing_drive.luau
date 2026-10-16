--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

return function(): { [string]: unknown }
	local loadTrack = getfenv(0).require :: (
		ModuleScript
	) -> { progress: (Vector3) -> number, point: (number) -> Vector3, checkpoints: number }
	local Track =
		loadTrack(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("RaceTrack") :: ModuleScript)
	local player = Players.LocalPlayer
	assert(player, "a local driver is required")
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	assert(humanoid, "the driver has no humanoid")
	local deadline = os.clock() + 10
	while humanoid.SeatPart == nil and os.clock() < deadline do
		RunService.Heartbeat:Wait()
	end
	local seat = humanoid.SeatPart
	assert(seat and seat:IsA("VehicleSeat"), "the race did not seat the player")
	local root = seat.AssemblyRootPart
	assert(root and not root.Anchored, "the player kart must use live physics")
	assert(player:GetAttribute("RaceAutopilot") ~= true, "scenario autopilot cannot prove driving")
	task.wait(3)
	assert(
		humanoid.SeatPart == seat and player:GetAttribute("Racing") == true,
		"the player was knocked out before driving lap one"
	)
	local start = root.Position
	local initialProgress = tonumber(root:GetAttribute("RaceProgress")) or 0
	local maxSteer = 0
	local maxDistance = 0
	local advanced = false
	RunService:BindToRenderStep("RaceDrivingCheck", Enum.RenderPriority.Camera.Value - 2, function()
		local progress = Track.progress(root.Position)
		local target = Track.point(progress + 0.025)
		local direction = root.CFrame:VectorToObjectSpace(target - root.Position)
		seat.ThrottleFloat = 1
		seat.SteerFloat = math.clamp(math.atan2(direction.X, -direction.Z) * 2, -0.7, 0.7)
		maxSteer = math.max(maxSteer, math.abs(seat.SteerFloat))
	end)
	local ok, problem = pcall(function()
		local endsAt = os.clock() + 45
		while os.clock() < endsAt do
			RunService.Heartbeat:Wait()
			assert(
				humanoid.SeatPart == seat and player:GetAttribute("Racing") == true,
				"the driver was removed from the race"
			)
			maxDistance = math.max(maxDistance, (root.Position - start).Magnitude)
			advanced = (tonumber(root:GetAttribute("RaceProgress")) or 0) >= initialProgress + 3 / Track.checkpoints
			if advanced and maxDistance > 30 and maxSteer > 0.05 then
				break
			end
		end
		assert(maxDistance > 30, "native throttle did not move the kart")
		assert(maxSteer > 0.05, "the route did not exercise native steering")
		assert(advanced, "live driving did not advance three ordered checkpoints")
	end)
	RunService:UnbindFromRenderStep("RaceDrivingCheck")
	seat.ThrottleFloat = 0
	seat.SteerFloat = 0
	assert(ok, tostring(problem))
	return { distance = maxDistance, steer = maxSteer, progress = root:GetAttribute("RaceProgress") }
end
