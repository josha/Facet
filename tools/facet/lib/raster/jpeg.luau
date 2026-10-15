--!strict
--!native

export type Raster = { width: number, height: number, channels: number, data: buffer }

type Huffman = { lookup: { [number]: number }, lengths: { [number]: number } }

type Component = {
	id: number,
	h: number,
	v: number,
	quant: number,
	dc: number,
	ac: number,
	predictor: number,
	blocksWide: number,
	blocksHigh: number,
	plane: buffer,
	stride: number,
}

local ZIGZAG = {
	0,
	1,
	8,
	16,
	9,
	2,
	3,
	10,
	17,
	24,
	32,
	25,
	18,
	11,
	4,
	5,
	12,
	19,
	26,
	33,
	40,
	48,
	41,
	34,
	27,
	20,
	13,
	6,
	7,
	14,
	21,
	28,
	35,
	42,
	49,
	56,
	57,
	50,
	43,
	36,
	29,
	22,
	15,
	23,
	30,
	37,
	44,
	51,
	58,
	59,
	52,
	45,
	38,
	31,
	39,
	46,
	53,
	60,
	61,
	54,
	47,
	55,
	62,
	63,
}

local COSINES = buffer.create(64 * 8)
for x = 0, 7 do
	for u = 0, 7 do
		local scale = if u == 0 then math.sqrt(0.5) else 1
		buffer.writef64(COSINES, (x * 8 + u) * 8, scale * math.cos((2 * x + 1) * u * math.pi / 16) / 2)
	end
end

local function fail(message: string): never
	error("jpeg: " .. message, 0)
end

local function u16(data: buffer, offset: number): number
	return buffer.readu8(data, offset) * 256 + buffer.readu8(data, offset + 1)
end

local function huffman(counts: { number }, symbols: { number }): Huffman
	local lookup: { [number]: number } = {}
	local lengths: { [number]: number } = {}
	local code = 0
	local index = 1
	for length = 1, 16 do
		for _ = 1, counts[length] do
			local key = bit32.bor(bit32.lshift(1, length), code)
			lookup[key] = symbols[index]
			lengths[length] = 1
			index += 1
			code += 1
		end
		code *= 2
	end
	return { lookup = lookup, lengths = lengths }
end

local function decode(data: buffer): Raster
	local size = buffer.len(data)
	if size < 4 or buffer.readu8(data, 0) ~= 0xFF or buffer.readu8(data, 1) ~= 0xD8 then
		fail "missing the start of image marker"
	end
	local quant: { [number]: { number } } = {}
	local dcTables: { [number]: Huffman } = {}
	local acTables: { [number]: Huffman } = {}
	local components: { Component } = {}
	local byId: { [number]: Component } = {}
	local width, height = 0, 0
	local hMax, vMax = 1, 1
	local adobeTransform: number? = nil
	local framed = false
	local scanned = false
	local offset = 2

	local function segment(): (number, number, number)
		local marker = 0
		while marker == 0 do
			while offset < size and buffer.readu8(data, offset) ~= 0xFF do
				offset += 1
			end
			while offset < size and buffer.readu8(data, offset) == 0xFF do
				offset += 1
			end
			if offset >= size then
				fail "the data ends before the end of image marker"
			end
			marker = buffer.readu8(data, offset)
			offset += 1
		end
		if marker == 0xD9 or (marker >= 0xD0 and marker <= 0xD7) or marker == 0x01 then
			return marker, offset, 0
		end
		if offset + 2 > size then
			fail "a segment header is truncated"
		end
		local length = u16(data, offset)
		if length < 2 or offset + length > size then
			fail(("segment %02X is truncated"):format(marker))
		end
		local start = offset + 2
		offset += length
		return marker, start, length - 2
	end

	local function readFrame(start: number, length: number)
		if framed then
			fail "the image has more than one frame"
		end
		framed = true
		if length < 6 then
			fail "the frame header is truncated"
		end
		if buffer.readu8(data, start) ~= 8 then
			fail "only 8-bit samples are supported"
		end
		height = u16(data, start + 1)
		width = u16(data, start + 3)
		local parts = buffer.readu8(data, start + 5)
		if width == 0 or height == 0 then
			fail "the image has no size"
		end
		if parts ~= 1 and parts ~= 3 then
			fail(("%d components are not supported"):format(parts))
		end
		if length < 6 + parts * 3 then
			fail "the frame header is truncated"
		end
		for index = 0, parts - 1 do
			local at = start + 6 + index * 3
			local sampling = buffer.readu8(data, at + 1)
			local component: Component = {
				id = buffer.readu8(data, at),
				h = bit32.rshift(sampling, 4),
				v = bit32.band(sampling, 15),
				quant = buffer.readu8(data, at + 2),
				dc = 0,
				ac = 0,
				predictor = 0,
				blocksWide = 0,
				blocksHigh = 0,
				plane = buffer.create(0),
				stride = 0,
			}
			if component.h < 1 or component.h > 4 or component.v < 1 or component.v > 4 then
				fail "a component has an invalid sampling factor"
			end
			hMax = math.max(hMax, component.h)
			vMax = math.max(vMax, component.v)
			table.insert(components, component)
			byId[component.id] = component
		end
		local mcusWide = math.ceil(width / (8 * hMax))
		local mcusHigh = math.ceil(height / (8 * vMax))
		for _, component in components do
			component.blocksWide = mcusWide * component.h
			component.blocksHigh = mcusHigh * component.v
			component.stride = component.blocksWide * 8
			component.plane = buffer.create(component.stride * component.blocksHigh * 8)
		end
	end

	local function readQuant(start: number, length: number)
		local cursor = start
		local finish = start + length
		while cursor < finish do
			local info = buffer.readu8(data, cursor)
			local precision = bit32.rshift(info, 4)
			local id = bit32.band(info, 15)
			cursor += 1
			local values: { number } = table.create(64, 0)
			for index = 1, 64 do
				if precision == 0 then
					values[index] = buffer.readu8(data, cursor)
					cursor += 1
				else
					values[index] = u16(data, cursor)
					cursor += 2
				end
			end
			if cursor > finish then
				fail "a quantization table is truncated"
			end
			quant[id] = values
		end
	end

	local function readHuffman(start: number, length: number)
		local cursor = start
		local finish = start + length
		while cursor < finish do
			if cursor + 17 > finish then
				fail "a Huffman table is truncated"
			end
			local info = buffer.readu8(data, cursor)
			local counts: { number } = {}
			local total = 0
			for index = 1, 16 do
				counts[index] = buffer.readu8(data, cursor + index)
				total += counts[index]
			end
			cursor += 17
			if cursor + total > finish then
				fail "a Huffman table is truncated"
			end
			local symbols: { number } = {}
			for index = 1, total do
				symbols[index] = buffer.readu8(data, cursor + index - 1)
			end
			cursor += total
			local decoded = huffman(counts, symbols)
			if bit32.rshift(info, 4) == 0 then
				dcTables[bit32.band(info, 15)] = decoded
			else
				acTables[bit32.band(info, 15)] = decoded
			end
		end
	end

	local position = 0
	local bits = 0
	local count = 0
	local function fill()
		local byte = 0
		if position < size then
			byte = buffer.readu8(data, position)
			if byte == 0xFF then
				local following = if position + 1 < size then buffer.readu8(data, position + 1) else 0
				if following == 0x00 then
					position += 2
				else
					byte = 0
				end
			else
				position += 1
			end
		end
		bits = bit32.bor(bit32.lshift(bits, 8), byte)
		count += 8
	end
	local function bit(): number
		if count == 0 then
			fill()
		end
		count -= 1
		local value = bit32.band(bit32.rshift(bits, count), 1)
		bits = bit32.band(bits, bit32.lshift(1, count) - 1)
		return value
	end
	local function receive(length: number): number
		local value = 0
		for _ = 1, length do
			value = value * 2 + bit()
		end
		return value
	end
	local function extend(value: number, length: number): number
		if length == 0 then
			return 0
		end
		if value < bit32.lshift(1, length - 1) then
			return value - bit32.lshift(1, length) + 1
		end
		return value
	end
	local function symbol(codes: Huffman): number
		local code = 1
		for length = 1, 16 do
			code = code * 2 + bit()
			if codes.lengths[length] ~= nil then
				local found = codes.lookup[code]
				if found ~= nil then
					return found
				end
			end
		end
		return fail "the entropy data has an invalid Huffman code"
	end
	local coefficients = buffer.create(64 * 8)
	local rows = buffer.create(64 * 8)
	local function block(component: Component, row: number, column: number)
		buffer.fill(coefficients, 0, 0, 64 * 8)
		local levels = quant[component.quant]
		if levels == nil then
			fail(("quantization table %d is missing"):format(component.quant))
		end
		local dcTable = dcTables[component.dc]
		local acTable = acTables[component.ac]
		if dcTable == nil or acTable == nil then
			fail "a Huffman table is missing"
		end
		local length = symbol(dcTable)
		component.predictor += extend(receive(length), length)
		buffer.writef64(coefficients, 0, component.predictor * levels[1])
		local index = 1
		while index < 64 do
			local pair = symbol(acTable)
			local run = bit32.rshift(pair, 4)
			local magnitude = bit32.band(pair, 15)
			if magnitude == 0 then
				if run ~= 15 then
					break
				end
				index += 16
			else
				index += run
				if index > 63 then
					fail "a block has too many coefficients"
				end
				buffer.writef64(
					coefficients,
					ZIGZAG[index + 1] * 8,
					extend(receive(magnitude), magnitude) * levels[index + 1]
				)
				index += 1
			end
		end
		for y = 0, 7 do
			for u = 0, 7 do
				local sum = 0
				for v = 0, 7 do
					local value = buffer.readf64(coefficients, (v * 8 + u) * 8)
					if value ~= 0 then
						sum += value * buffer.readf64(COSINES, (y * 8 + v) * 8)
					end
				end
				buffer.writef64(rows, (y * 8 + u) * 8, sum)
			end
		end
		local base = row * 8 * component.stride + column * 8
		for y = 0, 7 do
			for x = 0, 7 do
				local sum = 0
				for u = 0, 7 do
					sum += buffer.readf64(rows, (y * 8 + u) * 8) * buffer.readf64(COSINES, (x * 8 + u) * 8)
				end
				local sample = math.floor(sum + 128.5)
				buffer.writeu8(component.plane, base + y * component.stride + x, math.clamp(sample, 0, 255))
			end
		end
	end

	local function readScan(start: number, length: number)
		if not framed then
			fail "a scan comes before the frame header"
		end
		local members = buffer.readu8(data, start)
		if length < 4 + members * 2 then
			fail "the scan header is truncated"
		end
		local scan: { Component } = {}
		for index = 0, members - 1 do
			local component = byId[buffer.readu8(data, start + 1 + index * 2)]
			if component == nil then
				fail "the scan names an unknown component"
			end
			local tables = buffer.readu8(data, start + 2 + index * 2)
			component.dc = bit32.rshift(tables, 4)
			component.ac = bit32.band(tables, 15)
			component.predictor = 0
			table.insert(scan, component)
		end
		position = start + length
		bits = 0
		count = 0
		local units: { { component: Component, row: number, column: number } } = {}
		local total = 0
		local function unitsOf(index: number)
			table.clear(units)
			if #scan == 1 then
				local component = scan[1]
				local wide = math.ceil(math.ceil(width * component.h / hMax) / 8)
				local row = index // wide
				local column = index % wide
				table.insert(units, { component = component, row = row, column = column })
				return
			end
			local mcusWide = math.ceil(width / (8 * hMax))
			local mcuRow = index // mcusWide
			local mcuColumn = index % mcusWide
			for _, component in scan do
				for v = 0, component.v - 1 do
					for h = 0, component.h - 1 do
						table.insert(units, {
							component = component,
							row = mcuRow * component.v + v,
							column = mcuColumn * component.h + h,
						})
					end
				end
			end
		end
		if #scan == 1 then
			local component = scan[1]
			total = math.ceil(math.ceil(width * component.h / hMax) / 8)
				* math.ceil(math.ceil(height * component.v / vMax) / 8)
		else
			total = math.ceil(width / (8 * hMax)) * math.ceil(height / (8 * vMax))
		end
		for index = 0, total - 1 do
			unitsOf(index)
			for _, unit in units do
				block(unit.component, unit.row, unit.column)
			end
		end
		offset = position
		scanned = true
	end

	while true do
		local marker, start, length = segment()
		if marker == 0xD9 then
			break
		elseif marker == 0xC0 or marker == 0xC1 then
			readFrame(start, length)
		elseif marker >= 0xC2 and marker <= 0xCF and marker ~= 0xC4 and marker ~= 0xC8 and marker ~= 0xCC then
			fail(("frame type %02X is not supported; only baseline JPEG is"):format(marker))
		elseif marker == 0xDB then
			readQuant(start, length)
		elseif marker == 0xC4 then
			readHuffman(start, length)
		elseif marker == 0xDD then
			if length >= 2 and u16(data, start) > 0 then
				fail "restart intervals are not supported"
			end
		elseif marker == 0xDA then
			readScan(start, length)
		elseif marker == 0xEE and length >= 12 and buffer.readstring(data, start, 5) == "Adobe" then
			adobeTransform = buffer.readu8(data, start + 11)
		end
	end
	if not scanned then
		fail "the image has no scan"
	end

	if #components == 1 then
		local component = components[1]
		local out = buffer.create(width * height)
		for y = 0, height - 1 do
			buffer.copy(out, y * width, component.plane, y * component.stride, width)
		end
		return { width = width, height = height, channels = 1, data = out }
	end
	local out = buffer.create(width * height * 3)
	local first, second, third = components[1], components[2], components[3]
	local convert = adobeTransform ~= 0
	for y = 0, height - 1 do
		local y1 = (y * first.v // vMax) * first.stride
		local y2 = (y * second.v // vMax) * second.stride
		local y3 = (y * third.v // vMax) * third.stride
		for x = 0, width - 1 do
			local a = buffer.readu8(first.plane, y1 + x * first.h // hMax)
			local b = buffer.readu8(second.plane, y2 + x * second.h // hMax)
			local c = buffer.readu8(third.plane, y3 + x * third.h // hMax)
			local at = (y * width + x) * 3
			if convert then
				local cb = b - 128
				local cr = c - 128
				buffer.writeu8(out, at, math.clamp(math.floor(a + 1.402 * cr + 0.5), 0, 255))
				buffer.writeu8(out, at + 1, math.clamp(math.floor(a - 0.344136 * cb - 0.714136 * cr + 0.5), 0, 255))
				buffer.writeu8(out, at + 2, math.clamp(math.floor(a + 1.772 * cb + 0.5), 0, 255))
			else
				buffer.writeu8(out, at, a)
				buffer.writeu8(out, at + 1, b)
				buffer.writeu8(out, at + 2, c)
			end
		end
	end
	return { width = width, height = height, channels = 3, data = out }
end

return table.freeze {
	decode = decode,
}
