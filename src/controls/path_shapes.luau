--!strict
-- Pure Path2D shape math (native-substrate NS-A7; spike m5-path2d.json).
-- Produces NORMALIZED control points (unit box, center 0.5/0.5, radius 0.5)
-- for the UI.Path primitive; the Roblox adapter scales them into the solved
-- rect and feeds Path2D:SetControlPoints. Everything here is deterministic
-- and headlessly tested (tests/path.spec.luau) — the engine only strokes.
--
-- Control point shape: { x, y, inX, inY, outX, outY } — tangents are OFFSETS
-- RELATIVE to the point (engine truth, spike 2026-07-23): `in` is the
-- incoming handle (points BACK along the path), `out` the outgoing handle.
-- Bezier circular-arc handle length is exact: (4/3) * tan(theta/4) * r for a
-- segment sweeping theta — NOT the full-circle kappa shortcut, so partial
-- arcs (progress rings) keep stroke quality at any sweep.
--
-- Engine limits encoded here: Path2D supports at most 100 control points
-- (exact error measured in the spike) — segment counts assert against it.

local path_shapes = {}

export type PathPoint = { x: number, y: number, inX: number, inY: number, outX: number, outY: number }

local MAX_CONTROL_POINTS = 100
path_shapes.MAX_CONTROL_POINTS = MAX_CONTROL_POINTS

-- arc around the unit-box center: startDeg is measured clockwise from
-- 12 o'clock (screen convention: y grows DOWN, so 0deg = up, 90deg = right),
-- sweepDeg may be 0..360. radius is a fraction of the half-box (default 1 =
-- touch the box edge; callers inset for stroke thickness).
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
	-- exact circular-arc bezier handle length for one segment
	local handleLen = (4 / 3) * math.tan(math.abs(thetaSeg) / 4) * radius
	local dirSign = if sweepDeg >= 0 then 1 else -1
	local points: { PathPoint } = {}
	for i = 0, segments do
		local aDeg = startDeg + sweepDeg * (i / segments)
		local a = math.rad(aDeg)
		-- screen mapping: 0deg = up. x = sin, y = -cos (y grows down).
		local px = cx + radius * math.sin(a)
		local py = cy - radius * math.cos(a)
		-- path direction (clockwise for positive sweep): d/da of (sin, -cos)
		-- = (cos, sin), normalized; flips with sweep sign
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

-- full ring (closed circle) — 4 exact quarter segments, 5 points
function path_shapes.ring(opts: { radius: number? }?): { PathPoint }
	return path_shapes.arc(0, 360, { segments = 8, radius = opts and opts.radius })
end

-- straight needle from the center toward angleDeg (gauge/drama indicator):
-- two points, zero-length tangents (straight segment)
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

return path_shapes
