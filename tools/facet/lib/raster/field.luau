--!strict
--!native

local Blur = require("./blur")
local ImageModule = require("./image")
local Numeric = require("./numeric")

type Image = ImageModule.Image

export type Field = {
	width: number,
	height: number,
	channels: number,
	data: buffer,
}

export type Color = { number }
export type Stop = { at: number, color: Color }

local Field = {}

function Field.new(width: number, height: number, channels: number?, value: number?): Field
	local count = channels or 1
	local data = buffer.create(width * height * count * 8)
	local fill = value or 0
	if fill ~= 0 then
		for index = 0, width * height * count - 1 do
			buffer.writef64(data, index * 8, fill)
		end
	end
	return { width = width, height = height, channels = count, data = data }
end

function Field.at(field: Field, x: number, y: number, channel: number?): number
	return buffer.readf64(field.data, ((y * field.width + x) * field.channels + (channel or 1) - 1) * 8)
end

function Field.set(field: Field, x: number, y: number, value: number, channel: number?)
	buffer.writef64(field.data, ((y * field.width + x) * field.channels + (channel or 1) - 1) * 8, value)
end

function Field.copy(field: Field): Field
	local data = buffer.create(buffer.len(field.data))
	buffer.copy(data, 0, field.data, 0, buffer.len(field.data))
	return { width = field.width, height = field.height, channels = field.channels, data = data }
end

function Field.generate(
	width: number,
	height: number,
	channels: number,
	compute: (x: number, y: number, channel: number) -> number
): Field
	local field = Field.new(width, height, channels)
	local data = field.data
	local offset = 0
	for y = 0, height - 1 do
		for x = 0, width - 1 do
			for channel = 1, channels do
				buffer.writef64(data, offset, compute(x, y, channel))
				offset += 8
			end
		end
	end
	return field
end

function Field.map(field: Field, transform: (value: number) -> number): Field
	local out = Field.new(field.width, field.height, field.channels)
	for index = 0, field.width * field.height * field.channels - 1 do
		buffer.writef64(out.data, index * 8, transform(buffer.readf64(field.data, index * 8)))
	end
	return out
end

function Field.zip(left: Field, right: Field, combine: (a: number, b: number) -> number): Field
	if left.width ~= right.width or left.height ~= right.height then
		error("Field.zip needs fields of the same size", 2)
	end
	local channels = math.max(left.channels, right.channels)
	if (left.channels ~= channels and left.channels ~= 1) or (right.channels ~= channels and right.channels ~= 1) then
		error("Field.zip cannot broadcast these channel counts", 2)
	end
	local out = Field.new(left.width, left.height, channels)
	for pixel = 0, left.width * left.height - 1 do
		for channel = 0, channels - 1 do
			local a =
				buffer.readf64(left.data, (pixel * left.channels + (if left.channels == 1 then 0 else channel)) * 8)
			local b =
				buffer.readf64(right.data, (pixel * right.channels + (if right.channels == 1 then 0 else channel)) * 8)
			buffer.writef64(out.data, (pixel * channels + channel) * 8, combine(a, b))
		end
	end
	return out
end

function Field.scale(field: Field, factor: number): Field
	return Field.map(field, function(value: number): number
		return value * factor
	end)
end

function Field.clip(field: Field, low: number, high: number): Field
	return Field.map(field, function(value: number): number
		return Numeric.clamp(value, low, high)
	end)
end

function Field.difference(left: Field, right: Field): Field
	return Field.zip(left, right, function(a: number, b: number): number
		return Numeric.clamp(a - b, 0, 1)
	end)
end

function Field.product(left: Field, right: Field): Field
	return Field.zip(left, right, function(a: number, b: number): number
		return a * b
	end)
end

function Field.maximum(left: Field, right: Field): Field
	return Field.zip(left, right, function(a: number, b: number): number
		return math.max(a, b)
	end)
end

function Field.shift(field: Field, dx: number, dy: number): Field
	local out = Field.new(field.width, field.height, field.channels)
	local channels = field.channels
	for y = math.max(0, dy), math.min(field.height, field.height + dy) - 1 do
		for x = math.max(0, dx), math.min(field.width, field.width + dx) - 1 do
			buffer.copy(
				out.data,
				((y * field.width + x) * channels) * 8,
				field.data,
				(((y - dy) * field.width + (x - dx)) * channels) * 8,
				channels * 8
			)
		end
	end
	return out
end

function Field.roll(field: Field, dx: number, dy: number): Field
	local out = Field.new(field.width, field.height, field.channels)
	local channels = field.channels
	for y = 0, field.height - 1 do
		for x = 0, field.width - 1 do
			local sx = (x - dx) % field.width
			local sy = (y - dy) % field.height
			buffer.copy(
				out.data,
				((y * field.width + x) * channels) * 8,
				field.data,
				((sy * field.width + sx) * channels) * 8,
				channels * 8
			)
		end
	end
	return out
end

function Field.flip(field: Field, horizontal: boolean, vertical: boolean): Field
	local out = Field.new(field.width, field.height, field.channels)
	local channels = field.channels
	for y = 0, field.height - 1 do
		for x = 0, field.width - 1 do
			local sx = if horizontal then field.width - 1 - x else x
			local sy = if vertical then field.height - 1 - y else y
			buffer.copy(
				out.data,
				((y * field.width + x) * channels) * 8,
				field.data,
				((sy * field.width + sx) * channels) * 8,
				channels * 8
			)
		end
	end
	return out
end

function Field.maximumInto(target: Field, source: Field, x0: number, y0: number)
	for y = 0, source.height - 1 do
		for x = 0, source.width - 1 do
			local current = Field.at(target, x0 + x, y0 + y)
			Field.set(target, x0 + x, y0 + y, math.max(current, Field.at(source, x, y)))
		end
	end
end

function Field.fromImage(image: Image): Field
	local count = image.width * image.height * image.channels
	local field = Field.new(image.width, image.height, image.channels)
	for index = 0, count - 1 do
		buffer.writef64(field.data, index * 8, Numeric.clamp(buffer.readu8(image.data, index) / 255.0, 0.0, 1.0))
	end
	return field
end

function Field.toBytes(field: Field): Image
	local count = field.width * field.height * field.channels
	local image = ImageModule.new(field.width, field.height, field.channels)
	for index = 0, count - 1 do
		local value = Numeric.clamp(buffer.readf64(field.data, index * 8) * 255.0 + 0.5, 0, 255)
		buffer.writeu8(image.data, index, Numeric.trunc(value))
	end
	return image
end

function Field.blur(field: Field, radius: number): Field
	if radius <= 0 then
		return field
	end
	return Field.fromImage(Blur.gaussian(Field.toBytes(field), radius))
end

function Field.emboss(mask: Field, radius: number, distance: number): (Field, Field)
	local blurred = Field.blur(mask, radius)
	local high = Field.difference(blurred, Field.shift(blurred, distance, distance))
	local low = Field.difference(blurred, Field.shift(blurred, -distance, -distance))
	return high, low
end

function Field.vgrad(width: number, height: number, stops: { Stop }): Field
	local ys = Numeric.linspace(0.0, 1.0, height)
	local positions = table.create(#stops, 0)
	for index, stop in stops do
		positions[index] = stop.at
	end
	local columns: { { number } } = {}
	for channel = 1, 3 do
		local values = table.create(#stops, 0)
		for index, stop in stops do
			values[index] = stop.color[channel]
		end
		columns[channel] = Numeric.interp(ys, positions, values)
	end
	return Field.generate(width, height, 3, function(_x: number, y: number, channel: number): number
		return columns[channel][y + 1]
	end)
end

return table.freeze(Field)
