--!strict

type Vec3 = { X: number, Y: number, Z: number }
type CF = { _cframe: boolean }
type C3 = { R: number, G: number, B: number }

local Vector3: any
local CFrame: any

local v3Mt: any = {}
v3Mt.__add = function(a: any, b: any): any
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
v3Mt.__sub = function(a: any, b: any): any
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
v3Mt.__mul = function(a: any, b: any): any
	if type(b) == "number" then
		return Vector3.new(a.X * b, a.Y * b, a.Z * b)
	end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
v3Mt.__div = function(a: any, b: any): any
	if type(b) == "number" then
		return Vector3.new(a.X / b, a.Y / b, a.Z / b)
	end
	return Vector3.new(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
v3Mt.__unm = function(a: any): any
	return Vector3.new(-a.X, -a.Y, -a.Z)
end
v3Mt.__eq = function(a: any, b: any): boolean
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
v3Mt.__tostring = function(a: any): string
	return ("Vector3(%g, %g, %g)"):format(a.X, a.Y, a.Z)
end
v3Mt.__index = function(v: any, key: any): any
	if key == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif key == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return Vector3.new(v.X / m, v.Y / m, v.Z / m)
	end
	return rawget(v3Mt, key)
end

function v3Mt.Dot(a: any, b: any): number
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end

function v3Mt.Cross(a: any, b: any): any
	return Vector3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end

Vector3 = {
	new = function(x: number?, y: number?, z: number?): Vec3
		local v: any = { X = x or 0, Y = y or 0, Z = z or 0 }
		setmetatable(v, v3Mt)
		return v
	end,
}

local cfMt: any = {}

local function makeCFrame(x: number, y: number, z: number, r: { number }): CF
	local cf: any = { _cframe = true, X = x, Y = y, Z = z, r = r }
	setmetatable(cf, cfMt)
	return cf
end

local IDENTITY_R = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

cfMt.__index = function(cf: any, key: any): any
	local r = rawget(cf, "r") :: { number }
	if key == "Position" then
		return Vector3.new(cf.X, cf.Y, cf.Z)
	elseif key == "RightVector" or key == "XVector" then
		return Vector3.new(r[1], r[4], r[7])
	elseif key == "UpVector" or key == "YVector" then
		return Vector3.new(r[2], r[5], r[8])
	elseif key == "ZVector" then
		return Vector3.new(r[3], r[6], r[9])
	elseif key == "LookVector" then
		return Vector3.new(-r[3], -r[6], -r[9])
	end
	return rawget(cfMt, key)
end

cfMt.__mul = function(a: any, b: any): any
	local ar = rawget(a, "r") :: { number }
	if b ~= nil and rawget(b, "_cframe") ~= nil then
		local br = rawget(b, "r") :: { number }
		local r = table.create(9, 0)
		for row = 0, 2 do
			for col = 1, 3 do
				r[row * 3 + col] = ar[row * 3 + 1] * br[col]
					+ ar[row * 3 + 2] * br[col + 3]
					+ ar[row * 3 + 3] * br[col + 6]
			end
		end
		return makeCFrame(
			a.X + ar[1] * b.X + ar[2] * b.Y + ar[3] * b.Z,
			a.Y + ar[4] * b.X + ar[5] * b.Y + ar[6] * b.Z,
			a.Z + ar[7] * b.X + ar[8] * b.Y + ar[9] * b.Z,
			r
		)
	end
	return Vector3.new(
		a.X + ar[1] * b.X + ar[2] * b.Y + ar[3] * b.Z,
		a.Y + ar[4] * b.X + ar[5] * b.Y + ar[6] * b.Z,
		a.Z + ar[7] * b.X + ar[8] * b.Y + ar[9] * b.Z
	)
end

cfMt.__eq = function(a: any, b: any): boolean
	if a.X ~= b.X or a.Y ~= b.Y or a.Z ~= b.Z then
		return false
	end
	local ar = rawget(a, "r") :: { number }
	local br = rawget(b, "r") :: { number }
	for index = 1, 9 do
		if ar[index] ~= br[index] then
			return false
		end
	end
	return true
end

cfMt.__sub = function(a: any, b: any): any
	return makeCFrame(a.X - b.X, a.Y - b.Y, a.Z - b.Z, rawget(a, "r") :: { number })
end

function cfMt.GetComponents(cf: any): (
	number,
	number,
	number,
	number,
	number,
	number,
	number,
	number,
	number,
	number,
	number,
	number
)
	local r = rawget(cf, "r") :: { number }
	return cf.X, cf.Y, cf.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]
end

function cfMt.Inverse(cf: any): CF
	local r = rawget(cf, "r") :: { number }
	return makeCFrame(
		-(r[1] * cf.X + r[4] * cf.Y + r[7] * cf.Z),
		-(r[2] * cf.X + r[5] * cf.Y + r[8] * cf.Z),
		-(r[3] * cf.X + r[6] * cf.Y + r[9] * cf.Z),
		{ r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] }
	)
end

local function fromEulerAnglesXYZ(rx: number, ry: number, rz: number): CF
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)
	return makeCFrame(0, 0, 0, {
		cy * cz,
		-cy * sz,
		sy,
		sx * sy * cz + cx * sz,
		-sx * sy * sz + cx * cz,
		-sx * cy,
		-cx * sy * cz + sx * sz,
		cx * sy * sz + sx * cz,
		cx * cy,
	})
end

CFrame = {
	new = function(x: any?, y: any?, z: number?, ...: number): CF
		if type(x) == "table" then
			if type(y) == "table" then
				return CFrame.lookAt(x, y)
			end
			return makeCFrame(x.X, x.Y, x.Z, IDENTITY_R)
		end
		if select("#", ...) == 9 then
			return makeCFrame(x or 0, y or 0, z or 0, { ... })
		end
		return makeCFrame(x or 0, y or 0, z or 0, IDENTITY_R)
	end,
	Angles = fromEulerAnglesXYZ,
	fromEulerAnglesXYZ = fromEulerAnglesXYZ,
	lookAt = function(from: any, to: any, up: any?): CF
		local worldUp = up or Vector3.new(0, 1, 0)
		local look = (to - from).Unit
		local right = look:Cross(worldUp)
		if right.Magnitude < 1e-6 then
			right = look:Cross(Vector3.new(1, 0, 0))
			if right.Magnitude < 1e-6 then
				right = look:Cross(Vector3.new(0, 0, 1))
			end
		end
		right = right.Unit
		local newUp = right:Cross(look)
		return makeCFrame(from.X, from.Y, from.Z, {
			right.X,
			newUp.X,
			-look.X,
			right.Y,
			newUp.Y,
			-look.Y,
			right.Z,
			newUp.Z,
			-look.Z,
		})
	end,
}

local color3Mt: any = {}
color3Mt.__index = color3Mt
local makeColor3: (number, number, number) -> C3
function color3Mt:Lerp(other: C3, alpha: number): C3
	return makeColor3(
		self.R + (other.R - self.R) * alpha,
		self.G + (other.G - self.G) * alpha,
		self.B + (other.B - self.B) * alpha
	)
end
color3Mt.__eq = function(a: any, b: any): boolean
	return a.R == b.R and a.G == b.G and a.B == b.B
end
color3Mt.__tostring = function(a: any): string
	return ("%g, %g, %g"):format(a.R, a.G, a.B)
end

makeColor3 = function(r: number, g: number, b: number): C3
	local color: any = { R = r, G = g, B = b }
	setmetatable(color, color3Mt)
	return color
end

local Color3 = {
	fromRGB = function(r: number, g: number, b: number): C3
		return makeColor3(r / 255, g / 255, b / 255)
	end,
	new = function(r: number?, g: number?, b: number?): C3
		return makeColor3(r or 0, g or 0, b or 0)
	end,
}

local v2Mt: any = {}
local makeVector2: (number, number) -> any
v2Mt.__index = function(v: any, key: any): any
	if key == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	elseif key == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y)
		return makeVector2(v.X / m, v.Y / m)
	end
	return rawget(v2Mt, key)
end
v2Mt.__add = function(a: any, b: any): any
	return makeVector2(a.X + b.X, a.Y + b.Y)
end
v2Mt.__sub = function(a: any, b: any): any
	return makeVector2(a.X - b.X, a.Y - b.Y)
end
v2Mt.__mul = function(a: any, b: any): any
	if type(b) == "number" then
		return makeVector2(a.X * b, a.Y * b)
	end
	return makeVector2(a.X * b.X, a.Y * b.Y)
end
v2Mt.__div = function(a: any, b: any): any
	if type(b) == "number" then
		return makeVector2(a.X / b, a.Y / b)
	end
	return makeVector2(a.X / b.X, a.Y / b.Y)
end
v2Mt.__unm = function(a: any): any
	return makeVector2(-a.X, -a.Y)
end
v2Mt.__eq = function(a: any, b: any): boolean
	return a.X == b.X and a.Y == b.Y
end
v2Mt.__tostring = function(a: any): string
	return ("%g, %g"):format(a.X, a.Y)
end
function v2Mt.Dot(a: any, b: any): number
	return a.X * b.X + a.Y * b.Y
end
makeVector2 = function(x: number, y: number): any
	return setmetatable({ X = x, Y = y }, v2Mt)
end
local Vector2 = {
	new = function(x: number?, y: number?): any
		return makeVector2(x or 0, y or 0)
	end,
}

local udimMt: any = {}
udimMt.__eq = function(a: any, b: any): boolean
	return a.Scale == b.Scale and a.Offset == b.Offset
end
udimMt.__tostring = function(a: any): string
	return ("%g, %g"):format(a.Scale, a.Offset)
end
local UDim = {
	new = function(scale: number?, offset: number?): any
		return setmetatable({ Scale = scale or 0, Offset = offset or 0 }, udimMt)
	end,
}

local udim2Mt: any = {}
udim2Mt.__eq = function(a: any, b: any): boolean
	return a.X == b.X and a.Y == b.Y
end
udim2Mt.__tostring = function(a: any): string
	return ("{%g, %g}, {%g, %g}"):format(a.X.Scale, a.X.Offset, a.Y.Scale, a.Y.Offset)
end
local function makeUDim2(xs: any?, xo: any?, ys: number?, yo: number?): any
	local x, y
	if type(xs) == "table" then
		x, y = xs, xo
	else
		x, y = UDim.new(xs, xo), UDim.new(ys, yo)
	end
	return setmetatable({ X = x, Y = y, Width = x, Height = y }, udim2Mt)
end
local UDim2 = {
	new = makeUDim2,
	fromScale = function(x: number?, y: number?): any
		return makeUDim2(x or 0, 0, y or 0, 0)
	end,
	fromOffset = function(x: number?, y: number?): any
		return makeUDim2(0, x or 0, 0, y or 0)
	end,
}

local memberMt: any = {}
memberMt.__index = function(category: any, member: string): any
	local value = { _enum = member }
	rawset(category, member, value)
	return value
end
local enumMt: any = {}
enumMt.__index = function(enum: any, category: string): any
	local members = setmetatable({}, memberMt)
	rawset(enum, category, members)
	return members
end
local Enum = setmetatable({} :: any, enumMt)

local NumberSequenceKeypoint = {
	new = function(t: number, v: number, _envelope: number?): any
		return { Time = t, Value = v }
	end,
}

local ColorSequenceKeypoint = {
	new = function(t: number, color: any): any
		return { Time = t, Value = color }
	end,
}

local NumberRange = {
	new = function(min: number, max: number?): any
		return { Min = min, Max = max or min }
	end,
}

local NumberSequence = {
	new = function(value: any): any
		return { _ns = value }
	end,
}

local ColorSequence = {
	new = function(value: any): any
		return { _cs = value }
	end,
}

local Rect = {
	new = function(_x0: number?, _y0: number?, _x1: number?, _y1: number?): any
		return { _rect = true }
	end,
}

local TweenInfo = {
	new = function(
		_time: number?,
		_style: any?,
		_dir: any?,
		_count: number?,
		_reverses: boolean?,
		_delay: number?
	): any
		return { _tweenInfo = true }
	end,
}

local names: { [any]: string } = {
	[v3Mt] = "Vector3",
	[cfMt] = "CFrame",
	[color3Mt] = "Color3",
	[v2Mt] = "Vector2",
	[udimMt] = "UDim",
	[udim2Mt] = "UDim2",
}

local function typeName(value: any): string?
	if type(value) ~= "table" then
		return nil
	end
	return names[getmetatable(value)]
end

local function readCFrame(value: any): (number, number, number, { number })
	local r = rawget(value, "r") :: { number }
	return value.X, value.Y, value.Z, table.clone(r)
end

return {
	Color3 = Color3,
	Vector2 = Vector2,
	Vector3 = Vector3,
	CFrame = CFrame,
	Enum = Enum,
	UDim2 = UDim2,
	UDim = UDim,
	NumberSequenceKeypoint = NumberSequenceKeypoint,
	ColorSequenceKeypoint = ColorSequenceKeypoint,
	NumberRange = NumberRange,
	NumberSequence = NumberSequence,
	ColorSequence = ColorSequence,
	Rect = Rect,
	TweenInfo = TweenInfo,
	typeName = typeName,
	readCFrame = readCFrame,
}
