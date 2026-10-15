--!strict
local civil = require("./civil_date")
local Shared = require("./types")
local DTP = require("./date_time_picker_types")
local InputProps = require("./input_props")
local ComposeTypes = require("../vendor/compose/core")
local Parts = require("./date_time_parts")
local Options = require("./date_time_options")

type CivilDate = DTP.CivilDate
type Range = DTP.Range
type Spec = InputProps.DateTimePickerProps
type Use = ComposeTypes.Use
type Readable<T> = ComposeTypes.Readable<T>
type Cell<T> = ComposeTypes.Cell<T>
type Formula<T> = ComposeTypes.Formula<T>
type Held = { v: CivilDate? | Range }
export type State = {
	diagnostics: Cell<{ string }>,
	value: Readable<CivilDate?>,
	range: Readable<Range>,
	minDate: Readable<CivilDate?>,
	maxDate: Readable<CivilDate?>,
	enabled: (Use?) -> boolean,
	interactive: (Use?) -> boolean,
	today: Cell<CivilDate>,
	mayEdit: () -> boolean,
	isDisabled: (CivilDate, Use?) -> boolean,
	anchorDate: () -> CivilDate,
	viewMonth: Cell<CivilDate>,
	peekMonth: () -> CivilDate,
	paneMonth: (number, Use?) -> CivilDate,
	paneGrid: (number, Use?) -> { CivilDate },
	room: Cell<number>,
	dual: Formula<boolean>,
	panes: (Use?) -> number,
	monthClosed: (CivilDate, Use?) -> boolean,
	canPage: (number, Use?) -> boolean,
	page: (number) -> boolean,
	takeSnapshot: () -> (),
	propose: (CivilDate? | Range) -> boolean,
	commit: () -> (),
	restore: () -> (),
	presented: Formula<boolean>,
	requestPresented: (boolean) -> (),
	close: (DTP.DismissReason) -> (),
	choose: (CivilDate) -> (),
	typedError: Cell<string>,
	valueText: Formula<string>,
	longName: (CivilDate) -> string,
	preferred: Cell<Enum.PreferredInput> | Cell<unknown>,
	prefers: (Enum.PreferredInput, Use) -> boolean,
	typedEntry: Formula<boolean>,
	selected: Readable<GuiObject?>,
}

local CELL, GAP = Parts.CELL, Parts.GAP
local span, monthOf, sameRange = Parts.span, Parts.monthOf, Parts.sameRange

return function(ctx: Shared.Context, parts: Parts.Parts, spec: Spec, options: Options.Options): State
	local Compose, read = ctx.Compose, ctx.read
	local E = ctx.types.Enum
	local gui, input = parts.gui, parts.input
	local isRange, withTime, draft, overlay = options.isRange, options.withTime, options.draft, options.overlay
	local months, clock = options.months, options.clock

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
		return enabled(use) and read(spec.readOnly, use) ~= true and options.hasProposer
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
	local monthGrids: { Readable<{ CivilDate }> } = {}
	for k = 1, if isRange then 2 else 1 do
		monthGrids[k] = Compose.formula(function(use: Use): { CivilDate }
			local m = paneMonth(k, use)
			return civil.monthGrid(m.year, m.month, options.weekStart)
		end)
	end
	local function paneGrid(k: number, use: Use?): { CivilDate }
		local grid = monthGrids[k]
		return if use then use(grid) else grid:peek()
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
		local last: CivilDate = { year = m.year, month = m.month, day = civil.daysIn(m.year, m.month) }
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
				assert(options.proposeRange)(next :: Range)
			else
				assert(options.proposeSingle)(next :: CivilDate?)
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
			next = span(day, nil)
		elseif civil.compare(day, r.start) < 0 then
			next = span(day, r.start)
		else
			next = span(r.start, day)
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
		return if spec.format ~= nil then spec.format(v) else civil.format(v, options.locale)
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
		then ctx.observe.PreferredInput(input)
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
		then ctx.observe.SelectedObject(gui)
		else Compose.cell(nil :: GuiObject?)

	return {
		diagnostics = diagnostics,
		value = value,
		range = range,
		minDate = minDate,
		maxDate = maxDate,
		enabled = enabled,
		interactive = interactive,
		today = today,
		mayEdit = mayEdit,
		isDisabled = isDisabled,
		anchorDate = anchorDate,
		viewMonth = viewMonth,
		peekMonth = peekMonth,
		paneMonth = paneMonth,
		paneGrid = paneGrid,
		room = room,
		dual = dual,
		panes = panes,
		monthClosed = monthClosed,
		canPage = canPage,
		page = page,
		takeSnapshot = takeSnapshot,
		propose = propose,
		commit = commit,
		restore = restore,
		presented = presented,
		requestPresented = requestPresented,
		close = close,
		choose = choose,
		typedError = typedError,
		valueText = valueText,
		longName = longName,
		preferred = preferred,
		prefers = prefers,
		typedEntry = typedEntry,
		selected = selected,
	}
end
