--!strict
--!native

export type Options = { chain: number?, nice: number?, stored: boolean? }

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

local function crc32(data: buffer, offset: number?, length: number?, previous: number?): number
	local start = offset or 0
	local stop = start + (length or (buffer.len(data) - start)) - 1
	local crc = bit32.bnot(previous or 0)
	for index = start, stop do
		local slot = bit32.band(bit32.bxor(crc, buffer.readu8(data, index)), 0xFF)
		crc = bit32.bxor(buffer.readu32(CRC_TABLE, slot * 4), bit32.rshift(crc, 8))
	end
	return bit32.bnot(crc)
end

local function adler32(data: buffer, offset: number?, length: number?, previous: number?): number
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

local LENGTH_BASE = {
	3,
	4,
	5,
	6,
	7,
	8,
	9,
	10,
	11,
	13,
	15,
	17,
	19,
	23,
	27,
	31,
	35,
	43,
	51,
	59,
	67,
	83,
	99,
	115,
	131,
	163,
	195,
	227,
	258,
}
local LENGTH_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DISTANCE_BASE = {
	1,
	2,
	3,
	4,
	5,
	7,
	9,
	13,
	17,
	25,
	33,
	49,
	65,
	97,
	129,
	193,
	257,
	385,
	513,
	769,
	1025,
	1537,
	2049,
	3073,
	4097,
	6145,
	8193,
	12289,
	16385,
	24577,
}
local DISTANCE_EXTRA =
	{ 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CODE_LENGTH_ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

local LENGTH_CODE = buffer.create(259)
for code = 1, 29 do
	local base = LENGTH_BASE[code]
	local span = if code == 29 then 1 else 2 ^ LENGTH_EXTRA[code]
	for length = base, math.min(258, base + span - 1) do
		buffer.writeu8(LENGTH_CODE, length, code - 1)
	end
end
buffer.writeu8(LENGTH_CODE, 258, 28)

local DISTANCE_CODE = buffer.create(32769)
for code = 1, 30 do
	local base = DISTANCE_BASE[code]
	for distance = base, math.min(32768, base + 2 ^ DISTANCE_EXTRA[code] - 1) do
		buffer.writeu8(DISTANCE_CODE, distance, code - 1)
	end
end

type Table = { entries: buffer, bits: number, mask: number }

local function reverseBits(code: number, length: number): number
	local reversed = 0
	for _ = 1, length do
		reversed = reversed * 2 + bit32.band(code, 1)
		code = bit32.rshift(code, 1)
	end
	return reversed
end

local function buildTable(lengths: { number }, first: number, count: number): Table
	local counts = table.create(16, 0)
	local maxBits = 0
	for index = first, first + count - 1 do
		local length = lengths[index]
		if length > 0 then
			counts[length] += 1
			if length > maxBits then
				maxBits = length
			end
		end
	end
	if maxBits == 0 then
		return { entries = buffer.create(4), bits = 0, mask = 0 }
	end
	local left = 1
	for length = 1, 15 do
		left = left * 2 - counts[length]
		if left < 0 then
			error("deflate: an over-subscribed Huffman code", 0)
		end
	end
	local nextCode = table.create(16, 0)
	local code = 0
	for length = 1, 15 do
		code = (code + (counts[length - 1] or 0)) * 2
		nextCode[length] = code
	end
	local size = 2 ^ maxBits
	local entries = buffer.create(size * 4)
	for symbol = 0, count - 1 do
		local length = lengths[first + symbol]
		if length > 0 then
			local assigned = nextCode[length]
			nextCode[length] = assigned + 1
			local step = 2 ^ length
			local value = symbol * 16 + length
			local slot = reverseBits(assigned, length)
			while slot < size do
				buffer.writeu32(entries, slot * 4, value)
				slot += step
			end
		end
	end
	return { entries = entries, bits = maxBits, mask = size - 1 }
end

local FIXED_LITERAL: Table
local FIXED_DISTANCE: Table
do
	local lengths = table.create(288, 0)
	for symbol = 0, 287 do
		lengths[symbol + 1] = if symbol < 144 then 8 elseif symbol < 256 then 9 elseif symbol < 280 then 7 else 8
	end
	FIXED_LITERAL = buildTable(lengths, 1, 288)
	FIXED_DISTANCE = buildTable(table.create(30, 5), 1, 30)
end

local function inflate(data: buffer, offset: number?, expected: number?): (buffer, number)
	local length = buffer.len(data)
	local position = offset or 0
	local bits = 0
	local count = 0
	local capacity = math.max(expected or 0, 1024)
	local out = buffer.create(capacity)
	local written = 0

	local function fill(width: number)
		while count < width and position < length do
			bits += bit32.lshift(buffer.readu8(data, position), count)
			position += 1
			count += 8
		end
	end

	local function take(width: number): number
		if count < width then
			fill(width)
			if count < width then
				error("deflate: the stream ends early", 0)
			end
		end
		local value = bit32.band(bits, 2 ^ width - 1)
		bits = bit32.rshift(bits, width)
		count -= width
		return value
	end

	local function reserve(extra: number)
		if written + extra > capacity then
			while written + extra > capacity do
				capacity *= 2
			end
			local grown = buffer.create(capacity)
			buffer.copy(grown, 0, out, 0, written)
			out = grown
		end
	end

	local function decode(huffman: Table): number
		local width = huffman.bits
		if width == 0 then
			error("deflate: an empty Huffman code is used", 0)
		end
		if count < width then
			fill(width)
		end
		local entry = buffer.readu32(huffman.entries, bit32.band(bits, huffman.mask) * 4)
		local used = bit32.band(entry, 15)
		if used == 0 then
			error("deflate: an invalid Huffman code", 0)
		elseif used > count then
			error("deflate: the stream ends early", 0)
		end
		bits = bit32.rshift(bits, used)
		count -= used
		return bit32.rshift(entry, 4)
	end

	local final = false
	while not final do
		final = take(1) == 1
		local kind = take(2)
		if kind == 0 then
			position -= count // 8
			bits = 0
			count = 0
			if position + 4 > length then
				error("deflate: the stream ends early", 0)
			end
			local size = buffer.readu16(data, position)
			if bit32.bxor(size, buffer.readu16(data, position + 2)) ~= 0xFFFF then
				error("deflate: a stored block length does not match its complement", 0)
			end
			position += 4
			if position + size > length then
				error("deflate: the stream ends early", 0)
			end
			reserve(size)
			buffer.copy(out, written, data, position, size)
			written += size
			position += size
		elseif kind == 1 or kind == 2 then
			local literalTable = FIXED_LITERAL
			local distanceTable = FIXED_DISTANCE
			if kind == 2 then
				local literalCount = take(5) + 257
				local distanceCount = take(5) + 1
				local codeCount = take(4) + 4
				if literalCount > 286 or distanceCount > 30 then
					error("deflate: too many length or distance symbols", 0)
				end
				local codeLengths = table.create(19, 0)
				for index = 1, codeCount do
					codeLengths[CODE_LENGTH_ORDER[index] + 1] = take(3)
				end
				local codeTable = buildTable(codeLengths, 1, 19)
				local total = literalCount + distanceCount
				local lengths = table.create(total, 0)
				local index = 1
				while index <= total do
					local symbol = decode(codeTable)
					if symbol < 16 then
						lengths[index] = symbol
						index += 1
					else
						local repeatValue = 0
						local repeatCount
						if symbol == 16 then
							if index == 1 then
								error("deflate: a repeat code has no previous length", 0)
							end
							repeatValue = lengths[index - 1]
							repeatCount = 3 + take(2)
						elseif symbol == 17 then
							repeatCount = 3 + take(3)
						else
							repeatCount = 11 + take(7)
						end
						if index + repeatCount - 1 > total then
							error("deflate: the code lengths overrun their count", 0)
						end
						for _ = 1, repeatCount do
							lengths[index] = repeatValue
							index += 1
						end
					end
				end
				if lengths[257] == 0 then
					error("deflate: the literal code has no end-of-block symbol", 0)
				end
				literalTable = buildTable(lengths, 1, literalCount)
				distanceTable = buildTable(lengths, literalCount + 1, distanceCount)
			end
			while true do
				local symbol = decode(literalTable)
				if symbol < 256 then
					if written >= capacity then
						reserve(1)
					end
					buffer.writeu8(out, written, symbol)
					written += 1
				elseif symbol == 256 then
					break
				else
					local code = symbol - 256
					if code > 29 then
						error("deflate: an invalid length symbol", 0)
					end
					local extra = LENGTH_EXTRA[code]
					local size = LENGTH_BASE[code] + (if extra > 0 then take(extra) else 0)
					local distanceSymbol = decode(distanceTable) + 1
					if distanceSymbol > 30 then
						error("deflate: an invalid distance symbol", 0)
					end
					local distanceExtra = DISTANCE_EXTRA[distanceSymbol]
					local distance = DISTANCE_BASE[distanceSymbol]
						+ (if distanceExtra > 0 then take(distanceExtra) else 0)
					if distance > written then
						error("deflate: a distance reaches before the start of the output", 0)
					end
					reserve(size)
					if distance >= size then
						buffer.copy(out, written, out, written - distance, size)
						written += size
					else
						for _ = 1, size do
							buffer.writeu8(out, written, buffer.readu8(out, written - distance))
							written += 1
						end
					end
				end
			end
		else
			error("deflate: an invalid block type", 0)
		end
	end
	local consumed = position - count // 8
	if written == capacity then
		return out, consumed
	end
	local exact = buffer.create(written)
	buffer.copy(exact, 0, out, 0, written)
	return exact, consumed
end

type Writer = {
	out: buffer,
	size: number,
	bits: number,
	count: number,
}

local function writerNew(capacity: number): Writer
	return { out = buffer.create(math.max(capacity, 64)), size = 0, bits = 0, count = 0 }
end

local function ensure(writer: Writer, extra: number)
	local capacity = buffer.len(writer.out)
	if writer.size + extra > capacity then
		while writer.size + extra > capacity do
			capacity *= 2
		end
		local grown = buffer.create(capacity)
		buffer.copy(grown, 0, writer.out, 0, writer.size)
		writer.out = grown
	end
end

local function putBits(writer: Writer, value: number, width: number)
	writer.bits += value * 2 ^ writer.count
	writer.count += width
	if writer.count >= 8 then
		ensure(writer, 4)
		local out = writer.out
		while writer.count >= 8 do
			buffer.writeu8(out, writer.size, writer.bits % 256)
			writer.size += 1
			writer.bits = writer.bits // 256
			writer.count -= 8
		end
	end
end

local function alignByte(writer: Writer)
	if writer.count > 0 then
		putBits(writer, 0, 8 - writer.count)
	end
end

local function huffmanLengths(frequencies: { number }, limit: number): { number }
	local symbolCount = #frequencies
	local lengths = table.create(symbolCount, 0)
	local used: { number } = {}
	for symbol = 1, symbolCount do
		if frequencies[symbol] > 0 then
			table.insert(used, symbol)
		end
	end
	if #used == 0 then
		return lengths
	elseif #used == 1 then
		lengths[used[1]] = 1
		return lengths
	end
	table.sort(used, function(left: number, right: number): boolean
		local a = frequencies[left]
		local b = frequencies[right]
		if a == b then
			return left < right
		end
		return a < b
	end)
	local leafCount = #used
	local weight = table.create(leafCount * 2, 0)
	local parent = table.create(leafCount * 2, 0)
	for index = 1, leafCount do
		weight[index] = frequencies[used[index]]
	end
	local nextLeaf = 1
	local nextInternal = leafCount + 1
	local created = leafCount
	local function smallest(): number
		if nextLeaf <= leafCount and (nextInternal > created or weight[nextLeaf] <= weight[nextInternal]) then
			nextLeaf += 1
			return nextLeaf - 1
		end
		nextInternal += 1
		return nextInternal - 1
	end
	for _ = 1, leafCount - 1 do
		local first = smallest()
		local second = smallest()
		created += 1
		weight[created] = weight[first] + weight[second]
		parent[first] = created
		parent[second] = created
	end
	local depth = table.create(created, 0)
	for node = created - 1, 1, -1 do
		depth[node] = depth[parent[node]] + 1
	end
	local perLength = table.create(64, 0)
	local deepest = 0
	for index = 1, leafCount do
		local d = depth[index]
		perLength[d] += 1
		if d > deepest then
			deepest = d
		end
	end
	if deepest > limit then
		for d = limit + 1, deepest do
			perLength[limit] += perLength[d]
			perLength[d] = 0
		end
		local total = 0
		for d = limit, 1, -1 do
			total += perLength[d] * 2 ^ (limit - d)
		end
		while total ~= 2 ^ limit do
			perLength[limit] -= 1
			for d = limit - 1, 1, -1 do
				if perLength[d] > 0 then
					perLength[d] -= 1
					perLength[d + 1] += 2
					break
				end
			end
			total -= 1
		end
	end
	local cursor = leafCount
	for d = 1, limit do
		for _ = 1, perLength[d] do
			lengths[used[cursor]] = d
			cursor -= 1
		end
	end
	return lengths
end

local function canonicalCodes(lengths: { number }): { number }
	local counts = table.create(16, 0)
	for _, length in lengths do
		if length > 0 then
			counts[length] += 1
		end
	end
	local nextCode = table.create(16, 0)
	local code = 0
	for length = 1, 15 do
		code = (code + (counts[length - 1] or 0)) * 2
		nextCode[length] = code
	end
	local codes = table.create(#lengths, 0)
	for symbol, length in lengths do
		if length > 0 then
			codes[symbol] = reverseBits(nextCode[length], length)
			nextCode[length] += 1
		end
	end
	return codes
end

type Block = {
	symbols: buffer,
	distances: buffer,
	count: number,
	start: number,
	stop: number,
}

local function codeLengthRuns(lengths: { number }): ({ number }, { number })
	local symbols: { number } = {}
	local extras: { number } = {}
	local total = #lengths
	local index = 1
	while index <= total do
		local value = lengths[index]
		local run = 1
		while index + run <= total and lengths[index + run] == value do
			run += 1
		end
		if value == 0 then
			local remaining = run
			while remaining > 0 do
				if remaining >= 11 then
					local take = math.min(remaining, 138)
					table.insert(symbols, 18)
					table.insert(extras, take - 11)
					remaining -= take
				elseif remaining >= 3 then
					table.insert(symbols, 17)
					table.insert(extras, remaining - 3)
					remaining = 0
				else
					table.insert(symbols, 0)
					table.insert(extras, 0)
					remaining -= 1
				end
			end
		else
			table.insert(symbols, value)
			table.insert(extras, 0)
			local remaining = run - 1
			while remaining > 0 do
				if remaining >= 3 then
					local take = math.min(remaining, 6)
					table.insert(symbols, 16)
					table.insert(extras, take - 3)
					remaining -= take
				else
					table.insert(symbols, value)
					table.insert(extras, 0)
					remaining -= 1
				end
			end
		end
		index += run
	end
	return symbols, extras
end

local FIXED_LITERAL_LENGTHS = table.create(288, 0)
for symbol = 0, 287 do
	FIXED_LITERAL_LENGTHS[symbol + 1] = if symbol < 144
		then 8
		elseif symbol < 256 then 9
		elseif symbol < 280 then 7
		else 8
end
local FIXED_DISTANCE_LENGTHS = table.create(30, 5)
local FIXED_LITERAL_CODES = canonicalCodes(FIXED_LITERAL_LENGTHS)
local FIXED_DISTANCE_CODES = canonicalCodes(FIXED_DISTANCE_LENGTHS)

local function writeSymbols(
	writer: Writer,
	block: Block,
	literalLengths: { number },
	literalCodes: { number },
	distanceLengths: { number },
	distanceCodes: { number }
)
	local symbols = block.symbols
	local distances = block.distances
	for index = 0, block.count - 1 do
		local symbol = buffer.readu16(symbols, index * 2)
		if symbol < 256 then
			putBits(writer, literalCodes[symbol + 1], literalLengths[symbol + 1])
		else
			local size = symbol - 256
			local code = buffer.readu8(LENGTH_CODE, size)
			putBits(writer, literalCodes[code + 258], literalLengths[code + 258])
			local extra = LENGTH_EXTRA[code + 1]
			if extra > 0 then
				putBits(writer, size - LENGTH_BASE[code + 1], extra)
			end
			local distance = buffer.readu16(distances, index * 2)
			local distanceCode = buffer.readu8(DISTANCE_CODE, distance)
			putBits(writer, distanceCodes[distanceCode + 1], distanceLengths[distanceCode + 1])
			local distanceExtra = DISTANCE_EXTRA[distanceCode + 1]
			if distanceExtra > 0 then
				putBits(writer, distance - DISTANCE_BASE[distanceCode + 1], distanceExtra)
			end
		end
	end
	putBits(writer, literalCodes[257], literalLengths[257])
end

local function flushBlock(writer: Writer, block: Block, input: buffer, final: boolean)
	local literalFrequency = table.create(286, 0)
	local distanceFrequency = table.create(30, 0)
	local symbols = block.symbols
	local distances = block.distances
	local extraBits = 0
	for index = 0, block.count - 1 do
		local symbol = buffer.readu16(symbols, index * 2)
		if symbol < 256 then
			literalFrequency[symbol + 1] += 1
		else
			local code = buffer.readu8(LENGTH_CODE, symbol - 256)
			literalFrequency[code + 258] += 1
			extraBits += LENGTH_EXTRA[code + 1]
			local distanceCode = buffer.readu8(DISTANCE_CODE, buffer.readu16(distances, index * 2))
			distanceFrequency[distanceCode + 1] += 1
			extraBits += DISTANCE_EXTRA[distanceCode + 1]
		end
	end
	literalFrequency[257] += 1
	local literalUsed = 0
	for _, frequency in literalFrequency do
		if frequency > 0 then
			literalUsed += 1
		end
	end
	if literalUsed < 2 then
		if literalFrequency[1] == 0 then
			literalFrequency[1] = 1
		else
			literalFrequency[2] = 1
		end
	end
	local distanceUsed = 0
	for _, frequency in distanceFrequency do
		if frequency > 0 then
			distanceUsed += 1
		end
	end
	if distanceUsed < 2 then
		if distanceFrequency[1] == 0 then
			distanceFrequency[1] = 1
		else
			distanceFrequency[2] = 1
		end
	end
	local literalLengths = huffmanLengths(literalFrequency, 15)
	local distanceLengths = huffmanLengths(distanceFrequency, 15)
	local literalCount = 286
	while literalCount > 257 and literalLengths[literalCount] == 0 do
		literalCount -= 1
	end
	local distanceCount = 30
	while distanceCount > 1 and distanceLengths[distanceCount] == 0 do
		distanceCount -= 1
	end
	local combined = table.create(literalCount + distanceCount, 0)
	for index = 1, literalCount do
		combined[index] = literalLengths[index]
	end
	for index = 1, distanceCount do
		combined[literalCount + index] = distanceLengths[index]
	end
	local runSymbols, runExtras = codeLengthRuns(combined)
	local codeFrequency = table.create(19, 0)
	for _, symbol in runSymbols do
		codeFrequency[symbol + 1] += 1
	end
	local codeUsed = 0
	for _, frequency in codeFrequency do
		if frequency > 0 then
			codeUsed += 1
		end
	end
	if codeUsed < 2 then
		if codeFrequency[1] == 0 then
			codeFrequency[1] = 1
		else
			codeFrequency[2] = 1
		end
	end
	local codeLengths = huffmanLengths(codeFrequency, 7)
	local codeCount = 19
	while codeCount > 4 and codeLengths[CODE_LENGTH_ORDER[codeCount] + 1] == 0 do
		codeCount -= 1
	end

	local dynamicBits = 3 + 5 + 5 + 4 + codeCount * 3 + extraBits
	for _, symbol in runSymbols do
		dynamicBits += codeLengths[symbol + 1]
		if symbol == 16 then
			dynamicBits += 2
		elseif symbol == 17 then
			dynamicBits += 3
		elseif symbol == 18 then
			dynamicBits += 7
		end
	end
	local fixedBits = 3 + extraBits
	for symbol = 1, 286 do
		local frequency = literalFrequency[symbol]
		dynamicBits += frequency * literalLengths[symbol]
		fixedBits += frequency * FIXED_LITERAL_LENGTHS[symbol]
	end
	for symbol = 1, 30 do
		local frequency = distanceFrequency[symbol]
		dynamicBits += frequency * distanceLengths[symbol]
		fixedBits += frequency * 5
	end
	local rawLength = block.stop - block.start
	local storedChunks = math.max(1, math.ceil(rawLength / 65535))
	local storedBits = storedChunks * 40 + rawLength * 8 + 8

	if storedBits <= dynamicBits and storedBits <= fixedBits then
		local cursor = block.start
		for chunk = 1, storedChunks do
			local size = math.min(65535, block.stop - cursor)
			putBits(writer, if final and chunk == storedChunks then 1 else 0, 1)
			putBits(writer, 0, 2)
			alignByte(writer)
			ensure(writer, size + 4)
			buffer.writeu16(writer.out, writer.size, size)
			buffer.writeu16(writer.out, writer.size + 2, bit32.bxor(size, 0xFFFF))
			buffer.copy(writer.out, writer.size + 4, input, cursor, size)
			writer.size += size + 4
			cursor += size
		end
	elseif fixedBits <= dynamicBits then
		putBits(writer, if final then 1 else 0, 1)
		putBits(writer, 1, 2)
		writeSymbols(
			writer,
			block,
			FIXED_LITERAL_LENGTHS,
			FIXED_LITERAL_CODES,
			FIXED_DISTANCE_LENGTHS,
			FIXED_DISTANCE_CODES
		)
	else
		putBits(writer, if final then 1 else 0, 1)
		putBits(writer, 2, 2)
		putBits(writer, literalCount - 257, 5)
		putBits(writer, distanceCount - 1, 5)
		putBits(writer, codeCount - 4, 4)
		for index = 1, codeCount do
			putBits(writer, codeLengths[CODE_LENGTH_ORDER[index] + 1], 3)
		end
		local codeCodes = canonicalCodes(codeLengths)
		for index, symbol in runSymbols do
			putBits(writer, codeCodes[symbol + 1], codeLengths[symbol + 1])
			if symbol == 16 then
				putBits(writer, runExtras[index], 2)
			elseif symbol == 17 then
				putBits(writer, runExtras[index], 3)
			elseif symbol == 18 then
				putBits(writer, runExtras[index], 7)
			end
		end
		writeSymbols(
			writer,
			block,
			literalLengths,
			canonicalCodes(literalLengths),
			distanceLengths,
			canonicalCodes(distanceLengths)
		)
	end
end

local WINDOW = 32768
local HASH_SIZE = 32768
local MAX_MATCH = 258
local MIN_MATCH = 3
local BLOCK_SYMBOLS = 32768

local function deflateRaw(input: buffer, options: Options?): buffer
	local size = buffer.len(input)
	local chainLimit = if options and options.chain then options.chain else 256
	local niceLength = if options and options.nice then options.nice else 258
	local writer = writerNew(size // 2 + 64)
	local head = buffer.create(HASH_SIZE * 4)
	buffer.fill(head, 0, 0xFF)
	local previous = buffer.create(WINDOW * 4)
	local block: Block = {
		symbols = buffer.create(BLOCK_SYMBOLS * 2),
		distances = buffer.create(BLOCK_SYMBOLS * 2),
		count = 0,
		start = 0,
		stop = 0,
	}

	local function hashAt(position: number): number
		return bit32.band(
			bit32.bxor(
				bit32.lshift(buffer.readu8(input, position), 10),
				bit32.lshift(buffer.readu8(input, position + 1), 5),
				buffer.readu8(input, position + 2)
			),
			HASH_SIZE - 1
		)
	end

	local function insert(position: number)
		if position + MIN_MATCH <= size then
			local hash = hashAt(position)
			buffer.writei32(previous, (position % WINDOW) * 4, buffer.readi32(head, hash * 4))
			buffer.writei32(head, hash * 4, position)
		end
	end

	local function findMatch(position: number): (number, number)
		if position + MIN_MATCH > size then
			return 0, 0
		end
		local candidate = buffer.readi32(head, hashAt(position) * 4)
		local bestLength = MIN_MATCH - 1
		local bestDistance = 0
		local limit = math.min(MAX_MATCH, size - position)
		local chain = chainLimit
		while candidate >= 0 and position - candidate <= WINDOW and chain > 0 do
			if
				buffer.readu8(input, candidate + bestLength) == buffer.readu8(input, position + bestLength)
				and buffer.readu8(input, candidate) == buffer.readu8(input, position)
			then
				local length = 0
				while
					length < limit
					and buffer.readu8(input, candidate + length) == buffer.readu8(input, position + length)
				do
					length += 1
				end
				if length > bestLength then
					bestLength = length
					bestDistance = position - candidate
					if length >= niceLength or length >= limit then
						break
					end
				end
			end
			local older = buffer.readi32(previous, (candidate % WINDOW) * 4)
			if older >= candidate then
				break
			end
			candidate = older
			chain -= 1
		end
		if bestLength >= MIN_MATCH then
			return bestLength, bestDistance
		end
		return 0, 0
	end

	local function emit(symbol: number, distance: number, stop: number)
		buffer.writeu16(block.symbols, block.count * 2, symbol)
		buffer.writeu16(block.distances, block.count * 2, distance)
		block.count += 1
		block.stop = stop
		if block.count >= BLOCK_SYMBOLS then
			flushBlock(writer, block, input, false)
			block.count = 0
			block.start = stop
		end
	end

	local position = 0
	local cachedLength = -1
	local cachedDistance = 0
	while position < size do
		local length, distance
		if cachedLength >= 0 then
			length, distance = cachedLength, cachedDistance
			cachedLength = -1
		else
			length, distance = findMatch(position)
		end
		insert(position)
		if length >= MIN_MATCH and length < niceLength and position + 1 < size then
			local nextLength, nextDistance = findMatch(position + 1)
			if nextLength > length then
				cachedLength, cachedDistance = nextLength, nextDistance
				emit(buffer.readu8(input, position), 0, position + 1)
				position += 1
				continue
			end
		end
		if length >= MIN_MATCH then
			emit(256 + length, distance, position + length)
			for offset = 1, length - 1 do
				insert(position + offset)
			end
			position += length
		else
			emit(buffer.readu8(input, position), 0, position + 1)
			position += 1
		end
	end
	block.stop = size
	flushBlock(writer, block, input, true)
	alignByte(writer)
	local result = buffer.create(writer.size)
	buffer.copy(result, 0, writer.out, 0, writer.size)
	return result
end

local function store(input: buffer): buffer
	local size = buffer.len(input)
	local blocks = math.max(1, math.ceil(size / 65535))
	local out = buffer.create(size + blocks * 5)
	local cursor = 0
	local offset = 0
	for block = 1, blocks do
		local piece = math.min(65535, size - offset)
		buffer.writeu8(out, cursor, if block == blocks then 1 else 0)
		buffer.writeu16(out, cursor + 1, piece)
		buffer.writeu16(out, cursor + 3, bit32.bxor(piece, 0xFFFF))
		buffer.copy(out, cursor + 5, input, offset, piece)
		cursor += 5 + piece
		offset += piece
	end
	return out
end

local function deflate(input: buffer, options: Options?): buffer
	if options ~= nil and options.stored == true then
		return store(input)
	end
	return deflateRaw(input, options)
end

local function compress(input: buffer, options: Options?): buffer
	local raw = deflate(input, options)
	local size = buffer.len(raw)
	local result = buffer.create(size + 6)
	buffer.writeu8(result, 0, 0x78)
	buffer.writeu8(result, 1, if options ~= nil and options.stored == true then 0x01 else 0xDA)
	buffer.copy(result, 2, raw, 0, size)
	local adler = adler32(input)
	buffer.writeu8(result, size + 2, bit32.rshift(adler, 24))
	buffer.writeu8(result, size + 3, bit32.band(bit32.rshift(adler, 16), 0xFF))
	buffer.writeu8(result, size + 4, bit32.band(bit32.rshift(adler, 8), 0xFF))
	buffer.writeu8(result, size + 5, bit32.band(adler, 0xFF))
	return result
end

local function decompress(input: buffer, expected: number?): buffer
	local length = buffer.len(input)
	if length < 2 then
		error("zlib: the stream ends early", 0)
	end
	local method = buffer.readu8(input, 0)
	local flags = buffer.readu8(input, 1)
	if bit32.band(method, 0x0F) ~= 8 or (method * 256 + flags) % 31 ~= 0 then
		error("zlib: incorrect header check", 0)
	end
	if bit32.band(flags, 0x20) ~= 0 then
		error("zlib: a preset dictionary is not supported", 0)
	end
	local out, consumed = inflate(input, 2, expected or length * 4)
	if consumed + 4 > length then
		error("zlib: the Adler-32 trailer ends early", 0)
	end
	local recorded = buffer.readu8(input, consumed) * 16777216
		+ buffer.readu8(input, consumed + 1) * 65536
		+ buffer.readu8(input, consumed + 2) * 256
		+ buffer.readu8(input, consumed + 3)
	if recorded ~= adler32(out) then
		error("zlib: the Adler-32 checksum does not match", 0)
	end
	return out
end

local GZIP_HEADER = "\x1f\x8b\x08\x00\x00\x00\x00\x00\x00\xff"
local GZIP_HEADER_CRC = 2
local GZIP_EXTRA = 4
local GZIP_NAME = 8
local GZIP_COMMENT = 16

local function gzip(input: buffer, options: Options?): buffer
	local raw = deflate(input, options)
	local size = buffer.len(raw)
	local result = buffer.create(size + 18)
	buffer.writestring(result, 0, GZIP_HEADER)
	buffer.copy(result, 10, raw, 0, size)
	buffer.writeu32(result, size + 10, crc32(input))
	buffer.writeu32(result, size + 14, buffer.len(input) % 0x100000000)
	return result
end

local function skipText(input: buffer, position: number): number
	local length = buffer.len(input)
	while position < length and buffer.readu8(input, position) ~= 0 do
		position += 1
	end
	if position >= length then
		error("gzip: the header ends early", 0)
	end
	return position + 1
end

local function gunzip(input: buffer): buffer
	local length = buffer.len(input)
	local parts: { buffer } = {}
	local total = 0
	local offset = 0
	while offset < length do
		if #parts > 0 and buffer.readu8(input, offset) == 0 then
			offset += 1
			continue
		end
		if offset + 2 > length or buffer.readu8(input, offset) ~= 0x1F or buffer.readu8(input, offset + 1) ~= 0x8B then
			error(("gzip: no gzip magic at byte %d"):format(offset), 0)
		end
		if offset + 10 > length then
			error("gzip: the header ends early", 0)
		end
		if buffer.readu8(input, offset + 2) ~= 8 then
			error("gzip: the compression method is not deflate", 0)
		end
		local flags = buffer.readu8(input, offset + 3)
		if bit32.band(flags, 0xE0) ~= 0 then
			error("gzip: reserved header flags are set", 0)
		end
		local position = offset + 10
		if bit32.band(flags, GZIP_EXTRA) ~= 0 then
			if position + 2 > length then
				error("gzip: the header ends early", 0)
			end
			position += 2 + buffer.readu16(input, position)
		end
		if bit32.band(flags, GZIP_NAME) ~= 0 then
			position = skipText(input, position)
		end
		if bit32.band(flags, GZIP_COMMENT) ~= 0 then
			position = skipText(input, position)
		end
		if bit32.band(flags, GZIP_HEADER_CRC) ~= 0 then
			if position + 2 > length then
				error("gzip: the header ends early", 0)
			end
			if bit32.band(crc32(input, offset, position - offset), 0xFFFF) ~= buffer.readu16(input, position) then
				error("gzip: the header CRC does not match", 0)
			end
			position += 2
		end
		if position > length then
			error("gzip: the header ends early", 0)
		end
		local hint = if #parts == 0 then math.min(buffer.readu32(input, length - 4), length * 8, 0x10000000) else 0
		local output, after = inflate(input, position, hint)
		if after + 8 > length then
			error("gzip: the trailer ends early", 0)
		end
		if crc32(output) ~= buffer.readu32(input, after) then
			error("gzip: the CRC-32 does not match", 0)
		end
		if buffer.len(output) % 0x100000000 ~= buffer.readu32(input, after + 4) then
			error("gzip: the recorded length does not match", 0)
		end
		table.insert(parts, output)
		total += buffer.len(output)
		offset = after + 8
	end
	if #parts == 0 then
		error("gzip: no gzip member", 0)
	end
	if #parts == 1 then
		return parts[1]
	end
	local joined = buffer.create(total)
	local cursor = 0
	for _, part in parts do
		buffer.copy(joined, cursor, part, 0, buffer.len(part))
		cursor += buffer.len(part)
	end
	return joined
end

return table.freeze({
	crc32 = crc32,
	adler32 = adler32,
	inflate = inflate,
	deflate = deflate,
	compress = compress,
	decompress = decompress,
	gzip = gzip,
	gunzip = gunzip,
})
