--!strict
--!native

local ImageModule = require("./image")
local Numeric = require("./numeric")

type Image = ImageModule.Image

export type Filter = "nearest" | "box" | "bilinear" | "hamming" | "bicubic" | "lanczos"

local Image = ImageModule
local trunc = Numeric.trunc

local PRECISION = 4194304

local function boxFilter(x: number): number
	if x > -0.5 and x <= 0.5 then
		return 1.0
	end
	return 0.0
end

local function bilinearFilter(x: number): number
	if x < 0.0 then
		x = -x
	end
	if x < 1.0 then
		return 1.0 - x
	end
	return 0.0
end

local function hammingFilter(x: number): number
	if x < 0.0 then
		x = -x
	end
	if x == 0.0 then
		return 1.0
	end
	if x >= 1.0 then
		return 0.0
	end
	x = x * math.pi
	return math.sin(x) / x * (Numeric.f32(0.54) + Numeric.f32(0.46) * math.cos(x))
end

local function bicubicFilter(x: number): number
	if x < 0.0 then
		x = -x
	end
	if x < 1.0 then
		return ((-0.5 + 2.0) * x - (-0.5 + 3.0)) * x * x + 1
	end
	if x < 2.0 then
		return (((x - 5) * x + 8) * x - 4) * -0.5
	end
	return 0.0
end

local function sincFilter(x: number): number
	if x == 0.0 then
		return 1.0
	end
	x = x * math.pi
	return math.sin(x) / x
end

local function lanczosFilter(x: number): number
	if -3.0 <= x and x < 3.0 then
		return sincFilter(x) * sincFilter(x / 3)
	end
	return 0.0
end

type FilterSpec = { weight: (number) -> number, support: number }

local FILTERS: { [string]: FilterSpec } = {
	box = { weight = boxFilter, support = 0.5 },
	bilinear = { weight = bilinearFilter, support = 1.0 },
	hamming = { weight = hammingFilter, support = 1.0 },
	bicubic = { weight = bicubicFilter, support = 2.0 },
	lanczos = { weight = lanczosFilter, support = 3.0 },
}

type Coefficients = { size: number, bounds: buffer, weights: buffer }

local function precompute(inSize: number, outSize: number, spec: FilterSpec): Coefficients
	local scale = inSize / outSize
	local filterscale = if scale < 1.0 then 1.0 else scale
	local support = spec.support * filterscale
	local size = math.ceil(support) * 2 + 1
	local bounds = buffer.create(outSize * 8)
	local weights = buffer.create(outSize * size * 4)
	local inverse = 1.0 / filterscale
	local raw = table.create(size, 0.0)
	local weight = spec.weight
	for xx = 0, outSize - 1 do
		local center = 0 + (xx + 0.5) * scale
		local total = 0.0
		local xmin = trunc(center - support + 0.5)
		if xmin < 0 then
			xmin = 0
		end
		local xmax = trunc(center + support + 0.5)
		if xmax > inSize then
			xmax = inSize
		end
		xmax -= xmin
		for x = 0, xmax - 1 do
			local w = weight((x + xmin - center + 0.5) * inverse)
			raw[x + 1] = w
			total += w
		end
		for x = 0, size - 1 do
			local value = if x < xmax then raw[x + 1] else 0.0
			if x < xmax and total ~= 0.0 then
				value /= total
			end
			local fixed = if value < 0 then trunc(-0.5 + value * PRECISION) else trunc(0.5 + value * PRECISION)
			buffer.writei32(weights, (xx * size + x) * 4, fixed)
		end
		buffer.writei32(bounds, xx * 8, xmin)
		buffer.writei32(bounds, xx * 8 + 4, xmax)
	end
	return { size = size, bounds = bounds, weights = weights }
end

local function clip8(value: number): number
	local shifted = value // PRECISION
	if shifted < 0 then
		return 0
	elseif shifted > 255 then
		return 255
	end
	return shifted
end

local function solidColor(image: Image): { number }?
	if image.channels ~= 4 then
		return nil
	end
	local data = image.data
	local color: { number }? = nil
	for index = 0, image.width * image.height - 1 do
		local value = buffer.readu32(data, index * 4)
		if value ~= 0 then
			if color == nil then
				color = {
					buffer.readu8(data, index * 4),
					buffer.readu8(data, index * 4 + 1),
					buffer.readu8(data, index * 4 + 2),
					buffer.readu8(data, index * 4 + 3),
					value,
				}
			elseif value ~= color[5] then
				return nil
			end
		end
	end
	return color
end

local function horizontal(
	source: Image,
	first: number,
	rows: number,
	outWidth: number,
	coefficients: Coefficients
): Image
	local channels = source.channels
	local out = Image.new(outWidth, rows, channels)
	local inData = source.data
	local outData = out.data
	local inWidth = source.width
	local size = coefficients.size
	local bounds = coefficients.bounds
	local weights = coefficients.weights
	local solid = solidColor(source)
	if solid ~= nil then
		local c0, c1, c2, c3 = solid[1], solid[2], solid[3], solid[4]
		local fullWeight = table.create(outWidth, 0)
		for xx = 0, outWidth - 1 do
			local xmax = buffer.readi32(bounds, xx * 8 + 4)
			local kbase = xx * size * 4
			local total = 0
			for x = 0, xmax - 1 do
				total += buffer.readi32(weights, kbase + x * 4)
			end
			fullWeight[xx + 1] = total
		end
		local prefix = buffer.create((inWidth + 1) * 4)
		for yy = 0, rows - 1 do
			local rowBase = (yy + first) * inWidth
			local running = 0
			for x = 0, inWidth - 1 do
				if buffer.readu32(inData, (rowBase + x) * 4) ~= 0 then
					running += 1
				end
				buffer.writeu32(prefix, (x + 1) * 4, running)
			end
			if running == 0 then
				continue
			end
			for xx = 0, outWidth - 1 do
				local xmin = buffer.readi32(bounds, xx * 8)
				local xmax = buffer.readi32(bounds, xx * 8 + 4)
				local covered = buffer.readu32(prefix, (xmin + xmax) * 4) - buffer.readu32(prefix, xmin * 4)
				local total = 0
				if covered == xmax then
					total = fullWeight[xx + 1]
				elseif covered > 0 then
					local kbase = xx * size * 4
					local start = (rowBase + xmin) * 4
					for x = 0, xmax - 1 do
						if buffer.readu32(inData, start + x * 4) ~= 0 then
							total += buffer.readi32(weights, kbase + x * 4)
						end
					end
				end
				if total ~= 0 then
					local target = (yy * outWidth + xx) * 4
					buffer.writeu8(outData, target, clip8(2097152 + c0 * total))
					buffer.writeu8(outData, target + 1, clip8(2097152 + c1 * total))
					buffer.writeu8(outData, target + 2, clip8(2097152 + c2 * total))
					buffer.writeu8(outData, target + 3, clip8(2097152 + c3 * total))
				end
			end
		end
		return out
	end
	for yy = 0, rows - 1 do
		local rowBase = (yy + first) * inWidth
		for xx = 0, outWidth - 1 do
			local xmin = buffer.readi32(bounds, xx * 8)
			local xmax = buffer.readi32(bounds, xx * 8 + 4)
			local kbase = xx * size * 4
			local start = (rowBase + xmin) * channels
			local target = (yy * outWidth + xx) * channels
			if channels == 1 then
				local sum = 2097152
				for x = 0, xmax - 1 do
					sum += buffer.readu8(inData, start + x) * buffer.readi32(weights, kbase + x * 4)
				end
				buffer.writeu8(outData, target, clip8(sum))
			elseif channels == 4 then
				local s0, s1, s2, s3 = 2097152, 2097152, 2097152, 2097152
				for x = 0, xmax - 1 do
					local k = buffer.readi32(weights, kbase + x * 4)
					local at = start + x * 4
					s0 += buffer.readu8(inData, at) * k
					s1 += buffer.readu8(inData, at + 1) * k
					s2 += buffer.readu8(inData, at + 2) * k
					s3 += buffer.readu8(inData, at + 3) * k
				end
				buffer.writeu8(outData, target, clip8(s0))
				buffer.writeu8(outData, target + 1, clip8(s1))
				buffer.writeu8(outData, target + 2, clip8(s2))
				buffer.writeu8(outData, target + 3, clip8(s3))
			else
				for channel = 0, channels - 1 do
					local sum = 2097152
					for x = 0, xmax - 1 do
						sum += buffer.readu8(inData, start + x * channels + channel) * buffer.readi32(
							weights,
							kbase + x * 4
						)
					end
					buffer.writeu8(outData, target + channel, clip8(sum))
				end
			end
		end
	end
	return out
end

local function vertical(source: Image, outHeight: number, offset: number, coefficients: Coefficients): Image
	local channels = source.channels
	local width = source.width
	local out = Image.new(width, outHeight, channels)
	local inData = source.data
	local outData = out.data
	local size = coefficients.size
	local bounds = coefficients.bounds
	local weights = coefficients.weights
	local stride = width * channels
	local taps = table.create(size, 0)
	for yy = 0, outHeight - 1 do
		local ymin = buffer.readi32(bounds, yy * 8) - offset
		local ymax = buffer.readi32(bounds, yy * 8 + 4)
		local kbase = yy * size * 4
		for y = 0, ymax - 1 do
			taps[y + 1] = buffer.readi32(weights, kbase + y * 4)
		end
		local rowBase = ymin * stride
		local target = yy * stride
		for column = 0, stride - 1 do
			local sum = 2097152
			local at = rowBase + column
			for y = 1, ymax do
				sum += buffer.readu8(inData, at) * taps[y]
				at += stride
			end
			buffer.writeu8(outData, target + column, clip8(sum))
		end
	end
	return out
end

local function premultiply(image: Image): Image
	local out = Image.copy(image)
	local data = out.data
	for index = 0, image.width * image.height - 1 do
		local alpha = buffer.readu8(data, index * 4 + 3)
		if alpha == 0 then
			buffer.writeu32(data, index * 4, 0)
		elseif alpha ~= 255 then
			for channel = 0, 2 do
				local value = buffer.readu8(data, index * 4 + channel) * alpha + 128
				buffer.writeu8(data, index * 4 + channel, bit32.rshift(bit32.rshift(value, 8) + value, 8))
			end
		end
	end
	return out
end

local function unpremultiply(image: Image)
	local data = image.data
	for index = 0, image.width * image.height - 1 do
		local alpha = buffer.readu8(data, index * 4 + 3)
		if alpha ~= 255 and alpha ~= 0 then
			for channel = 0, 2 do
				local value = (255 * buffer.readu8(data, index * 4 + channel)) // alpha
				buffer.writeu8(data, index * 4 + channel, if value > 255 then 255 else value)
			end
		end
	end
end

local function nearest(image: Image, width: number, height: number): Image
	local channels = image.channels
	local out = Image.new(width, height, channels)
	local scaleX = image.width / width
	local scaleY = image.height / height
	local columns = table.create(width, -1)
	local xo = scaleX * 0.5
	local xmin = width
	local xmax = 0
	for x = 0, width - 1 do
		local xin = if xo < 0.0 then -1 else trunc(xo)
		if xin >= 0 and xin < image.width then
			xmax = x + 1
			if x < xmin then
				xmin = x
			end
			columns[x + 1] = xin
		end
		xo += scaleX
	end
	local yo = scaleY * 0.5
	for y = 0, height - 1 do
		local yi = if yo < 0.0 then -1 else trunc(yo)
		if yi >= 0 and yi < image.height then
			for x = xmin, xmax - 1 do
				buffer.copy(
					out.data,
					(y * width + x) * channels,
					image.data,
					(yi * image.width + columns[x + 1]) * channels,
					channels
				)
			end
		end
		yo += scaleY
	end
	return out
end

local Resample = {}

function Resample.resize(image: Image, width: number, height: number, filter: Filter): Image
	if image.width == width and image.height == height then
		return Image.copy(image)
	end
	if filter == "nearest" then
		return nearest(image, width, height)
	end
	local spec = FILTERS[filter]
	if spec == nil then
		error(`unknown resampling filter {filter}`, 2)
	end
	local source = if image.channels == 4 then premultiply(image) else image
	local verticalCoefficients = precompute(image.height, height, spec)
	local first = buffer.readi32(verticalCoefficients.bounds, 0)
	local last = buffer.readi32(verticalCoefficients.bounds, (height - 1) * 8)
		+ buffer.readi32(verticalCoefficients.bounds, (height - 1) * 8 + 4)
	local current = source
	local offset = 0
	if width ~= image.width then
		current = horizontal(source, first, last - first, width, precompute(image.width, width, spec))
		offset = first
	end
	if height ~= image.height then
		current = vertical(current, height, offset, verticalCoefficients)
	end
	if current == source then
		current = Image.copy(source)
	end
	if image.channels == 4 then
		unpremultiply(current)
	end
	return current
end

return table.freeze(Resample)
