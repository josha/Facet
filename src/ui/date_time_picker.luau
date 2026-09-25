--!strict
local civil = require("./civil_date")
local fieldChrome = require("./field_chrome")
local Shared = require("./types")
local Nav = require("./navigation_types")
local Inputs = require("./input_types")
local Collections = require("./collection_types")
local DTP = require("./date_time_picker_types")
local CivilTypes = require("./civil_date_types")
local ComposeTypes = require("../vendor/compose/core")

type CivilDate = DTP.CivilDate
type Range = DTP.Range
type Spec = DTP.DateTimePickerProps
type Use = ComposeTypes.Use
type Readable<T> = ComposeTypes.Readable<T>
type Cell<T> = ComposeTypes.Cell<T>
type Held = { v: CivilDate? | Range }
type Grab = { other: CivilDate, from: Range, last: CivilDate, moved: boolean }
type TimeRow = { id: string, hour: number, minute: number }
type Deps = {
	DateTimePicker: Shared.Constructor<Spec, Frame>,
	Button: Shared.Constructor<Inputs.ButtonProps, TextButton>,
	NumberInput: Shared.Constructor<Inputs.NumberInputProps, TextBox | Frame>,
	Chip: Shared.Constructor<Inputs.ChipProps, TextButton | Frame>,
	ShortcutHint: Shared.Constructor<Inputs.ShortcutHintProps, TextLabel | Frame>,
	Menu: Nav.MenuConstructor,
	Picker: Nav.PickerConstructor,
	VirtualList: Collections.CollectionConstructor,
}

local KEYS = {
	"selection",
	"value",
	"onChange",
	"onCommit",
	"range",
	"onRangeChange",
	"onRangeCommit",
	"time",
	"minuteStep",
	"hourCycle",
	"min",
	"max",
	"isDateDisabled",
	"weekStart",
	"locale",
	"clock",
	"referenceDate",
	"presets",
	"draft",
	"style",
	"format",
	"placeholder",
	"isPresented",
	"onPresentedChange",
	"onDismiss",
	"enabled",
	"readOnly",
	"label",
	"requiredMark",
	"hint",
	"errorText",
	"controlSize",
	"appearance",
	"corners",
}
local LOCALE_KEYS = { months = true, weekdays = true, order = true, separator = true, hourCycle = true }
local PRESET_KEYS = { id = true, label = true, range = true }
local ORDERS = { mdy = true, dmy = true, ymd = true }
local CELLS = 42
local CELL = 44
local DISC = 32
local GAP = 24
local YEAR_SPAN = 100
local ROW = 44

local function monthOf(d: CivilDate): CivilDate
	return { year = d.year, month = d.month, day = 1 }
end

local function sameRange(a: Range, b: Range): boolean
	return civil.same(a.start, b.start) and civil.same(a.finish, b.finish)
end

return function(ctx: Shared.Context, UI: Deps, surfaces: Nav.Surfaces): ()
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local E, D, D2, V2 = ctx.types.Enum, ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2
	local chrome = fieldChrome(ctx)
	local gui = ctx.config.guiService
	local input = ctx.config.services.UserInputService

	local function tagWhile(node: Instance, tag: string, on: (Use) -> boolean)
		Compose.watch(function(use: Use)
			if on(use) then
				node:AddTag(tag)
			elseif node:HasTag(tag) then
				node:RemoveTag(tag)
			end
		end)
	end
	local function frame(name: string, properties: Shared.FrameNativeProps?): Frame
		local native: Shared.FrameNativeProps = {
			Name = name,
			BorderSizePixel = 0,
			Size = D2.fromOffset(DISC, DISC),
			AnchorPoint = V2.new(0.5, 0.5),
			Position = D2.fromScale(0.5, 0.5),
		}
		local fields = (native :: unknown) :: { [unknown]: unknown }
		for key, value in ((properties or {}) :: unknown) :: { [unknown]: unknown } do
			if type(key) == "number" then
				fields[#fields + 1] = value
			else
				fields[key] = value
			end
		end
		return Host.Frame(native)
	end

	local function build(spec: Spec): Frame
		local function refuse(message: string): never
			error(`Facet UI.DateTimePicker: {message}`, 0)
		end
		local raw = (spec :: unknown) :: { [string]: unknown }
		local rootProps = ctx.props(spec, KEYS, { Name = "DateTimePicker" })
		local mode = spec.selection or "single"
		if mode ~= "single" and mode ~= "range" then
			refuse('selection is "single" or "range".')
		end
		local isRange = mode == "range"
		if isRange and (spec.value ~= nil or spec.onChange ~= nil or spec.onCommit ~= nil) then
			refuse("a range picker uses range, onRangeChange and onRangeCommit, not the single keys.")
		end
		if
			not isRange
			and (spec.range ~= nil or spec.onRangeChange ~= nil or spec.onRangeCommit ~= nil or spec.presets ~= nil)
		then
			refuse('range, onRangeChange, onRangeCommit and presets belong to selection = "range".')
		end
		for _, key in
			{
				"onChange",
				"onCommit",
				"onRangeChange",
				"onRangeCommit",
				"onPresentedChange",
				"onDismiss",
				"isDateDisabled",
				"clock",
				"format",
			}
		do
			if raw[key] ~= nil and type(raw[key]) ~= "function" then
				refuse(`{key} is a function.`)
			end
		end
		for _, key in { "time", "draft" } do
			if raw[key] ~= nil and type(raw[key]) ~= "boolean" then
				refuse(`{key} is true or false.`)
			end
		end
		local withTime = spec.time == true
		if withTime and isRange then
			refuse("time belongs to a single date; a range holds whole days.")
		end
		local draft = spec.draft == true
		local readOnlyNow: unknown = read(spec.readOnly)
		if readOnlyNow ~= nil and type(readOnlyNow) ~= "boolean" then
			refuse("readOnly is a boolean or a readable boolean.")
		end
		local proposeSingle = spec.onChange
		local proposeRange = spec.onRangeChange
		local hasProposer = if isRange then proposeRange ~= nil else proposeSingle ~= nil
		if not hasProposer and readOnlyNow ~= true then
			refuse(
				`an interactive picker needs {if isRange then "onRangeChange" else "onChange"}; only a readOnly one may omit it.`
			)
		end
		local minuteStep: number = spec.minuteStep or 5
		if type(minuteStep) ~= "number" or minuteStep < 1 or minuteStep % 1 ~= 0 or 60 % minuteStep ~= 0 then
			refuse("minuteStep is a whole number of minutes that divides 60.")
		end
		local weekStart: number = spec.weekStart or 1
		if type(weekStart) ~= "number" or weekStart % 1 ~= 0 or weekStart < 1 or weekStart > 7 then
			refuse("weekStart is 1 (Sunday) to 7 (Saturday).")
		end
		local english = civil.ENGLISH
		local months: { string } = assert(english.months)
		local weekdays: { string } = assert(english.weekdays)
		local order: CivilTypes.Order? = english.order
		local separator = english.separator
		local localeHour = english.hourCycle
		if spec.locale ~= nil then
			if type(spec.locale) ~= "table" then
				refuse("locale is a table: { months?, weekdays?, order?, separator?, hourCycle? }.")
			end
			for key in (spec.locale :: unknown) :: { [unknown]: unknown } do
				if type(key) ~= "string" or not LOCALE_KEYS[key] then
					refuse(`locale: unknown key '{tostring(key)}'.`)
				end
			end
			local given = spec.locale
			months = given.months or months
			weekdays = given.weekdays or weekdays
			order = given.order or order
			separator = given.separator or separator
			localeHour = given.hourCycle or localeHour
			if type(months) ~= "table" or #months ~= 12 then
				refuse("locale.months names the twelve months, January first.")
			end
			if type(weekdays) ~= "table" or #weekdays ~= 7 then
				refuse("locale.weekdays names the seven days, Sunday first.")
			end
			if order == nil or not ORDERS[order] then
				refuse('locale.order is "mdy", "dmy" or "ymd".')
			end
		end
		local hourCycle: number = spec.hourCycle or localeHour or 12
		if hourCycle ~= 12 and hourCycle ~= 24 then
			refuse("hourCycle is 12 or 24.")
		end
		local locale: CivilTypes.Locale = {
			months = months,
			weekdays = weekdays,
			order = order,
			separator = separator,
			hourCycle = hourCycle,
		}
		local style = spec.style or "automatic"
		if style ~= "automatic" and style ~= "inline" then
			refuse('style is "automatic" (a field that opens the calendar) or "inline".')
		end
		local overlay = style ~= "inline"
		if not overlay and (spec.isPresented ~= nil or spec.onPresentedChange ~= nil) then
			refuse("an inline calendar is always shown: isPresented and onPresentedChange belong to the field.")
		end
		if spec.placeholder ~= nil and type(spec.placeholder) ~= "string" then
			refuse("placeholder is a string.")
		end
		local function checkDate(key: string, v: unknown, time: boolean?)
			if v ~= nil then
				local why = civil.problem(v, time)
				if why ~= nil then
					refuse(`{key} {why}.`)
				end
			end
		end
		if isRange then
			local r: unknown = read(spec.range)
			if type(r) ~= "table" then
				refuse("range is { start?, finish? } or a readable one.")
			end
			local given = r :: Range
			checkDate("range.start", given.start)
			checkDate("range.finish", given.finish)
		else
			checkDate("value", read(spec.value), withTime)
		end
		checkDate("min", read(spec.min))
		checkDate("max", read(spec.max))
		checkDate("referenceDate", read(spec.referenceDate))
		local presets: { DTP.Preset } = {}
		if spec.presets ~= nil then
			if type(spec.presets) ~= "table" then
				refuse("presets is a list of { id, label, range = function(today) }.")
			end
			local seen: { [string]: boolean } = {}
			for i, p in spec.presets do
				local entry = (p :: unknown) :: { [unknown]: unknown }
				if
					type(entry) ~= "table"
					or type(entry.id) ~= "string"
					or type(entry.label) ~= "string"
					or type(entry.range) ~= "function"
				then
					refuse(`presets[{i}] is \{ id = string, label = string, range = function(today) }.`)
				end
				for key in entry do
					if type(key) ~= "string" or not PRESET_KEYS[key] then
						refuse(`presets[{i}]: unknown key '{tostring(key)}'.`)
					end
				end
				if seen[p.id] then
					refuse(`presets repeats the id '{p.id}'.`)
				end
				seen[p.id] = true
				table.insert(presets, p)
			end
		end
		chrome.check("DateTimePicker", {
			label = spec.label,
			requiredMark = spec.requiredMark,
			hint = spec.hint,
			errorText = spec.errorText,
			controlSize = spec.controlSize,
			appearance = spec.appearance,
			corners = spec.corners,
		})
		local clock: () -> CivilDate = spec.clock or civil.systemClock()

		local diagnostics = Compose.cell({} :: { string })
		local function note(message: string)
			local list = table.clone(diagnostics:peek())
			table.insert(list, message)
			diagnostics:set(list)
			if ctx.config.onError then
				ctx.config.onError(message)
			end
		end
		local function legal<T>(key: string, source: Shared.Value<T>?, ok: (unknown) -> boolean): Readable<T>
			local held: Cell<T> = Compose.cell(read(source))
			local refused = false
			Compose.watch(function(use: Use)
				local v: T = read(source, use)
				if ok(v) then
					refused = false
					held:set(v)
				elseif not refused then
					refused = true
					note(`Facet UI.DateTimePicker: {key} is not a legal value; the picker keeps the last one.`)
				end
			end)
			return held
		end
		local function optionalDate(v: unknown): boolean
			return v == nil or civil.problem(v) == nil
		end
		local value = legal("value", spec.value, function(v: unknown): boolean
			return v == nil or civil.problem(v, withTime) == nil
		end)
		local range = legal("range", if isRange then spec.range else {}, function(v: unknown): boolean
			if type(v) ~= "table" then
				return false
			end
			local r = v :: Range
			return optionalDate(r.start)
				and optionalDate(r.finish)
				and not (r.start ~= nil and r.finish ~= nil and civil.compare(r.start, r.finish) > 0)
		end)
		local minDate = legal("min", spec.min, optionalDate)
		local maxDate = legal("max", spec.max, optionalDate)
		local referenceDate = legal("referenceDate", spec.referenceDate, optionalDate)
		local function enabled(use: Use?): boolean
			return read(spec.enabled, use) ~= false
		end
		local function interactive(use: Use?): boolean
			return enabled(use) and read(spec.readOnly, use) ~= true and hasProposer
		end
		local today = Compose.cell(civil.dateOf(clock()))
		local disposed = false
		Compose.cleanup(function()
			disposed = true
		end)
		local function mayEdit(): boolean
			return not disposed and interactive()
		end
		local function isDisabled(d: CivilDate, use: Use?): boolean
			local lo = if use then use(minDate) else minDate:peek()
			local hi = if use then use(maxDate) else maxDate:peek()
			if not civil.within(d, lo, hi) then
				return true
			end
			local rule = spec.isDateDisabled
			return rule ~= nil and rule(civil.dateOf(d)) == true
		end
		local function anchorDate(): CivilDate
			local held = if isRange then range:peek().start else value:peek()
			return held or referenceDate:peek() or today:peek()
		end
		local viewMonth = Compose.cell(monthOf(anchorDate()))
		local function peekMonth(): CivilDate
			return viewMonth:peek()
		end
		local function paneMonth(k: number, use: Use?): CivilDate
			local m = if use then use(viewMonth) else viewMonth:peek()
			return civil.addMonths(m, k - 1)
		end
		local room = Compose.cell(0)
		local dual = Compose.formula(function(use: Use): boolean
			return isRange and use(room) >= 2 * 7 * CELL + GAP
		end)
		local function panes(use: Use?): number
			return if if use then use(dual) else dual:peek() then 2 else 1
		end
		local function monthClosed(m: CivilDate, use: Use?): boolean
			local lo = if use then use(minDate) else minDate:peek()
			local hi = if use then use(maxDate) else maxDate:peek()
			local last = { year = m.year, month = m.month, day = civil.daysIn(m.year, m.month) }
			return (lo ~= nil and civil.compare(last, lo) < 0) or (hi ~= nil and civil.compare(monthOf(m), hi) > 0)
		end
		local function canPage(delta: number, use: Use?): boolean
			local shown = paneMonth(1 + (if delta > 0 then delta + panes(use) - 1 else delta), use)
			return not monthClosed(shown, use)
		end
		local function page(delta: number): boolean
			if not canPage(delta) then
				return false
			end
			viewMonth:set(civil.addMonths(peekMonth(), delta))
			return true
		end

		local proposing = false
		local snapshot: Held = { v = nil }
		local function current(): CivilDate? | Range
			return if isRange then range:peek() else value:peek()
		end
		local function same(a: CivilDate? | Range, b: CivilDate? | Range): boolean
			if isRange then
				return sameRange(a :: Range, b :: Range)
			end
			return civil.same(a :: CivilDate?, b :: CivilDate?)
		end
		local function takeSnapshot()
			snapshot = { v = current() }
		end
		takeSnapshot()
		Compose.watch(function(use: Use)
			if isRange then
				use(range)
			else
				use(value)
			end
			if not proposing then
				takeSnapshot()
			end
		end)
		local function send(next: CivilDate? | Range)
			proposing = true
			local ok, err = pcall(function()
				if isRange then
					assert(proposeRange)(next :: Range)
				else
					assert(proposeSingle)(next :: CivilDate?)
				end
			end)
			proposing = false
			if not ok then
				error(err, 0)
			end
		end
		local function propose(next: CivilDate? | Range): boolean
			if not mayEdit() then
				return false
			end
			send(next)
			return same(current(), next)
		end
		local function commit()
			if disposed then
				return
			end
			if isRange then
				local r = range:peek()
				if spec.onRangeCommit ~= nil and r.start ~= nil and r.finish ~= nil then
					spec.onRangeCommit(r)
				end
			elseif spec.onCommit ~= nil then
				spec.onCommit(value:peek())
			end
		end
		local function restore()
			if disposed or not mayEdit() then
				return
			end
			if not same(current(), snapshot.v) then
				send(snapshot.v)
			end
		end

		local openCell = Compose.cell(false)
		local presented = Compose.formula(function(use: Use): boolean
			if not overlay then
				return true
			end
			if spec.isPresented ~= nil then
				return read(spec.isPresented, use) == true
			end
			return use(openCell)
		end)
		local closeWhy: DTP.DismissReason? = nil
		local function requestPresented(next: boolean)
			if next and (disposed or not interactive()) then
				return
			end
			if spec.onPresentedChange ~= nil then
				spec.onPresentedChange(next)
			elseif spec.isPresented == nil then
				openCell:set(next)
			else
				local bound = (spec.isPresented :: unknown) :: { set: unknown }
				if type(bound) == "table" and type(bound.set) == "function" then
					(spec.isPresented :: Cell<boolean>):set(next)
				end
			end
		end
		local function close(why: DTP.DismissReason)
			if not overlay or not presented:peek() then
				return
			end
			if draft and why ~= "apply" then
				restore()
			end
			closeWhy = why
			requestPresented(false)
		end
		local wasPresented = presented:peek()
		Compose.watch(function(use: Use)
			local on = use(presented)
			if on and not wasPresented then
				takeSnapshot()
				today:set(civil.dateOf(clock()))
				viewMonth:set(monthOf(anchorDate()))
			elseif not on and wasPresented and overlay then
				local why: DTP.DismissReason = closeWhy or "cancel"
				closeWhy = nil
				if spec.onDismiss then
					spec.onDismiss(why)
				end
			end
			wasPresented = on
		end)

		local function choose(d: CivilDate)
			if not mayEdit() or isDisabled(d) then
				return
			end
			local day = civil.dateOf(d)
			if not isRange then
				local held = value:peek()
				if withTime then
					day.hour = if held ~= nil and held.hour ~= nil then held.hour else 0
					day.minute = if held ~= nil and held.minute ~= nil then held.minute else 0
				end
				if not propose(day) then
					return
				end
				local shown = peekMonth()
				if day.month ~= shown.month or day.year ~= shown.year then
					if not (civil.same(monthOf(day), civil.addMonths(shown, 1)) and dual:peek()) then
						viewMonth:set(monthOf(day))
					end
				end
				if not draft then
					commit()
					if not withTime then
						close("activate")
					end
				end
				return
			end
			local r = range:peek()
			local next: Range
			if r.start == nil or r.finish ~= nil then
				next = { start = day, finish = nil }
			elseif civil.compare(day, r.start) < 0 then
				next = { start = day, finish = r.start }
			else
				next = { start = r.start, finish = day }
			end
			if propose(next) and next.finish ~= nil and not draft then
				commit()
				close("activate")
			end
		end

		local typedError = Compose.cell("")
		local function words(v: CivilDate?): string
			if v == nil then
				return ""
			end
			return if spec.format ~= nil then spec.format(v) else civil.format(v, locale)
		end
		local valueText = Compose.formula(function(use: Use): string
			if isRange then
				local r = use(range)
				if r.start == nil then
					return ""
				end
				return `{words(r.start)} – {if r.finish ~= nil then words(r.finish) else "…"}`
			end
			return words(use(value))
		end)
		local function longName(d: CivilDate): string
			return `{months[d.month]} {d.day}, {d.year}`
		end
		local preferred = if input and input.GetPropertyChangedSignal
			then ctx.observe(input, "PreferredInput")
			else Compose.cell(nil :: unknown)
		local function prefers(kind: Enum.PreferredInput, use: Use): boolean
			return use(preferred) == kind
		end
		local typedEntry = Compose.formula(function(use: Use): boolean
			if spec.format ~= nil then
				return false
			end
			local kind = use(preferred)
			return kind == nil or kind == E.PreferredInput.KeyboardAndMouse
		end)
		local selected: Readable<GuiObject?> = if gui and gui.GetPropertyChangedSignal
			then ctx.observe(gui, "SelectedObject")
			else Compose.cell(nil :: GuiObject?)

		local function parseOne(s: string): (CivilDate?, string?)
			local d, why = civil.parse(s, locale, withTime)
			if d ~= nil and isDisabled(d) then
				return nil, "That date is not available."
			end
			return d, why
		end
		local function typed(text: string): boolean
			if text == valueText:peek() then
				typedError:set("")
				return true
			end
			local next: (CivilDate? | Range)? = nil
			local why: string? = nil
			local found = false
			if isRange then
				local at, stop = string.find(text, "–", 1, true)
				if at == nil then
					at, stop = string.find(text, " - ", 1, true)
				end
				if at == nil and string.match(text, "^%s*$") ~= nil then
					next, found = {}, true
				elseif at == nil or stop == nil then
					why = "Enter two dates, like "
						.. civil.format({ year = 2026, month = 1, day = 2 }, locale)
						.. " – "
						.. civil.format({ year = 2026, month = 1, day = 9 }, locale)
				else
					local s, f
					s, why = parseOne(string.sub(text, 1, at - 1))
					if s ~= nil then
						f, why = parseOne(string.sub(text, stop + 1))
					end
					if s ~= nil and f ~= nil then
						next = if civil.compare(s, f) <= 0 then { start = s, finish = f } else { start = f, finish = s }
						found = true
					end
				end
			elseif string.match(text, "^%s*$") ~= nil then
				next, found = nil, true
			else
				local d
				d, why = parseOne(text)
				next, found = d, d ~= nil
			end
			if not found then
				typedError:set(why or "Enter a date.")
				return false
			end
			typedError:set("")
			if propose(next) then
				if not draft then
					commit()
				end
				local anchor = if isRange then (next :: Range).start else next :: CivilDate?
				if anchor ~= nil then
					viewMonth:set(monthOf(anchor))
				end
			end
			return true
		end

		local cells: { [number]: { [number]: TextButton } } = {}
		local cellIndex: { [Instance]: { k: number, i: number } } = {}
		local function gridDate(k: number, i: number): CivilDate
			local m = paneMonth(k)
			return civil.monthGrid(m.year, m.month, weekStart)[i]
		end
		local function cellFor(d: CivilDate, use: Use?): (number?, number?)
			for k = 1, panes(use) do
				local m = paneMonth(k, use)
				if d.year == m.year and d.month == m.month then
					for i, g in civil.monthGrid(m.year, m.month, weekStart) do
						if civil.compare(g, d) == 0 then
							return k, i
						end
					end
				end
			end
			return nil, nil
		end
		local function landing(): number
			local m = peekMonth()
			local grid = civil.monthGrid(m.year, m.month, weekStart)
			local want = if isRange then range:peek().start else value:peek()
			local candidates: { CivilDate } = { today:peek() }
			if want ~= nil then
				table.insert(candidates, 1, want)
			end
			for _, candidate in candidates do
				for i, d in grid do
					if civil.compare(d, candidate) == 0 and d.month == m.month and not isDisabled(d) then
						return i
					end
				end
			end
			for i, d in grid do
				if d.month == m.month and not isDisabled(d) then
					return i
				end
			end
			return 1
		end

		local grab: Grab? = nil
		local swallowTap = false
		local function dayUnder(x: number, y: number): CivilDate?
			for k, list in cells do
				for i, cell in list do
					local at, size = cell.AbsolutePosition, cell.AbsoluteSize
					if x >= at.X and x < at.X + size.X and y >= at.Y and y < at.Y + size.Y then
						return gridDate(k, i)
					end
				end
			end
			return nil
		end
		local function grabEnd(d: CivilDate): boolean
			local r = range:peek()
			if not isRange or r.start == nil or r.finish == nil or not mayEdit() then
				return false
			end
			local other = if civil.compare(d, r.start) == 0
				then r.finish
				elseif civil.compare(d, r.finish) == 0 then r.start
				else nil
			if other == nil then
				return false
			end
			grab = { other = other, from = r, last = d, moved = false }
			return true
		end
		local function dragTo(x: number, y: number)
			local held = grab
			if held == nil then
				return
			end
			local d = dayUnder(x, y)
			if d == nil or isDisabled(d) or civil.compare(d, held.last) == 0 then
				return
			end
			held.last, held.moved = d, true
			local a, b = held.other, civil.dateOf(d)
			propose(if civil.compare(b, a) < 0 then { start = b, finish = a } else { start = a, finish = b })
		end
		local function release(cancelled: boolean)
			local held = grab
			grab = nil
			if held == nil or not held.moved then
				return
			end
			swallowTap = not cancelled
			if cancelled then
				propose(held.from)
			elseif not draft then
				commit()
			end
		end
		if isRange and input then
			local function pointer(event: InputObject): boolean
				return event.UserInputType == E.UserInputType.MouseButton1
					or event.UserInputType == E.UserInputType.MouseMovement
					or event.UserInputType == E.UserInputType.Touch
			end
			runtime.connect(input, "InputChanged", function(event: InputObject)
				if grab ~= nil and pointer(event) then
					if event.UserInputState == E.UserInputState.Cancel then
						release(true)
					else
						dragTo(event.Position.X, event.Position.Y)
					end
				end
			end)
			runtime.connect(input, "InputEnded", function(event: InputObject)
				if grab ~= nil and pointer(event) then
					release(event.UserInputState == E.UserInputState.Cancel)
				end
			end)
			runtime.connect(input, "WindowFocusReleased", function()
				release(true)
			end)
		end

		local upTarget = Compose.cell(nil :: GuiObject?)
		local downTarget = Compose.cell(nil :: GuiObject?)
		local function shownAway(k: number, i: number, step: number, use: Use): boolean
			use(viewMonth)
			local m = paneMonth(k, use)
			local target = civil.addDays(civil.monthGrid(m.year, m.month, weekStart)[i], step)
			return cellFor(target, use) ~= nil
		end

		local function dayCell(k: number, i: number): TextButton
			local date = Compose.formula(function(use: Use): CivilDate
				local m = paneMonth(k, use)
				return civil.monthGrid(m.year, m.month, weekStart)[i]
			end)
			local outside = Compose.formula(function(use: Use): boolean
				return use(date).month ~= paneMonth(k, use).month
			end)
			local disabled = Compose.formula(function(use: Use): boolean
				return isDisabled(use(date), use)
			end)
			local chosen = Compose.formula(function(use: Use): boolean
				local d = use(date)
				if use(outside) then
					return false
				end
				if isRange then
					local r = use(range)
					return (r.start ~= nil and civil.compare(d, r.start) == 0)
						or (r.finish ~= nil and civil.compare(d, r.finish) == 0)
				end
				local v = use(value)
				return v ~= nil and civil.compare(d, v) == 0
			end)
			local banded = Compose.formula(function(use: Use): boolean
				if not isRange or use(outside) then
					return false
				end
				local r = use(range)
				return r.start ~= nil and r.finish ~= nil and civil.within(use(date), r.start, r.finish)
			end)
			local column = (i - 1) % 7 + 1
			local function edge(side: "leading" | "trailing", use: Use): boolean
				if not use(banded) then
					return true
				end
				local r = use(range)
				local stop = assert(if side == "leading" then r.start else r.finish)
				return civil.compare(use(date), stop) == 0 or column == (if side == "leading" then 1 else 7)
			end
			local function capped(use: Use): boolean
				return use(banded) and (edge("leading", use) or edge("trailing", use)) and not use(chosen)
			end
			local disc = frame("Disc", {
				Visible = function(use: Use)
					return use(chosen)
				end,
				ZIndex = 3,
				ctx.corner(DISC),
			})
			disc:AddTag("facet-calendar-disc")
			if isRange then
				disc:AddTag("facet-calendar-end")
			end
			local band = frame("Band", {
				Size = D2.new(1, 0, 0, DISC),
				Visible = function(use: Use)
					return use(banded)
				end,
				BackgroundTransparency = 1,
				ZIndex = 1,
				frame("Leading", {
					Size = D2.new(0.5, 0, 1, 0),
					AnchorPoint = V2.new(0, 0),
					Position = D2.fromScale(0, 0),
					Visible = function(use: Use)
						return not edge("leading", use)
					end,
				}),
				frame("Trailing", {
					Size = D2.new(0.5, 0, 1, 0),
					AnchorPoint = V2.new(0, 0),
					Position = D2.fromScale(0.5, 0),
					Visible = function(use: Use)
						return not edge("trailing", use)
					end,
				}),
			})
			for _, part in band:GetChildren() do
				part:AddTag("facet-calendar-band")
			end
			local cap = frame("Cap", {
				Visible = capped,
				ZIndex = 2,
				ctx.corner(DISC),
			})
			cap:AddTag("facet-calendar-band")
			local ring = frame("Today", {
				Visible = function(use: Use)
					return civil.compare(use(date), use(today)) == 0
				end,
				ZIndex = 4,
				BackgroundTransparency = 1,
				ctx.corner(DISC) :: Shared.Child,
				Host.UIStroke({ Thickness = 1 }) :: Shared.Child,
			})
			ring:AddTag("facet-calendar-today")
			local number = ctx.text({
				Name = "Day",
				Text = function(use: Use)
					return tostring(use(date).day)
				end,
				AutomaticSize = E.AutomaticSize.None,
				Size = D2.fromScale(1, 1),
				TextXAlignment = E.TextXAlignment.Center,
				ZIndex = 5,
			})
			number:AddTag("facet-calendar-number")
			tagWhile(number, "facet-calendar-dim", function(use: Use)
				return use(outside) or use(disabled)
			end)
			tagWhile(
				number,
				if isRange then "facet-calendar-chosen-end" else "facet-calendar-chosen",
				function(use: Use)
					return use(chosen)
				end
			)
			local strike = frame("Strike", {
				Size = D2.new(0.5, 0, 0, 1),
				Visible = function(use: Use)
					return use(disabled)
				end,
				ZIndex = 6,
			})
			strike:AddTag("facet-calendar-strike")
			local cell: TextButton
			local up = function(use: Use): GuiObject?
				if shownAway(k, i, -7, use) then
					return nil
				end
				return use(upTarget)
			end
			local down = function(use: Use): GuiObject?
				if shownAway(k, i, 7, use) then
					return nil
				end
				return use(downTarget)
			end
			cell = UI.Button({
				Name = `D{i}`,
				LayoutOrder = i,
				label = "",
				name = function(use: Use)
					return longName(use(date)) .. (if use(disabled) then ", unavailable" else "")
				end,
				Size = D2.fromOffset(CELL, CELL),
				AutomaticSize = E.AutomaticSize.None,
				enabled = function(use: Use)
					return interactive(use)
				end,
				Selectable = function(use: Use)
					return interactive(use) and not use(outside)
				end,
				NextSelectionUp = (up :: unknown) :: Shared.Value<GuiObject>,
				NextSelectionDown = (down :: unknown) :: Shared.Value<GuiObject>,
				onActivate = function()
					if swallowTap then
						swallowTap = false
						return
					end
					choose(date:peek())
				end,
				Host.Frame({
					Name = "Layers",
					BackgroundTransparency = 1,
					Size = D2.fromScale(1, 1),
					band :: Shared.Child,
					cap :: Shared.Child,
					disc :: Shared.Child,
					ring :: Shared.Child,
					number :: Shared.Child,
					strike :: Shared.Child,
				}),
			})
			cell:AddTag("facet-calendar-day")
			if isRange then
				runtime.connect(cell, "InputBegan", function(event: InputObject)
					if
						event.UserInputType == E.UserInputType.MouseButton1
						or event.UserInputType == E.UserInputType.Touch
					then
						swallowTap = false
						if not outside:peek() then
							grabEnd(date:peek())
						end
					end
				end)
			end
			cells[k] = cells[k] or {}
			cells[k][i] = cell
			cellIndex[cell] = { k = k, i = i }
			Compose.cleanup(function()
				if cells[k] and cells[k][i] == cell then
					cells[k][i] = nil
				end
				cellIndex[cell] = nil
			end)
			return cell
		end

		local function pane(k: number): Frame
			local names: { Shared.Child } = {}
			for c = 0, 6 do
				local dayIndex = (weekStart - 1 + c) % 7 + 1
				table.insert(
					names,
					ctx.styled(
						ctx.text({
							Name = `W{c + 1}`,
							Text = weekdays[dayIndex],
							Size = D2.fromOffset(CELL, 20),
							AutomaticSize = E.AutomaticSize.None,
							TextXAlignment = E.TextXAlignment.Center,
						}),
						"type-caption"
					)
				)
			end
			local weekdayRow = ctx.row(names, { Name = "Weekdays" })
			assert(weekdayRow:FindFirstChildWhichIsA("UIListLayout")).Padding = D.new(0, 0)
			local days: { Shared.Child } = {
				Host.UIListLayout({
					FillDirection = E.FillDirection.Horizontal,
					Wraps = true,
					Padding = D.new(0, 0),
					SortOrder = E.SortOrder.LayoutOrder,
				}),
			}
			for i = 1, CELLS do
				table.insert(days, dayCell(k, i))
			end
			local grid = Host.Frame({
				Name = "Days",
				BackgroundTransparency = 1,
				Size = D2.fromOffset(7 * CELL, 6 * CELL),
				table.unpack(days),
			})
			local title = ctx.styled(
				ctx.text({
					Name = "Title",
					Text = function(use: Use)
						local m = paneMonth(k, use)
						return `{months[m.month]} {m.year}`
					end,
					Visible = function(use: Use)
						return use(dual)
					end,
				}),
				"type-label"
			)
			local parts: { Shared.Child } = { title, weekdayRow, grid }
			return ctx.column(parts, { Name = `Pane{k}` })
		end

		local function menu(
			menuName: string,
			options: (Use) -> { { value: number, label: string, enabled: (Use) -> boolean } },
			get: (CivilDate) -> number,
			set: (number) -> ()
		): Frame
			local pick = Compose.cell(get(peekMonth()))
			Compose.watch(function(use: Use)
				pick:set(get(use(viewMonth)))
			end)
			local items = function(use: Use): { Nav.MenuItem<number> }
				local out: { Nav.MenuItem<number> } = {}
				for _, option in options(use) do
					local item: Nav.MenuItem<number> = {
						id = tostring(option.value),
						label = option.label,
						selected = pick,
						value = option.value,
						enabled = option.enabled,
						dismiss = true,
						onChange = set,
					}
					table.insert(out, item)
				end
				return out
			end
			local wordsOf = function(use: Use): string
				local now = use(pick)
				for _, option in options(use) do
					if option.value == now then
						return option.label
					end
				end
				return tostring(now)
			end
			local trigger = UI.Button({
				Name = menuName,
				label = wordsOf,
				trailingIcon = "chevron.down",
				appearance = "utility",
				enabled = function(use: Use)
					return interactive(use)
				end,
			})
			return UI.Menu({
				Name = menuName .. "Menu",
				items = items,
				trigger = trigger :: GuiObject,
				presentation = "menu" :: "menu",
				enabled = function(use: Use)
					return interactive(use)
				end,
			})
		end
		local function landIn(m: CivilDate)
			local lo, hi = minDate:peek(), maxDate:peek()
			if lo ~= nil and civil.compare(m, monthOf(lo)) < 0 then
				m = monthOf(lo)
			elseif hi ~= nil and civil.compare(m, monthOf(hi)) > 0 then
				m = monthOf(hi)
			end
			viewMonth:set(m)
		end
		local function header(): Frame
			local monthMenu = menu("Month", function(use: Use)
				local list = {}
				for m = 1, 12 do
					table.insert(list, {
						value = m,
						label = months[m],
						enabled = function(inner: Use): boolean
							return not monthClosed({ year = inner(viewMonth).year, month = m, day = 1 }, inner)
						end,
					})
				end
				return list
			end, function(m: CivilDate): number
				return m.month
			end, function(v: number)
				landIn({ year = peekMonth().year, month = v, day = 1 })
			end)
			local yearMenu = menu("Year", function(use: Use)
				local centre = use(viewMonth).year
				local lo, hi = use(minDate), use(maxDate)
				local list = {}
				for y = if lo then lo.year else centre - YEAR_SPAN, if hi then hi.year else centre + YEAR_SPAN do
					table.insert(list, {
						value = y,
						label = tostring(y),
						enabled = function(): boolean
							return true
						end,
					})
				end
				return list
			end, function(m: CivilDate): number
				return m.year
			end, function(v: number)
				landIn({ year = v, month = peekMonth().month, day = 1 })
			end)
			upTarget:set(assert(monthMenu:FindFirstChild("Month", true)) :: GuiObject)
			local function arrow(name: string, icon: string, words_: string, delta: number): TextButton
				return UI.Button({
					Name = name,
					icon = icon,
					name = words_,
					shape = "circle" :: "circle",
					appearance = "utility",
					enabled = function(use: Use)
						return interactive(use) and canPage(delta, use)
					end,
					onActivate = function()
						page(delta)
					end,
				})
			end
			local choose_ = ctx.row({ monthMenu, yearMenu }, { Name = "Choose" })
			runtime.mountFragment(function()
				return { Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }) }
			end, choose_)
			local row = ctx.row({
				arrow("Previous", "chevron.leading", "Previous month", -1),
				choose_,
				arrow("Next", "chevron.trailing", "Next month", 1),
			}, { Name = "Header", Size = D2.new(1, 0, 0, ROW), AutomaticSize = E.AutomaticSize.None })
			assert(row:FindFirstChildWhichIsA("UIListLayout")).VerticalAlignment = E.VerticalAlignment.Center
			return row
		end

		local function timeSection(): Frame
			local function base(): CivilDate
				local v = value:peek()
				if v ~= nil and v.hour ~= nil then
					return v
				end
				local d = civil.dateOf(v or anchorDate())
				d.hour, d.minute = 0, 0
				return d
			end
			local function field(
				name: string,
				lo: number,
				hi: number,
				step: number,
				get: (CivilDate) -> number,
				with: (CivilDate, number) -> CivilDate
			): TextBox | Frame
				local text = Compose.cell("")
				local number = Compose.cell(lo)
				Compose.watch(function(use: Use)
					local v = use(value)
					local n = if v ~= nil and v.hour ~= nil then get(v) else lo
					number:set(n)
					text:set(if v ~= nil then string.format("%02d", n) else "")
				end)
				return UI.NumberInput({
					Name = name,
					label = name,
					value = text,
					numericValue = number,
					min = lo,
					max = hi,
					step = step,
					precision = 0,
					stepButtons = true,
					enabled = function(use: Use)
						return interactive(use)
					end,
					format = function(n: number): string
						return string.format("%02d", n)
					end,
					onCommit = function(n: number)
						local v = value:peek()
						if not propose(with(base(), n)) then
							local held = if v ~= nil and v.hour ~= nil then get(v) else lo
							number:set(held)
							text:set(if v ~= nil then string.format("%02d", held) else "")
						elseif not draft then
							commit()
						end
					end,
				})
			end
			local function withHour(d: CivilDate, h: number): CivilDate
				local out = table.clone(d)
				local pm = (d.hour or 0) >= 12
				out.hour = if hourCycle == 12 then (h % 12) + (if pm then 12 else 0) else h
				return out
			end
			local function withMinute(d: CivilDate, m: number): CivilDate
				local out = table.clone(d)
				out.minute = m
				return out
			end
			local hour = field(
				"Hour",
				if hourCycle == 12 then 1 else 0,
				if hourCycle == 12 then 12 else 23,
				1,
				function(v)
					local h = v.hour or 0
					return if hourCycle == 12 then (if h % 12 == 0 then 12 else h % 12) else h
				end,
				withHour
			)
			local minute = field("Minute", 0, 60 - minuteStep, minuteStep, function(v)
				return v.minute or 0
			end, withMinute)
			downTarget:set(hour:FindFirstChild("Field", true) :: GuiObject?)
			local parts: { Shared.Child } = { hour, minute }
			if hourCycle == 12 then
				local half = Compose.cell("AM")
				Compose.watch(function(use: Use)
					local v = use(value)
					half:set(if v ~= nil and v.hour ~= nil and v.hour >= 12 then "PM" else "AM")
				end)
				local halfSpec: Nav.SinglePickerSpec<string> = {
					Name = "Half",
					options = { { value = "AM", label = "AM" }, { value = "PM", label = "PM" } },
					selected = half,
					style = "segmented" :: "segmented",
					sizing = "hug" :: "hug",
					Size = D2.fromOffset(0, 0),
					AutomaticSize = E.AutomaticSize.XY,
					enabled = function(use: Use)
						return interactive(use)
					end,
					onChanging = function(word: string): boolean?
						local v = value:peek()
						if v == nil or v.hour == nil then
							return false
						end
						local next = table.clone(v)
						next.hour = (v.hour :: number) % 12 + (if word == "PM" then 12 else 0)
						if not propose(next) then
							return false
						end
						if not draft then
							commit()
						end
						return true
					end,
				}
				table.insert(parts, UI.Picker(halfSpec))
			end
			local fields = ctx.row(parts, { Name = "Fields" })
			assert(fields:FindFirstChildWhichIsA("UIListLayout")).VerticalAlignment = E.VerticalAlignment.Bottom
			local times: { TimeRow } = {}
			for minutes = 0, 24 * 60 - 1, minuteStep do
				table.insert(
					times,
					{ id = `{minutes // 60}:{minutes % 60}`, hour = minutes // 60, minute = minutes % 60 }
				)
			end
			local list = Compose.show(function(use: Use)
				return prefers(E.PreferredInput.Touch, use)
			end, function()
				local at: CivilDate = value:peek() or clock()
				if at.hour == nil then
					at = clock()
				end
				local first = if at.hour ~= nil then (at.hour * 60 + (at.minute or 0)) // minuteStep else 0
				local timesSpec: Collections.KeyedCollectionSpec<TimeRow, string> = {
					Name = "Times",
					LayoutOrder = 2,
					from = times,
					key = "id",
					itemSize = ROW,
					Size = D2.new(1, 0, 0, 4 * ROW),
					CanvasPosition = V2.new(0, first * ROW),
					render = function(row: Readable<TimeRow>): GuiObject
						local t = row:peek()
						return UI.Button({
							Name = "Time",
							label = civil.formatTime(
								{ year = 2000, month = 1, day = 1, hour = t.hour, minute = t.minute },
								hourCycle
							),
							Size = D2.new(1, 0, 0, ROW),
							AutomaticSize = E.AutomaticSize.None,
							enabled = function(use: Use)
								return interactive(use)
							end,
							selected = function(use: Use)
								local v = use(value)
								return v ~= nil and v.hour == t.hour and v.minute == t.minute
							end,
							onActivate = function()
								local next = civil.dateOf(value:peek() or anchorDate())
								next.hour, next.minute = t.hour, t.minute
								if propose(next) and not draft then
									commit()
								end
							end,
						})
					end,
				}
				return UI.VirtualList(timesSpec)
			end)
			return ctx.column(
				{ fields, list },
				{ Name = "Time", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y }
			)
		end

		local function presetRow(): Frame
			local chips: { Shared.Child } = {}
			for _, p in presets do
				local clamped = Compose.formula(function(use: Use): Range?
					return civil.clampRange(p.range(use(today)), use(minDate), use(maxDate))
				end)
				local chipSpec: Inputs.ChipProps = {
					Name = `Preset-{p.id}`,
					label = p.label,
					controlSize = "compact" :: "compact",
					selected = function(use: Use): boolean
						local c = use(clamped)
						return c ~= nil and c.start ~= nil and sameRange(use(range), c)
					end,
					enabled = function(use: Use): boolean
						return use(clamped) ~= nil and interactive(use)
					end,
					onToggle = function()
						local c = clamped:peek()
						if c == nil then
							return
						end
						if propose(c) then
							if c.start ~= nil then
								viewMonth:set(monthOf(c.start))
							end
							if not draft then
								commit()
							end
						end
					end,
				}
				table.insert(chips, UI.Chip(chipSpec))
			end
			return ctx.row(chips, { Name = "Presets" })
		end

		local function panelView(route: (Use) -> string): Frame
			local children: { Shared.Child } = {
				header(),
				ctx.styled(
					frame(
						"HeaderRule",
						{ Size = D2.new(1, 0, 0, 1), AnchorPoint = V2.zero, Position = D2.fromScale(0, 0) }
					),
					"divider"
				),
			}
			local second = Compose.show(function(use: Use)
				return use(dual)
			end, function()
				local p = pane(2)
				p.LayoutOrder = 2
				return p
			end)
			local panesRow = ctx.row({ pane(1), second }, { Name = "Panes" })
			assert(panesRow:FindFirstChildWhichIsA("UIListLayout")).Padding = D.new(0, GAP)
			table.insert(children, panesRow)
			local hintOrder = #children + 1
			local hint = Compose.show(function(use: Use)
				return prefers(E.PreferredInput.Gamepad, use)
			end, function()
				local keys: Inputs.ShortcutHintProps = {
					Name = "PageKeys",
					keys = { { "LB" }, { "RB" } },
					controlSize = "compact" :: "compact",
				}
				local words_ = ctx.styled(ctx.text({ Name = "Words", Text = "Change month" }), "type-caption")
				return ctx.row({ UI.ShortcutHint(keys), words_ }, { Name = "PageHint", LayoutOrder = hintOrder })
			end)
			table.insert(children, hint)
			if withTime then
				table.insert(children, timeSection())
			end
			if #presets > 0 then
				table.insert(children, presetRow())
			end
			local function action(name: string, words_: string, fn: () -> (), look: string?): TextButton
				return UI.Button({
					Name = name,
					label = words_,
					onActivate = fn,
					appearance = look,
					enabled = function(use: Use)
						return interactive(use)
					end,
				})
			end
			local actions: Frame? = nil
			if draft then
				local reset = action("ResetAll", "Reset all", function()
					propose(if isRange then {} else nil)
				end, "link")
				local cancel = action("Cancel", "Cancel", function()
					restore()
					takeSnapshot()
					close("cancel")
				end)
				local apply = action("Apply", "Apply", function()
					if isRange then
						local r = range:peek()
						if spec.onRangeCommit ~= nil then
							spec.onRangeCommit(r)
						end
					else
						commit()
					end
					takeSnapshot()
					close("apply")
				end, "emphasis")
				local commitRow = ctx.row({ cancel, apply }, { Name = "Commit" })
				actions = ctx.row(
					{ reset, commitRow },
					{ Name = "Actions", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y }
				)
				downTarget:set(downTarget:peek() or reset)
			elseif overlay then
				local done = Compose.show(function(use: Use)
					return route(use) == "sheet"
				end, function()
					local button = action("Done", "Done", function()
						close("activate")
					end)
					if not withTime then
						downTarget:set(button)
					end
					Compose.cleanup(function()
						if downTarget:peek() == button then
							downTarget:set(nil)
						end
					end)
					return button
				end)
				actions = ctx.row({ done }, {
					Name = "Actions",
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					Visible = function(use: Use)
						return route(use) == "sheet"
					end,
				})
			end
			if actions then
				local layout = assert(actions:FindFirstChildWhichIsA("UIListLayout"))
				layout.VerticalAlignment = E.VerticalAlignment.Center
				layout.HorizontalFlex = if draft then E.UIFlexAlignment.SpaceBetween else E.UIFlexAlignment.None
				layout.HorizontalAlignment = E.HorizontalAlignment.Right
				local footer = ctx.styled(
					frame("FooterRule", {
						Size = D2.new(1, 0, 0, 1),
						AnchorPoint = V2.zero,
						Position = D2.fromScale(0, 0),
						Visible = if draft
							then true
							else function(use: Use)
								return route(use) == "sheet"
							end,
					}),
					"divider"
				)
				table.insert(children, footer)
				table.insert(children, actions)
			end
			local panel = ctx.column(children, {
				Name = "Calendar",
				Size = if overlay then nil else D2.new(1, 0, 0, 0),
				AutomaticSize = if overlay then E.AutomaticSize.Y else E.AutomaticSize.Y,
				ctx.padding(16, 16) :: Shared.Child,
			})
			assert(panel:FindFirstChildWhichIsA("UIListLayout")).Padding = D.new(0, 12)

			local function focusedCell(use: Use?): (number?, number?)
				local node = if use then use(selected) else selected:peek()
				local at = if node ~= nil then cellIndex[(node :: unknown) :: Instance] else nil
				if at == nil then
					return nil, nil
				end
				return at.k, at.i
			end
			local function plan(step: number, use: Use?): (string?, CivilDate?)
				local k, i = focusedCell(use)
				if k == nil or i == nil then
					return nil, nil
				end
				local m = paneMonth(k, use)
				local target = civil.addDays(civil.monthGrid(m.year, m.month, weekStart)[i], step)
				if cellFor(target, use) ~= nil then
					return "move", target
				end
				if math.abs(step) == 1 and canPage(step, use) then
					return "page", target
				end
				return nil, nil
			end
			local function focusDay(d: CivilDate)
				local k, i = cellFor(d)
				local list = if k then cells[k] else nil
				local cell = if list and i then list[i] else nil
				if gui and cell then
					gui.SelectedObject = cell
				end
			end
			local function walk(name: string, step: number, keys: { Shared.ActionBinding })
				ctx.action(panel, name, keys, function(use: Use)
					return interactive(use) and (plan(step, use)) ~= nil
				end, function()
					local how, target = plan(step)
					if how == "page" then
						page(if step > 0 then 1 else -1)
					end
					if target then
						focusDay(target)
					end
				end, { priority = 2200 })
			end
			walk("CalendarLeft", -1, { E.KeyCode.Left, E.KeyCode.DPadLeft })
			walk("CalendarRight", 1, { E.KeyCode.Right, E.KeyCode.DPadRight })
			walk("CalendarUp", -7, { E.KeyCode.Up, E.KeyCode.DPadUp })
			walk("CalendarDown", 7, { E.KeyCode.Down, E.KeyCode.DPadDown })
			local function turn(name: string, delta: number, keys: { Shared.ActionBinding })
				ctx.action(panel, name, keys, function(use: Use)
					return interactive(use) and (focusedCell(use)) ~= nil and canPage(delta, use)
				end, function()
					page(delta)
				end, { priority = 2200 })
			end
			turn("CalendarPreviousMonth", -1, { E.KeyCode.ButtonL1, E.KeyCode.Comma })
			turn("CalendarNextMonth", 1, { E.KeyCode.ButtonR1, E.KeyCode.Period })
			if gui then
				local last: unknown = selected:peek()
				Compose.watch(function(use: Use)
					local now = use(selected)
					local entering = now ~= nil
						and cellIndex[(now :: unknown) :: Instance] ~= nil
						and last ~= nil
						and cellIndex[(last :: unknown) :: Instance] == nil
					last = now
					if entering then
						local list = cells[1]
						local target = if list then list[landing()] else nil
						if target and (target :: unknown) ~= now and target.Selectable then
							gui.SelectedObject = target
						end
					end
				end)
			end
			return panel
		end

		local chromeSpec: fieldChrome.Options = {
			label = spec.label,
			requiredMark = spec.requiredMark,
			hint = spec.hint,
			errorText = spec.errorText,
			controlSize = if overlay then spec.controlSize else nil,
			appearance = spec.appearance,
			corners = spec.corners,
		}
		local root: Frame
		local routeCell = Compose.cell(if overlay then "popover" else "inline")
		if not overlay then
			local panel = panelView(function(): string
				return "inline"
			end)
			root = chrome.wrap({
				control = "DateTimePicker",
				spec = chromeSpec,
				plate = panel,
				focus = function()
					local list = cells[1]
					if gui and list and list[landing()] then
						gui.SelectedObject = list[landing()]
					end
				end,
				enabled = enabled,
				message = typedError,
				native = rootProps,
			})
			local size = ctx.observe(root, "AbsoluteSize")
			Compose.watch(function(use: Use)
				local measured = use(size) :: Vector2
				room:set(measured.X)
			end)
		else
			local entry: TextBox? = nil
			local function calendarButton(): TextButton
				return UI.Button({
					Name = "Open",
					LayoutOrder = 2,
					icon = "calendar",
					name = "Choose a date",
					shape = "circle" :: "circle",
					appearance = "utility",
					enabled = function(use: Use)
						return interactive(use)
					end,
					onActivate = function()
						requestPresented(not presented:peek())
					end,
				})
			end
			local entryView = Compose.show(function(use: Use)
				return use(typedEntry)
			end, function()
				local box = Host.TextBox({
					Name = "Entry",
					LayoutOrder = 1,
					Text = valueText:peek(),
					PlaceholderText = spec.placeholder or "",
					ClearTextOnFocus = false,
					BackgroundTransparency = 1,
					Size = D2.new(0, 0, 0, ROW),
					TextXAlignment = E.TextXAlignment.Left,
					TextEditable = function(use: Use)
						return interactive(use)
					end,
					Selectable = function(use: Use)
						return interactive(use)
					end,
					Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
				})
				ctx.styled(box, "text")
				entry = box
				Compose.cleanup(function()
					if entry == box then
						entry = nil
					end
				end)
				Compose.watch(function(use: Use)
					box.Text = use(valueText)
					typedError:set("")
				end)
				runtime.connect(box, "FocusLost", function(_: boolean, event: InputObject?)
					if event and (event.KeyCode == E.KeyCode.Escape or event.KeyCode == E.KeyCode.ButtonB) then
						box.Text = valueText:peek()
						return
					end
					if not mayEdit() then
						box.Text = valueText:peek()
						return
					end
					if typed(box.Text) and typedError:peek() == "" then
						box.Text = valueText:peek()
					end
				end)
				return box
			end)
			local showView = Compose.show(function(use: Use)
				return not use(typedEntry)
			end, function()
				local show = UI.Button({
					Name = "Show",
					LayoutOrder = 1,
					label = function(use: Use)
						local s = use(valueText)
						return if s ~= "" then s else spec.placeholder or ""
					end,
					Size = D2.new(0, 0, 0, ROW),
					AutomaticSize = E.AutomaticSize.None,
					TextXAlignment = E.TextXAlignment.Left,
					appearance = "utility",
					enabled = function(use: Use)
						return interactive(use)
					end,
					onActivate = function()
						requestPresented(true)
					end,
					Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
				})
				tagWhile(show, "facet-secondary", function(use: Use)
					return use(valueText) == ""
				end)
				return show
			end)
			local plate = ctx.row({ entryView, showView, calendarButton() }, {
				Name = "Field",
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				BackgroundTransparency = 0,
				ctx.padding(10, 0) :: Shared.Child,
			})
			local layout = assert(plate:FindFirstChildWhichIsA("UIListLayout"))
			layout.VerticalAlignment = E.VerticalAlignment.Center
			layout.Padding = D.new(0, 4)
			ctx.styled(plate, "text-input")
			local failure = chrome.errorOf(chromeSpec, typedError)
			chrome.paint("DateTimePicker", plate, chromeSpec, function(use: Use?): boolean
				return failure(use) ~= ""
			end)
			ctx.skin(plate, "field", {
				disabled = function(use: Use)
					return not enabled(use)
				end,
			})
			root = chrome.wrap({
				control = "DateTimePicker",
				spec = chromeSpec,
				plate = plate,
				focus = function()
					local box = entry
					if box and not box:IsFocused() then
						box:CaptureFocus()
					elseif box == nil then
						requestPresented(true)
					end
				end,
				enabled = enabled,
				message = typedError,
				native = rootProps,
			})
			local anchorAvailable = surfaces.available(plate)
			local anchorSeen = false
			Compose.watch(function(use: Use)
				if use(anchorAvailable) then
					anchorSeen = true
				elseif anchorSeen and presented:peek() then
					close("anchorLost")
				end
			end)
			surfaces.attach(root, {
				surfaces.overlay(plate, presented, function()
					local layer = plate:FindFirstAncestorWhichIsA("LayerCollector")
					local extent = if layer then ctx.observe(layer, "AbsoluteSize") else Compose.cell(V2.zero)
					local origin = if layer then ctx.observe(layer, "AbsolutePosition") else Compose.cell(V2.zero)
					local position = ctx.observe(plate, "AbsolutePosition")
					local bounds = ctx.observe(plate, "AbsoluteSize")
					local tenFoot = false
					if gui then
						local ok, answer = pcall(function(): boolean
							return (gui :: GuiService):IsTenFootInterface()
						end)
						tenFoot = ok and answer == true
					end
					local route = Compose.formula(function(use: Use): string
						if tenFoot then
							return "sheet"
						end
						local offer = use(extent) :: Vector2
						return if prefers(E.PreferredInput.Touch, use)
								and offer.X > 0
								and offer.X < 600
							then "sheet"
							else "popover"
					end)
					Compose.watch(function(use: Use)
						local offer = use(extent) :: Vector2
						room:set(offer.X - 96)
						routeCell:set(use(route))
					end)
					local function routeOf(use: Use): string
						return use(route)
					end
					local panel: Frame
					local surface: ScrollingFrame
					local modal = surfaces.modal(function()
						panel = panelView(routeOf)
						surface = Host.ScrollingFrame({
							Name = "CalendarSurface",
							BorderSizePixel = 0,
							Selectable = false,
							CanvasSize = D2.fromOffset(0, 0),
							AutomaticCanvasSize = E.AutomaticSize.Y,
							ScrollingDirection = E.ScrollingDirection.Y,
							ScrollBarThickness = 4,
							panel :: Shared.Child,
						})
						ctx.styled(surface, "panel")
						surfaces.skin(surface)
						return surface
					end, function()
						close("cancel")
					end, {
						Name = "Calendar" .. "Modal",
						initialFocus = `D{landing()}`,
						backgroundTransparency = function(use: Use): number
							return if use(route) == "sheet" then 0.5 else 1
						end,
						onOutside = function()
							close("outside")
						end,
					})
					local content = ctx.observe(panel, "AbsoluteSize")
					local measured = ctx.observe(surface, "AbsoluteSize")
					local function sheet(use: Use): boolean
						return use(route) == "sheet" and not tenFoot
					end
					runtime.decorate(panel, {
						Size = function(use: Use)
							if sheet(use) then
								return D2.new(1, 0, 0, 0)
							end
							local width = if use(dual) then 2 * 7 * CELL + GAP else 7 * CELL
							return D2.fromOffset(width + 32, 0)
						end,
					})
					runtime.decorate(surface, {
						Size = function(use: Use)
							local offer = use(extent) :: Vector2
							local height = (use(content) :: Vector2).Y
							if offer.Y > 0 then
								height = math.min(height, offer.Y - 16)
							end
							if sheet(use) then
								return D2.new(1, -24, 0, height)
							end
							local width = if use(dual) then 2 * 7 * CELL + GAP else 7 * CELL
							return D2.fromOffset(width + 32, height)
						end,
						Position = function(use: Use)
							local at, size, offer, box, offset =
								use(position) :: Vector2,
								use(bounds) :: Vector2,
								use(extent) :: Vector2,
								use(measured) :: Vector2,
								use(origin) :: Vector2
							if use(route) == "sheet" then
								if tenFoot then
									return D2.fromOffset(
										math.max(8, (offer.X - box.X) / 2),
										math.max(8, (offer.Y - box.Y) / 2)
									)
								end
								return D2.fromOffset(12, math.max(8, offer.Y - box.Y - 12))
							end
							local left = at.X - offset.X
							local top = at.Y - offset.Y + size.Y + 4
							local above = at.Y - offset.Y - box.Y - 4
							if offer.Y > 0 and top + box.Y > offer.Y - 8 then
								if above >= 8 then
									top = above
								else
									top = math.max(8, offer.Y - box.Y - 8)
								end
							end
							if offer.X > 0 then
								left = math.clamp(left, 8, math.max(8, offer.X - box.X - 8))
							end
							return D2.fromOffset(left, math.max(8, top))
						end,
					})
					return modal
				end),
			})
		end
		runtime.decorate(root, {
			Attributes = {
				month = function(use: Use): string
					local m = use(viewMonth)
					return string.format("%04d-%02d", m.year, m.month)
				end,
				dual = function(use: Use): boolean
					return use(dual)
				end,
				route = function(use: Use): string
					return use(routeCell)
				end,
				presented = function(use: Use): boolean
					return use(presented)
				end,
				text = function(use: Use): string
					return use(valueText)
				end,
				typedError = function(use: Use): string
					return use(typedError)
				end,
				diagnostics = function(use: Use): number
					return #use(diagnostics)
				end,
			} :: Shared.Attributes,
		})
		root:AddTag("facet-date-time-picker")
		return root
	end

	local constructor = ctx.construct("DateTimePicker", build)
	UI.DateTimePicker = (constructor :: unknown) :: Shared.Constructor<Spec, Frame>
end
