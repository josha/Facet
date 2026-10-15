--!strict

local Track = { segments = 80, checkpoints = 16, laps = 3, width = 26, seed = 20261015 }
local knots: { Vector3 } = {}
for index = 0, 11 do
	local angle = index / 12 * math.pi * 2
	knots[index + 1] = Vector3.new(130 * math.sin(angle), 2, -190 + 85 * math.cos(angle))
end

function Track.point(t: number): Vector3
	local scaled = t % 1 * #knots
	local index = math.floor(scaled)
	local u = scaled - index
	local a, b, c, d =
		knots[(index - 1) % #knots + 1],
		knots[index + 1],
		knots[(index + 1) % #knots + 1],
		knots[(index + 2) % #knots + 1]
	return (2 * b + (c - a) * u + (2 * a - 5 * b + 4 * c - d) * u ^ 2 + (-a + 3 * b - 3 * c + d) * u ^ 3) * 0.5
end

function Track.frame(t: number, lane: number?): CFrame
	local point = Track.point(t)
	local frame = CFrame.lookAt(point, Track.point(t + 0.0001))
	return frame * CFrame.new(lane or 0, 0, 0)
end

function Track.progress(point: Vector3): number
	return (math.atan2(point.X / 130, (point.Z + 190) / 85) / (math.pi * 2)) % 1
end

return Track
