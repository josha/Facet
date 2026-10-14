--!strict
--!native

local CRC_TABLE = buffer.create(1024)
for value = 0, 255 do
	local crc = value
	for _ = 1, 8 do
		if bit32.band(crc, 1) ~= 0 then
			crc = bit32.bxor(0xEDB88320, bit32.rshift(crc, 1))
		else
			crc = bit32.rshift(crc, 1)
		end
	end
	buffer.writeu32(CRC_TABLE, value * 4, crc)
end

local Checksum = {}

function Checksum.crc32(data: buffer, offset: number?, length: number?, previous: number?): number
	local start = offset or 0
	local stop = start + (length or (buffer.len(data) - start)) - 1
	local crc = bit32.bnot(previous or 0)
	for index = start, stop do
		local slot = bit32.band(bit32.bxor(crc, buffer.readu8(data, index)), 0xFF)
		crc = bit32.bxor(buffer.readu32(CRC_TABLE, slot * 4), bit32.rshift(crc, 8))
	end
	return bit32.bnot(crc)
end

function Checksum.adler32(data: buffer, offset: number?, length: number?, previous: number?): number
	local start = offset or 0
	local remaining = length or (buffer.len(data) - start)
	local seed = previous or 1
	local a = seed % 65536
	local b = seed // 65536
	local index = start
	while remaining > 0 do
		local chunk = math.min(remaining, 5552)
		for position = index, index + chunk - 1 do
			a += buffer.readu8(data, position)
			b += a
		end
		a %= 65521
		b %= 65521
		index += chunk
		remaining -= chunk
	end
	return b * 65536 + a
end

function Checksum.hex(digest: buffer): string
	local parts = table.create(buffer.len(digest), "")
	for index = 0, buffer.len(digest) - 1 do
		parts[index + 1] = string.format("%02x", buffer.readu8(digest, index))
	end
	return table.concat(parts)
end

return table.freeze(Checksum)
