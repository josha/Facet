--!strict
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type Compose = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Use = typeof(require("@repo/tools/typecheck/aliases").Use)
type Readable<T> = { peek: (Readable<T>) -> T }
type FrameProps = typeof(require("@repo/tools/typecheck/aliases").FrameProps)

local art = {}

function art.draw(
	Host: Host,
	C: Compose,
	types: typeof(require("@repo/tools/typecheck/aliases").RobloxTypes),
	progress: Readable<number>,
	radar: boolean,
	range: Readable<number>,
	headingUp: Readable<boolean>
): Frame
	local Vector2, UDim2, UDim, Color3 = types.Vector2, types.UDim2, types.UDim, types.Color3
	local course = {
		Vector2.new(0.24, 0.82),
		Vector2.new(0.12, 0.58),
		Vector2.new(0.18, 0.24),
		Vector2.new(0.42, 0.12),
		Vector2.new(0.78, 0.18),
		Vector2.new(0.88, 0.42),
		Vector2.new(0.64, 0.46),
		Vector2.new(0.72, 0.7),
		Vector2.new(0.54, 0.86),
	}
	local function position(progress: number): (Vector2, number)
		local step = (progress % 1) * #course
		local index = math.floor(step) + 1
		local from, to = course[index], course[index % #course + 1]
		local delta = to - from
		return from + delta * (step % 1), math.atan2(delta.X, -delta.Y)
	end

	local props: FrameProps = {
		Name = if radar then "RadarArt" else "CourseArt",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(15, 28, 39),
		BorderSizePixel = 0,
	}
	if radar then
		for _, diameter in { 0.48, 0.96 } do
			props[#props + 1] = Host.Frame "RadarRing" {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(diameter, diameter),
				BackgroundTransparency = 1,
				Host.UICorner { CornerRadius = UDim.new(0.5, 0) },
				Host.UIStroke { Color = Color3.fromRGB(65, 104, 119), Thickness = 1 },
			}
		end
	else
		for index, from in course do
			local to = course[index % #course + 1]
			local delta = to - from
			props[#props + 1] = Host.Frame {
				Name = `Track{index}`,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale((from.X + to.X) / 2, (from.Y + to.Y) / 2),
				Size = UDim2.new(delta.Magnitude, 0, 0, 5),
				Rotation = math.deg(math.atan2(delta.Y, delta.X)),
				BorderSizePixel = 0,
				BackgroundColor3 = Color3.fromRGB(95, 204, 211),
			}
		end
		props[#props + 1] = Host.Frame "Checkpoint" {
			BackgroundColor3 = Color3.fromRGB(255, 201, 89),
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(12, 12),
			Rotation = 45,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(course[4].X, course[4].Y),
			ZIndex = 2,
			Host.UIStroke { Color = Color3.fromRGB(15, 28, 39), Thickness = 2 },
		}
	end
	for index, offset in { 0, 0.06, -0.08, 0.3 } do
		local point = C.formula(function(use: Use): Vector2
			local current = use(progress)
			local target = position(current + offset)
			if not radar then
				return target
			end
			local player, heading = position(current)
			local relative = (target - player) * (100 / use(range))
			if use(headingUp) then
				local cosine, sine = math.cos(heading), math.sin(heading)
				relative =
					Vector2.new(relative.X * cosine + relative.Y * sine, -relative.X * sine + relative.Y * cosine)
			end
			return Vector2.new(0.5, 0.5) + relative * 0.46
		end)
		props[#props + 1] = Host.Frame(`Contact{index}`) {
			BackgroundColor3 = if index == 1 then Color3.fromRGB(15, 28, 39) else Color3.fromRGB(255, 176, 119),
			BorderSizePixel = 0,
			Size = if index == 1 then UDim2.fromOffset(24, 24) else UDim2.fromOffset(10, 10),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 3,
			Host.UICorner { CornerRadius = UDim.new(0.5, 0) },
			Host.UIStroke { Color = Color3.fromRGB(15, 28, 39), Thickness = 2 },
			if index == 1
				then Host.TextLabel "PlayerArrow" {
					Text = "▲",
					TextSize = 14,
					TextColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					ZIndex = 4,
				}
				else nil,
			Position = function(use: Use): UDim2
				local at = use(point)
				return UDim2.fromScale(at.X, at.Y)
			end,
			Visible = function(use: Use): boolean
				return not radar or (use(point) - Vector2.new(0.5, 0.5)).Magnitude <= 0.46
			end,
			Rotation = function(use: Use): number
				if index ~= 1 or (radar and use(headingUp)) then
					return 0
				end
				local _, heading = position(use(progress))
				return math.deg(heading)
			end,
		}
	end
	return Host.Frame(props)
end
return art
