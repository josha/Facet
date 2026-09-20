--!strict
local Compose = require(game:GetService("ReplicatedStorage").Facet).Compose
local scenes = {}

-- Each mounted card owns one clock and a small procedural world.
function scenes.card(runtime: any, target: Instance, item: any, motionPolicy: any, active: any)
	local Host = runtime.constructors
	return runtime.mount(function()
		local nodes: any = { Name = item.title }
		local accent = Color3.new(item.color.r, item.color.g, item.color.b)
		local variant = (item.index - 1) % 6
		local clock = runtime.timeline({ duration = 10 + item.index % 4, repeats = math.huge, autoplay = false })
		runtime:watch(function(use)
			if use(motionPolicy) ~= "reduced" and (not active or active(use)) then
				clock:play()
			else
				clock:pause()
			end
		end)
		local function phase(use)
			return (use(clock.progress) + (item.index % 7) / 7) * math.pi * 2
		end
		local function part(name, size, position, color, shape, yaw)
			table.insert(
				nodes,
				Host.Part({
					Name = name,
					Anchored = true,
					CanCollide = false,
					Size = size,
					CFrame = if type(position) == "function"
						then position
						else CFrame.new(position) * CFrame.Angles(0, yaw or 0, 0),
					Color = color,
					Material = Enum.Material.SmoothPlastic,
					Shape = shape or Enum.PartType.Block,
				})
			)
		end
		part("Island", Vector3.new(11, 0.8, 9), Vector3.new(0, -0.6, 0), Color3.fromRGB(49, 64, 77))
		if variant == 1 then
			for i = 1, 16 do
				local angle = i * math.pi / 8
				part(
					"Track",
					Vector3.new(2, 0.2, 1.6),
					Vector3.new(math.cos(angle) * 4, 0, math.sin(angle) * 3),
					Color3.fromRGB(205, 215, 226),
					nil,
					-angle
				)
			end
			part("Racer", Vector3.new(0.8, 0.5, 1.4), function(use)
				local angle = phase(use)
				local position = Vector3.new(math.cos(angle) * 4, 0.45, math.sin(angle) * 3)
				return CFrame.lookAt(position, position + Vector3.new(-math.sin(angle) * 4, 0, math.cos(angle) * 3))
			end, accent)
		elseif variant == 2 then
			for i = 1, 9 do
				local x, z = (i % 3 - 1) * 3, (math.floor((i - 1) / 3) - 1) * 2.6
				part("Trunk", Vector3.new(0.4, 1.8, 0.4), Vector3.new(x, 0.5, z), Color3.fromRGB(140, 101, 74))
				part(
					"Canopy",
					Vector3.new(2.3, 2.3, 2.3),
					Vector3.new(x, 2, z),
					accent:Lerp(Color3.fromRGB(130, 218, 151), i / 12),
					Enum.PartType.Ball
				)
			end
		elseif variant == 3 then
			part("Water", Vector3.new(10.8, 0.2, 8.8), Vector3.new(0, 0, 0), Color3.fromRGB(43, 126, 176))
			for i = 1, 7 do
				part(
					"Ruins",
					Vector3.new(0.6, 1 + i % 3, 0.6),
					Vector3.new((i % 4 - 1.5) * 2, 0.7, math.floor(i / 4) * 3 - 1),
					Color3.fromRGB(154, 192, 183)
				)
			end
		else
			for i = 1, 9 do
				local height = 1 + (i * 7 + item.index) % 5
				local x, z = (i % 3 - 1) * 3, (math.floor((i - 1) / 3) - 1) * 2.6
				part(
					"Tower",
					Vector3.new(1.6, height, 1.6),
					Vector3.new(x, height / 2, z),
					accent:Lerp(Color3.fromRGB(208, 219, 226), i / 14)
				)
				part("Roof", Vector3.new(1.9, 0.25, 1.9), Vector3.new(x, height + 0.12, z), Color3.fromRGB(39, 48, 67))
			end
		end
		if variant ~= 1 then
			-- Geometry also works in ViewportFrames that do not render particle effects.
			part("Beacon", Vector3.new(0.45, 0.45, 0.45), function(use)
				local angle = phase(use)
				return CFrame.new(math.cos(angle) * 2.4, 4.2 + math.sin(angle * 2) * 0.3, math.sin(angle) * 2)
					* CFrame.Angles(angle, angle, 0)
			end, accent:Lerp(Color3.new(1, 1, 1), 0.55))
		end
		return Host.Model(nodes)
	end, target)
end

function scenes.discovery(runtime: any, target: Instance)
	local Host = runtime.constructors
	return runtime.mount(function()
		local children: any = { Name = "Afterlight" }
		local function part(name, size, frame, color, material, shape)
			table.insert(
				children,
				Host.Part({
					Name = name,
					Anchored = true,
					CanCollide = false,
					Size = size,
					CFrame = frame,
					Color = color,
					Material = material or Enum.Material.SmoothPlastic,
					Shape = shape or Enum.PartType.Block,
				})
			)
		end
		local stone = Color3.fromRGB(65, 82, 97)
		local grass = Color3.fromRGB(100, 163, 149)
		local glow = Color3.fromRGB(117, 242, 237)
		local function island(center, radius)
			for tier = 0, 3 do
				local diameter = radius * 2 * (1 - tier * 0.16)
				part(
					"FloatingStratum",
					Vector3.new(0.7, diameter, diameter),
					CFrame.new(center - Vector3.new(0, tier * 0.62, 0)) * CFrame.Angles(0, 0, math.pi / 2),
					if tier == 0 then grass else stone,
					Enum.Material.Slate,
					Enum.PartType.Cylinder
				)
			end
		end
		island(Vector3.new(0, 0, 0), 4.5)
		island(Vector3.new(-6, 1, 3), 2)
		island(Vector3.new(6, 2, 5), 2.7)
		island(Vector3.new(1, 3, 10), 1.7)
		-- An ancient gate, built from individually articulated scene geometry.
		for index = 0, 12 do
			local angle = index / 12 * math.pi
			local position = Vector3.new(math.cos(angle) * 2.1, 1.5 + math.sin(angle) * 2.1, 1)
			part(
				"GateStone",
				Vector3.new(0.55, 0.8, 0.8),
				CFrame.new(position) * CFrame.Angles(0, 0, angle - math.pi / 2),
				Color3.fromRGB(199, 207, 195)
			)
			part(
				"GateLight",
				Vector3.new(0.08, 0.5, 0.85),
				CFrame.new(position) * CFrame.Angles(0, 0, angle - math.pi / 2),
				glow,
				Enum.Material.Neon
			)
		end
		for _, x in { -2.1, 2.1 } do
			part("GatePillar", Vector3.new(0.65, 1.5, 0.8), CFrame.new(x, 0.75, 1), Color3.fromRGB(179, 191, 185))
		end
		for index = 1, 7 do
			part(
				"Path",
				Vector3.new(0.7, 0.1, 0.55),
				CFrame.new(math.sin(index * 0.6) * 0.5, 0.42, -index * 0.48),
				Color3.fromRGB(216, 220, 194)
			)
		end
		for index, position in
			{
				Vector3.new(-3, 0, -1),
				Vector3.new(3, 0, 2),
				Vector3.new(-6, 1, 3),
				Vector3.new(6, 2, 5),
				Vector3.new(7.5, 2, 4),
			}
		do
			part(
				"TreeTrunk",
				Vector3.new(0.25, 1.7, 0.25),
				CFrame.new(position + Vector3.new(0, 1, 0)),
				Color3.fromRGB(89, 81, 103)
			)
			for tier = 1, 3 do
				local width = 2.1 - tier * 0.4
				part(
					"TreeCrown",
					Vector3.new(width, 0.85, width),
					CFrame.new(position + Vector3.new(0, 1.2 + tier * 0.6, 0)) * CFrame.Angles(0, index * 0.5, 0),
					Color3.fromRGB(68 + tier * 8, 107 + tier * 12, 127 + tier * 13)
				)
			end
		end
		for index = 1, 5 do
			part(
				"SkyStep",
				Vector3.new(0.85, 0.18, 0.8),
				CFrame.new(3 + index * 0.5, 0.5 + index * 0.28, 2 + index * 0.4),
				Color3.fromRGB(174, 206, 204)
			)
		end
		part("Beacon", Vector3.new(0.22, 3.5, 0.22), CFrame.new(1, 5, 10), glow, Enum.Material.Neon)
		return Host.Model(children)
	end, target)
end

function scenes.staticAvatar(runtime: any, target: Instance, angle: any, palette: any, hat: any, motionPolicy: any)
	local Host = runtime.constructors
	local animatedAngle: any
	local colors = {
		sage = Color3.fromRGB(130, 158, 126),
		clay = Color3.fromRGB(195, 121, 94),
		iris = Color3.fromRGB(146, 124, 191),
	}
	local skin = Color3.fromRGB(234, 183, 138)
	local function piece(name, size, position, color, extra)
		local props: any = {
			Name = name,
			Anchored = true,
			CanCollide = false,
			Size = size,
			CFrame = function(use)
				local rotation = if use(motionPolicy) == "reduced" then use(angle) else use(animatedAngle)
				return CFrame.Angles(0, math.rad(rotation), 0) * CFrame.new(position)
			end,
			Color = color,
			Material = Enum.Material.SmoothPlastic,
		}
		for key, value in extra or {} do
			props[key] = value
		end
		return Host.Part(props)
	end
	local function outfit(use)
		return colors[use(palette)]
	end
	local function visibility(use)
		return if use(hat) then 0 else 1
	end
	return runtime.mount(function()
		animatedAngle = runtime.spring(function(use)
			return use(angle)
		end, { period = 0.55, damping = 0.9 })
		return Host.Model({
			Name = "Explorer",
			-- Clothing details are game-owned geometry; Compose owns their lifetime
			-- and keeps every piece on the same interrupted rotation spring.
			piece("Shirt", Vector3.new(0.62, 1.55, 0.12), Vector3.new(0, 2.52, -0.49), Color3.fromRGB(238, 226, 202)),
			piece("JacketZip", Vector3.new(0.045, 1.52, 0.04), Vector3.new(0, 2.50, -0.58), Color3.fromRGB(79, 80, 67)),
			piece("LeftPocket", Vector3.new(0.49, 0.46, 0.10), Vector3.new(-0.54, 2.55, -0.51), outfit),
			piece("RightPocket", Vector3.new(0.49, 0.46, 0.10), Vector3.new(0.54, 2.55, -0.51), outfit),
			piece(
				"LeftPocketFlap",
				Vector3.new(0.51, 0.10, 0.13),
				Vector3.new(-0.54, 2.79, -0.53),
				Color3.fromRGB(78, 105, 88)
			),
			piece(
				"RightPocketFlap",
				Vector3.new(0.51, 0.10, 0.13),
				Vector3.new(0.54, 2.79, -0.53),
				Color3.fromRGB(78, 105, 88)
			),
			piece(
				"LeftStrap",
				Vector3.new(0.15, 1.75, 0.13),
				Vector3.new(-0.75, 2.46, -0.52),
				Color3.fromRGB(105, 74, 55)
			),
			piece(
				"RightStrap",
				Vector3.new(0.15, 1.75, 0.13),
				Vector3.new(0.75, 2.46, -0.52),
				Color3.fromRGB(105, 74, 55)
			),
			piece("Backpack", Vector3.new(1.55, 1.63, 0.60), Vector3.new(0, 2.49, 0.72), Color3.fromRGB(161, 113, 72)),
			piece("PackPocket", Vector3.new(1.25, 0.65, 0.22), Vector3.new(0, 2.15, 1.12), Color3.fromRGB(131, 90, 61)),
			piece("PackFlap", Vector3.new(1.60, 0.24, 0.66), Vector3.new(0, 3.20, 0.74), Color3.fromRGB(197, 151, 98)),
			piece("Belt", Vector3.new(1.82, 0.13, 0.95), Vector3.new(0, 1.68, 0), Color3.fromRGB(91, 67, 53)),
			piece("Buckle", Vector3.new(0.22, 0.19, 0.06), Vector3.new(0, 1.68, -0.50), Color3.fromRGB(226, 191, 121)),
			piece("Smile", Vector3.new(0.20, 0.045, 0.065), Vector3.new(0, 3.89, -0.62), Color3.fromRGB(117, 69, 49)),
			piece(
				"Nose",
				Vector3.new(0.13, 0.15, 0.10),
				Vector3.new(0, 4.02, -0.68),
				skin,
				{ Shape = Enum.PartType.Ball }
			),
			piece(
				"HatBand",
				Vector3.new(1.29, 0.14, 1.14),
				Vector3.new(0, 4.78, 0),
				Color3.fromRGB(105, 74, 55),
				{ Transparency = visibility }
			),
			piece("Body", Vector3.new(1.8, 1.8, 0.9), Vector3.new(0, 2.45, 0), outfit),
			piece("Head", Vector3.new(1.35, 1.4, 1.3), Vector3.new(0, 4.1, 0), skin, { Shape = Enum.PartType.Ball }),
			piece("LeftArm", Vector3.new(0.65, 1.65, 0.75), Vector3.new(-1.23, 2.4, 0), outfit),
			piece("RightArm", Vector3.new(0.65, 1.65, 0.75), Vector3.new(1.23, 2.4, 0), outfit),
			piece("LeftHand", Vector3.new(0.55, 0.55, 0.65), Vector3.new(-1.23, 1.5, 0), skin),
			piece("RightHand", Vector3.new(0.55, 0.55, 0.65), Vector3.new(1.23, 1.5, 0), skin),
			piece("LeftLeg", Vector3.new(0.75, 1.45, 0.85), Vector3.new(-0.48, 0.95, 0), Color3.fromRGB(65, 68, 75)),
			piece("RightLeg", Vector3.new(0.75, 1.45, 0.85), Vector3.new(0.48, 0.95, 0), Color3.fromRGB(65, 68, 75)),
			piece("LeftBoot", Vector3.new(0.85, 0.4, 1.2), Vector3.new(-0.48, 0.35, -0.12), Color3.fromRGB(96, 70, 55)),
			piece("RightBoot", Vector3.new(0.85, 0.4, 1.2), Vector3.new(0.48, 0.35, -0.12), Color3.fromRGB(96, 70, 55)),
			piece(
				"LeftEye",
				Vector3.new(0.12, 0.16, 0.08),
				Vector3.new(-0.26, 4.12, -0.62),
				Color3.fromRGB(43, 38, 39)
			),
			piece(
				"RightEye",
				Vector3.new(0.12, 0.16, 0.08),
				Vector3.new(0.26, 4.12, -0.62),
				Color3.fromRGB(43, 38, 39)
			),
			piece(
				"HatBrim",
				Vector3.new(2.1, 0.13, 1.9),
				Vector3.new(0, 4.7, 0),
				Color3.fromRGB(203, 178, 126),
				{ Transparency = visibility }
			),
			piece(
				"HatCrown",
				Vector3.new(1.25, 0.55, 1.1),
				Vector3.new(0, 4.94, 0),
				Color3.fromRGB(218, 195, 145),
				{ Transparency = visibility }
			),
		})
	end, target)
end
local avatarTemplate
function scenes.prepareAvatar()
	if avatarTemplate then
		return
	end
	-- Roblox supplies the standard R15 joints and default animation choices.
	local description = Instance.new("HumanoidDescription")
	local ok, rig = pcall(function()
		return game:GetService("Players"):CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
	end)
	description:Destroy()
	if not ok then
		warn("Avatar preview: " .. tostring(rig))
		return
	end
	local idle = rig.Animate.idle.Animation1:Clone()
	idle.Name = "PreviewIdle"
	idle.Parent = rig
	for _, node in rig:GetDescendants() do
		if node:IsA("BaseScript") then
			node:Destroy()
		end
		if node:IsA("BasePart") then
			node.Anchored = node.Name == "HumanoidRootPart"
			node.CanCollide = false
			node.CastShadow = false
		end
	end
	rig.Name = "Explorer"
	rig.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	avatarTemplate = rig
end
function scenes.disposeAvatar()
	if avatarTemplate then
		avatarTemplate:Destroy()
		avatarTemplate = nil
	end
end
function scenes.avatar(runtime, target, angle, palette, hat, motionPolicy, active)
	if not avatarTemplate then
		return scenes.staticAvatar(runtime, target, angle, palette, hat, motionPolicy)
	end
	local Host = runtime.constructors
	local colors = {
		sage = Color3.fromRGB(130, 158, 126),
		clay = Color3.fromRGB(195, 121, 94),
		iris = Color3.fromRGB(146, 124, 191),
	}
	local stop, rig = runtime.mount(function()
		local model = runtime.adopt(avatarTemplate:Clone())
		local rotation = runtime.spring(function(use)
			return use(angle)
		end, { period = 0.55, damping = 1 })
		runtime.decorate(model.HumanoidRootPart, {
			CFrame = function(use)
				local degrees = if use(motionPolicy) == "reduced" then use(angle) else use(rotation)
				return CFrame.new(0, 3, 0) * CFrame.Angles(0, math.rad(degrees), 0)
			end,
		})
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				local name = part.Name
				runtime.decorate(part, {
					Color = function(use)
						if name == "Head" or name:find("Hand") then
							return Color3.fromRGB(234, 183, 138)
						end
						if name:find("Leg") or name:find("Foot") then
							return Color3.fromRGB(65, 68, 75)
						end
						return colors[use(palette)]
					end,
				})
			end
		end
		local head = model.Head
		runtime.mountFragment(function()
			local pieces = {}
			for _, spec in
				{
					{ "Brim", Vector3.new(2.1, 0.13, 1.9), 0.58, Color3.fromRGB(203, 178, 126) },
					{ "Crown", Vector3.new(1.25, 0.55, 1.1), 0.88, Color3.fromRGB(218, 195, 145) },
					{ "Band", Vector3.new(1.28, 0.14, 1.14), 0.66, Color3.fromRGB(105, 74, 55) },
				}
			do
				local part = Host.Part({
					Name = "Hat" .. spec[1],
					Size = spec[2],
					Color = spec[4],
					CFrame = head.CFrame * CFrame.new(0, spec[3], 0),
					CanCollide = false,
					Massless = true,
					Transparency = function(use)
						return if use(hat) then 0 else 1
					end,
				})
				table.insert(pieces, part)
				table.insert(
					pieces,
					Host.Weld({
						Part0 = Compose.static(head),
						Part1 = Compose.static(part),
						C0 = CFrame.new(0, spec[3], 0),
					})
				)
			end
			return pieces
		end, model)
		return model
	end, target)
	local animator = rig.Humanoid:FindFirstChildOfClass("Animator")
	local ok, track = pcall(function()
		return animator:LoadAnimation(rig.PreviewIdle)
	end)
	if ok then
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Idle
		track:Play(0.2)
		runtime:watch(function(use)
			local moving = use(motionPolicy) ~= "reduced" and (not active or active(use))
			track:AdjustSpeed(if moving then 1 else 0)
		end)
	else
		warn("Avatar idle animation: " .. tostring(track))
	end
	return function()
		if ok then
			track:Stop(0)
			track:Destroy()
		end
		stop()
	end
end

return scenes
