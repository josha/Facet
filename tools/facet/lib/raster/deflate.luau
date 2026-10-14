--!strict
--!native

local Checksum = require("./checksum")

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

type Table = { entries: buffer, bits: number }

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
		return { entries = buffer.create(4), bits = 0 }
	end
	local left = 1
	for length = 1, 15 do
		left = left * 2 - counts[length]
		if left < 0 then
			error("deflate: over-subscribed Huffman code", 0)
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
			local reversed = reverseBits(assigned, length)
			local step = 2 ^ length
			local value = symbol * 16 + length
			local slot = reversed
			while slot < size do
				buffer.writeu32(entries, slot * 4, value)
				slot += step
			end
		end
	end
	return { entries = entries, bits = maxBits }
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

local Deflate = {}

function Deflate.inflateRaw(data: buffer, offset: number?, expected: number?): (buffer, number)
	local source = data
	local length = buffer.len(source)
	local position = offset or 0
	local bits = 0
	local count = 0
	local capacity = math.max(expected or 0, 1024)
	local out = buffer.create(capacity)
	local written = 0

	local function need(width: number)
		while count < width do
			if position < length then
				bits += bit32.lshift(buffer.readu8(source, position), count)
				position += 1
			elseif position < length + 8 then
				position += 1
			else
				error("deflate: unexpected end of stream", 0)
			end
			count += 8
		end
	end

	local function take(width: number): number
		need(width)
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
			error("deflate: empty Huffman code used", 0)
		end
		need(width)
		local entry = buffer.readu32(huffman.entries, bit32.band(bits, 2 ^ width - 1) * 4)
		local used = bit32.band(entry, 15)
		if used == 0 then
			error("deflate: invalid Huffman code", 0)
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
				error("deflate: truncated stored block", 0)
			end
			local size = buffer.readu16(source, position)
			local complement = buffer.readu16(source, position + 2)
			if bit32.bxor(size, complement) ~= 0xFFFF then
				error("deflate: stored block length mismatch", 0)
			end
			position += 4
			if position + size > length then
				error("deflate: truncated stored block", 0)
			end
			reserve(size)
			buffer.copy(out, written, source, position, size)
			written += size
			position += size
		elseif kind == 1 or kind == 2 then
			local literalTable = FIXED_LITERAL
			local distanceTable = FIXED_DISTANCE
			if kind == 2 then
				local literalCount = take(5) + 257
				local distanceCount = take(5) + 1
				local codeCount = take(4) + 4
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
								error("deflate: repeat with no previous length", 0)
							end
							repeatValue = lengths[index - 1]
							repeatCount = 3 + take(2)
						elseif symbol == 17 then
							repeatCount = 3 + take(3)
						else
							repeatCount = 11 + take(7)
						end
						if index + repeatCount - 1 > total then
							error("deflate: code lengths overflow", 0)
						end
						for _ = 1, repeatCount do
							lengths[index] = repeatValue
							index += 1
						end
					end
				end
				if lengths[257] == 0 then
					error("deflate: missing end-of-block code", 0)
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
						error("deflate: invalid length code", 0)
					end
					local extra = LENGTH_EXTRA[code]
					local size = LENGTH_BASE[code] + (if extra > 0 then take(extra) else 0)
					local distanceSymbol = decode(distanceTable) + 1
					if distanceSymbol > 30 then
						error("deflate: invalid distance code", 0)
					end
					local distanceExtra = DISTANCE_EXTRA[distanceSymbol]
					local distance = DISTANCE_BASE[distanceSymbol]
						+ (if distanceExtra > 0 then take(distanceExtra) else 0)
					if distance > written then
						error("deflate: distance beyond output", 0)
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
			error("deflate: invalid block type", 0)
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

export type Options = { chain: number?, nice: number? }

function Deflate.deflateRaw(input: buffer, options: Options?): buffer
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

function Deflate.compress(input: buffer, options: Options?): buffer
	local raw = Deflate.deflateRaw(input, options)
	local result = buffer.create(buffer.len(raw) + 6)
	buffer.writeu8(result, 0, 0x78)
	buffer.writeu8(result, 1, 0xDA)
	buffer.copy(result, 2, raw, 0, buffer.len(raw))
	local adler = Checksum.adler32(input)
	local tail = buffer.len(raw) + 2
	buffer.writeu8(result, tail, bit32.rshift(adler, 24))
	buffer.writeu8(result, tail + 1, bit32.band(bit32.rshift(adler, 16), 0xFF))
	buffer.writeu8(result, tail + 2, bit32.band(bit32.rshift(adler, 8), 0xFF))
	buffer.writeu8(result, tail + 3, bit32.band(adler, 0xFF))
	return result
end

function Deflate.decompress(input: buffer, expected: number?): buffer
	if buffer.len(input) < 6 then
		error("zlib: stream is too short", 0)
	end
	local cmf = buffer.readu8(input, 0)
	local flg = buffer.readu8(input, 1)
	if bit32.band(cmf, 0x0F) ~= 8 or (cmf * 256 + flg) % 31 ~= 0 then
		error("zlib: invalid stream header", 0)
	end
	if bit32.band(flg, 0x20) ~= 0 then
		error("zlib: preset dictionaries are not supported", 0)
	end
	local out, consumed = Deflate.inflateRaw(input, 2, expected)
	if consumed + 4 > buffer.len(input) then
		error("zlib: missing Adler-32 checksum", 0)
	end
	local stored = buffer.readu8(input, consumed) * 16777216
		+ buffer.readu8(input, consumed + 1) * 65536
		+ buffer.readu8(input, consumed + 2) * 256
		+ buffer.readu8(input, consumed + 3)
	if stored ~= Checksum.adler32(out) then
		error("zlib: Adler-32 checksum mismatch", 0)
	end
	return out
end

return table.freeze(Deflate)
