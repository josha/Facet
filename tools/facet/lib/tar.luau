--!strict

export type Entry = {
	name: string,
	kind: "file" | "directory" | "link" | "other",
	data: string,
}

local Tar = {}

local function field(block: string, offset: number, length: number): string
	local raw = string.sub(block, offset + 1, offset + length)
	local terminated = string.match(raw, "^([^%z]*)") or raw
	return terminated
end

local function octal(block: string, offset: number, length: number): number
	local raw = field(block, offset, length)
	local digits = string.match(raw, "^%s*([0-7]+)")
	if digits == nil then
		return 0
	end
	return tonumber(digits, 8) or 0
end

local function paxRecords(data: string): { [string]: string }
	local records: { [string]: string } = {}
	local index = 1
	while index <= #data do
		local length = string.match(data, "^(%d+) ", index)
		if length == nil then
			break
		end
		local size = tonumber(length) :: number
		local record = string.sub(data, index, index + size - 1)
		local key, value = string.match(record, "^%d+ ([^=]+)=(.*)\n$")
		if key ~= nil and value ~= nil then
			records[key] = value
		end
		index += size
	end
	return records
end

function Tar.read(archive: string): { Entry }
	local entries: { Entry } = {}
	local offset = 0
	local pending: { [string]: string } = {}
	local global: { [string]: string } = {}
	local longName: string? = nil
	while offset + 512 <= #archive do
		local header = string.sub(archive, offset + 1, offset + 512)
		if string.match(header, "^%z+$") then
			break
		end
		local stored = octal(header, 148, 8)
		local sum = 0
		for index = 1, 512 do
			if index > 148 and index <= 156 then
				sum += 32
			else
				sum += string.byte(header, index)
			end
		end
		if sum ~= stored then
			error(("tar header checksum mismatch at offset %d"):format(offset), 0)
		end
		local size = octal(header, 124, 12)
		local typeflag = string.sub(header, 157, 157)
		local data = string.sub(archive, offset + 513, offset + 512 + size)
		offset += 512 + math.ceil(size / 512) * 512
		if typeflag == "x" then
			pending = paxRecords(data)
		elseif typeflag == "g" then
			for key, value in paxRecords(data) do
				global[key] = value
			end
		elseif typeflag == "L" then
			longName = string.match(data, "^([^%z]*)")
		else
			local name = field(header, 0, 100)
			if string.sub(header, 258, 262) == "ustar" then
				local prefix = field(header, 345, 155)
				if prefix ~= "" then
					name = prefix .. "/" .. name
				end
			end
			if longName ~= nil then
				name = longName
			end
			local pathRecord = pending.path or global.path
			if pathRecord ~= nil then
				name = pathRecord
			end
			local kind: "file" | "directory" | "link" | "other" = if typeflag == "0"
					or typeflag == ""
					or typeflag == "\0"
				then "file"
				elseif typeflag == "5" then "directory"
				elseif typeflag == "1" or typeflag == "2" then "link"
				else "other"
			table.insert(entries, { name = name, kind = kind, data = data })
			pending = {}
			longName = nil
		end
	end
	return entries
end

return table.freeze(Tar)
