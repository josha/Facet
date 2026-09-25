--!strict
local Types = require("./civil_date_types")
local freeze = require("./freeze")
export type CivilDate = Types.CivilDate
export type Range = Types.Range
export type Locale = Types.Locale
export type Module = Types.Module
local civil_date = {} :: Module

local english: Locale = {
	months = table.freeze({
		"January",
		"February",
		"March",
		"April",
		"May",
		"June",
		"July",
		"August",
		"September",
		"October",
		"November",
		"December",
	}),
	weekdays = table.freeze({ "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa" }),
	order = "mdy",
	separator = "/",
	hourCycle = 12,
}
civil_date.ENGLISH = freeze(english)

local function int(v: unknown): boolean
	return type(v) == "number" and v == v and v % 1 == 0 and math.abs(v) < 2 ^ 31
end

function civil_date.isLeap(year: number): boolean
	return (year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0
end

local LENGTHS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
function civil_date.daysIn(year: number, month: number): number
	return if month == 2 and civil_date.isLeap(year) then 29 else LENGTHS[month]
end

function civil_date.problem(value: unknown, withTime: boolean?): string?
	if type(value) ~= "table" then
		return "is a { year, month, day } table"
	end
	local fields = value :: { [string]: unknown }
	if not (int(fields.year) and int(fields.month) and int(fields.day)) then
		return "has whole-number year, month and day"
	end
	if (fields.hour ~= nil and not int(fields.hour)) or (fields.minute ~= nil and not int(fields.minute)) then
		return "has an hour 0..23 and a minute 0..59"
	end
	local d = value :: CivilDate
	if d.month < 1 or d.month > 12 or d.day < 1 or d.day > civil_date.daysIn(d.year, d.month) then
		return `names no calendar day ({d.year}-{d.month}-{d.day})`
	end
	if (d.hour == nil) ~= (d.minute == nil) then
		return "gives hour and minute together or neither"
	end
	local hour, minute = d.hour, d.minute
	if hour ~= nil and minute ~= nil and not (hour >= 0 and hour < 24 and minute >= 0 and minute < 60) then
		return "has an hour 0..23 and a minute 0..59"
	end
	if withTime == true and d.hour == nil then
		return "carries hour and minute when `time = true`"
	end
	return nil
end

function civil_date.toDays(d: CivilDate): number
	local y = if d.month <= 2 then d.year - 1 else d.year
	local era = (if y >= 0 then y else y - 399) // 400
	local yoe = y - era * 400
	local mp = (d.month + 9) % 12
	local doy = (153 * mp + 2) // 5 + d.day - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	return era * 146097 + doe - 719468
end

function civil_date.fromDays(n: number): CivilDate
	local z = n + 719468
	local era = (if z >= 0 then z else z - 146096) // 146097
	local doe = z - era * 146097
	local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
	local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
	local mp = (5 * doy + 2) // 153
	local day = doy - (153 * mp + 2) // 5 + 1
	local month = if mp < 10 then mp + 3 else mp - 9
	return { year = yoe + era * 400 + (if month <= 2 then 1 else 0), month = month, day = day }
end

function civil_date.dateOf(d: CivilDate): CivilDate
	return { year = d.year, month = d.month, day = d.day }
end

function civil_date.addDays(d: CivilDate, n: number): CivilDate
	local out = civil_date.fromDays(civil_date.toDays(d) + n)
	out.hour, out.minute = d.hour, d.minute
	return out
end

function civil_date.addMonths(d: CivilDate, n: number): CivilDate
	local index = d.year * 12 + (d.month - 1) + n
	local year, month = index // 12, index % 12 + 1
	return {
		year = year,
		month = month,
		day = math.min(d.day, civil_date.daysIn(year, month)),
		hour = d.hour,
		minute = d.minute,
	}
end

function civil_date.compare(a: CivilDate, b: CivilDate): number
	local x, y = civil_date.toDays(a), civil_date.toDays(b)
	return if x < y then -1 elseif x > y then 1 else 0
end

function civil_date.same(a: CivilDate?, b: CivilDate?): boolean
	if a == nil or b == nil then
		return a == b
	end
	return a.year == b.year and a.month == b.month and a.day == b.day and a.hour == b.hour and a.minute == b.minute
end

function civil_date.weekday(d: CivilDate): number
	return (civil_date.toDays(d) + 4) % 7 + 1
end

function civil_date.monthGrid(year: number, month: number, weekStart: number): { CivilDate }
	local first: CivilDate = { year = year, month = month, day = 1 }
	local lead = (civil_date.weekday(first) - weekStart) % 7
	local start = civil_date.toDays(first) - lead
	local out = {}
	for i = 0, 41 do
		table.insert(out, civil_date.fromDays(start + i))
	end
	return out
end

function civil_date.within(d: CivilDate, min: CivilDate?, max: CivilDate?): boolean
	return (min == nil or civil_date.compare(d, min) >= 0) and (max == nil or civil_date.compare(d, max) <= 0)
end

function civil_date.clampRange(range: Range, min: CivilDate?, max: CivilDate?): Range?
	local s, f = range.start, range.finish
	if s == nil or f == nil then
		return range
	end
	if (max ~= nil and civil_date.compare(s, max) > 0) or (min ~= nil and civil_date.compare(f, min) < 0) then
		return nil
	end
	if min ~= nil and civil_date.compare(s, min) < 0 then
		s = civil_date.dateOf(min)
	end
	if max ~= nil and civil_date.compare(f, max) > 0 then
		f = civil_date.dateOf(max)
	end
	return { start = s, finish = f }
end

function civil_date.fromUnix(seconds: number, offsetMinutes: number): CivilDate
	local local_ = math.floor(seconds) + offsetMinutes * 60
	local days = local_ // 86400
	local rest = local_ - days * 86400
	local out = civil_date.fromDays(days)
	out.hour = rest // 3600
	out.minute = (rest % 3600) // 60
	return out
end

function civil_date.toUnix(d: CivilDate, offsetMinutes: number): number
	return civil_date.toDays(d) * 86400 + ((d.hour or 0) * 60 + (d.minute or 0) - offsetMinutes) * 60
end

function civil_date.systemClock(offsetMinutes: number?): () -> CivilDate
	return function(): CivilDate
		local engine = (DateTime :: unknown) :: typeof(DateTime)?
		if offsetMinutes ~= nil or engine == nil then
			local seconds = if engine ~= nil then engine.now().UnixTimestamp else os.time()
			if offsetMinutes ~= nil then
				return civil_date.fromUnix(seconds, offsetMinutes)
			end
			local t = os.date("*t", seconds)
			return { year = t.year, month = t.month, day = t.day, hour = t.hour, minute = t.min }
		end
		local t = (engine.now():ToLocalTime() :: unknown) :: { [string]: number }
		return { year = t.Year, month = t.Month, day = t.Day, hour = t.Hour, minute = t.Minute }
	end
end

local function pad(n: number, width: number): string
	return string.format(`%0{width}d`, n)
end

function civil_date.formatTime(d: CivilDate, hourCycle: number): string
	if d.hour == nil then
		return ""
	end
	local minute = pad(d.minute :: number, 2)
	if hourCycle == 24 then
		return `{pad(d.hour, 2)}:{minute}`
	end
	local h = (d.hour :: number) % 12
	return `{if h == 0 then 12 else h}:{minute} {if (d.hour :: number) < 12 then "AM" else "PM"}`
end

function civil_date.format(d: CivilDate, locale: Locale?): string
	local l: Locale = locale or civil_date.ENGLISH
	local order = l.order or "mdy"
	local sep = l.separator or "/"
	local fields: { [string]: string } = {
		m = pad(d.month, 2),
		d = pad(d.day, 2),
		y = pad(d.year, 4),
	}
	local out = fields[string.sub(order, 1, 1)]
		.. sep
		.. fields[string.sub(order, 2, 2)]
		.. sep
		.. fields[string.sub(order, 3, 3)]
	if d.hour ~= nil then
		out ..= " " .. civil_date.formatTime(d, l.hourCycle or 12)
	end
	return out
end

function civil_date.parse(text: string, locale: Locale?, withTime: boolean?): (CivilDate?, string?)
	local l: Locale = locale or civil_date.ENGLISH
	local order = l.order or "mdy"
	local a, b, c, rest = string.match(text, "^%s*(%d+)%D(%d+)%D(%d+)(.*)$")
	if a == nil then
		return nil, "Enter a date like " .. civil_date.format({ year = 2026, month = 12, day = 31 }, l)
	end
	local texts = { a, b :: string, c :: string }
	local parts: { [string]: number } = {}
	local names: { [string]: string } = { m = "month", d = "day", y = "year" }
	for i = 1, 3 do
		local field = names[string.sub(order, i, i)]
		if field == "year" and #texts[i] < 4 then
			return nil, "Enter a date like " .. civil_date.format({ year = 2026, month = 12, day = 31 }, l)
		end
		parts[field] = tonumber(texts[i]) :: number
	end
	local d: CivilDate = { year = parts.year, month = parts.month, day = parts.day }
	local trailing: string = string.gsub(rest or "", "^%s+", "")
	trailing = string.gsub(trailing, "%s+$", "")
	if trailing ~= "" then
		local h, m, meridiem = string.match(string.upper(trailing), "^(%d%d?):(%d%d)%s*([AP]?M?)$")
		if h == nil then
			return nil, "Enter a time like 9:30 AM or 21:30."
		end
		local hour, minute = tonumber(h) :: number, tonumber(m) :: number
		if meridiem == "AM" or meridiem == "PM" then
			if hour < 1 or hour > 12 then
				return nil, "A 12-hour time runs from 1 to 12."
			end
			hour = hour % 12 + (if meridiem == "PM" then 12 else 0)
		elseif meridiem ~= "" then
			return nil, "Enter a time like 9:30 AM or 21:30."
		elseif (l.hourCycle or 12) == 12 and hour >= 1 and hour <= 12 then
			return nil, "Add AM or PM, or write the 24-hour time like 21:30."
		end
		d.hour, d.minute = hour, minute
	elseif withTime == true then
		return nil, "Add a time, like 9:30 AM."
	end
	local why = civil_date.problem(d)
	if why ~= nil then
		return nil, "That date is not on the calendar."
	end
	return d, nil
end

return (table.freeze(civil_date) :: unknown) :: Module
