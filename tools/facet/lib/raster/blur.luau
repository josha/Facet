--!strict
--!native

local ImageModule = require("./image")
local Numeric = require("./numeric")

type Image = ImageModule.Image

local f32 = Numeric.f32

local function gaussianRadius(radius: number, passes: number): number
	local sigma2 = f32(f32(radius * radius) / passes)
	local length = f32(math.sqrt(12.0 * sigma2 + 1.0))
	local whole = f32(math.floor((length - 1.0) / 2.0))
	local next = f32(whole + 1)
	local fraction = f32(f32(2 * whole + 1) * f32(f32(whole * next) - f32(3 * sigma2)))
	fraction = f32(fraction / f32(6 * f32(sigma2 - f32(next * next))))
	return f32(whole + fraction)
end

local function blurLine(
	line: buffer,
	out: buffer,
	last: number,
	radius: number,
	edgeA: number,
	edgeB: number,
	ww: number,
	fw: number
)
	local acc = buffer.readu8(line, 0) * (radius + 1)
	for x = 0, edgeA - 2 do
		acc += buffer.readu8(line, x)
	end
	acc += buffer.readu8(line, last) * (radius - edgeA + 1)
	local function save(x: number, left: number, right: number)
		local bulk = acc * ww + (buffer.readu8(line, left) + buffer.readu8(line, right)) * fw
		buffer.writeu8(out, x, (bulk + 8388608) // 16777216)
	end
	if edgeA <= edgeB then
		for x = 0, edgeA - 1 do
			acc += buffer.readu8(line, x + radius) - buffer.readu8(line, 0)
			save(x, 0, x + radius + 1)
		end
		for x = edgeA, edgeB - 1 do
			acc += buffer.readu8(line, x + radius) - buffer.readu8(line, x - radius - 1)
			save(x, x - radius - 1, x + radius + 1)
		end
		for x = edgeB, last do
			acc += buffer.readu8(line, last) - buffer.readu8(line, x - radius - 1)
			save(x, x - radius - 1, last)
		end
	else
		for x = 0, edgeB - 1 do
			acc += buffer.readu8(line, x + radius) - buffer.readu8(line, 0)
			save(x, 0, x + radius + 1)
		end
		for x = edgeB, edgeA - 1 do
			acc += buffer.readu8(line, last) - buffer.readu8(line, 0)
			save(x, 0, last)
		end
		for x = edgeA, last do
			acc += buffer.readu8(line, last) - buffer.readu8(line, x - radius - 1)
			save(x, x - radius - 1, last)
		end
	end
end

local function boxPass(plane: buffer, width: number, height: number, floatRadius: number)
	local radius = Numeric.trunc(floatRadius)
	local ww = Numeric.trunc(f32(16777216 / f32(f32(floatRadius * 2) + 1)))
	local fw = (16777216 - (radius * 2 + 1) * ww) // 2
	local edgeA = math.min(radius + 1, width)
	local edgeB = math.max(width - radius - 1, 0)
	local line = buffer.create(width)
	local out = buffer.create(width)
	for y = 0, height - 1 do
		buffer.copy(line, 0, plane, y * width, width)
		blurLine(line, out, width - 1, radius, edgeA, edgeB, ww, fw)
		buffer.copy(plane, y * width, out, 0, width)
	end
end

local function transpose(plane: buffer, width: number, height: number): buffer
	local out = buffer.create(width * height)
	for y = 0, height - 1 do
		for x = 0, width - 1 do
			buffer.writeu8(out, x * height + y, buffer.readu8(plane, y * width + x))
		end
	end
	return out
end

local Blur = {}

function Blur.gaussian(image: Image, radius: number, passes: number?): Image
	local count = passes or 3
	local out = ImageModule.copy(image)
	if radius == 0 or image.width == 0 or image.height == 0 then
		return out
	end
	local boxRadius = gaussianRadius(f32(radius), count)
	local width, height, channels = image.width, image.height, image.channels
	for channel = 0, channels - 1 do
		local plane = buffer.create(width * height)
		for index = 0, width * height - 1 do
			buffer.writeu8(plane, index, buffer.readu8(image.data, index * channels + channel))
		end
		if boxRadius ~= 0 then
			for _ = 1, count do
				boxPass(plane, width, height, boxRadius)
			end
			local turned = transpose(plane, width, height)
			for _ = 1, count do
				boxPass(turned, height, width, boxRadius)
			end
			plane = transpose(turned, height, width)
		end
		for index = 0, width * height - 1 do
			buffer.writeu8(out.data, index * channels + channel, buffer.readu8(plane, index))
		end
	end
	return out
end

return table.freeze(Blur)
