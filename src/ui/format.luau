--!strict
export type CompactOptions = { significantDigits: number? }
export type GroupedOptions = { decimals: number?, separator: string? }
export type DurationOptions = { hours: boolean? }

local function finite(value: number)
	assert(value == value and math.abs(value) < math.huge, "Facet format requires a finite number")
end

local function integer(value: number, low: number, high: number): number
	assert(value >= low and value <= high and value % 1 == 0, `Facet format precision must be {low} through {high}`)
	return value
end

local function trim(value: string): string
	if string.find(value, ".", 1, true) then
		return (string.gsub(string.gsub(value, "0+$", ""), "%.$", ""))
	end
	return value
end

local function compact(value: number, options: CompactOptions?): string
	finite(value)
	local digits = integer(if options and options.significantDigits then options.significantDigits else 3, 1, 15)
	local suffixes = { "", "K", "M", "B", "T" }
	local magnitude, tier = math.abs(value), 1
	while magnitude >= 1000 and tier < #suffixes do
		magnitude /= 1000
		tier += 1
	end
	local rounded = assert(tonumber(string.format(`%.{digits}g`, magnitude)))
	if rounded >= 1000 and tier < #suffixes then
		rounded /= 1000
		tier += 1
	end
	local places = if rounded == 0 then 0 else math.max(0, digits - 1 - math.floor(math.log10(rounded)))
	local text = if places > 15
		then string.format(`%.{digits}g`, rounded)
		else trim(string.format(`%.{places}f`, rounded))
	return (if value < 0 and rounded ~= 0 then "-" else "") .. text .. suffixes[tier]
end

local function grouped(value: number, options: GroupedOptions?): string
	finite(value)
	local decimals = integer(if options and options.decimals then options.decimals else 0, 0, 15)
	local separator = if options and options.separator then options.separator else ","
	local fixed = string.format(`%.{decimals}f`, math.abs(value))
	local whole, fraction = string.match(fixed, "^(%d+)(.*)$")
	assert(whole and fraction)
	local parts: { string } = {}
	local first = (#whole - 1) % 3 + 1
	table.insert(parts, string.sub(whole, 1, first))
	for index = first + 1, #whole, 3 do
		table.insert(parts, string.sub(whole, index, index + 2))
	end
	return (if value < 0 and tonumber(fixed) ~= 0 then "-" else "") .. table.concat(parts, separator) .. fraction
end

local function duration(seconds: number, options: DurationOptions?): string
	finite(seconds)
	local total = math.floor(math.max(0, seconds))
	local hours = math.floor(total / 3600)
	local minutes = math.floor(total / 60) % 60
	local tail = string.format("%02d", total % 60)
	if hours > 0 or (options and options.hours) then
		return string.format("%.0f:%02d:%s", hours, minutes, tail)
	end
	return string.format("%d:%s", minutes, tail)
end

return table.freeze({ compact = compact, grouped = grouped, duration = duration })
