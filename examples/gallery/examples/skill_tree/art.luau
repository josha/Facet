--!strict
type Context = typeof(require("@repo/examples/types").Context)
type Point = typeof(require("@repo/tools/typecheck/aliases").PathPoint)
type ReadOnlyValue<T> = { peek: (ReadOnlyValue<T>) -> T }
type Use = <T>(ReadOnlyValue<T>) -> T
type Paint = Color3 | ReadOnlyValue<Color3> | (Use) -> Color3
local drawings: { [string]: { { number } } } = {
	bolt = {
		{ 0.62, 0.05 },
		{ 0.19, 0.55 },
		{ 0.46, 0.55 },
		{ 0.34, 0.95 },
		{ 0.81, 0.4 },
		{ 0.55, 0.4 },
		{ 0.62, 0.05 },
	},
	shield = {
		{ 0.5, 0.05 },
		{ 0.86, 0.21 },
		{ 0.81, 0.62 },
		{ 0.67, 0.81 },
		{ 0.5, 0.95 },
		{ 0.33, 0.81 },
		{ 0.19, 0.62 },
		{ 0.14, 0.21 },
		{ 0.5, 0.05 },
	},
	wing = {
		{ 0.12, 0.85 },
		{ 0.26, 0.38 },
		{ 0.9, 0.09 },
		{ 0.72, 0.45 },
		{ 0.47, 0.55 },
		{ 0.68, 0.56 },
		{ 0.52, 0.76 },
		{
			0.12,
			0.85,
		},
	},
	heart = {
		{ 0.5, 0.91 },
		{ 0.13, 0.48 },
		{ 0.1, 0.28 },
		{ 0.2, 0.12 },
		{ 0.36, 0.12 },
		{ 0.5, 0.29 },
		{ 0.64, 0.12 },
		{ 0.8, 0.12 },
		{ 0.9, 0.28 },
		{ 0.87, 0.48 },
		{ 0.5, 0.91 },
	},
	diamond = { { 0.5, 0.05 }, { 0.9, 0.5 }, { 0.5, 0.95 }, { 0.1, 0.5 }, { 0.5, 0.05 }, { 0.5, 0.95 } },
	star = {
		{ 0.5, 0.03 },
		{ 0.63, 0.34 },
		{ 0.97, 0.38 },
		{ 0.71, 0.61 },
		{ 0.79, 0.95 },
		{ 0.5, 0.77 },
		{ 0.21, 0.95 },
		{ 0.29, 0.61 },
		{ 0.03, 0.38 },
		{ 0.37, 0.34 },
		{ 0.5, 0.03 },
	},
	lock = {
		{ 0.24, 0.43 },
		{ 0.24, 0.28 },
		{ 0.33, 0.12 },
		{ 0.67, 0.12 },
		{ 0.76, 0.28 },
		{ 0.76, 0.43 },
		{ 0.85, 0.43 },
		{ 0.85, 0.9 },
		{ 0.15, 0.9 },
		{ 0.15, 0.43 },
		{ 0.76, 0.43 },
	},
	check = { { 0.15, 0.5 }, { 0.4, 0.75 }, { 0.85, 0.22 } },
}
local art = {}
function art.hex(ctx: Context, name: string, size: number, paint: Paint, z: number): Frame
	local H, D2, V2 = ctx.Host, ctx.types.UDim2, ctx.types.Vector2
	local pieces: { Instance } = {}
	for _, angle in { 0, 60, 120 } do
		table.insert(
			pieces,
			H.Frame {
				Size = D2.fromOffset(size / 2, size * math.sqrt(3) / 2),
				Position = D2.fromScale(0.5, 0.5),
				AnchorPoint = V2.new(0.5, 0.5),
				Rotation = angle,
				BackgroundColor3 = paint,
				BorderSizePixel = 0,
				ZIndex = z,
			}
		)
	end
	return H.Frame(name) {
		Size = D2.fromOffset(size, size * math.sqrt(3) / 2),
		Position = D2.fromScale(0.5, 0.5),
		AnchorPoint = V2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = z,
		table.unpack(pieces),
	}
end
function art.outline(ctx: Context, tint: Paint): Frame
	local points: { Point } = {}
	for _, p in { { 0, 0.5 }, { 0.25, 0 }, { 0.75, 0 }, { 1, 0.5 }, { 0.75, 1 }, { 0.25, 1 } } do
		table.insert(points, { x = p[1], y = p[2], inX = 0, inY = 0, outX = 0, outY = 0 })
	end
	return ctx.UI.Path "HexFocusOutline" {
		points = points,
		closed = true,
		tint = tint,
		thickness = 3,
		width = 190,
		height = 190 * math.sqrt(3) / 2,
		AnchorPoint = ctx.types.Vector2.new(0.5, 0.5),
		Position = ctx.types.UDim2.fromScale(0.5, 0.5),
		ZIndex = 12,
	}
end
function art.icon(ctx: Context, name: string, tint: Paint, size: number): Frame
	local points: { Point } = {}
	for _, p in drawings[name] or drawings.star do
		table.insert(points, { x = p[1], y = p[2], inX = 0, inY = 0, outX = 0, outY = 0 })
	end
	return ctx.UI.Path {
		points = points,
		tint = tint,
		thickness = 3,
		width = size,
		height = size,
		AnchorPoint = ctx.types.Vector2.new(0.5, 0.5),
		Position = ctx.types.UDim2.fromScale(0.5, 0.5),
		ZIndex = 8,
	}
end
return art
