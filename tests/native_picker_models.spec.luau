--!strict
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local civil = Facet.civilDate
local expect = t.expect

local TODAY = { year = 2026, month = 9, day = 23 }
local function D(y: number, m: number, d: number): any
	return { year = y, month = m, day = d }
end
local function iso(d: any): string
	if d == nil then
		return "nil"
	end
	local out = string.format("%04d-%02d-%02d", d.year, d.month, d.day)
	if d.hour ~= nil then
		out ..= string.format(" %02d:%02d", d.hour, d.minute)
	end
	return out
end

t.describe("civilDate model", function()
	t.it("counts leap years, clamps month arithmetic and rolls over years", function()
		expect(civil.isLeap(2024)).toBe(true)
		expect(civil.isLeap(1900)).toBe(false)
		expect(civil.isLeap(2000)).toBe(true)
		expect(iso(civil.addMonths(D(2024, 1, 31), 1))).toBe("2024-02-29")
		expect(iso(civil.addMonths(D(2023, 1, 31), 1))).toBe("2023-02-28")
		expect(iso(civil.addMonths(D(2026, 12, 15), 1))).toBe("2027-01-15")
		expect(iso(civil.addMonths(D(2026, 1, 15), -1))).toBe("2025-12-15")
		expect(iso(civil.addDays(D(2026, 12, 31), 1))).toBe("2027-01-01")
		expect(iso(civil.addDays(D(2024, 2, 28), 1))).toBe("2024-02-29")
		expect(civil.weekday(TODAY)).toBe(4)
		for _, n in { -800000, -1, 0, 1, 19999, 800000 } do
			expect(civil.toDays(civil.fromDays(n))).toBe(n)
		end
		expect(civil.problem(D(2023, 2, 29)) ~= nil).toBe(true)
		expect(civil.problem(D(2024, 2, 29))).toBeNil()
		expect(civil.problem({ year = 2024, month = 2, day = 29, hour = 3 }) ~= nil).toBe(true)
		expect(civil.problem({ year = 2024, month = 2, day = 29, hour = 3, minute = 60 }) ~= nil).toBe(true)
		expect(civil.problem(D(2024, 2, 29), true) ~= nil).toBe(true)
		expect(civil.problem("2024-02-29") ~= nil).toBe(true)
		expect(civil.same(D(2024, 2, 29), D(2024, 2, 29))).toBe(true)
		expect(civil.same({ year = 2024, month = 2, day = 29, hour = 1, minute = 0 }, D(2024, 2, 29))).toBe(false)
		expect(civil.compare(D(2024, 2, 29), D(2024, 3, 1))).toBe(-1)
		expect(civil.within(D(2024, 2, 29), D(2024, 3, 1), nil)).toBe(false)
		expect(civil.within(D(2024, 2, 29), nil, D(2024, 3, 1))).toBe(true)
		expect(table.isfrozen(civil)).toBe(true)
	end)

	t.it("lays six weeks from the week start, and a date-only value survives any fixed offset", function()
		local sunday = civil.monthGrid(2026, 9, 1)
		expect(iso(sunday[1])).toBe("2026-08-30")
		expect(#sunday).toBe(42)
		local monday = civil.monthGrid(2026, 9, 2)
		expect(iso(monday[1])).toBe("2026-08-31")
		for _, offset in { -660, 0, 840 } do
			local stored = civil.toUnix(D(2026, 3, 1), offset)
			expect(`{offset}:{iso(civil.dateOf(civil.fromUnix(stored, offset)))}`).toBe(`{offset}:2026-03-01`)
		end
		expect(iso(civil.fromUnix(0, -660))).toBe("1969-12-31 13:00")
	end)

	t.it("writes and reads the numeric form in the locale's order; a non-date is refused, never moved", function()
		expect(civil.format(D(2026, 9, 3))).toBe("09/03/2026")
		expect(civil.format(D(2026, 9, 3), { order = "dmy", separator = "." })).toBe("03.09.2026")
		local t12 = { year = 2026, month = 9, day = 3, hour = 0, minute = 5 }
		expect(civil.format(t12)).toBe("09/03/2026 12:05 AM")
		expect(civil.format(t12, { hourCycle = 24 })).toBe("09/03/2026 00:05")
		expect(iso(civil.parse("9/3/2026"))).toBe("2026-09-03")
		expect(iso(civil.parse("03.09.2026", { order = "dmy" }))).toBe("2026-09-03")
		expect(iso(civil.parse("2026-09-03", { order = "ymd" }))).toBe("2026-09-03")
		expect(iso(civil.parse("09/03/2026 9:30 PM", nil, true))).toBe("2026-09-03 21:30")
		expect(iso(civil.parse("09/03/2026 21:30", nil, true))).toBe("2026-09-03 21:30")
		local bare, why = civil.parse("09/03/2026 12:30", nil, true)
		expect(`{iso(bare)}:{why}`).toBe("nil:Add AM or PM, or write the 24-hour time like 21:30.")
		expect(iso(civil.parse("09/03/2026 12:30", { hourCycle = 24 }, true))).toBe("2026-09-03 12:30")
		expect(iso(civil.parse("09/03/2026 0:30", nil, true))).toBe("2026-09-03 00:30")
		for _, bad in { "02/30/2026", "13/01/2026", "hello", "09/03/2026 25:00", "12/31/26" } do
			expect(`{bad}:{iso(civil.parse(bad, nil, false))}`).toBe(`{bad}:nil`)
		end
		local missing, reason = civil.parse("09/03/2026", nil, true)
		expect(missing).toBeNil()
		expect(reason).toBe("Add a time, like 9:30 AM.")
		local r = civil.clampRange({ start = D(2026, 1, 1), finish = D(2026, 1, 31) }, D(2026, 1, 10), nil)
		expect(iso((r :: any).start)).toBe("2026-01-10")
		expect(iso((r :: any).finish)).toBe("2026-01-31")
		expect(civil.clampRange({ start = D(2025, 1, 1), finish = D(2025, 1, 31) }, D(2026, 1, 10), nil)).toBeNil()
	end)

	t.it("the default clock reads the player's local wall clock, not UTC", function()
		local env: any = getfenv(0)
		local saved = env.DateTime
		env.DateTime = {
			now = function()
				return {
					UnixTimestamp = civil.toUnix({ year = 2026, month = 9, day = 24, hour = 1, minute = 0 }, 0),
					ToLocalTime = function()
						return { Year = 2026, Month = 9, Day = 23, Hour = 18, Minute = 0 }
					end,
				}
			end,
		}
		local ok, err = pcall(function()
			expect(iso(civil.systemClock()())).toBe("2026-09-23 18:00")
			expect(iso(civil.systemClock(0)())).toBe("2026-09-24 01:00")
		end)
		env.DateTime = saved
		assert(ok, err)
	end)
end)

t.describe("arithmetic recipe", function()
	t.it("four operators, parentheses, both spellings, and no division by zero", function()
		local parse = Facet.recipes.arithmetic.parse
		expect(parse("2*3")).toBe(6)
		expect(parse("10/4")).toBe(2.5)
		expect(parse("(1+2)*3")).toBe(9)
		expect(parse("6 \u{00F7} 2")).toBe(3)
		expect(parse("3 \u{00D7} 4")).toBe(12)
		expect(parse("\u{2212}4")).toBe(-4)
		expect(parse(" 1.5 + .5 ")).toBe(2)
		for _, bad in { "1/0", "2 +", "(1+2", "print('hi')", "1e5", "", "0x1F" } do
			expect(`{bad}: {parse(bad)}`).toBe(`{bad}: nil`)
		end
		expect(parse(42)).toBeNil()
		expect(table.isfrozen(Facet.recipes)).toBe(true)
		expect(table.isfrozen(Facet.recipes.arithmetic)).toBe(true)
	end)

	t.it("it is total: length and nesting are bounded, so a hostile string answers nil", function()
		local parse = Facet.recipes.arithmetic.parse
		expect(parse(string.rep("(", 5000) .. "1" .. string.rep(")", 5000))).toBeNil()
		expect(parse(string.rep("-", 5000) .. "1")).toBeNil()
		expect(parse(string.rep("1+", 500) .. "1")).toBeNil()
		expect(parse(string.rep("9", 400))).toBeNil()
		expect(parse("(((1 + 2)))")).toBe(3)
		expect(parse("---4")).toBe(-4)
		expect(parse(string.rep("1+", 60) .. "1")).toBe(61)
	end)
end)
