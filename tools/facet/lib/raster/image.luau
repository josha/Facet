--!strict
--!native

export type Image = {
	width: number,
	height: number,
	channels: number,
	data: buffer,
}

local Image = {}

local function div255(value: number): number
	local shifted = value + 128
	return bit32.rshift(bit32.rshift(shifted, 8) + shifted, 8)
end

local function blend(mask: number, under: number, over: number): number
	return div255(under * (255 - mask) + over * mask)
end

Image.div255 = div255

function Image.new(width: number, height: number, channels: number, fill: { number }?): Image
	local data = buffer.create(width * height * channels)
	if fill ~= nil and width * height > 0 then
		if channels == 1 then
			buffer.fill(data, 0, fill[1])
		else
			for channel = 1, channels do
				buffer.writeu8(data, channel - 1, fill[channel])
			end
			local filled = channels
			local total = width * height * channels
			while filled < total do
				local span = math.min(filled, total - filled)
				buffer.copy(data, filled, data, 0, span)
				filled += span
			end
		end
	end
	return { width = width, height = height, channels = channels, data = data }
end

function Image.copy(image: Image): Image
	local data = buffer.create(buffer.len(image.data))
	buffer.copy(data, 0, image.data, 0, buffer.len(image.data))
	return { width = image.width, height = image.height, channels = image.channels, data = data }
end

function Image.equal(left: Image, right: Image): boolean
	return left.width == right.width
		and left.height == right.height
		and left.channels == right.channels
		and buffer.tostring(left.data) == buffer.tostring(right.data)
end

function Image.crop(image: Image, x0: number, y0: number, x1: number, y1: number): Image
	local width = math.max(0, x1 - x0)
	local height = math.max(0, y1 - y0)
	local channels = image.channels
	local out = Image.new(width, height, channels)
	local left = math.max(x0, 0)
	local right = math.min(x1, image.width)
	if right <= left then
		return out
	end
	local span = (right - left) * channels
	for y = math.max(y0, 0), math.min(y1, image.height) - 1 do
		buffer.copy(
			out.data,
			((y - y0) * width + (left - x0)) * channels,
			image.data,
			(y * image.width + left) * channels,
			span
		)
	end
	return out
end

function Image.flipLeftRight(image: Image): Image
	local out = Image.new(image.width, image.height, image.channels)
	local channels = image.channels
	local width = image.width
	for y = 0, image.height - 1 do
		local row = y * width
		for x = 0, width - 1 do
			buffer.copy(out.data, (row + width - 1 - x) * channels, image.data, (row + x) * channels, channels)
		end
	end
	return out
end

function Image.flipTopBottom(image: Image): Image
	local out = Image.new(image.width, image.height, image.channels)
	local stride = image.width * image.channels
	for y = 0, image.height - 1 do
		buffer.copy(out.data, (image.height - 1 - y) * stride, image.data, y * stride, stride)
	end
	return out
end

function Image.rotate180(image: Image): Image
	return Image.flipTopBottom(Image.flipLeftRight(image))
end

function Image.convert(image: Image, channels: number): Image
	local from = image.channels
	if from == channels then
		return Image.copy(image)
	end
	local count = image.width * image.height
	local out = Image.new(image.width, image.height, channels)
	local source = image.data
	local target = out.data
	for index = 0, count - 1 do
		local r, g, b, a
		local base = index * from
		if from == 1 then
			r = buffer.readu8(source, base)
			g, b, a = r, r, 255
		elseif from == 2 then
			r = buffer.readu8(source, base)
			g, b = r, r
			a = buffer.readu8(source, base + 1)
		elseif from == 3 then
			r = buffer.readu8(source, base)
			g = buffer.readu8(source, base + 1)
			b = buffer.readu8(source, base + 2)
			a = 255
		else
			r = buffer.readu8(source, base)
			g = buffer.readu8(source, base + 1)
			b = buffer.readu8(source, base + 2)
			a = buffer.readu8(source, base + 3)
		end
		local offset = index * channels
		if channels == 1 then
			buffer.writeu8(target, offset, bit32.rshift(r * 19595 + g * 38470 + b * 7471 + 0x8000, 16))
		elseif channels == 2 then
			buffer.writeu8(target, offset, bit32.rshift(r * 19595 + g * 38470 + b * 7471 + 0x8000, 16))
			buffer.writeu8(target, offset + 1, a)
		elseif channels == 3 then
			buffer.writeu8(target, offset, r)
			buffer.writeu8(target, offset + 1, g)
			buffer.writeu8(target, offset + 2, b)
		else
			buffer.writeu8(target, offset, r)
			buffer.writeu8(target, offset + 1, g)
			buffer.writeu8(target, offset + 2, b)
			buffer.writeu8(target, offset + 3, a)
		end
	end
	return out
end

function Image.band(image: Image, channel: number): Image
	local out = Image.new(image.width, image.height, 1)
	local channels = image.channels
	for index = 0, image.width * image.height - 1 do
		buffer.writeu8(out.data, index, buffer.readu8(image.data, index * channels + channel - 1))
	end
	return out
end

function Image.paste(target: Image, source: Image, x: number, y: number, mask: Image?)
	local channels = target.channels
	local sourceImage = source
	if source.channels ~= channels and not (channels == 3 and (source.channels == 4 or source.channels == 2)) then
		sourceImage = Image.convert(source, channels)
	end
	local sourceChannels = sourceImage.channels
	local left = math.max(0, x)
	local top = math.max(0, y)
	local right = math.min(target.width, x + source.width)
	local bottom = math.min(target.height, y + source.height)
	if right <= left or bottom <= top then
		return
	end
	local targetData = target.data
	local sourceData = sourceImage.data
	if mask == nil then
		if sourceChannels == channels then
			local span = (right - left) * channels
			for row = top, bottom - 1 do
				buffer.copy(
					targetData,
					(row * target.width + left) * channels,
					sourceData,
					((row - y) * source.width + (left - x)) * channels,
					span
				)
			end
		else
			for row = top, bottom - 1 do
				for column = left, right - 1 do
					local out = (row * target.width + column) * channels
					local from = ((row - y) * source.width + (column - x)) * sourceChannels
					for channel = 0, channels - 1 do
						buffer.writeu8(targetData, out + channel, buffer.readu8(sourceData, from + channel))
					end
				end
			end
		end
		return
	end
	local maskChannels = mask.channels
	local maskOffset = if maskChannels == 4 then 3 elseif maskChannels == 2 then 1 else 0
	local maskData = mask.data
	for row = top, bottom - 1 do
		for column = left, right - 1 do
			local index = (row - y) * source.width + (column - x)
			local alpha = buffer.readu8(maskData, index * maskChannels + maskOffset)
			local out = (row * target.width + column) * channels
			local from = index * sourceChannels
			for channel = 0, channels - 1 do
				buffer.writeu8(
					targetData,
					out + channel,
					blend(alpha, buffer.readu8(targetData, out + channel), buffer.readu8(sourceData, from + channel))
				)
			end
		end
	end
end

function Image.alphaComposite(target: Image, source: Image, x: number?, y: number?)
	if target.channels ~= 4 or source.channels ~= 4 then
		error("alphaComposite needs two RGBA images", 2)
	end
	local dx = x or 0
	local dy = y or 0
	local left = math.max(0, dx)
	local top = math.max(0, dy)
	local right = math.min(target.width, dx + source.width)
	local bottom = math.min(target.height, dy + source.height)
	local targetData = target.data
	local sourceData = source.data
	for row = top, bottom - 1 do
		for column = left, right - 1 do
			local from = ((row - dy) * source.width + (column - dx)) * 4
			local sa = buffer.readu8(sourceData, from + 3)
			if sa ~= 0 then
				local out = (row * target.width + column) * 4
				local da = buffer.readu8(targetData, out + 3)
				local blendWeight = da * (255 - sa)
				local outa255 = sa * 255 + blendWeight
				local coef1 = (sa * 255 * 255 * 128) // outa255
				local coef2 = 255 * 128 - coef1
				for channel = 0, 2 do
					local value = buffer.readu8(sourceData, from + channel) * coef1
						+ buffer.readu8(targetData, out + channel) * coef2
						+ 0x80 * 128
					buffer.writeu8(
						targetData,
						out + channel,
						bit32.rshift(bit32.rshift(bit32.rshift(value, 8) + value, 8), 7)
					)
				end
				local alpha = outa255 + 0x80
				buffer.writeu8(targetData, out + 3, bit32.rshift(bit32.rshift(alpha, 8) + alpha, 8))
			end
		end
	end
end

function Image.composite(over: Image, under: Image, mask: Image): Image
	local out = Image.copy(under)
	Image.paste(out, over, 0, 0, mask)
	return out
end

return table.freeze(Image)
