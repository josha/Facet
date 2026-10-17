--!strict
local Geometry = {}
function Geometry.fit(bounds: Vector2, canvas: Vector2): Vector2
	assert(bounds.X > 0 and bounds.Y > 0 and canvas.X > 0 and canvas.Y > 0)
	local width = math.min(bounds.X, bounds.Y * canvas.X / canvas.Y)
	return canvas * (width / canvas.X)
end
function Geometry.match(surface: CFrame, extent: Vector2, fieldOfView: number, frames: typeof(CFrame)): CFrame
	assert(fieldOfView > 0 and fieldOfView < 180)
	local distance = extent.Y / (2 * math.tan(math.rad(fieldOfView / 2)))
	return surface * frames.new(0, 0, -distance) * frames.Angles(0, math.pi, 0)
end
return Geometry
