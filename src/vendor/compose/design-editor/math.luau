--!strict

export type Point = { X: number, Y: number }
export type Vector = { X: number, Y: number, Z: number }

local function add(a: Point, b: Point): Point
	return { X = a.X + b.X, Y = a.Y + b.Y }
end

local function sub(a: Point, b: Point): Point
	return { X = a.X - b.X, Y = a.Y - b.Y }
end

local function scale(a: Point, factor: number): Point
	return { X = a.X * factor, Y = a.Y * factor }
end

local function length(a: Point): number
	return math.sqrt(a.X * a.X + a.Y * a.Y)
end

local function vadd(a: Vector, b: Vector): Vector
	return { X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }
end

local function vsub(a: Vector, b: Vector): Vector
	return { X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }
end

local function vscale(a: Vector, factor: number): Vector
	return { X = a.X * factor, Y = a.Y * factor, Z = a.Z * factor }
end

local function dot(a: Vector, b: Vector): number
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end

local function magnitude(a: Vector): number
	return math.sqrt(dot(a, a))
end

local function unit(a: Vector): Vector
	local size = magnitude(a)
	return vscale(a, if size > 0 then 1 / size else 0)
end

local function cross(a: Vector, b: Vector): Vector
	return { X = a.Y * b.Z - a.Z * b.Y, Y = a.Z * b.X - a.X * b.Z, Z = a.X * b.Y - a.Y * b.X }
end

local function frame(position: Vector): { number }
	return { position.X, position.Y, position.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1 }
end

local function transform(a: { number }, v: Vector): Vector
	return {
		X = a[4] * v.X + a[5] * v.Y + a[6] * v.Z,
		Y = a[7] * v.X + a[8] * v.Y + a[9] * v.Z,
		Z = a[10] * v.X + a[11] * v.Y + a[12] * v.Z,
	}
end

local function multiply(a: { number }, b: { number }): { number }
	local offset = transform(a, { X = b[1], Y = b[2], Z = b[3] })
	local result = frame { X = a[1] + offset.X, Y = a[2] + offset.Y, Z = a[3] + offset.Z }
	for row = 0, 2 do
		for col = 0, 2 do
			local sum = 0
			for index = 0, 2 do
				sum += a[4 + row * 3 + index] * b[4 + index * 3 + col]
			end
			result[4 + row * 3 + col] = sum
		end
	end
	return result
end

local function rotation(pitch: number, yaw: number, roll: number): { number }
	local cx, sx, cy, sy, cz, sz =
		math.cos(pitch), math.sin(pitch), math.cos(yaw), math.sin(yaw), math.cos(roll), math.sin(roll)
	return {
		0,
		0,
		0,
		cy * cz + sy * sx * sz,
		-cy * sz + sy * sx * cz,
		sy * cx,
		cx * sz,
		cx * cz,
		-sx,
		-sy * cz + cy * sx * sz,
		sy * sz + cy * sx * cz,
		cy * cx,
	}
end

local function lookAt(position: Vector, target: Vector): { number }
	local back = unit(vsub(position, target))
	local right = unit(cross({ X = 0, Y = 1, Z = 0 }, back))
	if magnitude(right) < 1e-6 then
		right = unit(cross({ X = 0, Y = 0, Z = 1 }, back))
	end
	local up = cross(back, right)
	return { position.X, position.Y, position.Z, right.X, up.X, back.X, right.Y, up.Y, back.Y, right.Z, up.Z, back.Z }
end

return {
	add = add,
	sub = sub,
	scale = scale,
	length = length,
	vadd = vadd,
	vsub = vsub,
	vscale = vscale,
	dot = dot,
	magnitude = magnitude,
	unit = unit,
	cross = cross,
	frame = frame,
	transform = transform,
	multiply = multiply,
	rotation = rotation,
	lookAt = lookAt,
}
