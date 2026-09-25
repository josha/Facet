--!strict

local path_shapes = {}

export type PathPoint = { x: number, y: number, inX: number, inY: number, outX: number, outY: number }

local MAX_CONTROL_POINTS = 100
path_shapes.MAX_CONTROL_POINTS = MAX_CONTROL_POINTS

function path_shapes.arc(
	startDeg: number,
	sweepDeg: number,
	opts: { segments: number?, radius: number? }?
): { PathPoint }
	local segments = (opts and opts.segments) or math.max(2, math.ceil(math.abs(sweepDeg) / 45))
	assert(segments + 1 <= MAX_CONTROL_POINTS, "path_shapes.arc: segment count exceeds the engine's 100-point limit")
	local radius = 0.5 * ((opts and opts.radius) or 1)
	local cx, cy = 0.5, 0.5
	sweepDeg = math.clamp(sweepDeg, -360, 360)
	local thetaSeg = math.rad(sweepDeg / segments)

	local handleLen = (4 / 3) * math.tan(math.abs(thetaSeg) / 4) * radius
	local dirSign = if sweepDeg >= 0 then 1 else -1
	local points: { PathPoint } = {}
	for i = 0, segments do
		local aDeg = startDeg + sweepDeg * (i / segments)
		local a = math.rad(aDeg)

		local px = cx + radius * math.sin(a)
		local py = cy - radius * math.cos(a)

		local dx = math.cos(a) * dirSign
		local dy = math.sin(a) * dirSign
		table.insert(points, {
			x = px,
			y = py,
			inX = -dx * handleLen,
			inY = -dy * handleLen,
			outX = dx * handleLen,
			outY = dy * handleLen,
		})
	end
	return points
end

function path_shapes.ring(opts: { radius: number? }?): { PathPoint }
	return path_shapes.arc(0, 360, { segments = 8, radius = opts and opts.radius })
end

function path_shapes.needle(angleDeg: number, opts: { innerRadius: number?, radius: number? }?): { PathPoint }
	local rOuter = 0.5 * ((opts and opts.radius) or 1)
	local rInner = 0.5 * ((opts and opts.innerRadius) or 0)
	local a = math.rad(angleDeg)
	local cx, cy = 0.5, 0.5
	local function pt(r: number): PathPoint
		return { x = cx + r * math.sin(a), y = cy - r * math.cos(a), inX = 0, inY = 0, outX = 0, outY = 0 }
	end
	return { pt(rInner), pt(rOuter) }
end

return table.freeze(path_shapes)
