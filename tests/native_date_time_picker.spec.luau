--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local Roblox = require("../src/vendor/compose/roblox")
local controls = require("../src/ui")
local themes = require("../src/ui/themes")
local civil: any = require("../src/ui/civil_date")
local engines = require("./lib/native_engine")
local expect = t.expect

local TODAY = { year = 2026, month = 9, day = 23 }
local function clock(): any
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
local function span(cell: any): string
	local r = cell:peek()
	return `{iso(r.start)}..{iso(r.finish)}`
end

local function find(root: any, name: string): any
	if root.Name == name then
		return root
	end
	for _, child in root:GetChildren() do
		local found = find(child, name)
		if found then
			return found
		end
	end
	return nil
end
local function all(root: any, name: string, out: { any }?): { any }
	local list = out or {}
	if root.Name == name then
		table.insert(list, root)
	end
	for _, child in root:GetChildren() do
		all(child, name, list)
	end
	return list
end
local function must(root: any, name: string): any
	local found = find(root, name)
	assert(found ~= nil, `nothing named {name}`)
	return found
end
local function shown(node: any): boolean
	local at = node
	while at do
		if at:IsA("GuiObject") and at.Visible == false then
			return false
		end
		at = at.Parent
	end
	return true
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

local PREFERRED = { pointer = "KeyboardAndMouse", touch = "Touch", pad = "Gamepad" }

local function world(build: (any, any) -> any, options: any?): any
	local o = options or {}
	local engine: any = engines.new()
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	local E = engine.types.Enum
	input.PreferredInput = E.PreferredInput[PREFERRED[o.input or "pointer"]]
	input.GetFocusedTextBox = function()
		return nil
	end
	if o.tenFoot then
		gui.IsTenFootInterface = function()
			return true
		end
	end
	local runtime = Roblox.createRuntime(engine)
	local errors: { any } = {}
	local UI: any = controls(
		Compose,
		runtime,
		{
			types = engine.types,
			services = { GuiService = gui, UserInputService = input },
			onError = function(message)
				table.insert(errors, message)
			end,
		} :: any
	)
	local target = engine.new("Folder")
	local view = o.viewport or { w = 600, h = 900 }
	local stop, screen = runtime.mount(function()
		return runtime.constructors.ScreenGui({ build(UI, runtime.constructors) })
	end, target)
	screen.AbsoluteSize = engine.types.Vector2.new(view.w, view.h)
	local w: any = {
		engine = engine,
		gui = gui,
		input = input,
		runtime = runtime,
		screen = screen,
		E = E,
		errors = errors,
		V2 = engine.types.Vector2,
		V3 = engine.types.Vector3,
		weekStart = 1,
	}
	function w.stop()
		stop()
		runtime:dispose()
	end
	function w.picker(name: string?): any
		return must(screen, name or "P")
	end
	function w.attr(key: string, name: string?): any
		return w.picker(name):GetAttribute(key)
	end
	function w.month(name: string?): string
		return w.attr("month", name)
	end
	function w.opener(name: string?): any
		return must(must(w.picker(name), "Field"), "Open")
	end
	function w.open(name: string?)
		w.opener(name).Activated.fire()
	end
	function w.panel(name: string?): any
		if w.attr("route", name) == "inline" then
			return must(w.picker(name), "Calendar")
		end
		return must(must(screen, "CalendarModal"), "Calendar")
	end
	function w.cellAt(i: number, k: number?, name: string?): any
		return must(must(must(w.panel(name), `Pane{k or 1}`), "Days"), `D{i}`)
	end
	function w.cellOf(d: any, k: number?, name: string?): any
		local y, m = string.match(w.month(name), "^(%d+)%-(%d+)$")
		local first = civil.addMonths(D(tonumber(y) :: number, tonumber(m) :: number, 1), (k or 1) - 1)
		for i, day in civil.monthGrid(first.year, first.month, w.weekStart) do
			if civil.compare(day, d) == 0 then
				return w.cellAt(i, k, name)
			end
		end
		error(`{iso(d)} is not on pane {k or 1}`)
	end
	function w.press(name: string, within: any?)
		must(within or screen, name).Pressed.fire()
	end
	function w.enabled(name: string, within: any?): boolean
		return must(within or screen, "Facet" .. name).Enabled
	end
	function w.selected(): any
		return gui.SelectedObject
	end
	function w.select(node: any)
		gui.SelectedObject = node
	end
	return w
end

local function mount(spec: any, options: any?): any
	local full = table.clone(spec)
	full.clock = full.clock or clock
	local w = world(function(UI, Host)
		return Host.Frame({
			Name = "Col",
			Host.UIListLayout({}),
			UI.DateTimePicker("P")(full),
			UI.Button("Other")({ label = "Other" }),
		})
	end, options)
	w.weekStart = full.weekStart or 1
	return w
end

local function disc(cell: any): boolean
	return shown(must(cell, "Disc"))
end

local function typeInto(w: any, box: any, text: string)
	box:CaptureFocus()
	box.Text = text
	box:ReleaseFocus(true)
end

t.describe("DateTimePicker: a single date", function()
	t.it("the calendar opens anchored on the chosen day's month; a pick commits once and closes", function()
		local cell, _, change = caller(D(2026, 2, 14))
		local commits = {}
		local w = mount({
			value = cell,
			onChange = change,
			onCommit = function(v: any)
				table.insert(commits, iso(v))
			end,
		}, { input = "pad" })
		w.select(w.opener())
		w.open()
		expect(w.attr("presented")).toBe(true)
		expect(w.attr("route")).toBe("popover")
		expect(w.month()).toBe("2026-02")
		expect(disc(w.cellOf(D(2026, 2, 14)))).toBe(true)
		expect(w.selected()).toBe(w.cellOf(D(2026, 2, 14)))
		w.cellOf(D(2026, 2, 20)).Activated.fire()
		expect(iso(cell:peek())).toBe("2026-02-20")
		expect(table.concat(commits, ",")).toBe("2026-02-20")
		expect(w.attr("presented")).toBe(false)
		expect(find(w.screen, "CalendarModal")).toBeNil()
		w.stop()
	end)

	t.it("the year and month menus open on the shown ones and honour min/max (owner: opened at 1926)", function()
		local cell, _, change = caller(D(2026, 9, 5))
		local w = mount(
			{ value = cell, onChange = change, style = "inline", min = D(2020, 3, 10), max = D(2030, 6, 1) },
			{ input = "pad" }
		)
		must(w.picker(), "Year").Activated.fire()
		local rows = must(w.screen, "MenuRows")
		expect(w.selected()).toBe(must(rows, "2026"))
		expect(must(rows, "2026"):GetAttribute("selected")).toBe(true)
		local listed = `{find(rows, "2019") ~= nil} {find(rows, "2020") ~= nil} `
			.. `{find(rows, "2030") ~= nil} {find(rows, "2031") ~= nil}`
		expect(listed).toBe("false true true false")
		must(rows, "2030").Activated.fire()
		expect(w.month()).toBe("2030-06")
		expect(find(w.screen, "MenuRows")).toBeNil()
		must(w.picker(), "Month").Activated.fire()
		rows = must(w.screen, "MenuRows")
		expect(w.selected()).toBe(must(rows, "6"))
		expect(`{must(rows, "6").Interactable} {must(rows, "7").Interactable}`).toBe("true false")
		w.stop()
	end)

	t.it("a refused pick paints nothing; a disabled or out-of-bounds day is focusable, inert and struck", function()
		local cell, seen, change = caller(D(2026, 9, 10), false)
		local w = mount({
			value = cell,
			onChange = change,
			min = D(2026, 9, 5),
			isDateDisabled = function(d: any)
				return d.day == 15
			end,
		})
		w.open()
		w.cellOf(D(2026, 9, 12)).Activated.fire()
		expect(#seen).toBe(1)
		expect(disc(w.cellOf(D(2026, 9, 12)))).toBe(false)
		expect(disc(w.cellOf(D(2026, 9, 10)))).toBe(true)
		for _, day in { D(2026, 9, 15), D(2026, 9, 1) } do
			local node = w.cellOf(day)
			expect(node.Selectable).toBe(true)
			w.select(node)
			expect(w.selected()).toBe(node)
			expect(shown(must(node, "Strike"))).toBe(true)
			expect(string.find(node:GetAttribute("label"), "unavailable", 1, true) ~= nil).toBe(true)
			node.Activated.fire()
		end
		expect(#seen).toBe(1)
		expect(shown(must(w.cellOf(D(2026, 9, 12)), "Strike"))).toBe(false)
		w.stop()
	end)

	t.it("typed entry commits a date; a refused text stays with its error and commits nothing", function()
		local cell, seen, change = caller(nil)
		local commits = {}
		local reasons = {}
		local w = mount({
			onDismiss = function(reason: string)
				table.insert(reasons, reason)
			end,
			value = cell,
			onChange = change,
			label = "Race day",
			max = D(2026, 12, 31),
			onCommit = function(v: any)
				table.insert(commits, iso(v))
			end,
		})
		local plate = must(w.picker(), "Field")
		local entry = must(plate, "Entry")
		expect(entry.ClassName).toBe("TextBox")
		expect(plate:HasTag("facet-field")).toBe(true)
		expect(entry:HasTag("facet-field") or entry:HasTag("facet-text-input")).toBe(false)
		expect(w.opener().Parent).toBe(plate)
		expect(w.opener().LayoutOrder > entry.LayoutOrder).toBe(true)
		plate.AbsolutePosition = w.V2.new(0, 100)
		plate.AbsoluteSize = w.V2.new(400, 44)
		w.open()
		local panel = w.panel()
		local surface = must(w.screen, "CalendarSurface")
		expect(surface:HasTag("facet-panel")).toBe(true)
		panel.AbsoluteSize = w.V2.new(340, 380)
		expect(surface.Size).toBe(w.engine.types.UDim2.fromOffset(7 * 44 + 32, 380))
		surface.AbsoluteSize = w.V2.new(340, 380)
		expect(surface.Position).toBe(w.engine.types.UDim2.fromOffset(8, 148))
		plate.AbsolutePosition = w.V2.new(100, 700)
		expect(surface.Position).toBe(w.engine.types.UDim2.fromOffset(100, 316))
		panel.AbsoluteSize = w.V2.new(340, 1200)
		expect(surface.Size).toBe(w.engine.types.UDim2.fromOffset(7 * 44 + 32, 900 - 16))
		expect(surface.AutomaticCanvasSize).toBe(w.E.AutomaticSize.Y)
		surface.AbsoluteSize = w.V2.new(340, 884)
		expect(surface.Position).toBe(w.engine.types.UDim2.fromOffset(100, 8))
		surface.AbsoluteSize = w.V2.new(340, 380)
		surface.AbsolutePosition = w.V2.new(100, 316)
		must(w.screen, "DismissOutside").Activated.fire({ Position = w.V3.new(480, 722, 0) })
		expect(w.attr("presented")).toBe(false)
		expect(table.concat(reasons, ",")).toBe("outside")
		typeInto(w, entry, "02/30/2026")
		expect(#seen).toBe(0)
		expect(w.attr("typedError") ~= "").toBe(true)
		expect(plate:HasTag("facet-invalid")).toBe(true)
		expect(must(w.picker(), "Validation").Text).toBe(w.attr("typedError"))
		expect(entry.Text).toBe("02/30/2026")
		typeInto(w, entry, "01/05/2027")
		expect(#seen).toBe(0)
		typeInto(w, entry, "7/4/2026")
		expect(plate:HasTag("facet-invalid")).toBe(false)
		expect(iso(cell:peek())).toBe("2026-07-04")
		expect(table.concat(commits, ",")).toBe("2026-07-04")
		expect(w.attr("typedError")).toBe("")
		expect(entry.Text).toBe("07/04/2026")
		typeInto(w, entry, "12/31/26")
		expect(iso(cell:peek())).toBe("2026-07-04")
		expect(w.attr("typedError") ~= "").toBe(true)
		w.stop()
	end)

	t.it("a typed range reads back its own words in every locale order; a draft's typed text only proposes", function()
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
				local entry = must(w.picker(), "Entry")
				local words = entry.Text
				local old = civil.format(D(2026, 1, 2), locale)
				local at = string.find(words, old, 1, true) :: number
				local edited = civil.format(D(2026, 1, 3), locale) .. string.sub(words, at + #old)
				typeInto(w, entry, edited)
				local where = `{locale.order} draft={draft}`
				expect(`{where} {w.attr("typedError")}`).toBe(`{where} `)
				expect(`{where} {span(cell)}`).toBe(`{where} 2026-01-03..2026-01-09`)
				expect(`{where} {commits}`).toBe(`{where} {if draft then 0 else 1}`)
				w.stop()
			end
		end
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
		typeInto(w, must(w.picker(), "Entry"), "7/4/2026")
		expect(iso(cell:peek())).toBe("2026-07-04")
		expect(commits).toBe(0)
		w.stop()
	end)

	t.it(
		"keyboard and pad: the arrows walk the grid with its contribution attached, a row's end continues, L1/R1 page",
		function()
			local cell, _, change = caller(D(2026, 9, 16))
			local w = mount({ value = cell, onChange = change }, { input = "pad" })
			w.select(w.opener())
			w.open()
			expect(w.selected()).toBe(w.cellOf(D(2026, 9, 16)))
			w.press("CalendarRight")
			expect(w.selected()).toBe(w.cellOf(D(2026, 9, 17)))
			w.press("CalendarDown")
			expect(w.selected()).toBe(w.cellOf(D(2026, 9, 24)))
			w.select(w.cellOf(D(2026, 9, 19)))
			w.press("CalendarRight")
			expect(w.selected()).toBe(w.cellOf(D(2026, 9, 20)))
			local held = w.selected()
			w.press("CalendarNextMonth")
			expect(w.month()).toBe("2026-10")
			expect(w.selected()).toBe(held)
			w.press("CalendarPreviousMonth")
			w.press("CalendarPreviousMonth")
			expect(w.month()).toBe("2026-08")
			w.selected().Activated.fire()
			expect(cell:peek().month).toBe(8)
			expect(w.attr("presented")).toBe(false)
			expect(w.selected()).toBe(w.opener())
			w.stop()
		end
	)

	t.it(
		"the grid is one selection group; the arrows walk days across months; grey days are no stop; paging stops at the bounds",
		function()
			local cell, _, change = caller(D(2026, 9, 16))
			local w = mount({ value = cell, onChange = change, draft = true, max = D(2026, 10, 31) }, { input = "pad" })
			w.input.PreferredInput = w.E.PreferredInput.KeyboardAndMouse
			w.select(w.opener())
			w.open()
			expect(w.selected()).toBe(w.cellOf(D(2026, 9, 16)))
			expect(find(w.panel(), "PageHint")).toBeNil()
			w.select(w.cellOf(D(2026, 9, 1)))
			w.press("CalendarLeft")
			expect(w.month()).toBe("2026-08")
			expect(w.selected()).toBe(w.cellOf(D(2026, 8, 31)))
			w.press("CalendarRight")
			expect(w.month()).toBe("2026-09")
			expect(w.selected()).toBe(w.cellOf(D(2026, 9, 1)))
			w.select(w.cellOf(D(2026, 9, 16)))
			w.press("CalendarUp")
			w.press("CalendarUp")
			expect(w.selected()).toBe(w.cellOf(D(2026, 9, 2)))
			expect(w.enabled("CalendarUp")).toBe(false)
			local month = must(w.panel(), "Month")
			expect(w.selected().NextSelectionUp).toBe(month)
			expect(w.cellOf(D(2026, 9, 9)).NextSelectionUp).toBeNil()
			expect(w.month()).toBe("2026-09")
			local grey = w.cellAt(1)
			expect(must(grey, "Day"):HasTag("facet-calendar-dim")).toBe(true)
			expect(grey.Selectable).toBe(false)
			expect(grey.Interactable).toBe(true)
			expect(must(w.screen, "CalendarSurface").SelectionGroup).toBe(true)
			must(w.panel(), "Next").Activated.fire()
			expect(w.month()).toBe("2026-10")
			expect(must(w.panel(), "Next").Interactable).toBe(false)
			w.select(w.cellOf(D(2026, 10, 28)))
			expect(w.enabled("CalendarNextMonth")).toBe(false)
			w.press("CalendarNextMonth")
			expect(w.month()).toBe("2026-10")
			expect(w.enabled("CalendarDown")).toBe(false)
			expect(w.selected().NextSelectionDown).toBe(must(w.panel(), "ResetAll"))
			expect(w.month()).toBe("2026-10")
			w.stop()
		end
	)

	t.it(
		"a draft on a TV: Down from any day leaves the months below; Up from the first row reaches the header",
		function()
			local function walkDown(w: any)
				for _ = 1, 12 do
					local here = w.selected()
					if w.enabled("CalendarDown") then
						w.press("CalendarDown")
					elseif here.NextSelectionDown then
						w.select(here.NextSelectionDown)
					end
					if w.selected() == here then
						break
					end
				end
			end
			for _, withTime in { true, false } do
				for _, start in { D(2026, 9, 1), D(2026, 9, 16), D(2026, 9, 24), D(2026, 9, 30) } do
					local initial = if withTime
						then { year = 2026, month = 9, day = 16, hour = 9, minute = 30 }
						else D(2026, 9, 16)
					local cell, _, change = caller(initial)
					local commits = 0
					local w = mount({
						value = cell,
						onChange = change,
						draft = true,
						time = withTime,
						onCommit = function()
							commits += 1
						end,
					}, { input = "pad", tenFoot = true })
					w.select(w.opener())
					w.open()
					expect(w.attr("route")).toBe("sheet")
					expect(shown(must(w.panel(), "PageHint"))).toBe(true)
					w.select(w.cellOf(start))
					walkDown(w)
					local landed = w.selected()
					if withTime then
						expect(landed).toBe(must(must(w.panel(), "Hour"), "Field"))
					else
						expect(landed).toBe(must(w.panel(), "ResetAll"))
					end
					expect(w.month()).toBe("2026-09")
					must(w.panel(), "Apply").Activated.fire()
					expect(commits).toBe(1)
					w.stop()
				end
			end
			local cell, _, change = caller(D(2026, 9, 16))
			local w = mount({ value = cell, onChange = change, draft = true }, { input = "pad", tenFoot = true })
			w.select(w.opener())
			w.open()
			w.select(w.cellOf(D(2026, 9, 3)))
			expect(w.enabled("CalendarUp")).toBe(false)
			expect(w.selected().NextSelectionUp).toBe(must(w.panel(), "Month"))
			expect(w.month()).toBe("2026-09")
			w.stop()
		end
	)

	t.it("a pad sets a date and time: each pick commits, B keeps it and returns focus; a draft's B restores", function()
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
			}, { input = "pad" })
			local button = w.opener()
			w.select(button)
			w.open()
			w.select(w.cellOf(D(2026, 9, 18)))
			w.selected().Activated.fire()
			expect(iso(cell:peek())).toBe("2026-09-18 09:30")
			expect(w.attr("presented")).toBe(true)
			w.press("ModalBack")
			expect(w.attr("presented")).toBe(false)
			expect(w.selected()).toBe(button)
			if draft then
				expect(iso(cell:peek())).toBe("2026-09-16 09:30")
				expect(#commits).toBe(0)
			else
				expect(iso(cell:peek())).toBe("2026-09-18 09:30")
				expect(table.concat(commits, ",")).toBe("2026-09-18 09:30")
			end
			w.stop()
		end
	end)

	t.it("time: hour and minute fields step on the minute grid, AM/PM flips, and a touch list sets both", function()
		local cell, _, change = caller({ year = 2026, month = 9, day = 16, hour = 9, minute = 30 })
		local w = mount({ value = cell, onChange = change, time = true, minuteStep = 15, style = "inline" })
		must(must(w.picker(), "Half"), "PM").Activated.fire()
		expect(iso(cell:peek())).toBe("2026-09-16 21:30")
		local minute = must(w.picker(), "Minute")
		must(minute, "Increment").Activated.fire()
		expect(iso(cell:peek())).toBe("2026-09-16 21:45")
		expect(must(minute, "Increment").Interactable).toBe(false)
		must(minute, "Increment").Activated.fire()
		expect(iso(cell:peek())).toBe("2026-09-16 21:45")
		expect(must(must(w.picker(), "Hour"), "Field").Text).toBe("09")
		expect(find(w.picker(), "Times")).toBeNil()
		w.stop()
		local touch = mount(
			{ value = cell, onChange = change, time = true, minuteStep = 30, style = "inline" },
			{ input = "touch" }
		)
		local times = must(touch.picker(), "Times")
		times.AbsoluteWindowSize = touch.V2.new(300, 176)
		expect(times.CanvasPosition.Y).toBe(43 * 44)
		expect(find(times, "0:0")).toBeNil()
		must(must(times, "22:0"), "Time").Activated.fire()
		expect(iso(cell:peek())).toBe("2026-09-16 22:00")
		touch.stop()
	end)
end)

t.describe("DateTimePicker: ranges, presets and drafts", function()
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

	t.it("the first pick anchors, an earlier second pick swaps, and onRangeCommit waits for both ends", function()
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
		w.open()
		w.cellOf(D(2026, 12, 20)).Activated.fire()
		expect(#commits).toBe(0)
		expect(iso(cell:peek().start)).toBe("2026-12-20")
		w.cellOf(D(2026, 12, 5)).Activated.fire()
		expect(span(cell)).toBe("2026-12-05..2026-12-20")
		expect(table.concat(commits, ",")).toBe("2026-12-05..2026-12-20")
		expect(#seen).toBe(2)
		expect(w.attr("presented")).toBe(false)
		w.open()
		expect(shown(must(w.cellOf(D(2026, 12, 12)), "Band"))).toBe(true)
		expect(shown(must(w.cellOf(D(2026, 12, 21)), "Band"))).toBe(false)
		local function parts(d: any): string
			local function v(name: string): string
				return if shown(must(w.cellOf(d), name)) then "1" else "0"
			end
			return v("Leading") .. v("Trailing") .. v("Cap")
		end
		expect(`{parts(D(2026, 12, 9))} {parts(D(2026, 12, 6))} {parts(D(2026, 12, 12))} {parts(D(2026, 12, 5))}`).toBe(
			"110 011 101 000"
		)
		local ends = must(w.cellOf(D(2026, 12, 20)), "Disc")
		expect(ends:HasTag("facet-calendar-disc") and ends:HasTag("facet-calendar-end")).toBe(true)
		expect(must(w.cellOf(D(2026, 12, 20)), "Day"):HasTag("facet-calendar-chosen-end")).toBe(true)
		local inMonth = must(w.cellOf(D(2026, 12, 9)), "Day")
		local neighbour = must(w.cellAt(1), "Day")
		expect(`{inMonth:HasTag("facet-calendar-dim")} {neighbour:HasTag("facet-calendar-dim")}`).toBe("false true")
		local engine: any = engines.new()
		local runtime = Roblox.createRuntime(engine)
		local sheet: any = nil
		local stop = runtime.mount(function()
			sheet = themes(Compose).createStyleSheet(runtime, nil, { types = engine.types })
			return sheet
		end, engine.new("Folder"))
		local rules: { [string]: any } = {}
		for _, rule in sheet:GetChildren() do
			rules[rule.Selector] = rule:GetProperties()
		end
		expect(rules[".facet-calendar-end"].BackgroundColor3).toBe(rules[".facet-text"].TextColor3)
		expect(rules[".facet-calendar-number"].FontFace.Weight).toBe(engine.types.Enum.FontWeight.SemiBold)
		expect(rules[".facet-calendar-dim"].FontFace.Weight).toBe(engine.types.Enum.FontWeight.Regular)
		expect(rules[".facet-calendar-dim"].TextColor3).toBe(rules[".facet-secondary"].TextColor3)
		stop()
		must(w.panel(), "Previous").Activated.fire()
		local grey = w.cellAt(35)
		expect(must(grey, "Day").Text).toBe("5")
		expect(shown(must(grey, "Disc"))).toBe(false)
		expect(shown(must(grey, "Band"))).toBe(false)
		w.stop()
	end)

	t.it("presets clip to the bounds: outside is shown disabled, overlapping is clamped and enabled", function()
		local cell, _, change = caller({})
		local w = mount({
			selection = "range",
			range = cell,
			onRangeChange = change,
			presets = presets(),
			min = D(2026, 9, 10),
			max = D(2026, 12, 31),
		})
		w.open()
		expect(must(w.panel(), "Preset-lastYear").Interactable).toBe(false)
		expect(must(w.panel(), "Preset-month").Interactable).toBe(true)
		must(w.panel(), "Preset-month").Activated.fire()
		expect(span(cell)).toBe("2026-09-10..2026-09-30")
		w.stop()
	end)

	t.it("draft: picks and presets propose live, only Apply commits, Cancel restores, Reset all clears", function()
		local cell, _, change = caller({ start = D(2026, 9, 1), finish = D(2026, 9, 3) })
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
		w.open()
		local panel = w.panel()
		local actions = must(panel, "Actions")
		local reset, commitRow = must(actions, "ResetAll"), must(actions, "Commit")
		local cancel, apply = must(commitRow, "Cancel"), must(commitRow, "Apply")
		expect(`{reset:HasTag("facet-accent")} {reset:HasTag("facet-appearance-link")} {apply:HasTag("facet-accent")}`).toBe(
			"false true true"
		)
		expect(reset.Parent == actions and commitRow.Parent == actions).toBe(true)
		expect(reset.LayoutOrder < commitRow.LayoutOrder and cancel.LayoutOrder < apply.LayoutOrder).toBe(true)
		expect(actions:FindFirstChildWhichIsA("UIListLayout").HorizontalFlex).toBe(w.E.UIFlexAlignment.SpaceBetween)
		expect(find(panel, "FooterRule") ~= nil and find(panel, "HeaderRule") ~= nil).toBe(true)
		expect(must(panel, "Preset-week"):GetAttribute("controlSize")).toBe("compact")
		must(panel, "Preset-week").Activated.fire()
		expect(span(cell)).toBe("2026-09-20..2026-09-26")
		expect(#commits).toBe(0)
		cancel.Activated.fire()
		expect(span(cell)).toBe("2026-09-01..2026-09-03")
		expect(w.attr("presented")).toBe(false)
		w.open()
		must(w.panel(), "ResetAll").Activated.fire()
		expect(cell:peek().start).toBeNil()
		w.cellOf(D(2026, 9, 7)).Activated.fire()
		w.cellOf(D(2026, 9, 9)).Activated.fire()
		expect(#commits).toBe(0)
		must(w.panel(), "Apply").Activated.fire()
		expect(table.concat(commits, ",")).toBe("2026-09-07..2026-09-09")
		expect(w.attr("presented")).toBe(false)
		w.stop()
	end)

	t.it("a caller write during an open draft re-bases what Cancel restores", function()
		local cell, _, change = caller({ start = D(2026, 9, 1), finish = D(2026, 9, 3) })
		local w = mount({ selection = "range", range = cell, onRangeChange = change, draft = true })
		w.open()
		cell:set({ start = D(2026, 10, 1), finish = D(2026, 10, 2) })
		w.cellOf(D(2026, 9, 14)).Activated.fire()
		must(w.panel(), "Cancel").Activated.fire()
		expect(span(cell)).toBe("2026-10-01..2026-10-02")
		w.stop()
	end)

	local function layout(w: any, panes: number)
		for k = 1, panes do
			for i = 1, 42 do
				local node = w.cellAt(i, k)
				node.AbsolutePosition = w.V2.new((k - 1) * 332 + ((i - 1) % 7) * 44, 100 + ((i - 1) // 7) * 44)
				node.AbsoluteSize = w.V2.new(44, 44)
			end
		end
	end
	local function centre(w: any, d: any, k: number?): any
		local node = w.cellOf(d, k)
		return w.V3.new(node.AbsolutePosition.X + 22, node.AbsolutePosition.Y + 22, 0)
	end
	local function drag(w: any, from: any, to: { any }, finish: string?, fromPane: number?)
		local touch = w.E.UserInputType.Touch
		w.cellOf(from, fromPane).InputBegan.fire({ UserInputType = touch, Position = centre(w, from, fromPane) })
		for _, step in to do
			w.input.InputChanged.fire({
				UserInputType = touch,
				UserInputState = w.E.UserInputState.Change,
				Position = centre(w, step[1], step[2]),
			})
		end
		local last = to[#to]
		w.input.InputEnded.fire({
			UserInputType = touch,
			UserInputState = if finish == "cancel" then w.E.UserInputState.Cancel else w.E.UserInputState.End,
			Position = centre(w, last[1], last[2]),
		})
	end

	t.it("a range's end drags across days and panes, crossing swaps, release commits once (owner)", function()
		local cell, _, change = caller({ start = D(2026, 9, 10), finish = D(2026, 9, 15) })
		local commits: { string } = {}
		local w = mount({
			selection = "range",
			range = cell,
			onRangeChange = change,
			onRangeCommit = function(r: any)
				table.insert(commits, `{iso(r.start)}..{iso(r.finish)}`)
			end,
			style = "inline",
		}, { viewport = { w = 900, h = 900 } })
		w.picker().AbsoluteSize = w.V2.new(900, 700)
		expect(w.attr("dual")).toBe(true)
		layout(w, 2)
		drag(w, D(2026, 9, 15), { { D(2026, 9, 22), 1 }, { D(2026, 10, 6), 2 } })
		expect(span(cell)).toBe("2026-09-10..2026-10-06")
		expect(table.concat(commits, ",")).toBe("2026-09-10..2026-10-06")
		w.cellOf(D(2026, 10, 6), 2).Activated.fire()
		expect(span(cell)).toBe("2026-09-10..2026-10-06")
		drag(w, D(2026, 9, 10), { { D(2026, 10, 8), 2 } })
		expect(span(cell)).toBe("2026-10-06..2026-10-08")
		drag(w, D(2026, 10, 8), { { D(2026, 10, 20), 2 } }, "cancel", 2)
		expect(span(cell)).toBe("2026-10-06..2026-10-08")
		expect(#commits).toBe(2)
		local between = w.cellOf(D(2026, 10, 7), 2)
		between.InputBegan.fire({ UserInputType = w.E.UserInputType.Touch, Position = centre(w, D(2026, 10, 7), 2) })
		w.input.InputEnded.fire({
			UserInputType = w.E.UserInputType.Touch,
			UserInputState = w.E.UserInputState.End,
			Position = centre(w, D(2026, 10, 7), 2),
		})
		between.Activated.fire()
		expect(span(cell)).toBe("2026-10-07..nil")
		w.stop()
	end)

	t.it("a drafted range drags live but commits only on Apply", function()
		local cell, _, change = caller({ start = D(2026, 9, 10), finish = D(2026, 9, 15) })
		local commits = 0
		local w = mount({
			selection = "range",
			range = cell,
			onRangeChange = change,
			onRangeCommit = function()
				commits += 1
			end,
			draft = true,
			style = "inline",
		})
		layout(w, 1)
		drag(w, D(2026, 9, 15), { { D(2026, 9, 18) } })
		expect(span(cell)).toBe("2026-09-10..2026-09-18")
		expect(commits).toBe(0)
		must(w.picker(), "Apply").Activated.fire()
		expect(commits).toBe(1)
		w.stop()
	end)
end)

t.describe("DateTimePicker: the gallery tab", function()
	t.it("the Pickers scenario's window applies a preset only on Apply, and a refusal changes nothing", function()
		local refuse = Compose.cell(false)
		local committed = Compose.cell("nothing yet")
		local raceDay = Compose.cell(D(2026, 10, 4) :: any)
		local window = Compose.cell({} :: any)
		local function accept(cell: any): (any) -> ()
			return function(next: any)
				if not refuse:peek() then
					cell:set(next)
				end
			end
		end
		local w = world(function(UI, Host)
			return Host.Frame({
				Name = "Pickers",
				Host.UIListLayout({}),
				UI.Toggle("Refuse")({ label = "Refuse changes", value = refuse }),
				UI.Label("Committed")({
					text = function(use: any): string
						return `Committed: {use(committed)}`
					end,
				}),
				UI.DateTimePicker("RaceDay")({
					label = "Race day",
					value = raceDay,
					onChange = accept(raceDay),
					clock = clock,
				}),
				UI.DateTimePicker("Window")({
					label = "Season window",
					selection = "range",
					range = window,
					onRangeChange = accept(window),
					onRangeCommit = function(r: any)
						committed:set(`{civil.format(r.start)} – {civil.format(r.finish)}`)
					end,
					draft = true,
					weekStart = 2,
					placeholder = "Choose a start and an end",
					clock = clock,
					presets = {
						{
							id = "week",
							label = "This week",
							range = function(today: any)
								local start = civil.addDays(today, -((civil.weekday(today) + 5) % 7))
								return { start = start, finish = civil.addDays(start, 6) }
							end,
						},
					},
				}),
			})
		end, { input = "touch" })
		local line = must(w.screen, "Committed")
		local text = if line:IsA("TextLabel") then line else line:FindFirstChildWhichIsA("TextLabel", true)
		expect(must(w.picker("Window"), "Show").Text).toBe("Choose a start and an end")
		w.open("Window")
		must(w.panel("Window"), "Preset-week").Activated.fire()
		expect(text.Text).toBe("Committed: nothing yet")
		expect(w.attr("text", "Window")).toBe("09/21/2026 – 09/27/2026")
		must(w.panel("Window"), "Apply").Activated.fire()
		expect(text.Text).toBe("Committed: 09/21/2026 – 09/27/2026")
		must(w.screen, "Refuse").Activated.fire()
		expect(refuse:peek()).toBe(true)
		w.open("RaceDay")
		w.cellAt(20, 1, "RaceDay").Activated.fire()
		expect(w.attr("text", "RaceDay")).toBe("10/04/2026")
		w.stop()
	end)
end)

t.describe("DateTimePicker: layout, routes and refusals", function()
	t.it("a wide screen shows two consecutive months, and they stay consecutive through paging and bounds", function()
		local single, _, changeSingle = caller(D(2026, 12, 5))
		local one = mount({ value = single, onChange = changeSingle, style = "inline" })
		one.picker().AbsoluteSize = one.V2.new(1000, 700)
		expect(one.attr("dual")).toBe(false)
		one.stop()
		local cell, _, change = caller({ start = D(2026, 12, 5) })
		local bound = Compose.cell(nil :: any)
		local w = mount({
			selection = "range",
			range = cell,
			onRangeChange = change,
			style = "inline",
			min = function(use: any)
				return use(bound)
			end,
		}, { input = "pad" })
		w.picker().AbsoluteSize = w.V2.new(1000, 700)
		expect(w.attr("dual")).toBe(true)
		local function titles(): string
			local panel = w.panel()
			return `{must(must(panel, "Pane1"), "Title").Text} | {must(must(panel, "Pane2"), "Title").Text}`
		end
		expect(titles()).toBe("December 2026 | January 2027")
		expect(shown(must(must(w.panel(), "Pane1"), "Title"))).toBe(true)
		w.select(w.cellOf(D(2026, 12, 30)))
		w.press("CalendarDown")
		expect(w.selected()).toBe(w.cellOf(D(2027, 1, 6), 2))
		w.select(w.cellOf(D(2027, 1, 27), 2))
		expect(w.enabled("CalendarDown")).toBe(false)
		expect(w.selected().NextSelectionDown).toBeNil()
		expect(titles()).toBe("December 2026 | January 2027")
		must(w.panel(), "Next").Activated.fire()
		expect(titles()).toBe("January 2027 | February 2027")
		bound:set(D(2027, 3, 1))
		expect(titles()).toBe("January 2027 | February 2027")
		expect(must(w.panel(), "Previous").Interactable).toBe(false)
		w.stop()
		local narrow = mount({ selection = "range", range = cell, onRangeChange = change, style = "inline" })
		narrow.picker().AbsoluteSize = narrow.V2.new(390, 700)
		expect(narrow.attr("dual")).toBe(false)
		expect(find(narrow.picker(), "Pane2")).toBeNil()
		expect(shown(must(must(narrow.panel(), "Pane1"), "Title"))).toBe(false)
		narrow.stop()
	end)

	t.it("two time pickers on one page: Down from a picker's last week reaches ITS OWN hour field", function()
		local w = world(function(UI, Host)
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
			return Host.Frame({ Name = "Col", Host.UIListLayout({}), picker("A"), picker("B") })
		end, { input = "pad" })
		for _, id in { "A", "B" } do
			local last = 0
			for i, day in civil.monthGrid(2026, 9, 1) do
				if day.month == 9 then
					last = i
				end
			end
			local cell = w.cellAt(last, 1, id)
			w.select(cell)
			expect(cell.NextSelectionDown).toBe(must(must(w.picker(id), "Hour"), "Field"))
			expect(w.cellAt(last - 7, 1, id).NextSelectionDown).toBeNil()
		end
		w.stop()
	end)

	t.it("phone portrait and landscape: the calendar fits, every day keeps the floor, Apply is on screen", function()
		for _, view in { { w = 390, h = 844 }, { w = 844, h = 390 } } do
			for _, range in { false, true } do
				local cell, _, change = caller(if range then { start = D(2026, 9, 1) } else D(2026, 9, 16))
				local spec: any = if range
					then {
						selection = "range",
						range = cell,
						onRangeChange = change,
						draft = true,
						presets = {
							{
								id = "week",
								label = "This week",
								range = function(today: any)
									return { start = today, finish = civil.addDays(today, 6) }
								end,
							},
						},
					}
					else { value = cell, onChange = change, draft = true }
				local w = mount(spec, { input = "touch", viewport = view })
				local where = `{view.w}x{view.h} {if range then "range" else "single"}`
				must(w.picker(), "Show").Activated.fire()
				local compact = view.w < 600
				expect(`{where} {w.attr("route")}`).toBe(`{where} {if compact then "sheet" else "popover"}`)
				for i = 1, 42 do
					local size = w.cellAt(i).Size
					expect(`{where} {size.X.Offset} {size.Y.Offset}`).toBe(`{where} 44 44`)
				end
				expect(`{where} {w.attr("dual")}`).toBe(`{where} {range and not compact}`)
				local panel = w.panel()
				local surface = must(w.screen, "CalendarSurface")
				panel.AbsoluteSize = w.V2.new(340, 900)
				local height = view.h - 16
				expect(`{where} {surface.Size}`).toBe(
					`{where} {if compact
						then w.engine.types.UDim2.new(1, -24, 0, height)
						else w.engine.types.UDim2.fromOffset(
							if range then 2 * 7 * 44 + 24 + 32 else 7 * 44 + 32,
							height
						)}`
				)
				expect(must(panel, "Apply") ~= nil).toBe(true)
				w.stop()
			end
		end
	end)

	t.it("a single date's panel hugs its six weeks: no room kept for an absent hint, caption or footer", function()
		local cell, _, change = caller(D(2026, 9, 16))
		local w = mount({ value = cell, onChange = change })
		w.open()
		local panel = w.panel()
		expect(panel.AutomaticSize).toBe(w.E.AutomaticSize.Y)
		expect(panel.Size).toBe(w.engine.types.UDim2.fromOffset(7 * 44 + 32, 0))
		expect(find(panel, "PageHint")).toBeNil()
		expect(shown(must(must(panel, "Pane1"), "Title"))).toBe(false)
		expect(shown(must(panel, "Actions"))).toBe(false)
		expect(shown(must(panel, "FooterRule"))).toBe(false)
		expect(must(panel, "Header").Size).toBe(w.engine.types.UDim2.new(1, 0, 0, 44))
		local days = must(must(panel, "Pane1"), "Days")
		expect(days.Size).toBe(w.engine.types.UDim2.fromOffset(7 * 44, 6 * 44))
		w.stop()
	end)

	t.it(
		"the week starts where the caller says; a compact touch field opens a sheet with Done, ten feet a centred sheet",
		function()
			local cell, _, change = caller(D(2026, 9, 16))
			local w = mount(
				{ value = cell, onChange = change, weekStart = 2 },
				{ input = "touch", viewport = { w = 390, h = 844 } }
			)
			local show = must(w.picker(), "Show")
			expect(find(w.picker(), "Entry")).toBeNil()
			expect(show.TextXAlignment).toBe(w.E.TextXAlignment.Left)
			show.Activated.fire()
			expect(w.attr("route")).toBe("sheet")
			expect(must(must(w.panel(), "Weekdays"), "W1").Text).toBe("Mo")
			local done = must(must(w.panel(), "Actions"), "Done")
			expect(shown(done)).toBe(true)
			expect(find(must(w.panel(), "Header"), "Close")).toBeNil()
			done.Activated.fire()
			expect(w.attr("presented")).toBe(false)
			w.stop()
			local tv = mount({ value = cell, onChange = change }, { input = "pad", tenFoot = true })
			tv.select(tv.opener())
			tv.open()
			expect(tv.attr("route")).toBe("sheet")
			local surface = must(tv.screen, "CalendarSurface")
			surface.AbsoluteSize = tv.V2.new(340, 400)
			expect(surface.Position).toBe(tv.engine.types.UDim2.fromOffset(130, 250))
			local icon = must(tv.opener(), "LeadingIcon")
			expect(icon.Image).toBe("rbxassetid://93477762216058")
			tv.stop()
		end
	)

	t.it("refuses a malformed contract at construction and quarantines a late bad value", function()
		local function build(spec: any): string
			local ok, err = pcall(function()
				local w = world(function(UI)
					spec.clock = clock
					return UI.DateTimePicker(spec)
				end)
				w.stop()
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
		expect(has({ value = TODAY, onChange = noop, env = {} }, "unknown option 'env'")).toBe(true)
		expect(build({ value = TODAY, readOnly = true })).toBe("ok")
		local source = Compose.cell(TODAY :: any)
		local m = mount({
			value = function(use: any)
				return use(source)
			end,
			onChange = noop,
		})
		source:set(D(2026, 2, 30))
		expect(m.attr("text")).toBe("09/23/2026")
		expect(m.attr("diagnostics")).toBe(1)
		expect(#m.errors).toBe(1)
		source:set(D(2026, 2, 28))
		expect(m.attr("text")).toBe("02/28/2026")
		m.stop()
	end)
end)
