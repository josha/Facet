--!strict
local Compose = require(game:GetService("ReplicatedStorage").Facet).Compose
local scenes = {}

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
		local random = Random.new(item.index * 7919)
		local function part(name, size, position, color, shape, yaw, material)
			local instance = Host.Part({
				Name = name,
				Anchored = true,
				CanCollide = false,
				Size = size,
				CFrame = if type(position) == "function"
					then position
					elseif typeof(position) == "CFrame" then position
					else CFrame.new(position) * CFrame.Angles(0, yaw or 0, 0),
				Color = color,
				Material = material or Enum.Material.SmoothPlastic,
				Shape = shape or Enum.PartType.Block,
			})
			table.insert(nodes, instance)
			return instance
		end
		local function wedge(name, size, cframe, color)
			table.insert(
				nodes,
				Host.WedgePart({
					Name = name,
					Anchored = true,
					CanCollide = false,
					Size = size,
					CFrame = cframe,
					Color = color,
					Material = Enum.Material.SmoothPlastic,
				})
			)
		end
		local function pillar(name, radius, height, position, color, material)
			return part(
				name,
				Vector3.new(height, radius * 2, radius * 2),
				CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
				color,
				Enum.PartType.Cylinder,
				nil,
				material
			)
		end
		local function jitter(amount)
			return (random:NextNumber() - 0.5) * 2 * amount
		end
		local round = random:NextNumber() < 0.5
		local ground = ({
			Color3.fromRGB(49, 64, 77),
			Color3.fromRGB(62, 78, 58),
			Color3.fromRGB(78, 66, 58),
			Color3.fromRGB(44, 52, 70),
		})[variant % 4 + 1]
		if variant == 3 then
			part(
				"Water",
				Vector3.new(0.3, 13, 13),
				CFrame.new(0, -0.3, 0) * CFrame.Angles(0, 0, math.pi / 2),
				Color3.fromRGB(43, 126, 176),
				Enum.PartType.Cylinder
			)
		elseif round then
			part(
				"Island",
				Vector3.new(0.8, 11.5, 11.5),
				CFrame.new(0, -0.6, 0) * CFrame.Angles(0, 0, math.pi / 2),
				ground,
				Enum.PartType.Cylinder
			)
		else
			part("Island", Vector3.new(11, 0.8, 9), Vector3.new(0, -0.6, 0), ground)
		end
		if variant == 0 then
			local columns = 3 + random:NextInteger(0, 1)
			for i = 1, columns * 3 do
				local x = ((i - 1) % columns - (columns - 1) / 2) * 2.6
				local z = (math.floor((i - 1) / columns) - 1) * 2.6
				local height = 1.5 + random:NextNumber() * 4.5
				local tone = accent:Lerp(Color3.fromRGB(208, 219, 226), random:NextNumber() * 0.6)
				part("Tower", Vector3.new(1.8, height, 1.8), Vector3.new(x, height / 2, z), tone)
				for level = 1, math.floor(height / 1.2) do
					part(
						"Lights",
						Vector3.new(1.84, 0.12, 1.84),
						Vector3.new(x, level * 1.1, z),
						Color3.fromRGB(255, 214, 140),
						nil,
						nil,
						Enum.Material.Neon
					)
				end
				part("Roof", Vector3.new(2, 0.25, 2), Vector3.new(x, height + 0.12, z), Color3.fromRGB(39, 48, 67))
			end
			part("Glider", Vector3.new(1.6, 0.1, 0.6), function(use)
				local angle = phase(use)
				return CFrame.new(math.cos(angle) * 4.5, 6.5 + math.sin(angle * 2) * 0.5, math.sin(angle) * 3.5)
					* CFrame.Angles(0, -angle, math.sin(angle) * 0.3)
			end, accent:Lerp(Color3.new(1, 1, 1), 0.4))
		elseif variant == 1 then
			local rx, rz = 3.6 + jitter(0.5), 2.8 + jitter(0.4)
			local figure = random:NextNumber() < 0.4
			local function track(angle)
				if figure then
					return Vector3.new(math.sin(angle) * rx, 0, math.sin(angle * 2) * rz * 0.8)
				end
				return Vector3.new(math.cos(angle) * rx, 0, math.sin(angle) * rz)
			end
			for i = 1, 24 do
				local angle = i * math.pi / 12
				local here, ahead = track(angle), track(angle + 0.05)
				part(
					"Track",
					Vector3.new(1.8, 0.16, 1.3),
					CFrame.lookAt(here, ahead),
					if i % 2 == 0 then Color3.fromRGB(205, 215, 226) else Color3.fromRGB(180, 190, 204)
				)
			end
			local start = track(0)
			part(
				"StartLine",
				Vector3.new(1.9, 0.18, 0.2),
				CFrame.lookAt(start, track(0.05)) * CFrame.Angles(0, math.pi / 2, 0),
				Color3.new(1, 1, 1),
				nil,
				nil,
				Enum.Material.Neon
			)
			for car = 0, 2 do
				local tint = ({ accent, Color3.fromRGB(235, 90, 80), Color3.fromRGB(250, 205, 70) })[car + 1]
				part("Racer", Vector3.new(0.7, 0.45, 1.3), function(use)
					local angle = phase(use) * (1 + car * 0.08) + car * 0.6
					local position = track(angle) + Vector3.new(0, 0.4, 0)
					return CFrame.lookAt(position, track(angle + 0.05) + Vector3.new(0, 0.4, 0))
				end, tint)
			end
			for i = 1, 4 do
				pillar("Flag", 0.08, 2.2, Vector3.new((i - 2.5) * 2.2, 0, -rz - 1.4), Color3.fromRGB(220, 220, 230))
			end
		elseif variant == 2 then
			local floors = 5 + random:NextInteger(0, 3)
			for level = 1, floors do
				local size = 3.2 - level * 0.18
				local tone = accent:Lerp(Color3.fromRGB(240, 200, 120), level / floors)
				part("Block", Vector3.new(size, 0.8, size), function(use)
					local lift = if level == floors then (math.sin(phase(use) * 2) + 1) * 0.6 else 0
					return CFrame.new(-1.2, level * 0.82 - 0.2 + lift, 0) * CFrame.Angles(0, level * 0.18, 0)
				end, tone)
			end
			pillar("Mast", 0.18, 7, Vector3.new(3, 0, 1.5), Color3.fromRGB(250, 190, 60))
			part("Jib", Vector3.new(6, 0.22, 0.22), function(use)
				local angle = phase(use) * 0.5
				return CFrame.new(3, 7, 1.5) * CFrame.Angles(0, angle, 0) * CFrame.new(-2, 0, 0)
			end, Color3.fromRGB(250, 190, 60))
			for i = 1, 6 do
				part(
					"Brick",
					Vector3.new(0.9, 0.45, 0.45),
					Vector3.new(2 + jitter(1.5), 0.2, -2.5 + jitter(1)),
					({ Color3.fromRGB(220, 90, 70), Color3.fromRGB(80, 160, 220), Color3.fromRGB(120, 200, 110) })[i % 3 + 1],
					nil,
					random:NextNumber() * math.pi
				)
			end
		elseif variant == 3 then
			for i = 1, 3 do
				local center = Vector3.new(jitter(3.5), 0, jitter(3))
				local radius = 1.2 + random:NextNumber()
				part(
					"Isle",
					Vector3.new(0.5, radius * 2, radius * 2),
					CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2),
					Color3.fromRGB(214, 196, 150),
					Enum.PartType.Cylinder
				)
				for r = 1, 2 do
					part(
						"Ruin",
						Vector3.new(0.4, 0.8 + random:NextNumber() * 1.4, 0.4),
						center + Vector3.new(jitter(radius * 0.6), 0.6, jitter(radius * 0.6)),
						Color3.fromRGB(154, 192, 183)
					)
				end
			end
			pillar("Lighthouse", 0.5, 4.5, Vector3.new(-3.5, 0, 3), Color3.fromRGB(235, 235, 240))
			part("Lamp", Vector3.new(0.3, 0.3, 3), function(use)
				return CFrame.new(-3.5, 4.8, 3) * CFrame.Angles(0, phase(use) * 2, 0) * CFrame.new(0, 0, 1.4)
			end, Color3.fromRGB(255, 236, 170), nil, nil, Enum.Material.Neon)
			part("Boat", Vector3.new(0.6, 0.35, 1.4), function(use)
				local angle = phase(use)
				local position =
					Vector3.new(math.cos(angle) * 4.5, 0.05 + math.sin(angle * 5) * 0.06, math.sin(angle) * 4.5)
				return CFrame.lookAt(position, position + Vector3.new(-math.sin(angle), 0, math.cos(angle)))
			end, accent)
		elseif variant == 4 then
			local houses = 5 + random:NextInteger(0, 2)
			for i = 1, houses do
				local angle = i / houses * math.pi * 2 + jitter(0.15)
				local origin = CFrame.new(math.cos(angle) * 3.8, 0, math.sin(angle) * 3.2)
					* CFrame.Angles(0, -angle + math.pi / 2, 0)
				local wall = ({
					Color3.fromRGB(236, 222, 196),
					Color3.fromRGB(214, 170, 140),
					Color3.fromRGB(190, 206, 222),
				})[random:NextInteger(1, 3)]
				local roof = accent:Lerp(Color3.fromRGB(150, 60, 50), random:NextNumber() * 0.7)
				part("House", Vector3.new(1.8, 1.3, 1.6), origin * CFrame.new(0, 0.65, 0), wall)
				wedge("Roof", Vector3.new(1.9, 0.8, 0.85), origin * CFrame.new(0, 1.7, 0.42), roof)
				wedge(
					"Roof",
					Vector3.new(1.9, 0.8, 0.85),
					origin * CFrame.new(0, 1.7, -0.42) * CFrame.Angles(0, math.pi, 0),
					roof
				)
			end
			pillar("Fountain", 0.9, 0.4, Vector3.new(0, 0, 0), Color3.fromRGB(190, 196, 206))
			pillar("Spray", 0.2, 0.9, Vector3.new(0, 0.4, 0), Color3.fromRGB(140, 210, 240), Enum.Material.Neon)
			for walker = 1, 4 do
				part(
					"Villager",
					Vector3.new(0.35, 0.7, 0.35),
					function(use)
						local angle = phase(use) * (if walker % 2 == 0 then 1 else -1) + walker * 1.6
						return CFrame.new(math.cos(angle) * 1.8, 0.35, math.sin(angle) * 1.6)
					end,
					({
						accent,
						Color3.fromRGB(240, 170, 90),
						Color3.fromRGB(110, 170, 240),
						Color3.fromRGB(230, 110, 140),
					})[walker]
				)
			end
		else
			for i = 1, 8 do
				local position = Vector3.new(jitter(4.8), 0, jitter(3.8))
				if position.Magnitude > 2.2 then
					pillar("Trunk", 0.18, 1.2, position, Color3.fromRGB(110, 80, 60))
					for tier = 0, 2 do
						part(
							"Needles",
							Vector3.new(1.6 - tier * 0.4, 0.7, 1.6 - tier * 0.4),
							position + Vector3.new(0, 1.3 + tier * 0.55, 0),
							Color3.fromRGB(54, 110, 78):Lerp(accent, 0.2),
							nil,
							math.pi / 4
						)
					end
				end
			end
			for log = 0, 2 do
				part(
					"Log",
					Vector3.new(1.4, 0.25, 0.25),
					CFrame.new(0, 0.12, 0) * CFrame.Angles(0, log * math.pi / 3, 0),
					Color3.fromRGB(96, 66, 46)
				)
			end
			part("Fire", Vector3.new(0.6, 0.9, 0.6), function(use)
				local flicker = 0.85 + math.abs(math.sin(phase(use) * 9)) * 0.3
				return CFrame.new(0, 0.5 * flicker, 0) * CFrame.Angles(0, phase(use) * 4, 0)
			end, Color3.fromRGB(255, 150, 60), nil, nil, Enum.Material.Neon)
			for tent = 0, 1 do
				local origin = CFrame.new(if tent == 0 then -2.2 else 2.4, 0, 1.6)
					* CFrame.Angles(0, tent * 0.8 - 0.4, 0)
				wedge("Tent", Vector3.new(1.8, 1.2, 1), origin * CFrame.new(0, 0.6, 0.5), accent)
				wedge(
					"Tent",
					Vector3.new(1.8, 1.2, 1),
					origin * CFrame.new(0, 0.6, -0.5) * CFrame.Angles(0, math.pi, 0),
					accent:Lerp(Color3.new(0, 0, 0), 0.2)
				)
			end
			part("Drone", Vector3.new(0.6, 0.2, 0.6), function(use)
				local angle = phase(use)
				return CFrame.new(math.cos(angle) * 3, 4 + math.sin(angle * 3) * 0.3, math.sin(angle) * 2.5)
					* CFrame.Angles(0, angle * 3, 0)
			end, Color3.fromRGB(220, 225, 235))
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

function scenes.staticAvatar(
	runtime: any,
	target: Instance,
	angle: any,
	palette: any,
	hat: any,
	motionPolicy: any,
	hatTint: any
)
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
	local function crown(use)
		local tint = use(hatTint)
		return Color3.fromRGB(tint[1], tint[2], tint[3])
	end
	local function brim(use)
		local tint = use(hatTint)
		return Color3.fromRGB(tint[1] * 0.85, tint[2] * 0.85, tint[3] * 0.85)
	end
	return runtime.mount(function()
		animatedAngle = runtime.spring(function(use)
			return use(angle)
		end, { period = 0.55, damping = 0.9 })
		return Host.Model "Explorer" {

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
			piece("HatBrim", Vector3.new(2.1, 0.13, 1.9), Vector3.new(0, 4.7, 0), brim, { Transparency = visibility }),
			piece(
				"HatCrown",
				Vector3.new(1.25, 0.55, 1.1),
				Vector3.new(0, 4.94, 0),
				crown,
				{ Transparency = visibility }
			),
		}
	end, target)
end
local avatarTemplate
local avatarIsPlayer = false
function scenes.prepareAvatar()
	if avatarTemplate then
		return
	end

	local players = game:GetService("Players")
	local player = players.LocalPlayer
	local fetched, playerDescription = pcall(function()
		return if player and player.UserId > 0
			then players:GetHumanoidDescriptionFromUserIdAsync(player.UserId)
			else nil
	end)
	local description = if fetched and playerDescription then playerDescription else Instance.new("HumanoidDescription")
	avatarIsPlayer = fetched and playerDescription ~= nil
	local ok, rig = pcall(function()
		return players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
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
function scenes.avatar(runtime, target, angle, palette, hat, motionPolicy, active, hatTint)
	if not avatarTemplate then
		return scenes.staticAvatar(runtime, target, angle, palette, hat, motionPolicy, hatTint)
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
		for _, accessory in model:GetChildren() do
			local handle = accessory:IsA("Accessory") and accessory:FindFirstChild("Handle")
			if handle and accessory.AccessoryType == Enum.AccessoryType.Hat then
				local resting = handle.Transparency
				runtime.decorate(handle, {
					Transparency = function(use)
						return if use(hat) then 1 else resting
					end,
				})
			end
		end
		for _, part in model:GetChildren() do
			if not avatarIsPlayer and part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
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
		local anchor = head:FindFirstChild("HatAttachment")
		local crownBase = if anchor and anchor:IsA("Attachment") then anchor.CFrame else CFrame.new(0, 0.6, 0)
		local fit = math.clamp(head.Size.X / 1.2, 0.55, 1.3)
		runtime.mountFragment(function()
			local pieces = {}
			for _, spec in
				{
					{ "Brim", Vector3.new(2.1, 0.13, 1.9), -0.16, "shade" },
					{ "Crown", Vector3.new(1.25, 0.55, 1.1), 0.12, "tint" },
					{ "Band", Vector3.new(1.28, 0.14, 1.14), -0.08, Color3.fromRGB(105, 74, 55) },
				}
			do
				local fixed = spec[4]
				local part = Host.Part({
					Name = "Hat" .. spec[1],
					Size = spec[2] * fit,
					Color = if fixed == "tint" or fixed == "shade"
						then function(use)
							local tint = use(hatTint)
							local k = if fixed == "shade" then 0.85 else 1
							return Color3.fromRGB(tint[1] * k, tint[2] * k, tint[3] * k)
						end
						else fixed,
					CFrame = head.CFrame * crownBase * CFrame.new(0, spec[3] * fit, 0),
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
						C0 = crownBase * CFrame.new(0, spec[3] * fit, 0),
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
