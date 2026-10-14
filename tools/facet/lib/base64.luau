--!strict

local Base64 = {}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local values: { [number]: number } = {}
for index = 1, #ALPHABET do
	values[string.byte(ALPHABET, index)] = index - 1
end

local PAD = string.byte("=")

function Base64.decode(text: string): string
	local sextets: { number } = {}
	local padding = 0
	for index = 1, #text do
		local byte = string.byte(text, index)
		local value = values[byte]
		if value ~= nil then
			if padding > 0 then
				error("base64: data continues after padding", 0)
			end
			table.insert(sextets, value)
		elseif byte == PAD then
			padding += 1
		end
	end
	local remainder = #sextets % 4
	if remainder == 1 or (remainder > 0 and remainder + padding < 4) then
		error("base64: incorrect padding", 0)
	end
	local output = buffer.create(math.floor(#sextets * 3 / 4))
	local written = 0
	local index = 1
	while index + 3 <= #sextets do
		local group = sextets[index] * 262144 + sextets[index + 1] * 4096 + sextets[index + 2] * 64 + sextets[index + 3]
		buffer.writeu8(output, written, bit32.rshift(group, 16))
		buffer.writeu8(output, written + 1, bit32.band(bit32.rshift(group, 8), 0xFF))
		buffer.writeu8(output, written + 2, bit32.band(group, 0xFF))
		written += 3
		index += 4
	end
	if remainder >= 2 then
		local group = sextets[index] * 262144 + sextets[index + 1] * 4096
		if remainder == 3 then
			group += sextets[index + 2] * 64
		end
		buffer.writeu8(output, written, bit32.rshift(group, 16))
		written += 1
		if remainder == 3 then
			buffer.writeu8(output, written, bit32.band(bit32.rshift(group, 8), 0xFF))
			written += 1
		end
	end
	return buffer.readstring(output, 0, written)
end

local function letter(value: number): string
	return string.sub(ALPHABET, value + 1, value + 1)
end

function Base64.encode(data: string): string
	local parts: { string } = {}
	for index = 1, #data, 3 do
		local first, second, third = string.byte(data, index, index + 2)
		local group = first * 65536 + (second or 0) * 256 + (third or 0)
		table.insert(
			parts,
			letter(bit32.rshift(group, 18))
				.. letter(bit32.band(bit32.rshift(group, 12), 63))
				.. (if second ~= nil then letter(bit32.band(bit32.rshift(group, 6), 63)) else "=")
				.. (if third ~= nil then letter(bit32.band(group, 63)) else "=")
		)
	end
	return table.concat(parts)
end

return table.freeze(Base64)
