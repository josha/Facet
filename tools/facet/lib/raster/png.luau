--!strict
--!native

local Checksum = require("./checksum")
local Deflate = require("./deflate")
local ImageModule = require("./image")

type Image = ImageModule.Image

local SIGNATURE = "\137PNG\r\n\26\n"
local CHANNELS_BY_TYPE: { [number]: number } = { [0] = 1, [2] = 3, [3] = 1, [4] = 2, [6] = 4 }
local TYPE_BY_CHANNELS: { [number]: number } = { [1] = 0, [2] = 4, [3] = 2, [4] = 6 }
local VALID_DEPTHS: { [number]: { number } } = {
	[0] = { 1, 2, 4, 8, 16 },
	[2] = { 8, 16 },
	[3] = { 1, 2, 4, 8 },
	[4] = { 8, 16 },
	[6] = { 8, 16 },
}

local function readU32(data: buffer, offset: number): number
	return buffer.readu8(data, offset) * 16777216
		+ buffer.readu8(data, offset + 1) * 65536
		+ buffer.readu8(data, offset + 2) * 256
		+ buffer.readu8(data, offset + 3)
end

local function writeU32(data: buffer, offset: number, value: number)
	buffer.writeu8(data, offset, bit32.rshift(value, 24))
	buffer.writeu8(data, offset + 1, bit32.band(bit32.rshift(value, 16), 0xFF))
	buffer.writeu8(data, offset + 2, bit32.band(bit32.rshift(value, 8), 0xFF))
	buffer.writeu8(data, offset + 3, bit32.band(value, 0xFF))
end

local function paeth(a: number, b: number, c: number): number
	local p = a + b - c
	local pa = math.abs(p - a)
	local pb = math.abs(p - b)
	local pc = math.abs(p - c)
	if pa <= pb and pa <= pc then
		return a
	elseif pb <= pc then
		return b
	end
	return c
end

local function unfilter(raw: buffer, stride: number, height: number, bpp: number): buffer
	local out = buffer.create(stride * height)
	for y = 0, height - 1 do
		local source = y * (stride + 1)
		local filter = buffer.readu8(raw, source)
		local row = y * stride
		local above = row - stride
		source += 1
		if filter == 0 then
			buffer.copy(out, row, raw, source, stride)
		elseif filter == 1 then
			for x = 0, stride - 1 do
				local left = if x >= bpp then buffer.readu8(out, row + x - bpp) else 0
				buffer.writeu8(out, row + x, bit32.band(buffer.readu8(raw, source + x) + left, 0xFF))
			end
		elseif filter == 2 then
			if y == 0 then
				buffer.copy(out, row, raw, source, stride)
			else
				for x = 0, stride - 1 do
					buffer.writeu8(
						out,
						row + x,
						bit32.band(buffer.readu8(raw, source + x) + buffer.readu8(out, above + x), 0xFF)
					)
				end
			end
		elseif filter == 3 then
			for x = 0, stride - 1 do
				local left = if x >= bpp then buffer.readu8(out, row + x - bpp) else 0
				local up = if y > 0 then buffer.readu8(out, above + x) else 0
				buffer.writeu8(out, row + x, bit32.band(buffer.readu8(raw, source + x) + (left + up) // 2, 0xFF))
			end
		elseif filter == 4 then
			for x = 0, stride - 1 do
				local left = if x >= bpp then buffer.readu8(out, row + x - bpp) else 0
				local up = if y > 0 then buffer.readu8(out, above + x) else 0
				local corner = if x >= bpp and y > 0 then buffer.readu8(out, above + x - bpp) else 0
				buffer.writeu8(out, row + x, bit32.band(buffer.readu8(raw, source + x) + paeth(left, up, corner), 0xFF))
			end
		else
			error(("png: unknown filter type %d on row %d"):format(filter, y), 0)
		end
	end
	return out
end

local function residual(
	pixels: buffer,
	row: number,
	x: number,
	y: number,
	stride: number,
	bpp: number,
	filter: number
): number
	local value = buffer.readu8(pixels, row + x)
	if filter == 0 then
		return value
	end
	local left = if x >= bpp then buffer.readu8(pixels, row + x - bpp) else 0
	local up = if y > 0 then buffer.readu8(pixels, row - stride + x) else 0
	local predicted
	if filter == 1 then
		predicted = left
	elseif filter == 2 then
		predicted = up
	elseif filter == 3 then
		predicted = (left + up) // 2
	else
		local corner = if x >= bpp and y > 0 then buffer.readu8(pixels, row - stride + x - bpp) else 0
		predicted = paeth(left, up, corner)
	end
	return bit32.band(value - predicted, 0xFF)
end

local function filterRows(pixels: buffer, width: number, height: number, bpp: number): buffer
	local stride = width * bpp
	local out = buffer.create((stride + 1) * height)
	for y = 0, height - 1 do
		local row = y * stride
		local best = 0
		local bestCost = math.huge
		for filter = 0, 4 do
			local cost = 0
			for x = 0, stride - 1 do
				local value = residual(pixels, row, x, y, stride, bpp, filter)
				cost += if value < 128 then value else 256 - value
				if cost >= bestCost then
					break
				end
			end
			if cost < bestCost then
				bestCost = cost
				best = filter
			end
		end
		local target = y * (stride + 1)
		buffer.writeu8(out, target, best)
		for x = 0, stride - 1 do
			buffer.writeu8(out, target + 1 + x, residual(pixels, row, x, y, stride, bpp, best))
		end
	end
	return out
end

local Png = {}

export type Chunk = { kind: string, data: buffer }

function Png.chunks(data: buffer): { Chunk }
	if buffer.len(data) < 8 or buffer.readstring(data, 0, 8) ~= SIGNATURE then
		error("png: missing PNG signature", 0)
	end
	local chunks: { Chunk } = {}
	local offset = 8
	local size = buffer.len(data)
	while offset < size do
		if offset + 12 > size then
			error("png: truncated chunk header", 0)
		end
		local length = readU32(data, offset)
		local kind = buffer.readstring(data, offset + 4, 4)
		if offset + 12 + length > size then
			error(("png: truncated %s chunk"):format(kind), 0)
		end
		local stored = readU32(data, offset + 8 + length)
		if Checksum.crc32(data, offset + 4, length + 4) ~= stored then
			error(("png: CRC mismatch in %s chunk"):format(kind), 0)
		end
		local body = buffer.create(length)
		buffer.copy(body, 0, data, offset + 8, length)
		table.insert(chunks, { kind = kind, data = body })
		offset += 12 + length
		if kind == "IEND" then
			break
		end
	end
	return chunks
end

function Png.decode(data: buffer): Image
	local chunks = Png.chunks(data)
	local header = chunks[1]
	if header == nil or header.kind ~= "IHDR" or buffer.len(header.data) ~= 13 then
		error("png: the first chunk is not IHDR", 0)
	end
	local width = readU32(header.data, 0)
	local height = readU32(header.data, 4)
	local depth = buffer.readu8(header.data, 8)
	local colorType = buffer.readu8(header.data, 9)
	local interlace = buffer.readu8(header.data, 12)
	local channels = CHANNELS_BY_TYPE[colorType]
	if channels == nil then
		error(("png: unknown color type %d"):format(colorType), 0)
	end
	local depths = VALID_DEPTHS[colorType]
	if table.find(depths, depth) == nil then
		error(("png: bit depth %d is not valid for color type %d"):format(depth, colorType), 0)
	end
	if interlace ~= 0 then
		error("png: interlaced images are not supported", 0)
	end
	local palette: buffer? = nil
	local transparency: buffer? = nil
	local parts: { buffer } = {}
	local total = 0
	for _, chunk in chunks do
		if chunk.kind == "PLTE" then
			palette = chunk.data
		elseif chunk.kind == "tRNS" then
			transparency = chunk.data
		elseif chunk.kind == "IDAT" then
			table.insert(parts, chunk.data)
			total += buffer.len(chunk.data)
		end
	end
	if #parts == 0 then
		error("png: no IDAT chunk", 0)
	end
	local compressed = buffer.create(total)
	local cursor = 0
	for _, part in parts do
		buffer.copy(compressed, cursor, part, 0, buffer.len(part))
		cursor += buffer.len(part)
	end
	local bitsPerPixel = channels * depth
	local stride = (width * bitsPerPixel + 7) // 8
	local expected = (stride + 1) * height
	local raw = Deflate.decompress(compressed, expected)
	if buffer.len(raw) < expected then
		error("png: image data is shorter than the header declares", 0)
	end
	local rows = unfilter(raw, stride, height, math.max(1, bitsPerPixel // 8))
	if depth == 8 and colorType ~= 3 and transparency == nil then
		return { width = width, height = height, channels = channels, data = rows }
	end
	local maximum = 2 ^ depth - 1
	local function sample(x: number, y: number, channel: number): number
		local index = x * channels + channel
		local row = y * stride
		if depth == 8 then
			return buffer.readu8(rows, row + index)
		elseif depth == 16 then
			return buffer.readu8(rows, row + index * 2) * 256 + buffer.readu8(rows, row + index * 2 + 1)
		end
		local bit = index * depth
		return bit32.band(bit32.rshift(buffer.readu8(rows, row + bit // 8), 8 - depth - bit % 8), maximum)
	end
	local function scaled(value: number): number
		if depth == 8 then
			return value
		elseif depth == 16 then
			return value // 256
		end
		return value * 255 // maximum
	end
	if colorType == 3 then
		if palette == nil then
			error("png: palette image without PLTE", 0)
		end
		local outChannels = if transparency ~= nil then 4 else 3
		local out = ImageModule.new(width, height, outChannels)
		local entries = buffer.len(palette) // 3
		for y = 0, height - 1 do
			for x = 0, width - 1 do
				local slot = sample(x, y, 0)
				if slot >= entries then
					error("png: palette index out of range", 0)
				end
				local offset = (y * width + x) * outChannels
				for channel = 0, 2 do
					buffer.writeu8(out.data, offset + channel, buffer.readu8(palette, slot * 3 + channel))
				end
				if transparency ~= nil then
					local alpha = if slot < buffer.len(transparency) then buffer.readu8(transparency, slot) else 255
					buffer.writeu8(out.data, offset + 3, alpha)
				end
			end
		end
		return out
	end
	local keyed = transparency ~= nil and (colorType == 0 or colorType == 2)
	local key: { number } = {}
	if keyed and transparency ~= nil then
		for channel = 0, channels - 1 do
			key[channel + 1] = buffer.readu8(transparency, channel * 2) * 256
				+ buffer.readu8(transparency, channel * 2 + 1)
		end
	end
	local outChannels = if keyed then channels + 1 else channels
	local out = ImageModule.new(width, height, outChannels)
	for y = 0, height - 1 do
		for x = 0, width - 1 do
			local offset = (y * width + x) * outChannels
			local matches = keyed
			for channel = 0, channels - 1 do
				local value = sample(x, y, channel)
				if value ~= key[channel + 1] then
					matches = false
				end
				buffer.writeu8(out.data, offset + channel, scaled(value))
			end
			if keyed then
				buffer.writeu8(out.data, offset + channels, if matches then 0 else 255)
			end
		end
	end
	return out
end

local function chunk(kind: string, body: buffer): buffer
	local length = buffer.len(body)
	local out = buffer.create(length + 12)
	writeU32(out, 0, length)
	buffer.writestring(out, 4, kind)
	buffer.copy(out, 8, body, 0, length)
	writeU32(out, 8 + length, Checksum.crc32(out, 4, length + 4))
	return out
end

function Png.encode(image: Image): buffer
	local colorType = TYPE_BY_CHANNELS[image.channels]
	if colorType == nil then
		error("png: images need 1 to 4 channels", 2)
	end
	local header = buffer.create(13)
	writeU32(header, 0, image.width)
	writeU32(header, 4, image.height)
	buffer.writeu8(header, 8, 8)
	buffer.writeu8(header, 9, colorType)
	local filtered = filterRows(image.data, image.width, image.height, image.channels)
	local compressed = Deflate.compress(filtered)
	local pieces = { chunk("IHDR", header) }
	local offset = 0
	local total = buffer.len(compressed)
	repeat
		local size = math.min(65536, total - offset)
		local part = buffer.create(size)
		buffer.copy(part, 0, compressed, offset, size)
		table.insert(pieces, chunk("IDAT", part))
		offset += size
	until offset >= total
	table.insert(pieces, chunk("IEND", buffer.create(0)))
	local length = 8
	for _, piece in pieces do
		length += buffer.len(piece)
	end
	local out = buffer.create(length)
	buffer.writestring(out, 0, SIGNATURE)
	local cursor = 8
	for _, piece in pieces do
		buffer.copy(out, cursor, piece, 0, buffer.len(piece))
		cursor += buffer.len(piece)
	end
	return out
end

return table.freeze(Png)
