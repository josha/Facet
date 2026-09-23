--!strict
--[[ UI.DateTimePicker and Facet.civilDate (phase5 P5b). The model cases pin the
	calendar arithmetic (leap years, rollover, week start, fixed-offset instants);
	the control cases drive real routes (a tap on a day, typed entry, the arrows,
	L1/R1, A and B, presets, Apply/Cancel) with an injected clock and read the
	MOUNTED paint and the caller's value. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local world = require("./lib/world")
local Facet = require("../src") :: any
local civil = Facet.civilDate
local Compose = Facet.Compose

local POINTER = { mouse = true, keyboard = true, touch = false, gamepad = false }
local TOUCH = { mouse = false, keyboard = false, touch = true, gamepad = false }
local PAD = { mouse = false, keyboard = false, touch = false, gamepad = true }
local TODAY = { year = 2026, month = 9, day = 23 }
local function clock()
	return TODAY
end

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

local function mount(spec: any, opts: any?): any
	local o = opts or {}
	local w = world.new({
		viewport = o.viewport or { x = 0, y = 0, w = 600, h = 900 },
		reducedMotion = true,
		capabilities = o.capabilities or POINTER,
		preferredInput = o.preferredInput,
		displaySize = o.displaySize,
		hostOpts = { keyboardNavigation = true },
	})
	local UI = w.UI
	local full = table.clone(spec)
	full.clock = full.clock or clock
	w.present(function()
		return UI.Screen("S")({
			padding = 0,
			UI.VStack("Col")({
				width = UI.fill(),
				UI.DateTimePicker("P")(full),
				UI.Button("Other")({ label = "Other" }),
			}),
		})
	end)
	w.settle(3)
	return w
end

local function caller(initial: any, accept: boolean?): (any, { any }, (any) -> ())
	local cell = Compose.cell(initial)
	local seen: { any } = {}
	return cell,
		seen,
		function(next: any)
			table.insert(seen, next)
			if accept ~= false then
				cell:set(next)
			end
		end
end

local function find(w: any, suffix: string): string?
	for _, p in w.adapter.paths() do
		if string.sub(p, -#suffix) == suffix then
			return p
		end
	end
	return nil
end
local function must(w: any, suffix: string): string
	local p = find(w, suffix)
	assert(p ~= nil, `nothing mounted at *{suffix}`)
	return p
end

-- the calendar icon inside a field's plate (in the typed field's trailing slot
-- or beside the shown words)
local function opener(w: any, id: string): string
	for _, p in w.adapter.paths() do
		if string.find(p, `/{id}/Field/`, 1, true) ~= nil and string.sub(p, -5) == "/Open" then
			return p
		end
	end
	error(`no calendar icon under {id}`)
end

local function open(w: any)
	w.adapter.tap(opener(w, "P"), { source = "pointer", x = 5, y = 5 })
	w.settle(3)
end

-- the cell path in pane k showing date d
local function cellOf(w: any, d: any, k: number?): string
	local dump = w.record("P").dump()
	local m = civil.addMonths(D(dump.month.year, dump.month.month, 1), (k or 1) - 1)
	for i, day in civil.monthGrid(m.year, m.month, dump.weekStart) do
		if civil.compare(day, d) == 0 then
			return dump.cellPaths[k or 1][i]
		end
	end
	error(`{iso(d)} is not on pane {k or 1}`)
end

local function discShown(w: any, path: string): boolean
	return w.adapter.visibleOf(path .. "/Layers/Disc") == true
end

describe("civilDate: the calendar model", function()
	it("counts leap years, clamps month arithmetic and rolls over years", function()
		expect(civil.isLeap(2024)).toBe(true)
		expect(civil.isLeap(1900)).toBe(false)
		expect(civil.isLeap(2000)).toBe(true)
		expect(iso(civil.addMonths(D(2024, 1, 31), 1))).toBe("2024-02-29")
		expect(iso(civil.addMonths(D(2023, 1, 31), 1))).toBe("2023-02-28")
		expect(iso(civil.addMonths(D(2026, 12, 15), 1))).toBe("2027-01-15")
		expect(iso(civil.addMonths(D(2026, 1, 15), -1))).toBe("2025-12-15")
		expect(iso(civil.addDays(D(2026, 12, 31), 1))).toBe("2027-01-01")
		expect(iso(civil.addDays(D(2024, 2, 28), 1))).toBe("2024-02-29")
		expect(civil.weekday(TODAY)).toBe(4) -- a Wednesday, as the engine reads it
		for _, n in { -800000, -1, 0, 1, 19999, 800000 } do
			expect(civil.toDays(civil.fromDays(n))).toBe(n)
		end
		expect(civil.problem(D(2023, 2, 29)) ~= nil).toBe(true)
		expect(civil.problem(D(2024, 2, 29))).toBeNil()
	end)

	it("lays six weeks from the week start, and a date-only value survives any fixed offset", function()
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

	it("writes and reads the numeric form in the locale's order; a non-date is refused, never moved", function()
		expect(civil.format(D(2026, 9, 3))).toBe("09/03/2026")
		expect(civil.format(D(2026, 9, 3), { order = "dmy", separator = "." })).toBe("03.09.2026")
		local t12 = { year = 2026, month = 9, day = 3, hour = 0, minute = 5 }
		expect(civil.format(t12)).toBe("09/03/2026 12:05 AM")
		expect(civil.format(t12, { hourCycle = 24 })).toBe("09/03/2026 00:05")
		expect(iso(civil.parse("9/3/2026"))).toBe("2026-09-03")
		expect(iso(civil.parse("03.09.2026", { order = "dmy" }))).toBe("2026-09-03")
		expect(iso(civil.parse("09/03/2026 9:30 PM", nil, true))).toBe("2026-09-03 21:30")
		expect(iso(civil.parse("09/03/2026 21:30", nil, true))).toBe("2026-09-03 21:30")
		-- on a 12-hour clock a bare 1-12 hour is ambiguous: it asks for AM or PM
		local bare, why = civil.parse("09/03/2026 12:30", nil, true)
		expect(`{iso(bare)}:{why}`).toBe("nil:Add AM or PM, or write the 24-hour time like 21:30.")
		expect(iso(civil.parse("09/03/2026 12:30", { hourCycle = 24 }, true))).toBe("2026-09-03 12:30")
		expect(iso(civil.parse("09/03/2026 0:30", nil, true))).toBe("2026-09-03 00:30")
		for _, bad in { "02/30/2026", "13/01/2026", "hello", "09/03/2026 25:00", "12/31/26" } do
			expect(`{bad}:{iso(civil.parse(bad, nil, false))}`).toBe(`{bad}:nil`)
		end
		expect(civil.parse("09/03/2026", nil, true)).toBeNil()
		local r = civil.clampRange({ start = D(2026, 1, 1), finish = D(2026, 1, 31) }, D(2026, 1, 10), nil)
		expect(iso((r :: any).start)).toBe("2026-01-10")
		expect(civil.clampRange({ start = D(2025, 1, 1), finish = D(2025, 1, 31) }, D(2026, 1, 10), nil)).toBeNil()
	end)
end)

describe("civilDate: the player's clock", function()
	it("the default clock reads the player's local wall clock, not UTC", function()
		local env: any = getfenv(0)
		local saved = env.DateTime
		-- 01:00 UTC on the 24th is 18:00 on the 23rd at UTC-7
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

describe("DateTimePicker: a single date", function()
	it("the calendar opens anchored on the chosen day's month; a pick commits once and closes", function()
		local cell, _, change = caller(D(2026, 2, 14))
		local commits = {}
		local w = mount({
			value = cell,
			onChange = change,
			onCommit = function(v: any)
				table.insert(commits, iso(v))
			end,
		})
		open(w)
		local dump = w.record("P").dump()
		expect(dump.route).toBe("popover")
		expect(`{dump.month.year}-{dump.month.month}`).toBe("2026-2")
		expect(discShown(w, cellOf(w, D(2026, 2, 14)))).toBe(true)
		-- focus lands on the chosen day
		expect(w.pres.focus.focused:peek()).toBe(cellOf(w, D(2026, 2, 14)))
		w.adapter.tap(cellOf(w, D(2026, 2, 20)))
		w.settle(3)
		expect(iso(cell:peek())).toBe("2026-02-20")
		expect(table.concat(commits, ",")).toBe("2026-02-20")
		expect(w.record("P").dump().presented).toBe(false)
	end)

	it("a refused pick paints nothing; a disabled or out-of-bounds day is focusable, inert and struck", function()
		local cell, seen, change = caller(D(2026, 9, 10), false)
		local w = mount({
			value = cell,
			onChange = change,
			min = D(2026, 9, 5),
			isDateDisabled = function(d: any)
				return d.day == 15
			end,
		})
		open(w)
		w.adapter.tap(cellOf(w, D(2026, 9, 12)))
		w.settle(2)
		expect(#seen).toBe(1)
		expect(discShown(w, cellOf(w, D(2026, 9, 12)))).toBe(false)
		expect(discShown(w, cellOf(w, D(2026, 9, 10)))).toBe(true)
		for _, day in { D(2026, 9, 15), D(2026, 9, 1) } do
			local path = cellOf(w, day)
			expect(w.pres.focus.focusOn(path)).toBe(true)
			expect(w.adapter.visibleOf(path .. "/Layers/Strike")).toBe(true)
			w.press("ButtonA")
			w.settle(1)
		end
		expect(#seen).toBe(1)
	end)

	it("typed entry commits a date; a refused text stays with its error and commits nothing", function()
		local cell, seen, change = caller(nil)
		local commits = {}
		local w = mount({
			value = cell,
			onChange = change,
			label = "Race day",
			max = D(2026, 12, 31),
			onCommit = function(v: any)
				table.insert(commits, iso(v))
			end,
		})
		local entry = must(w, "/Words/then/Entry/Input/Row/Field")
		-- one plate: the field's own, never a second one inside it
		expect(w.adapter.node(must(w, "/P/Field")).props.surface).toBe("plain")
		expect(w.adapter.node(must(w, "/Words/then/Entry/Input")).props.surface).toBe("chip")
		-- the calendar icon sits inside that plate, at its trailing edge
		expect(string.find(opener(w, "P"), "/Entry/Input/Row/Trailing/Open", 1, true) ~= nil).toBe(true)
		-- ...and the calendar hangs from the FIELD: below it, start-aligned
		open(w)
		local field = w.adapter.node(must(w, "/P/Field")).rect
		local surface = w.adapter.node(must(w, "/Popover-P/Layer/Surface")).rect
		-- (the screen's own 8 px edge inset holds it off x = 0)
		expect(`{surface.x - field.x <= 8} {surface.y >= field.y + field.h}`).toBe("true true")
		-- the icon toggles: a second press closes it
		w.adapter.tap(opener(w, "P"), { source = "pointer", x = 5, y = 5 })
		w.settle(3)
		expect(w.record("P").dump().presented).toBe(false)
		local function typeCommit(text: string)
			w.adapter.focusText(entry)
			w.adapter.node(entry).textBuffer = ""
			w.adapter.typeText(entry, text)
			w.adapter.commitText(entry)
			w.settle(2)
		end
		typeCommit("02/30/2026")
		expect(#seen).toBe(0)
		expect(w.record("P").dump().typedError ~= "").toBe(true)
		-- the refusal borders the field's plate in the danger role
		local plate = must(w, "/Words/then/Entry/Input")
		expect(w.adapter.node(plate).props.stroke ~= nil).toBe(true)
		expect(w.adapter.node(entry).props.text).toBe("02/30/2026")
		typeCommit("01/05/2027")
		expect(#seen).toBe(0)
		typeCommit("7/4/2026")
		expect(w.adapter.node(plate).props.stroke).toBeNil()
		expect(iso(cell:peek())).toBe("2026-07-04")
		expect(table.concat(commits, ",")).toBe("2026-07-04")
		expect(w.record("P").dump().typedError).toBe("")
		expect(w.adapter.node(entry).props.text).toBe("07/04/2026")
		-- a two-digit year is not a year
		typeCommit("12/31/26")
		expect(iso(cell:peek())).toBe("2026-07-04")
		expect(w.record("P").dump().typedError ~= "").toBe(true)
	end)

	it("a typed range reads back its own words in every locale order; a draft's typed text only proposes", function()
		for _, locale in { { order = "mdy" }, { order = "dmy", separator = "." }, { order = "ymd", separator = "-" } } do
			for _, draft in { false, true } do
				local cell, _, change = caller({ start = D(2026, 1, 2), finish = D(2026, 1, 9) })
				local commits = 0
				local w = mount({
					selection = "range",
					range = cell,
					onRangeChange = change,
					draft = draft,
					locale = locale,
					onRangeCommit = function()
						commits += 1
					end,
				})
				local entry = must(w, "/Words/then/Entry/Input/Row/Field")
				-- the shown words, with the start moved a day: edited as a player would
				local shown = w.adapter.node(entry).props.text
				local old = civil.format(D(2026, 1, 2), locale)
				local at = string.find(shown, old, 1, true) :: number
				local edited = civil.format(D(2026, 1, 3), locale) .. string.sub(shown, at + #old)
				w.adapter.focusText(entry)
				w.adapter.node(entry).textBuffer = ""
				w.adapter.typeText(entry, edited)
				w.adapter.commitText(entry)
				w.settle(2)
				local where = `{locale.order} draft={draft}`
				expect(`{where} {w.record("P").dump().typedError}`).toBe(`{where} `)
				expect(`{where} {iso(cell:peek().start)}..{iso(cell:peek().finish)}`).toBe(
					`{where} 2026-01-03..2026-01-09`
				)
				expect(`{where} {commits}`).toBe(`{where} {if draft then 0 else 1}`)
			end
		end
		-- and a single draft's typed date proposes without committing
		local cell, _, change = caller(nil)
		local commits = 0
		local w = mount({
			value = cell,
			onChange = change,
			draft = true,
			onCommit = function()
				commits += 1
			end,
		})
		local entry = must(w, "/Words/then/Entry/Input/Row/Field")
		w.adapter.focusText(entry)
		w.adapter.typeText(entry, "7/4/2026")
		w.adapter.commitText(entry)
		w.settle(2)
		expect(iso(cell:peek())).toBe("2026-07-04")
		expect(commits).toBe(0)
	end)

	it(
		"keyboard and pad: the arrows walk the grid with its contribution attached, a row's end continues, L1/R1 page",
		function()
			local cell, _, change = caller(D(2026, 9, 16))
			local w = mount({ value = cell, onChange = change }, { capabilities = PAD, preferredInput = "Gamepad" })
			w.pres.focus.focusOn(opener(w, "P"))
			w.press("ButtonA")
			w.settle(3)
			local start = cellOf(w, D(2026, 9, 16))
			expect(w.pres.focus.focused:peek()).toBe(start)
			w.press("DPadRight")
			w.settle(1)
			expect(w.pres.focus.focused:peek()).toBe(cellOf(w, D(2026, 9, 17)))
			w.press("DPadDown")
			w.settle(1)
			expect(w.pres.focus.focused:peek()).toBe(cellOf(w, D(2026, 9, 24)))
			-- Saturday's right is the next Sunday
			expect(w.pres.focus.focusOn(cellOf(w, D(2026, 9, 19)))).toBe(true)
			w.press("DPadRight")
			w.settle(1)
			expect(w.pres.focus.focused:peek()).toBe(cellOf(w, D(2026, 9, 20)))
			-- R1 pages the month; the ring keeps its cell
			local held = w.pres.focus.focused:peek()
			w.press("ButtonR1")
			w.settle(2)
			local d = w.record("P").dump()
			expect(`{d.month.year}-{d.month.month}`).toBe("2026-10")
			expect(w.pres.focus.focused:peek()).toBe(held)
			w.press("ButtonL1")
			w.press("ButtonL1")
			w.settle(2)
			d = w.record("P").dump()
			expect(`{d.month.year}-{d.month.month}`).toBe("2026-8")
			-- A chooses; the value moves and the panel closes
			w.press("ButtonA")
			w.settle(3)
			expect(cell:peek().month).toBe(8)
			expect(w.record("P").dump().presented).toBe(false)
		end
	)

	it(
		"the grid is one Tab stop; the arrows walk days across months; grey days are no stop; paging stops at the bounds",
		function()
			local cell, _, change = caller(D(2026, 9, 16))
			-- a draft, so the grid has a row of actions below it
			local w = mount({ value = cell, onChange = change, draft = true, max = D(2026, 10, 31) })
			open(w)
			local function month(): string
				local d = w.record("P").dump()
				return `{d.month.year}-{d.month.month}`
			end
			local function isDay(path: string?): boolean
				return path ~= nil and string.match(path, "/Days/R%d/D%d+$") ~= nil
			end
			expect(w.pres.focus.focused:peek()).toBe(cellOf(w, D(2026, 9, 16)))
			expect(w.adapter.visibleOf(must(w, "/Calendar/PageHint")) == true).toBe(false)
			-- left past the first day pages back into August; right pages forward again
			expect(w.pres.focus.focusOn(cellOf(w, D(2026, 9, 1)))).toBe(true)
			w.press("Left")
			w.settle(2)
			expect(month()).toBe("2026-8")
			expect(w.pres.focus.focused:peek()).toBe(cellOf(w, D(2026, 8, 31)))
			w.press("Right")
			w.settle(2)
			expect(month()).toBe("2026-9")
			expect(w.pres.focus.focused:peek()).toBe(cellOf(w, D(2026, 9, 1)))
			-- up walks a week at a time, and past the first row leaves for the header
			expect(w.pres.focus.focusOn(cellOf(w, D(2026, 9, 16)))).toBe(true)
			for _ = 1, 2 do
				w.press("Up")
				w.settle(1)
			end
			expect(w.pres.focus.focused:peek()).toBe(cellOf(w, D(2026, 9, 2)))
			w.press("Up")
			w.settle(2)
			expect(month()).toBe("2026-9")
			expect(string.find(w.pres.focus.focused:peek() or "", "/Header/", 1, true) ~= nil).toBe(true)
			expect(w.pres.focus.focusOn(cellOf(w, D(2026, 9, 2)))).toBe(true)
			-- the neighbouring month's grey days are tappable but never a stop
			expect(w.pres.focus.focusOn(w.record("P").dump().cellPaths[1][1])).toBe(false)
			-- Tab leaves the grid in one press; Shift+Tab comes back to the chosen day
			w.press("Tab")
			w.settle(1)
			expect(isDay(w.pres.focus.focused:peek())).toBe(false)
			w.system.deviceKey("LeftShift", true)
			w.press("Tab")
			w.system.deviceKey("LeftShift", false)
			w.settle(1)
			expect(w.pres.focus.focused:peek()).toBe(cellOf(w, D(2026, 9, 16)))
			-- October is the last month with a day to choose: Next and R1 stop there
			w.adapter.tap(must(w, "/Header/Next"))
			w.settle(2)
			expect(month()).toBe("2026-10")
			expect(w.adapter.node(must(w, "/Header/Next")).props.enabled).toBe(false)
			expect(w.pres.focus.focusOn(cellOf(w, D(2026, 10, 28)))).toBe(true)
			w.press("ButtonR1")
			w.settle(2)
			expect(month()).toBe("2026-10")
			-- and Down from the last week leaves the grid for the actions below
			w.press("Down")
			w.settle(2)
			expect(month()).toBe("2026-10")
			expect(string.find(w.pres.focus.focused:peek() or "", "/Actions/", 1, true) ~= nil).toBe(true)
		end
	)

	it(
		"a draft on a TV: Down from any day leaves the months for Apply; Up from the first row reaches the header",
		function()
			for _, start in { D(2026, 9, 1), D(2026, 9, 16), D(2026, 9, 24), D(2026, 9, 30) } do
				local cell, _, change = caller({ year = 2026, month = 9, day = 16, hour = 9, minute = 30 })
				local commits = 0
				local w = mount({
					value = cell,
					onChange = change,
					draft = true,
					time = true,
					onCommit = function()
						commits += 1
					end,
				}, { capabilities = PAD, preferredInput = "Gamepad", displaySize = "Large" })
				w.pres.focus.focusOn(opener(w, "P"))
				w.press("ButtonA")
				w.settle(3)
				local held = w.record("P").dump().month
				-- a live pad is told which keys page the month
				expect(w.adapter.visibleOf(must(w, "/Calendar/PageHint"))).toBe(true)
				expect(w.pres.focus.focusOn(cellOf(w, start, #w.record("P").dump().cellPaths))).toBe(true)
				local function at(): string
					return w.pres.focus.focused:peek() or ""
				end
				for _ = 1, 12 do
					if string.find(at(), "/Actions/", 1, true) then
						break
					end
					w.press("DPadDown")
					w.settle(2)
				end
				expect(string.find(at(), "/Actions/", 1, true) ~= nil).toBe(true)
				-- leaving never paged the months
				expect(w.record("P").dump().month.month).toBe(held.month)
				for _ = 1, 3 do
					if string.sub(at(), -6) == "/Apply" then
						break
					end
					w.press("DPadRight")
					w.settle(1)
				end
				expect(string.sub(at(), -6)).toBe("/Apply")
				w.press("ButtonA")
				w.settle(3)
				expect(commits).toBe(1)
			end
			local cell, _, change = caller(D(2026, 9, 16))
			local w = mount(
				{ value = cell, onChange = change, draft = true },
				{ capabilities = PAD, preferredInput = "Gamepad", displaySize = "Large" }
			)
			w.pres.focus.focusOn(opener(w, "P"))
			w.press("ButtonA")
			w.settle(3)
			expect(w.pres.focus.focusOn(cellOf(w, D(2026, 9, 3)))).toBe(true)
			w.press("DPadUp")
			w.settle(2)
			expect(string.find(w.pres.focus.focused:peek() or "", "/Header/", 1, true) ~= nil).toBe(true)
			expect(w.record("P").dump().month.month).toBe(9)
		end
	)

	it("a pad sets a date and time: each pick commits, B keeps it and returns focus; a draft's B restores", function()
		for _, draft in { false, true } do
			local cell, _, change = caller({ year = 2026, month = 9, day = 16, hour = 9, minute = 30 })
			local commits = {}
			local w = mount({
				value = cell,
				onChange = change,
				time = true,
				draft = draft,
				onCommit = function(v: any)
					table.insert(commits, iso(v))
				end,
			}, { capabilities = PAD, preferredInput = "Gamepad" })
			local button = opener(w, "P")
			w.pres.focus.focusOn(button)
			w.press("ButtonA")
			w.settle(3)
			w.pres.focus.focusOn(cellOf(w, D(2026, 9, 18)))
			w.press("ButtonA")
			w.settle(2)
			expect(iso(cell:peek())).toBe("2026-09-18 09:30")
			expect(w.record("P").dump().presented).toBe(true)
			w.press("ButtonB")
			w.settle(3)
			expect(w.pres.focus.focused:peek()).toBe(button)
			if draft then
				expect(iso(cell:peek())).toBe("2026-09-16 09:30")
				expect(#commits).toBe(0)
			else
				expect(iso(cell:peek())).toBe("2026-09-18 09:30")
				expect(table.concat(commits, ",")).toBe("2026-09-18 09:30")
			end
		end
	end)

	it("time: hour and minute fields step on the minute grid, AM/PM flips, and a touch list sets both", function()
		local cell, _, change = caller({ year = 2026, month = 9, day = 16, hour = 9, minute = 30 })
		local w = mount({ value = cell, onChange = change, time = true, minuteStep = 15, style = "inline" })
		w.adapter.tap(must(w, "/Half/Indicator/Options/Opt2"))
		w.settle(2)
		expect(iso(cell:peek())).toBe("2026-09-16 21:30")
		w.adapter.tap(must(w, "/Minute/Input/Row/Increment"))
		w.settle(2)
		expect(iso(cell:peek())).toBe("2026-09-16 21:45")
		-- the top step is the last on the grid, never :59
		w.adapter.tap(must(w, "/Minute/Input/Row/Increment"))
		w.settle(2)
		expect(iso(cell:peek())).toBe("2026-09-16 21:45")
		expect(find(w, "/TouchTimes/then/Times")).toBeNil()
		local touch = mount(
			{ value = cell, onChange = change, time = true, minuteStep = 30, style = "inline" },
			{ capabilities = TOUCH, preferredInput = "Touch" }
		)
		expect(find(touch, "/TouchTimes/then/Times") ~= nil).toBe(true)
		-- the list opens at the held time, not at midnight
		expect(find(touch, "/Times/Canvas/W/[0:0]/Row/Time")).toBeNil()
		touch.adapter.tap(must(touch, "/Times/Canvas/W/[22:0]/Row/Time"))
		touch.settle(2)
		expect(iso(cell:peek())).toBe("2026-09-16 22:00")
	end)
end)

describe("DateTimePicker: ranges, presets and drafts", function()
	local function presets(): { any }
		return {
			{
				id = "week",
				label = "This week",
				range = function(today: any)
					local start = civil.addDays(today, -(civil.weekday(today) - 1))
					return { start = start, finish = civil.addDays(start, 6) }
				end,
			},
			{
				id = "lastYear",
				label = "Last year",
				range = function(today: any)
					return { start = D(today.year - 1, 1, 1), finish = D(today.year - 1, 12, 31) }
				end,
			},
			{
				id = "month",
				label = "This month",
				range = function(today: any)
					return { start = D(today.year, today.month, 1), finish = D(today.year, today.month, 30) }
				end,
			},
		}
	end

	it("the first pick anchors, an earlier second pick swaps, and onRangeCommit waits for both ends", function()
		local cell, seen, change = caller({})
		local commits = {}
		local w = mount({
			selection = "range",
			range = cell,
			onRangeChange = change,
			onRangeCommit = function(r: any)
				table.insert(commits, `{iso(r.start)}..{iso(r.finish)}`)
			end,
			referenceDate = D(2026, 12, 1),
		})
		open(w)
		w.adapter.tap(cellOf(w, D(2026, 12, 20)))
		w.settle(2)
		expect(#commits).toBe(0)
		expect(iso(cell:peek().start)).toBe("2026-12-20")
		-- across the year: page forward is not needed, the grid's grey days reach January
		w.adapter.tap(cellOf(w, D(2026, 12, 5)))
		w.settle(2)
		expect(`{iso(cell:peek().start)}..{iso(cell:peek().finish)}`).toBe("2026-12-05..2026-12-20")
		expect(table.concat(commits, ",")).toBe("2026-12-05..2026-12-20")
		expect(#seen).toBe(2)
		open(w)
		expect(w.adapter.visibleOf(cellOf(w, D(2026, 12, 12)) .. "/Layers/Band")).toBe(true)
		expect(w.adapter.visibleOf(cellOf(w, D(2026, 12, 21)) .. "/Layers/Band")).toBe(false)
		-- one pill: a middle day paints both halves; a week's edge rounds the pill with
		-- a cap (Dec 6 is a Sunday, Dec 12 a Saturday); an end paints no half past
		-- itself (Dec 5, a Saturday start, stands alone on its row)
		local function shown(d: any): string
			local function v(part: string): string
				return if w.adapter.visibleOf(cellOf(w, d) .. "/Layers/" .. part) then "1" else "0"
			end
			return v("Band/Leading") .. v("Band/Trailing") .. v("Cap")
		end
		expect(`{shown(D(2026, 12, 9))} {shown(D(2026, 12, 6))} {shown(D(2026, 12, 12))} {shown(D(2026, 12, 5))}`).toBe(
			"110 011 101 000"
		)
		-- the ends are the content colour with a surface numeral (light on dark)
		local ends = w.adapter.node(cellOf(w, D(2026, 12, 20)) .. "/Layers/Disc").props.tint
		expect(ends.role).toBe("content")
		expect(w.adapter.node(cellOf(w, D(2026, 12, 20)) .. "/Layers/Day").props.tint.role).toBe("surface")
		-- a day of this month is strong; a neighbour's is the dim body role
		local inMonth = w.adapter.node(cellOf(w, D(2026, 12, 9)) .. "/Layers/Day").props
		local neighbour = w.adapter.node(w.record("P").dump().cellPaths[1][1] .. "/Layers/Day").props
		expect(`{inMonth.textFont.weight} {neighbour.textFont.weight}`).toBe("SemiBold Regular")
		expect(neighbour.tint.role).toBe("contentSecondary")
		-- November's grey December days are December's: no disc, no band there
		w.adapter.tap(must(w, "/Header/Previous"))
		w.settle(2)
		local grey = w.record("P").dump().cellPaths[1][35]
		expect(w.adapter.node(grey .. "/Layers/Day").props.text).toBe("5")
		expect(w.adapter.visibleOf(grey .. "/Layers/Disc")).toBe(false)
		expect(w.adapter.visibleOf(grey .. "/Layers/Band")).toBe(false)
	end)

	it("presets clip to the bounds: outside is shown disabled, overlapping is clamped and enabled", function()
		local cell, _, change = caller({})
		local w = mount({
			selection = "range",
			range = cell,
			onRangeChange = change,
			presets = presets(),
			min = D(2026, 9, 10),
			max = D(2026, 12, 31),
		})
		open(w)
		expect(w.adapter.node(must(w, "/Preset-lastYear")).props.enabled).toBe(false)
		w.adapter.tap(must(w, "/Preset-month"))
		w.settle(2)
		expect(`{iso(cell:peek().start)}..{iso(cell:peek().finish)}`).toBe("2026-09-10..2026-09-30")
	end)

	it("draft: picks and presets propose live, only Apply commits, Cancel restores, Reset all clears", function()
		local startRange = { start = D(2026, 9, 1), finish = D(2026, 9, 3) }
		local cell, _, change = caller(startRange)
		local commits = {}
		local w = mount({
			selection = "range",
			range = cell,
			onRangeChange = change,
			presets = presets(),
			draft = true,
			onRangeCommit = function(r: any)
				table.insert(commits, `{iso(r.start)}..{iso(r.finish)}`)
			end,
		})
		open(w)
		-- the footer: Reset all a leading text link, Cancel then the accent Apply at
		-- the trailing edge, a rule above it and under the header, compact chips
		local reset = w.adapter.node(must(w, "/Actions/ResetAll"))
		local apply = w.adapter.node(must(w, "/Actions/Apply"))
		local cancel = w.adapter.node(must(w, "/Actions/Cancel"))
		expect(`{reset.props.surface == "accent"} {apply.props.surface}`).toBe("false accent")
		expect(reset.rect.x < cancel.rect.x and cancel.rect.x < apply.rect.x).toBe(true)
		expect(find(w, "/Calendar/FooterRule") ~= nil and find(w, "/Calendar/HeaderRule") ~= nil).toBe(true)
		expect(w.adapter.node(must(w, "/Preset-week")).rect.h < apply.rect.h).toBe(true)
		w.adapter.tap(must(w, "/Preset-week"))
		w.settle(2)
		expect(`{iso(cell:peek().start)}..{iso(cell:peek().finish)}`).toBe("2026-09-20..2026-09-26")
		expect(#commits).toBe(0)
		w.adapter.tap(must(w, "/Actions/Cancel"))
		w.settle(3)
		expect(`{iso(cell:peek().start)}..{iso(cell:peek().finish)}`).toBe("2026-09-01..2026-09-03")
		open(w)
		w.adapter.tap(must(w, "/Actions/ResetAll"))
		w.settle(2)
		expect(cell:peek().start).toBeNil()
		w.adapter.tap(cellOf(w, D(2026, 9, 7)))
		w.adapter.tap(cellOf(w, D(2026, 9, 9)))
		w.settle(2)
		expect(#commits).toBe(0)
		w.adapter.tap(must(w, "/Actions/Apply"))
		w.settle(3)
		expect(table.concat(commits, ",")).toBe("2026-09-07..2026-09-09")
		expect(w.record("P").dump().presented).toBe(false)
	end)

	it("a caller write during an open draft re-bases what Cancel restores", function()
		local cell, _, change = caller({ start = D(2026, 9, 1), finish = D(2026, 9, 3) })
		local w = mount({ selection = "range", range = cell, onRangeChange = change, draft = true })
		open(w)
		local server = { start = D(2026, 10, 1), finish = D(2026, 10, 2) }
		cell:set(server)
		w.settle(2)
		w.adapter.tap(cellOf(w, D(2026, 9, 14)))
		w.settle(2)
		w.adapter.tap(must(w, "/Actions/Cancel"))
		w.settle(3)
		expect(`{iso(cell:peek().start)}..{iso(cell:peek().finish)}`).toBe("2026-10-01..2026-10-02")
	end)
end)

describe("DateTimePicker: the gallery tab", function()
	it("the Pickers scenario's window applies a preset only on Apply, and a refusal changes nothing", function()
		local scenario = require("../examples/gallery/scenarios/pickers") :: any
		local w = world.new({ viewport = { x = 0, y = 0, w = 1000, h = 900 }, reducedMotion = true })
		local built = scenario.build({
			Facet = Facet,
			UI = w.UI,
			Compose = Compose,
			Color3 = require("./lib/gui_value_shim").colorValues().Color3,
			app = w.app,
			core = w.core,
			env = w.env,
		})
		w.present(built.screen)
		w.settle(3)
		local line = must(w, "/Pickers/Committed")
		-- an empty window says what it wants
		local words = find(w, "/Window/Field/Words/then/Entry/Input/Row/Field")
			or must(w, "/Window/Field/Words/else/Show")
		local shown = w.adapter.node(words).props
		expect(shown.placeholder or shown.label).toBe("Choose a start and an end")
		w.adapter.tap(opener(w, "Window"), { source = "pointer", x = 5, y = 5 })
		w.settle(3)
		w.adapter.tap(must(w, "/Preset-week"))
		w.settle(2)
		expect(w.adapter.node(line).props.text).toBe("Committed: nothing yet")
		expect(w.record("Window").dump().text).toBe("09/21/2026 – 09/27/2026")
		w.adapter.tap(must(w, "/Actions/Apply"))
		w.settle(3)
		expect(w.adapter.node(line).props.text).toBe("Committed: 09/21/2026 – 09/27/2026")
		w.adapter.tap(must(w, "/Pickers/Refuse"))
		w.settle(2)
		w.adapter.tap(opener(w, "RaceDay"), { source = "pointer", x = 5, y = 5 })
		w.settle(3)
		local d = w.record("RaceDay").dump()
		w.adapter.tap(d.cellPaths[1][20])
		w.settle(2)
		expect(w.record("RaceDay").dump().text).toBe("10/04/2026")
	end)
end)

describe("DateTimePicker: layout, routes and refusals", function()
	it(
		"a wide screen shows a range two consecutive months, and they stay consecutive through paging and bounds",
		function()
			local cell, _, change = caller({ start = D(2026, 12, 5) })
			local bound = Compose.cell(nil :: any)
			-- a single date keeps to one month however wide the screen (the reference's form)
			local single, _, changeSingle = caller(D(2026, 12, 5))
			local one = mount(
				{ value = single, onChange = changeSingle, style = "inline" },
				{ viewport = { x = 0, y = 0, w = 1000, h = 900 } }
			)
			expect(one.record("P").dump().dual).toBe(false)
			local w = mount({
				selection = "range",
				range = cell,
				onRangeChange = change,
				style = "inline",
				min = function(use)
					return use(bound)
				end,
			}, { viewport = { x = 0, y = 0, w = 1000, h = 900 } })
			expect(w.record("P").dump().dual).toBe(true)
			local function titles(): string
				return w.adapter.node(must(w, "/Pane1/Title")).props.text
					.. " | "
					.. w.adapter.node(must(w, "/Pane2/Title")).props.text
			end
			expect(titles()).toBe("December 2026 | January 2027")
			-- Down crosses from the first month into the second; only the second's
			-- last row leaves the months (for the control below), never paging
			expect(w.pres.focus.focusOn(cellOf(w, D(2026, 12, 30)))).toBe(true)
			w.press("Down")
			w.settle(2)
			expect(w.pres.focus.focused:peek()).toBe(cellOf(w, D(2027, 1, 6), 2))
			expect(w.pres.focus.focusOn(cellOf(w, D(2027, 1, 27), 2))).toBe(true)
			w.press("Down")
			w.settle(2)
			expect(w.pres.focus.focused:peek()).toBe(must(w, "/Col/Other"))
			expect(titles()).toBe("December 2026 | January 2027")
			w.adapter.tap(must(w, "/Header/Next"))
			w.settle(2)
			expect(titles()).toBe("January 2027 | February 2027")
			bound:set(D(2027, 3, 1))
			w.settle(2)
			expect(titles()).toBe("January 2027 | February 2027")
			local narrow = mount(
				{ selection = "range", range = cell, onRangeChange = change, style = "inline" },
				{ viewport = { x = 0, y = 0, w = 390, h = 844 } }
			)
			expect(narrow.record("P").dump().dual).toBe(false)
			expect(find(narrow, "/Pane2/Days")).toBeNil()
		end
	)

	it("two time pickers on one page: Down from a picker's last week reaches ITS OWN hour field", function()
		local w = world.new({
			viewport = { x = 0, y = 0, w = 380, h = 1800 },
			reducedMotion = true,
			capabilities = PAD,
			preferredInput = "Gamepad",
			hostOpts = { keyboardNavigation = true },
		})
		local UI = w.UI
		local function picker(id: string): any
			local cell, _, change = caller({ year = 2026, month = 9, day = 16, hour = 9, minute = 30 })
			return UI.DateTimePicker(id)({
				value = cell,
				onChange = change,
				time = true,
				style = "inline",
				clock = clock,
			})
		end
		w.present(function()
			return UI.Screen("S")({ padding = 0, UI.VStack("Col")({ width = UI.fill(), picker("A"), picker("B") }) })
		end)
		w.settle(3)
		for _, id in { "A", "B" } do
			local dump = w.record(id).dump()
			local grid = civil.monthGrid(dump.month.year, dump.month.month, dump.weekStart)
			-- the last week that still holds a day of this month
			local last = 0
			for i, day in grid do
				if day.month == dump.month.month then
					last = i
				end
			end
			expect(w.pres.focus.focusOn(dump.cellPaths[1][last])).toBe(true)
			w.press("DPadDown")
			w.settle(2)
			expect(string.find(w.pres.focus.focused:peek() or "", `/Col/{id}/`, 1, true) ~= nil).toBe(true)
			expect(string.find(w.pres.focus.focused:peek() or "", "/Hour/", 1, true) ~= nil).toBe(true)
		end
	end)

	it(
		"the week starts where the caller says; a compact touch field opens a sheet with Done, ten feet a centred sheet",
		function()
			local cell, _, change = caller(D(2026, 9, 16))
			local w = mount(
				{ value = cell, onChange = change, weekStart = 2 },
				{ capabilities = TOUCH, preferredInput = "Touch", viewport = { x = 0, y = 0, w = 390, h = 844 } }
			)
			expect(find(w, "/Words/else/Show") ~= nil).toBe(true)
			w.adapter.tap(must(w, "/Words/else/Show"))
			w.settle(3)
			expect(w.record("P").dump().route).toBe("sheet")
			expect(w.adapter.node(must(w, "/Pane1/Weekdays/W1")).props.text).toBe("Mo")
			expect(find(w, "/Actions/Done") ~= nil).toBe(true)
			local tv = mount(
				{ value = cell, onChange = change },
				{ capabilities = PAD, preferredInput = "Gamepad", displaySize = "Large" }
			)
			tv.pres.focus.focusOn(opener(tv, "P"))
			tv.press("ButtonA")
			tv.settle(3)
			expect(tv.record("P").dump().route).toBe("sheet")
			-- Pixel Quest paints a calendar on the open button, not a chevron
			local pixel = (require("../examples/themes/pixel_quest") :: any).build(Facet.themes)
			local art = require("../src/themes/package").resolveIcon(pixel, "calendar")
			expect(art.contentId).toBe(require("../src/themes/standard_icons").resolve("calendar").contentId)
		end
	)

	it("refuses a malformed contract at construction and quarantines a late bad value", function()
		local w = world.new({ reducedMotion = true })
		local function build(spec: any): string
			local ok, err = pcall(function()
				w.scoped(function()
					spec.clock = clock
					w.UI.DateTimePicker(spec)
				end)
			end)
			return if ok then "ok" else tostring(err)
		end
		local noop = function() end
		local function has(spec: any, word: string): boolean
			return string.find(build(spec), word, 1, true) ~= nil
		end
		expect(has({ value = D(2023, 2, 29), onChange = noop }, "calendar day")).toBe(true)
		expect(has({ value = TODAY }, "onChange")).toBe(true)
		expect(has({ selection = "range", value = TODAY, onChange = noop }, "range")).toBe(true)
		expect(has({ value = TODAY, onChange = noop, minuteStep = 7 }, "minuteStep")).toBe(true)
		expect(has({ value = TODAY, onChange = noop, time = true }, "hour")).toBe(true)
		expect(has({ selection = "range", range = {}, onRangeChange = noop, time = true }, "whole days")).toBe(true)
		expect(has({ value = TODAY, onChange = noop, weekStart = 0 }, "weekStart")).toBe(true)
		expect(has({
			selection = "range",
			range = {},
			onRangeChange = noop,
			presets = { { id = "a", label = "A", range = noop, rnage = noop } },
		}, "rnage")).toBe(true)
		local source = Compose.cell(TODAY :: any)
		local m = mount({
			value = function(use)
				return use(source)
			end,
			onChange = noop,
		})
		source:set(D(2026, 2, 30))
		m.settle(2)
		expect(m.record("P").dump().text).toBe("09/23/2026")
		expect(#m.record("P").api.diagnostics()).toBe(1)
	end)
end)
