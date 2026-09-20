--!strict

local Compose = require "../core"
local Engine = require "./engine"

local function quaternionFromRotation(rotation: { number }): (number, number, number, number)
	local m11, m12, m13 = rotation[1], rotation[2], rotation[3]
	local m21, m22, m23 = rotation[4], rotation[5], rotation[6]
	local m31, m32, m33 = rotation[7], rotation[8], rotation[9]
	local trace = m11 + m22 + m33

	if trace > 0 then
		local s = math.sqrt(trace + 1) * 2
		return (m32 - m23) / s, (m13 - m31) / s, (m21 - m12) / s, s / 4
	elseif m11 > m22 and m11 > m33 then
		local s = math.sqrt(1 + m11 - m22 - m33) * 2
		return s / 4, (m12 + m21) / s, (m13 + m31) / s, (m32 - m23) / s
	elseif m22 > m33 then
		local s = math.sqrt(1 + m22 - m11 - m33) * 2
		return (m12 + m21) / s, s / 4, (m23 + m32) / s, (m13 - m31) / s
	end
	local s = math.sqrt(1 + m33 - m11 - m22) * 2
	return (m13 + m31) / s, (m23 + m32) / s, s / 4, (m21 - m12) / s
end

local function rotationFromQuaternion(x: number, y: number, z: number, w: number): { number }
	return {
		1 - 2 * (y * y + z * z),
		2 * (x * y - z * w),
		2 * (x * z + y * w),
		2 * (x * y + z * w),
		1 - 2 * (x * x + z * z),
		2 * (y * z - x * w),
		2 * (x * z - y * w),
		2 * (y * z + x * w),
		1 - 2 * (x * x + y * y),
	}
end

local function register(engine: Engine.Engine): { string }
	local datatypes = engine.datatypes
	local registered: { string } = {}

	local function add<T>(name: string, codec: Compose.Codec<T>)
		Compose.registerCodec(name, codec)
		table.insert(registered, name)
	end

	local vector2 = datatypes.Vector2
	if vector2 ~= nil then
		add("Vector2", {
			arity = 2,
			encode = function(value: any, out: { number })
				out[1], out[2] = value.X, value.Y
			end,
			decode = function(c: { number }): any
				return vector2(c[1], c[2])
			end,
		})
	end

	local vector3 = datatypes.Vector3
	if vector3 ~= nil then
		add("Vector3", {
			arity = 3,
			encode = function(value: any, out: { number })
				out[1], out[2], out[3] = value.X, value.Y, value.Z
			end,
			decode = function(c: { number }): any
				return vector3(c[1], c[2], c[3])
			end,
		})
	end

	local color3 = datatypes.Color3
	if color3 ~= nil then
		add("Color3", {
			arity = 3,
			encode = function(value: any, out: { number })
				out[1], out[2], out[3] = value.R, value.G, value.B
			end,
			decode = function(c: { number }): any
				return color3(c[1], c[2], c[3])
			end,
			normalise = function(c: { number })
				c[1] = math.clamp(c[1], 0, 1)
				c[2] = math.clamp(c[2], 0, 1)
				c[3] = math.clamp(c[3], 0, 1)
			end,
		})
	end

	local udim = datatypes.UDim
	if udim ~= nil then
		add("UDim", {
			arity = 2,
			encode = function(value: any, out: { number })
				out[1], out[2] = value.Scale, value.Offset
			end,
			decode = function(c: { number }): any
				return udim(c[1], math.round(c[2]))
			end,
		})
	end

	local udim2 = datatypes.UDim2
	if udim2 ~= nil then
		add("UDim2", {
			arity = 4,
			encode = function(value: any, out: { number })
				out[1], out[2] = value.X.Scale, value.X.Offset
				out[3], out[4] = value.Y.Scale, value.Y.Offset
			end,
			decode = function(c: { number }): any
				return udim2(c[1], math.round(c[2]), c[3], math.round(c[4]))
			end,
		})
	end

	local cframe = datatypes.CFrame
	local readCFrame = engine.readCFrame
	if cframe ~= nil and readCFrame ~= nil and vector3 ~= nil then
		add("CFrame", {
			arity = 7,
			encode = function(value: any, out: { number })
				local x, y, z, rotation = readCFrame(value)
				out[1], out[2], out[3] = x, y, z
				local qx, qy, qz, qw = quaternionFromRotation(rotation)

				if out[4] ~= nil and (out[4] * qx + out[5] * qy + out[6] * qz + out[7] * qw) < 0 then
					qx, qy, qz, qw = -qx, -qy, -qz, -qw
				end
				out[4], out[5], out[6], out[7] = qx, qy, qz, qw
			end,
			normalise = function(c: { number })
				local length = math.sqrt(c[4] * c[4] + c[5] * c[5] + c[6] * c[6] + c[7] * c[7])
				if length < 1e-9 then
					c[4], c[5], c[6], c[7] = 0, 0, 0, 1
					return
				end
				c[4], c[5], c[6], c[7] = c[4] / length, c[5] / length, c[6] / length, c[7] / length
			end,
			decode = function(c: { number }): any
				return cframe(vector3(c[1], c[2], c[3]), rotationFromQuaternion(c[4], c[5], c[6], c[7]))
			end,
		})
	end

	return registered
end

return {
	register = register,
	quaternionFromRotation = quaternionFromRotation,
	rotationFromQuaternion = rotationFromQuaternion,
}
