--!strict
--[[ CIVIL DATES — the calendar model UI.DateTimePicker holds its values in
	(phase5 P5b, D7 as amended by the phase5 design recheck §C/§E.4). Public as
	`Facet.civilDate`.

	A CIVIL DATE IS A WALL-CLOCK FACT, NEVER AN INSTANT: `{ year, month, day }`,
	optionally with `hour` and `minute`, in no time zone at all. Nothing here reads
	a clock except `systemClock`, the default a control uses when the caller
	injects none. Crossing to an instant is the caller's decision and always names
	its offset: `fromUnix(ts, offsetMinutes)` / `toUnix(date, offsetMinutes)` —
	there is no zone database, so a zone with daylight time is the caller's
	conversion to a fixed offset.

	THE ARITHMETIC IS DAYS FROM A FIXED EPOCH (proleptic Gregorian). The engine's
	`DateTime.fromUniversalTime` refuses an out-of-range field (measured: 2023-02-29
	and month 13 both error) rather than normalising it, so it cannot do month
	arithmetic; one integer day count does, exactly, in both directions. ]]
local civil_date = {}

export type CivilDate = { year: number, month: number, day: number, hour: number?, minute: number? }
export type Range = { start: CivilDate?, finish: CivilDate? }
export type Locale = {
	months: { string }?, -- twelve names, January first
	weekdays: { string }?, -- seven short names, Sunday first
	order: ("mdy" | "dmy" | "ymd")?, -- the numeric field order
	separator: string?,
	hourCycle: number?, -- 12 or 24
}

civil_date.ENGLISH = table.freeze({
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
})

local function int(v: any): boolean
	return type(v) == "number" and v == v and v % 1 == 0 and math.abs(v) < 2 ^ 31
end

function civil_date.isLeap(year: number): boolean
	return (year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0
end

local LENGTHS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
function civil_date.daysIn(year: number, month: number): number
	return if month == 2 and civil_date.isLeap(year) then 29 else LENGTHS[month]
end

-- nil when `d` is a civil date (with a complete time when `withTime`), else why not
function civil_date.problem(d: any, withTime: boolean?): string?
	if type(d) ~= "table" then
		return "is a { year, month, day } table"
	end
	if not (int(d.year) and int(d.month) and int(d.day)) then
		return "has whole-number year, month and day"
	end
	if d.month < 1 or d.month > 12 or d.day < 1 or d.day > civil_date.daysIn(d.year, d.month) then
		return `names no calendar day ({d.year}-{d.month}-{d.day})`
	end
	if (d.hour == nil) ~= (d.minute == nil) then
		return "gives hour and minute together or neither"
	end
	if
		d.hour ~= nil
		and not (int(d.hour) and int(d.minute) and d.hour >= 0 and d.hour < 24 and d.minute >= 0 and d.minute < 60)
	then
		return "has an hour 0..23 and a minute 0..59"
	end
	if withTime == true and d.hour == nil then
		return "carries hour and minute when `time = true`"
	end
	return nil
end

-- days since 1970-01-01 (negative before it)
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

-- the date alone, dropping any time
function civil_date.dateOf(d: CivilDate): CivilDate
	return { year = d.year, month = d.month, day = d.day }
end

function civil_date.addDays(d: CivilDate, n: number): CivilDate
	local out = civil_date.fromDays(civil_date.toDays(d) + n)
	out.hour, out.minute = d.hour, d.minute
	return out
end

-- a month `n` months on; the day clamps into it (Jan 31 + 1 -> Feb 28/29)
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

-- -1, 0 or 1 by the DATE (time ignored)
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

-- 1 = Sunday … 7 = Saturday
function civil_date.weekday(d: CivilDate): number
	return (civil_date.toDays(d) + 4) % 7 + 1
end

-- the 42 days of a six-week grid for a month, starting on `weekStart` (1..7)
function civil_date.monthGrid(year: number, month: number, weekStart: number): { CivilDate }
	local first = { year = year, month = month, day = 1 }
	local lead = (civil_date.weekday(first) - weekStart) % 7
	local start = civil_date.toDays(first) - lead
	local out = {}
	for i = 0, 41 do
		table.insert(out, civil_date.fromDays(start + i))
	end
	return out
end

-- within [min, max] inclusive, either bound optional
function civil_date.within(d: CivilDate, min: CivilDate?, max: CivilDate?): boolean
	return (min == nil or civil_date.compare(d, min) >= 0) and (max == nil or civil_date.compare(d, max) <= 0)
end

-- a range clamped into [min, max]; nil when it lies entirely outside
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

-- ===== instants: the caller names the offset ===============================
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

--[[ TODAY, from the engine's clock at a fixed offset (default UTC). The one
	place a clock is read; a control takes `clock` from its caller and falls back
	to this. ]]
function civil_date.systemClock(offsetMinutes: number?): () -> CivilDate
	return function(): CivilDate
		local engine: any = DateTime
		local seconds = if engine ~= nil then engine.now().UnixTimestamp else os.time()
		return civil_date.dateOf(civil_date.fromUnix(seconds, offsetMinutes or 0))
	end
end

-- ===== words ================================================================
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

-- the numeric form in the locale's order, with a time when the value has one
function civil_date.format(d: CivilDate, locale: Locale?): string
	local l: any = locale or civil_date.ENGLISH
	local order = l.order or "mdy"
	local sep = l.separator or "/"
	local fields = {
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

--[[ The inverse of `format`: three numbers in the locale's order (any single
	non-digit separators), then an optional `h:mm` with AM/PM on a 12-hour
	clock. Answers the date or (nil, why); never a different day. ]]
function civil_date.parse(text: string, locale: Locale?, withTime: boolean?): (CivilDate?, string?)
	local l: any = locale or civil_date.ENGLISH
	local order = l.order or "mdy"
	local a, b, c, rest = string.match(text, "^%s*(%d+)%D(%d+)%D(%d+)(.*)$")
	if a == nil then
		return nil, "Enter a date like " .. civil_date.format({ year = 2026, month = 12, day = 31 }, l)
	end
	local parts = { tonumber(a), tonumber(b), tonumber(c) }
	local d: any = {}
	for i = 1, 3 do
		d[({ m = "month", d = "day", y = "year" })[string.sub(order, i, i)]] = parts[i]
	end
	rest = string.gsub(rest or "", "^%s+", "")
	rest = string.gsub(rest, "%s+$", "")
	if rest ~= "" then
		local h, m, meridiem = string.match(string.upper(rest), "^(%d%d?):(%d%d)%s*([AP]?M?)$")
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

return civil_date
