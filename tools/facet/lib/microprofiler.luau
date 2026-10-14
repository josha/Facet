--!strict

local Base64 = require("./base64")
local Inflate = require("./inflate")

export type Row = {
	total: number,
	worst: number,
	count: number,
	name: string,
}

export type Dump = {
	frames: number,
	frequency: number,
	rows: { Row },
	raw: string,
}

export type LayoutRecord = {
	context: string,
	cause: string,
	root: string,
	relayouts: number,
	updates: number,
	resizes: number,
}

export type Options = {
	all: boolean,
	layout: boolean,
}

type Ranked = { row: Row, order: number }

local Microprofiler = {}

Microprofiler.FRAMEWORK_PREFIXES = { "Facet/", "LuauUI/" }
Microprofiler.LEGACY_PREFIX = "LuauUI/"

local function adler32(data: buffer, length: number): number
	local low = 1
	local high = 0
	local index = 0
	while index < length do
		local stop = math.min(index + 5552, length)
		for position = index, stop - 1 do
			low += buffer.readu8(data, position)
			high += low
		end
		low %= 65521
		high %= 65521
		index = stop
	end
	return high * 65536 + low
end

function Microprofiler.zlib(data: string): string
	local input = buffer.fromstring(data)
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
	local output, written, after = Inflate.rawBuffer(input, 2, length * 4)
	if after + 4 > length then
		error("zlib: the Adler-32 trailer ends early", 0)
	end
	local recorded = bit32.bor(
		bit32.lshift(buffer.readu8(input, after), 24),
		bit32.lshift(buffer.readu8(input, after + 1), 16),
		bit32.lshift(buffer.readu8(input, after + 2), 8),
		buffer.readu8(input, after + 3)
	)
	if adler32(output, written) ~= recorded then
		error("zlib: the Adler-32 checksum does not match", 0)
	end
	return buffer.readstring(output, 0, written)
end

local function adlerBytes(data: string): string
	local value = adler32(buffer.fromstring(data), #data)
	return string.char(
		bit32.band(bit32.rshift(value, 24), 0xFF),
		bit32.band(bit32.rshift(value, 16), 0xFF),
		bit32.band(bit32.rshift(value, 8), 0xFF),
		bit32.band(value, 0xFF)
	)
end

function Microprofiler.zlibStored(plain: string): string
	return "\x78\x01" .. Inflate.stored(plain) .. adlerBytes(plain)
end

local function u32(data: buffer, offset: number): number
	return buffer.readu32(data, offset)
end

local function u64(data: buffer, offset: number): number
	return buffer.readu32(data, offset) + buffer.readu32(data, offset + 4) * 4294967296
end

local function littleEndian(value: number): string
	return string.char(
		bit32.band(value, 0xFF),
		bit32.band(bit32.rshift(value, 8), 0xFF),
		bit32.band(bit32.rshift(value, 16), 0xFF),
		bit32.band(bit32.rshift(value, 24), 0xFF)
	)
end

function Microprofiler.load(path: string, raw: string): string
	if string.sub(raw, 1, 4) ~= "<!--" then
		error(("%s: no leading HTML comment - not a MicroProfiler dump"):format(path), 0)
	end
	local close = string.find(raw, "-->", 5, true)
	if close == nil then
		error(("%s: no leading HTML comment - not a MicroProfiler dump"):format(path), 0)
	end
	local blob = Base64.decode(string.sub(raw, 5, close - 1))
	if string.sub(blob, 1, 3) ~= "GAK" then
		error(("%s: bad magic %q, expected GAK"):format(path, string.sub(blob, 1, 3)), 0)
	end
	if #blob < 11 then
		error(("%s: the container header ends early"):format(path), 0)
	end
	local size = buffer.readu32(buffer.fromstring(string.sub(blob, 4, 7)), 0)
	local body = Microprofiler.zlib(string.sub(blob, 12))
	if #body ~= size then
		error(("%s: size mismatch %d != %d"):format(path, #body, size), 0)
	end
	return body
end

function Microprofiler.pack(body: string): string
	local container = "GAK" .. littleEndian(#body) .. littleEndian(0) .. Microprofiler.zlibStored(body)
	return "<!--" .. Base64.encode(container) .. "-->\n<html></html>"
end

function Microprofiler.parse(body: string): Dump
	local data = buffer.fromstring(body)
	local length = buffer.len(data)
	local count = u32(data, 0x4C)
	local tableOffset = u32(data, 0x50)
	local nameSize = u32(data, 0xC4)
	local nameBase = length - nameSize
	local function name(offset: number): string
		local start = nameBase + offset
		local terminator = string.find(body, "\0", start + 1, true)
		local stop = if terminator ~= nil then terminator - 1 else length - 1
		return string.sub(body, start + 1, stop)
	end
	local rows: { Row } = {}
	for index = 0, count - 1 do
		local offset = tableOffset + index * 80
		if offset + 80 > length then
			break
		end
		table.insert(rows, {
			total = u64(data, offset),
			worst = u64(data, offset + 8),
			count = u32(data, offset + 28),
			name = name(u32(data, offset + 32)),
		})
	end
	local frequency = u64(data, 0x28)
	return {
		frames = u32(data, 0x20),
		frequency = if frequency == 0 then 1000000000 else frequency,
		rows = rows,
		raw = body,
	}
end

function Microprofiler.layoutRecords(raw: string): { LayoutRecord }
	local records: { LayoutRecord } = {}
	local position = 1
	while true do
		local start = string.find(raw, "Context=", position, true)
		if start == nil then
			break
		end
		local tail = start + 8
		local terminator = string.find(raw, "\0", tail, true)
		local run = math.min((terminator or #raw + 1) - tail, 200)
		if run < 10 then
			position = start + 1
			continue
		end
		local text = string.sub(raw, start, tail + run - 1)
		position = tail + run
		local trimmed = string.match(text, "^%s*(.-)%s*$") or text
		local context, cause, root, relayouts, updates, resizes =
			string.match(trimmed, "^Context=(%S+) Cause=(%S+) Root=(%S+) Relayouts=(%d+) Updates=(%d+) Resizes=(%d+)")
		if
			context ~= nil
			and cause ~= nil
			and root ~= nil
			and relayouts ~= nil
			and updates ~= nil
			and resizes ~= nil
		then
			table.insert(records, {
				context = context,
				cause = cause,
				root = root,
				relayouts = tonumber(relayouts) or 0,
				updates = tonumber(updates) or 0,
				resizes = tonumber(resizes) or 0,
			})
		end
	end
	return records
end

function Microprofiler.isFramework(name: string): boolean
	for _, prefix in Microprofiler.FRAMEWORK_PREFIXES do
		if string.sub(name, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

function Microprofiler.render(path: string, dump: Dump, options: Options): { string }
	local lines: { string } = {}
	local frequency = dump.frequency
	local frames = dump.frames
	table.insert(lines, "")
	table.insert(lines, ("=== %s ==="):format(path))
	if frames == 0 then
		table.insert(lines, "  WINDOW=0 - NO AGGREGATE, THIS CAPTURE HAS NO TIMINGS.")
		table.insert(lines, "  The timer table and names are present and every count is zero. The")
		table.insert(lines, "  MicroProfiler's accumulator had collected no frames when it was dumped.")
	else
		local tick: Row? = nil
		for _, row in dump.rows do
			if row.name == "Facet/tick" or row.name == "LuauUI/tick" then
				tick = row
				break
			end
		end
		local line = ("  window=%d frames  freq=%d"):format(frames, frequency)
		if tick ~= nil then
			line ..= ("  tick==%d (%s)"):format(tick.count, if tick.count == frames then "OK" else "MISMATCH")
		end
		table.insert(lines, line)
	end
	local indexed: { Ranked } = {}
	for order, row in dump.rows do
		if row.count > 0 and (options.all or Microprofiler.isFramework(row.name)) then
			table.insert(indexed, { row = row, order = order })
		end
	end
	table.sort(indexed, function(left: Ranked, right: Ranked): boolean
		if left.row.total ~= right.row.total then
			return left.row.total > right.row.total
		end
		return left.order < right.order
	end)
	local legacy = 0
	for _, entry in indexed do
		if string.sub(entry.row.name, 1, #Microprofiler.LEGACY_PREFIX) == Microprofiler.LEGACY_PREFIX then
			legacy += 1
		end
	end
	if legacy > 0 and not options.all then
		table.insert(
			lines,
			("  NOTE: %d of these scopes carry the pre-rename `%s` prefix — this dump was taken before 2026-08 and its names are part of the evidence."):format(
				legacy,
				Microprofiler.LEGACY_PREFIX
			)
		)
	end
	if #indexed == 0 and not options.all then
		table.insert(
			lines,
			"  NO FRAMEWORK SCOPES IN THIS DUMP. Either the capture was taken with profiler scopes off (they ship OFF — the lab opts in), or it is not a Facet place. Re-run with --all to see what IS in it before concluding the framework was idle."
		)
	end
	if #indexed > 0 then
		table.insert(
			lines,
			("  %-26s%7s%8s%11s%9s%10s%9s"):format("scope", "occ", "occ/fr", "total ms", "ms/occ", "ms/frame", "worst")
		)
		local window = math.max(frames, 1)
		for index = 1, math.min(#indexed, 30) do
			local row = indexed[index].row
			local total = row.total / frequency * 1000
			table.insert(
				lines,
				("  %-26s%7d%8.2f%11.2f%9.4f%10.3f%9.3f"):format(
					row.name,
					row.count,
					row.count / window,
					total,
					total / row.count,
					total / window,
					row.worst / frequency * 1000
				)
			)
		end
	end
	if options.layout then
		local records = Microprofiler.layoutRecords(dump.raw)
		table.insert(lines, "")
		table.insert(lines, ("  engine layout records (%d):"):format(#records))
		table.insert(lines, ("  %-20s%-34s%10s%9s%9s"):format("context", "cause", "relayouts", "updates", "resizes"))
		local relayouts, updates, resizes = 0, 0, 0
		for _, record in records do
			table.insert(
				lines,
				("  %-20s%-34s%10d%9d%9d"):format(
					record.context,
					record.cause,
					record.relayouts,
					record.updates,
					record.resizes
				)
			)
			relayouts += record.relayouts
			updates += record.updates
			resizes += record.resizes
		end
		table.insert(lines, ("  %-54s%10d%9d%9d"):format("TOTAL", relayouts, updates, resizes))
	end
	return lines
end

local function header(fields: { [number]: { width: number, value: number } }, size: number): buffer
	local data = buffer.create(size)
	for offset, field in fields do
		if field.width == 8 then
			buffer.writeu32(data, offset, field.value % 4294967296)
			buffer.writeu32(data, offset + 4, math.floor(field.value / 4294967296))
		else
			buffer.writeu32(data, offset, field.value)
		end
	end
	return data
end

function Microprofiler.synthetic(): string
	local names: { [string]: number } = {}
	local blob: { string } = {}
	local blobLength = 0
	for _, name in { "Facet/tick", "LuauUI/arrange", "Sleep" } do
		names[name] = blobLength
		table.insert(blob, name .. "\0")
		blobLength += #name + 1
	end
	local layout = "Context=Rendering Cause=Facet_Probe Root=/P Relayouts=3 Updates=4 Resizes=5\0"
	local head = header({
		[0x20] = { width = 4, value = 2 },
		[0x28] = { width = 8, value = 1000000000 },
		[0x4C] = { width = 4, value = 3 },
		[0x50] = { width = 4, value = 0x100 + #layout },
		[0xC4] = { width = 4, value = blobLength },
	}, 0x100)
	local records: { string } = {}
	for _, record in
		{
			{ total = 4000000, worst = 3000000, count = 2, name = "Facet/tick" },
			{ total = 20000000, worst = 12000000, count = 6, name = "LuauUI/arrange" },
			{ total = 1000000, worst = 1000000, count = 1, name = "Sleep" },
		}
	do
		local entry = header({
			[0] = { width = 8, value = record.total },
			[8] = { width = 8, value = record.worst },
			[28] = { width = 4, value = record.count },
			[32] = { width = 4, value = names[record.name] },
		}, 80)
		table.insert(records, buffer.tostring(entry))
	end
	return buffer.tostring(head) .. layout .. table.concat(records) .. table.concat(blob)
end

return table.freeze(Microprofiler)
