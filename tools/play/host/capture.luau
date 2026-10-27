--!strict

local fs = require("@std/fs")

local Jpeg = require("../../facet/lib/raster/jpeg")
local Media = require("../../../tools/vendor/verify/src/codec/image")
local Png = require("../../facet/lib/raster/png")

export type Raster = Jpeg.Raster
export type Classification = "unusable" | "needs-review" | "unreviewed"

export type Inspection = {
	width: number,
	height: number,
	blank: boolean,
	classification: Classification,
	spread: number,
	dominant: number,
	reason: string?,
}

local GRID = 64

local function decode(bytes: string): (Raster?, string?)
	local kind = Media.mediaType(bytes)
	local ok, value: unknown = pcall(function(): Raster
		if kind == "image/jpeg" then
			return Jpeg.decode(buffer.fromstring(bytes))
		elseif kind == "image/png" then
			return Png.decode(buffer.fromstring(bytes))
		end
		error("the capture is not a PNG or a JPEG image", 0)
	end)
	if not ok then
		return nil, tostring(value)
	end
	return value :: Raster, nil
end

local function inspect(raster: Raster): Inspection
	local uniform = true
	for offset = raster.channels, buffer.len(raster.data) - 1, raster.channels do
		for channel = 0, raster.channels - 1 do
			if buffer.readu8(raster.data, offset + channel) ~= buffer.readu8(raster.data, channel) then
				uniform = false
				break
			end
		end
		if not uniform then
			break
		end
	end
	local luminances: { number } = {}
	local buckets: { [number]: number } = {}
	local samples = 0
	local stepX = math.max(1, raster.width // GRID)
	local stepY = math.max(1, raster.height // GRID)
	for y = 0, raster.height - 1, stepY do
		for x = 0, raster.width - 1, stepX do
			local offset = (y * raster.width + x) * raster.channels
			local red = buffer.readu8(raster.data, offset)
			local green = if raster.channels >= 3 then buffer.readu8(raster.data, offset + 1) else red
			local blue = if raster.channels >= 3 then buffer.readu8(raster.data, offset + 2) else red
			local luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
			table.insert(luminances, luminance)
			local key = (red // 8) * 1024 + (green // 8) * 32 + blue // 8
			buckets[key] = (buckets[key] or 0) + 1
			samples += 1
		end
	end
	local sum = 0
	for _, value in luminances do
		sum += value
	end
	local mean = sum / math.max(1, samples)
	local variance = 0
	for _, value in luminances do
		variance += (value - mean) ^ 2
	end
	local spread = math.sqrt(variance / math.max(1, samples))
	local largest = 0
	for _, count in buckets do
		largest = math.max(largest, count)
	end
	local dominant = largest / math.max(1, samples)
	local reason: string? = nil
	local classification: Classification = "unreviewed"
	if raster.width < 64 or raster.height < 64 then
		reason = ("the capture is only %d x %d pixels"):format(raster.width, raster.height)
		classification = "unusable"
	elseif uniform then
		reason = "the capture is one uniform color"
		classification = "unusable"
	elseif spread < 4 then
		reason = ("the capture has almost no contrast (luminance spread %.1f)"):format(spread)
		classification = "needs-review"
	elseif dominant > 0.97 then
		reason = ("%.1f%% of the capture is one color"):format(dominant * 100)
		classification = "needs-review"
	end
	return {
		width = raster.width,
		height = raster.height,
		blank = uniform,
		classification = classification,
		spread = spread,
		dominant = dominant,
		reason = reason,
	}
end

local function convert(source: string, target: string): (Inspection?, string?)
	if not fs.exists(source) then
		return nil, "no capture exists at " .. source
	end
	local raster, problem = decode(fs.readFileToString(source))
	if raster == nil then
		return nil, problem
	end
	local inspection = inspect(raster :: Raster)
	fs.writeStringToFile(target, buffer.tostring(Png.encode(raster :: Raster, true)))
	return inspection, nil
end

return {
	decode = decode,
	inspect = inspect,
	convert = convert,
}
