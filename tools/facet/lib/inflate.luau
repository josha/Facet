--!strict

local Case = require("./case")

type Huffman = { lookup: { number }, bits: number, mask: number }

local Inflate = {}

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

local GZIP_TEXT = 1
local GZIP_HEADER_CRC = 2
local GZIP_EXTRA = 4
local GZIP_NAME = 8
local GZIP_COMMENT = 16

local crcEntries: { number }? = nil
local fixedTables: { literal: Huffman, distance: Huffman }? = nil

local function crcTable(): { number }
	local existing = crcEntries
	if existing ~= nil then
		return existing
	end
	local entries = table.create(256, 0)
	for index = 0, 255 do
		local value = index
		for _ = 1, 8 do
			if bit32.band(value, 1) == 1 then
				value = bit32.bxor(0xEDB88320, bit32.rshift(value, 1))
			else
				value = bit32.rshift(value, 1)
			end
		end
		entries[index + 1] = value
	end
	crcEntries = entries
	return entries
end

local function crcOf(source: buffer, from: number, length: number): number
	local entries = crcTable()
	local crc = 0xFFFFFFFF
	for index = from, from + length - 1 do
		crc = bit32.bxor(
			entries[bit32.band(bit32.bxor(crc, buffer.readu8(source, index)), 0xFF) + 1],
			bit32.rshift(crc, 8)
		)
	end
	return bit32.bxor(crc, 0xFFFFFFFF)
end

function Inflate.crc32(data: string): number
	return crcOf(buffer.fromstring(data), 0, #data)
end

local function huffman(lengths: { number }, from: number, count: number, kind: "codes" | "symbols"): Huffman
	local counts = table.create(15, 0)
	local longest = 0
	for symbol = 0, count - 1 do
		local length = lengths[from + symbol]
		if length > 0 then
			counts[length] += 1
			if length > longest then
				longest = length
			end
		end
	end
	if longest == 0 then
		if kind == "codes" then
			error("deflate: the code length code is empty", 0)
		end
		return { lookup = { -1, -1 }, bits = 1, mask = 1 }
	end
	local left = 1
	for length = 1, 15 do
		left = left * 2 - counts[length]
		if left < 0 then
			error("deflate: an over-subscribed Huffman code", 0)
		end
	end
	if left > 0 and (kind == "codes" or longest ~= 1) then
		error("deflate: an incomplete Huffman code", 0)
	end
	local nextCode = table.create(15, 0)
	local code = 0
	for length = 1, 15 do
		code = (code + (if length > 1 then counts[length - 1] else 0)) * 2
		nextCode[length] = code
	end
	local size = bit32.lshift(1, longest)
	local lookup = table.create(size, -1)
	for symbol = 0, count - 1 do
		local length = lengths[from + symbol]
		if length > 0 then
			local assigned = nextCode[length]
			nextCode[length] = assigned + 1
			local reversed = 0
			for _ = 1, length do
				reversed = reversed * 2 + bit32.band(assigned, 1)
				assigned = bit32.rshift(assigned, 1)
			end
			local entry = symbol * 16 + length
			local step = bit32.lshift(1, length)
			for index = reversed, size - 1, step do
				lookup[index + 1] = entry
			end
		end
	end
	return { lookup = lookup, bits = longest, mask = size - 1 }
end

local function fixed(): { literal: Huffman, distance: Huffman }
	local existing = fixedTables
	if existing ~= nil then
		return existing
	end
	local literalLengths = table.create(288, 0)
	for symbol = 0, 287 do
		literalLengths[symbol + 1] = if symbol < 144 then 8 elseif symbol < 256 then 9 elseif symbol < 280 then 7 else 8
	end
	local distanceLengths = table.create(32, 5)
	local built = {
		literal = huffman(literalLengths, 1, 288, "symbols"),
		distance = huffman(distanceLengths, 1, 32, "symbols"),
	}
	fixedTables = built
	return built
end

function Inflate.rawBuffer(input: buffer, start: number, sizeHint: number?): (buffer, number, number)
	local inputLength = buffer.len(input)
	local position = start
	local bits = 0
	local count = 0
	local capacity = math.max(sizeHint or 0, 4096)
	local output = buffer.create(capacity)
	local written = 0

	local function fill(wanted: number)
		while count < wanted and position < inputLength do
			bits = bit32.bor(bits, bit32.lshift(buffer.readu8(input, position), count))
			position += 1
			count += 8
		end
	end

	local function take(wanted: number): number
		if wanted == 0 then
			return 0
		end
		fill(wanted)
		if count < wanted then
			error("deflate: the stream ends early", 0)
		end
		local value = bit32.band(bits, bit32.lshift(1, wanted) - 1)
		bits = bit32.rshift(bits, wanted)
		count -= wanted
		return value
	end

	local function decode(code: Huffman): number
		fill(code.bits)
		local entry = code.lookup[bit32.band(bits, code.mask) + 1]
		if entry < 0 then
			error("deflate: an invalid Huffman code", 0)
		end
		local length = bit32.band(entry, 15)
		if length > count then
			error("deflate: the stream ends early", 0)
		end
		bits = bit32.rshift(bits, length)
		count -= length
		return bit32.rshift(entry, 4)
	end

	local function reserve(extra: number)
		if written + extra <= capacity then
			return
		end
		local grown = capacity
		while written + extra > grown do
			grown *= 2
		end
		local replacement = buffer.create(grown)
		buffer.copy(replacement, 0, output, 0, written)
		output = replacement
		capacity = grown
	end

	local function stored()
		local unread = bit32.rshift(count, 3)
		position -= unread
		bits = 0
		count = 0
		if position + 4 > inputLength then
			error("deflate: the stream ends early", 0)
		end
		local length = buffer.readu16(input, position)
		local complement = buffer.readu16(input, position + 2)
		position += 4
		if bit32.bxor(length, complement) ~= 0xFFFF then
			error("deflate: a stored block length does not match its complement", 0)
		end
		if position + length > inputLength then
			error("deflate: the stream ends early", 0)
		end
		reserve(length)
		buffer.copy(output, written, input, position, length)
		written += length
		position += length
	end

	local function dynamic(): (Huffman, Huffman)
		local literalCount = take(5) + 257
		local distanceCount = take(5) + 1
		local codeLengthCount = take(4) + 4
		if literalCount > 286 or distanceCount > 30 then
			error("deflate: too many length or distance symbols", 0)
		end
		local codeLengths = table.create(19, 0)
		for index = 1, codeLengthCount do
			codeLengths[CODE_LENGTH_ORDER[index] + 1] = take(3)
		end
		local lengthCode = huffman(codeLengths, 1, 19, "codes")
		local total = literalCount + distanceCount
		local lengths = table.create(total, 0)
		local filled = 0
		while filled < total do
			local symbol = decode(lengthCode)
			if symbol < 16 then
				filled += 1
				lengths[filled] = symbol
			else
				local repeated = 0
				local times = 0
				if symbol == 16 then
					if filled == 0 then
						error("deflate: a repeat code has no previous length", 0)
					end
					repeated = lengths[filled]
					times = 3 + take(2)
				elseif symbol == 17 then
					times = 3 + take(3)
				else
					times = 11 + take(7)
				end
				if filled + times > total then
					error("deflate: the code lengths overrun their count", 0)
				end
				for _ = 1, times do
					filled += 1
					lengths[filled] = repeated
				end
			end
		end
		if lengths[257] == 0 then
			error("deflate: the literal code has no end-of-block symbol", 0)
		end
		return huffman(lengths, 1, literalCount, "symbols"),
			huffman(lengths, literalCount + 1, distanceCount, "symbols")
	end

	local function compressed(literal: Huffman, distance: Huffman)
		local literalLookup = literal.lookup
		local literalMask = literal.mask
		local literalBits = literal.bits
		while true do
			if count < literalBits then
				fill(literalBits)
			end
			local entry = literalLookup[bit32.band(bits, literalMask) + 1]
			if entry < 0 then
				error("deflate: an invalid Huffman code", 0)
			end
			local codeLength = bit32.band(entry, 15)
			if codeLength > count then
				error("deflate: the stream ends early", 0)
			end
			bits = bit32.rshift(bits, codeLength)
			count -= codeLength
			local symbol = bit32.rshift(entry, 4)
			if symbol < 256 then
				if written >= capacity then
					reserve(1)
				end
				buffer.writeu8(output, written, symbol)
				written += 1
			elseif symbol == 256 then
				return
			else
				local lengthIndex = symbol - 256
				if lengthIndex > 29 then
					error("deflate: an invalid length symbol", 0)
				end
				local length = LENGTH_BASE[lengthIndex] + take(LENGTH_EXTRA[lengthIndex])
				local distanceSymbol = decode(distance)
				if distanceSymbol > 29 then
					error("deflate: an invalid distance symbol", 0)
				end
				local back = DISTANCE_BASE[distanceSymbol + 1] + take(DISTANCE_EXTRA[distanceSymbol + 1])
				if back > written then
					error("deflate: a distance reaches before the start of the output", 0)
				end
				reserve(length)
				local from = written - back
				if back >= length then
					buffer.copy(output, written, output, from, length)
				else
					for offset = 0, length - 1 do
						buffer.writeu8(output, written + offset, buffer.readu8(output, from + offset))
					end
				end
				written += length
			end
		end
	end

	local final = false
	while not final do
		final = take(1) == 1
		local kind = take(2)
		if kind == 0 then
			stored()
		elseif kind == 1 then
			local tables = fixed()
			compressed(tables.literal, tables.distance)
		elseif kind == 2 then
			local literal, distance = dynamic()
			compressed(literal, distance)
		else
			error("deflate: an invalid block type", 0)
		end
	end
	return output, written, position - bit32.rshift(count, 3)
end

function Inflate.raw(data: string): string
	local output, written = Inflate.rawBuffer(buffer.fromstring(data), 0, #data * 4)
	return buffer.readstring(output, 0, written)
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

function Inflate.gunzip(data: string): string
	local input = buffer.fromstring(data)
	local length = buffer.len(input)
	local parts: { string } = {}
	local offset = 0
	local members = 0
	while offset < length do
		if members > 0 and buffer.readu8(input, offset) == 0 then
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
			local recorded = buffer.readu16(input, position)
			if bit32.band(crcOf(input, offset, position - offset), 0xFFFF) ~= recorded then
				error("gzip: the header CRC does not match", 0)
			end
			position += 2
		end
		if position > length then
			error("gzip: the header ends early", 0)
		end
		local hint = if members == 0 then math.min(buffer.readu32(input, length - 4), length * 8, 0x10000000) else 0
		local output, written, after = Inflate.rawBuffer(input, position, hint)
		if after + 8 > length then
			error("gzip: the trailer ends early", 0)
		end
		if crcOf(output, 0, written) ~= buffer.readu32(input, after) then
			error("gzip: the CRC-32 does not match", 0)
		end
		if written % 0x100000000 ~= buffer.readu32(input, after + 4) then
			error("gzip: the recorded length does not match", 0)
		end
		table.insert(parts, buffer.readstring(output, 0, written))
		offset = after + 8
		members += 1
	end
	if members == 0 then
		error("gzip: no gzip member", 0)
	end
	return table.concat(parts)
end

local function littleEndian(value: number, width: number): string
	local bytes = table.create(width, "")
	for index = 1, width do
		bytes[index] = string.char(bit32.band(bit32.rshift(value, (index - 1) * 8), 0xFF))
	end
	return table.concat(bytes)
end

function Inflate.gzipMember(deflated: string, plain: string, header: string?): string
	return (header or "\x1f\x8b\x08\x00\x00\x00\x00\x00\x00\xff")
		.. deflated
		.. littleEndian(Inflate.crc32(plain), 4)
		.. littleEndian(#plain % 0x100000000, 4)
end

function Inflate.stored(plain: string): string
	local blocks: { string } = {}
	local offset = 1
	repeat
		local piece = string.sub(plain, offset, offset + 65534)
		offset += #piece
		local final = if offset > #plain then "\x01" else "\x00"
		table.insert(blocks, final .. littleEndian(#piece, 2) .. littleEndian(bit32.bxor(#piece, 0xFFFF), 2) .. piece)
	until offset > #plain
	return table.concat(blocks)
end

local FIXED_TEXT = "hello hello hello hello\n"
local FIXED_DEFLATE = "\xcb\x48\xcd\xc9\xc9\x57\xc8\x40\x27\xb9\x00"
local DYNAMIC_TEXT = string.rep(
	"crane fjord mocha ninja sushi adieu grey colour theatre centre favour litre cheque kerb tyre pyjamas "
		.. "crane fjord mocha ninja sushi adieu axe asked cakes walked chairs\n",
	3
)
local DYNAMIC_DEFLATE = "\xed\x8e\x3b\x16\xc2\x30\x0c\x04\x7b\x4e\xb1\x57\x5b\x64\x05\x7f\x12\x1b\x24\x1b\xf0"
	.. "\xed\x21\x39\x01\x45\x4a\xaa\x7d\x3b\xcd\x8c\x18\xab\x62\xc9\xcd\x02\xb6\x26\x91\xa8\xa9\x66\xc2"
	.. "\x87\xc7\x04\x86\xa4\x03\x37\xd3\x09\x69\x6b\x1b\x86\x1e\x95\xdd\x14\xa2\x75\x9f\x85\xcf\x9d\xae"
	.. "\xe9\x60\x51\x1f\x43\x51\xd4\xae\xe8\xf3\x0b\xee\x33\x73\xa3\x43\x7e\x90\xf0\xad\xa0\x17\x0d\x10"
	.. "\x16\x75\xbc\xb8\x1e\x27\x32\x99\x5f\xe4\x9f\x79\x62\xe6\x07"
local PYTHON_GZIP = "\x1f\x8b\x08\x00\x00\x00\x00\x00\x02\xff\x4b\x4b\x4c\x4e\x2d\x51\x28\xcf\x2f\x4a\x29"
	.. "\xe6\x02\x00\x34\x8e\x09\x81\x0c\x00\x00\x00"
local FAR_DISTANCE = "\x03\x02\x00"

local function refuses(body: () -> (), fragment: string): string?
	local message = ""
	local ok = xpcall(body, function(problem: unknown)
		message = tostring(problem)
	end)
	if ok then
		return ("expected a refusal containing '%s', but it decoded"):format(fragment)
	end
	if string.find(message, fragment, 1, true) == nil then
		return ("expected a refusal containing '%s', got '%s'"):format(fragment, message)
	end
	return nil
end

function Inflate.cases(): { Case.Case }
	return {
		{
			name = "inflate: CRC-32 of the standard check string",
			run = function(): string?
				return Case.equal(Inflate.crc32("123456789"), 0xCBF43926, "crc32")
			end,
		},
		{
			name = "inflate: a fixed Huffman block from zlib",
			run = function(): string?
				return Case.equal(Inflate.raw(FIXED_DEFLATE), FIXED_TEXT, "fixed block")
			end,
		},
		{
			name = "inflate: a dynamic Huffman block from zlib",
			run = function(): string?
				return Case.equal(Inflate.raw(DYNAMIC_DEFLATE), DYNAMIC_TEXT, "dynamic block")
			end,
		},
		{
			name = "inflate: stored blocks across the 65535-byte block limit",
			run = function(): string?
				local plain = string.rep("0123456789abcdef", 9000)
				return Case.equal(Inflate.raw(Inflate.stored(plain)) == plain, true, "stored round trip")
			end,
		},
		{
			name = "inflate: an empty stored stream",
			run = function(): string?
				return Case.equal(Inflate.gunzip(Inflate.gzipMember(Inflate.stored(""), "")), "", "empty member")
			end,
		},
		{
			name = "inflate: a gzip member written by Python",
			run = function(): string?
				return Case.equal(Inflate.gunzip(PYTHON_GZIP), "facet words\n", "python gzip")
			end,
		},
		{
			name = "inflate: gzip header fields are skipped",
			run = function(): string?
				local header = "\x1f\x8b\x08"
					.. string.char(GZIP_TEXT + GZIP_EXTRA + GZIP_NAME + GZIP_COMMENT)
					.. "\x00\x00\x00\x00\x00\x03"
					.. "\x03\x00abc"
					.. "words.txt\x00"
					.. "a comment\x00"
				local member = Inflate.gzipMember(FIXED_DEFLATE, FIXED_TEXT, header)
				local checked = "\x1f\x8b\x08"
					.. string.char(GZIP_NAME + GZIP_HEADER_CRC)
					.. "\x00\x00\x00\x00\x00\x03x\x00"
				local headerCrc = bit32.band(Inflate.crc32(checked), 0xFFFF)
				local withCrc = Inflate.gzipMember(DYNAMIC_DEFLATE, DYNAMIC_TEXT, checked .. littleEndian(headerCrc, 2))
				return Case.first(
					Case.equal(Inflate.gunzip(member), FIXED_TEXT, "extra, name and comment"),
					Case.equal(Inflate.gunzip(withCrc) == DYNAMIC_TEXT, true, "header CRC")
				)
			end,
		},
		{
			name = "inflate: concatenated members and zero padding",
			run = function(): string?
				local joined = Inflate.gzipMember(FIXED_DEFLATE, FIXED_TEXT)
					.. Inflate.gzipMember(Inflate.stored("tail\n"), "tail\n")
					.. "\x00\x00\x00"
				return Case.equal(Inflate.gunzip(joined), FIXED_TEXT .. "tail\n", "two members")
			end,
		},
		{
			name = "inflate: refuses a CRC-32 mismatch",
			run = function(): string?
				local member = Inflate.gzipMember(FIXED_DEFLATE, FIXED_TEXT)
				local damaged = string.sub(member, 1, #member - 8) .. "\x00\x00\x00\x00" .. string.sub(member, -4)
				return refuses(function()
					Inflate.gunzip(damaged)
				end, "CRC-32 does not match")
			end,
		},
		{
			name = "inflate: refuses a length mismatch",
			run = function(): string?
				local member = Inflate.gzipMember(FIXED_DEFLATE, FIXED_TEXT)
				local damaged = string.sub(member, 1, #member - 4) .. "\x01\x00\x00\x00"
				return refuses(function()
					Inflate.gunzip(damaged)
				end, "recorded length does not match")
			end,
		},
		{
			name = "inflate: refuses data that is not gzip",
			run = function(): string?
				return Case.first(
					refuses(function()
						Inflate.gunzip("PK\x03\x04 not a gzip file")
					end, "no gzip magic"),
					refuses(function()
						Inflate.gunzip(PYTHON_GZIP .. "trailing")
					end, "no gzip magic"),
					refuses(function()
						Inflate.gunzip("")
					end, "no gzip member")
				)
			end,
		},
		{
			name = "inflate: refuses a truncated stream",
			run = function(): string?
				return Case.first(
					refuses(function()
						Inflate.raw(string.sub(DYNAMIC_DEFLATE, 1, 40))
					end, "ends early"),
					refuses(function()
						Inflate.gunzip(string.sub(PYTHON_GZIP, 1, #PYTHON_GZIP - 3))
					end, "trailer ends early")
				)
			end,
		},
		{
			name = "inflate: refuses malformed blocks",
			run = function(): string?
				return Case.first(
					refuses(function()
						Inflate.raw("\x07")
					end, "invalid block type"),
					refuses(function()
						Inflate.raw("\x01\x05\x00\x00\x00hello")
					end, "does not match its complement"),
					refuses(function()
						Inflate.raw(FAR_DISTANCE)
					end, "before the start of the output")
				)
			end,
		},
	}
end

return table.freeze(Inflate)
