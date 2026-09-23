--!strict
--[[ DateTimePicker — a date field that opens a calendar, or the calendar inline
	(phase5 P5b, D7).

	CIVIL VALUES, CONTROLLED. `value` is the caller's `{ year, month, day }` (with
	`hour`/`minute` when `time = true`), or with `selection = "range"` the caller's
	`range = { start?, finish? }` — wall-clock facts in no zone (`civil_date`). A
	pick proposes `onChange` / `onRangeChange`, and the calendar repaints only from
	what the caller then holds. ONE COMMIT MODEL, every route and input: without
	`draft`, every change commits as it happens (a pick, a time step, a typed
	date; `onRangeCommit` once both ends are set) and B, Escape, an outside tap or
	a sheet's Close only close. With `draft = true` nothing commits until Apply
	and every other close restores the open-time value. "Today" comes from the
	injected `clock`; this control reads no clock of its own.

	THE CLOSED FORM is field chrome: the value's words — an editable field when a
	keyboard or pointer is live (a refused text stays visible with its error and
	commits nothing), a button that opens the calendar otherwise — and a calendar
	Button. It opens through `UI.Popover` (anchored; a hug sheet with Done on
	compact touch; a centred sheet at ten feet) and owns its open state unless the
	caller binds `isPresented`.

	THE CALENDAR: a header (previous, month menu, year menu, next), six weeks of
	day cells keyed by POSITION, so paging keeps the ring on the same weekday, a
	second consecutive month when the offered width fits two, a time section, the
	range presets and the draft actions. Pane two is always pane one + 1 month.
	Disabled days stay focusable and inert (struck through); a neighbouring
	month's grey days are shown and tappable but never a focus stop. The grid is
	ONE Tab stop: the arrows walk the days (±1 across a row's end, ±7 across the
	shown months), ←/→ paging when the day is not shown; ↓ past the last shown
	month's last row and ↑ past the first month's first row leave the grid. Its
	cells are adjust targets WITHOUT an axis, so L1/R1 (named by a hint while a
	pad is live) and Comma/Period page the month while the arrows stay with
	navigation. Paging stops at a month wholly outside `min`/`max`. ]]
local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")
local ownedFormula = require("../core/owned_formula")
local contribution = require("../input/contribution")
local guard = require("../spec_guard")
local selection = require("../selection_model")
local surfaceEnv = require("../env/surface_env")
local themeSnapshot = require("../themes/snapshot")
local fieldChrome = require("./field_chrome")
local labelControl = require("./label")
local civil = require("./civil_date")

type CivilDate = civil.CivilDate
type Range = civil.Range

local date_time_picker = {}

local specTypes = require("../spec_types/date_time_picker")
export type Spec = specTypes.Spec

local KEYS = guard.keySet({
	"appearance",
	"clock",
	"controlSize",
	"corners",
	"draft",
	"enabled",
	"env",
	"errorText",
	"format",
	"hint",
	"hourCycle",
	"id",
	"isDateDisabled",
	"isPresented",
	"label",
	"locale",
	"max",
	"min",
	"minuteStep",
	"onChange",
	"onCommit",
	"onDismiss",
	"onPresentedChange",
	"onRangeChange",
	"onRangeCommit",
	"placeholder",
	"presets",
	"range",
	"readOnly",
	"referenceDate",
	"requiredMark",
	"selection",
	"style",
	"time",
	"value",
	"weekStart",
})
local LOCALE_KEYS = guard.keySet({ "months", "weekdays", "order", "separator", "hourCycle" })
local PRESET_KEYS = guard.keySet({ "id", "label", "range" })
local ORDERS = { mdy = true, dmy = true, ymd = true }
local DUMP_SCHEMA = "facet-date_time_picker-dump/1"
local CELLS = 42
-- a year menu spans this many years either side of where the calendar opens,
-- widened to reach the bounds
local YEAR_SPAN = 100

local function build(Facet: any, core: any, spec: Spec, owner: any)
	guard.assertKnownKeys("UI.DateTimePicker", spec, KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "DateTimePicker"
	local where = `UI.DateTimePicker('{id}')`
	local function refuse(message: string)
		error(`Facet {where}: {message}`, 0)
	end

	-- ===== the contract, refused at construction ==========================
	local mode = spec.selection or "single"
	if mode ~= "single" and mode ~= "range" then
		refuse('`selection` is "single" or "range".')
	end
	local isRange = mode == "range"
	if isRange and (spec.value ~= nil or spec.onChange ~= nil or spec.onCommit ~= nil) then
		refuse("a range picker uses `range` / `onRangeChange` / `onRangeCommit`, not the single keys.")
	end
	if
		not isRange
		and (spec.range ~= nil or spec.onRangeChange ~= nil or spec.onRangeCommit ~= nil or spec.presets ~= nil)
	then
		refuse('`range`, `onRangeChange`, `onRangeCommit` and `presets` belong to `selection = "range"`.')
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
		if (spec :: any)[key] ~= nil and type((spec :: any)[key]) ~= "function" then
			refuse(`\`{key}\` is a function.`)
		end
	end
	for _, key in { "time", "draft" } do
		if (spec :: any)[key] ~= nil and type((spec :: any)[key]) ~= "boolean" then
			refuse(`\`{key}\` is true or false.`)
		end
	end
	local withTime = spec.time == true
	if withTime and isRange then
		refuse("`time` belongs to a single date; a range is whole days.")
	end
	local draft = spec.draft == true
	local readOnlyNow = selection.read(spec.readOnly)
	if readOnlyNow ~= nil and type(readOnlyNow) ~= "boolean" then
		refuse("`readOnly` is a boolean or a bound boolean.")
	end
	local proposer: any = if isRange then spec.onRangeChange else spec.onChange
	if proposer == nil and readOnlyNow ~= true then
		refuse(
			`an interactive picker needs \`{if isRange then "onRangeChange" else "onChange"}\`; only a readOnly one may omit it.`
		)
	end
	local minuteStep = spec.minuteStep or 5
	if type(minuteStep) ~= "number" or minuteStep < 1 or minuteStep % 1 ~= 0 or 60 % minuteStep ~= 0 then
		refuse("`minuteStep` is a whole number of minutes that divides 60.")
	end
	local weekStart = spec.weekStart or 1
	if type(weekStart) ~= "number" or weekStart % 1 ~= 0 or weekStart < 1 or weekStart > 7 then
		refuse("`weekStart` is 1 (Sunday) … 7 (Saturday).")
	end
	local locale: any = table.clone(civil.ENGLISH)
	if spec.locale ~= nil then
		if type(spec.locale) ~= "table" then
			refuse("`locale` is a table: { months?, weekdays?, order?, separator?, hourCycle? }.")
		end
		guard.assertKnownKeys("UI.DateTimePicker", spec.locale, LOCALE_KEYS, "locale")
		for key, v in spec.locale :: any do
			locale[key] = v
		end
		if type(locale.months) ~= "table" or #locale.months ~= 12 then
			refuse("`locale.months` names the twelve months, January first.")
		end
		if type(locale.weekdays) ~= "table" or #locale.weekdays ~= 7 then
			refuse("`locale.weekdays` names the seven days, Sunday first.")
		end
		if not ORDERS[locale.order] then
			refuse('`locale.order` is "mdy", "dmy" or "ymd".')
		end
	end
	local hourCycle = spec.hourCycle or locale.hourCycle or 12
	if hourCycle ~= 12 and hourCycle ~= 24 then
		refuse("`hourCycle` is 12 or 24.")
	end
	locale.hourCycle = hourCycle
	local style = spec.style or "automatic"
	if style ~= "automatic" and style ~= "inline" then
		refuse('`style` is "automatic" (a field that opens the calendar) or "inline".')
	end
	if style == "inline" and (spec.isPresented ~= nil or spec.onPresentedChange ~= nil) then
		refuse("an inline calendar is always shown: `isPresented`/`onPresentedChange` belong to the field.")
	end
	if spec.placeholder ~= nil and type(spec.placeholder) ~= "string" then
		refuse("`placeholder` is a string.")
	end
	local function checkDate(key: string, v: any, time: boolean?)
		if v ~= nil then
			local why = civil.problem(v, time)
			if why ~= nil then
				refuse(`\`{key}\` {why}.`)
			end
		end
	end
	if isRange then
		local r = selection.read(spec.range)
		if type(r) ~= "table" then
			refuse("`range` is { start?, finish? } (or a bound one).")
		end
		checkDate("range.start", r.start)
		checkDate("range.finish", r.finish)
	else
		checkDate("value", selection.read(spec.value), withTime)
	end
	checkDate("min", selection.read(spec.min))
	checkDate("max", selection.read(spec.max))
	checkDate("referenceDate", selection.read(spec.referenceDate))
	local presets: { any } = {}
	if spec.presets ~= nil then
		if type(spec.presets) ~= "table" then
			refuse("`presets` is a list of { id, label, range = function(today) }.")
		end
		local seen: { [string]: boolean } = {}
		for i, p in spec.presets :: { any } do
			if
				type(p) ~= "table"
				or type(p.id) ~= "string"
				or type(p.label) ~= "string"
				or type(p.range) ~= "function"
			then
				refuse(`\`presets[{i}]\` is \{ id = string, label = string, range = function(today) }.`)
			end
			guard.assertKnownKeys("UI.DateTimePicker", p, PRESET_KEYS, `presets[{i}]`)
			if seen[p.id] then
				refuse(`\`presets\` repeats the id '{p.id}'.`)
			end
			seen[p.id] = true
			table.insert(presets, p)
		end
	end
	fieldChrome.assertSpec("UI.DateTimePicker", spec)
	local env = if spec.env ~= nil then spec.env else surfaceEnv.find(core)
	local clock: () -> CivilDate = spec.clock or civil.systemClock()

	-- ===== legal values only ==============================================
	local diagnostics: { string } = {}
	local function legal(key: string, source: any, ok: (any) -> boolean, what: string): any
		local last = selection.read(source)
		local refused = false
		return ownedFormula(owner, function(use)
			local v = selection.read(source, use)
			if ok(v) then
				last, refused = v, false
			elseif not refused then
				refused = true
				selection.note(diagnostics, `Facet {where}: \`{key}\` {what} — keeping the last legal value`)
			end
			return last
		end)
	end
	local function optionalDate(v: any): boolean
		return v == nil or civil.problem(v) == nil
	end
	local value = legal("value", spec.value, function(v)
		return v == nil or civil.problem(v, withTime) == nil
	end, "is a calendar date")
	local range = legal("range", spec.range, function(r)
		return type(r) == "table"
			and optionalDate(r.start)
			and optionalDate(r.finish)
			and not (r.start ~= nil and r.finish ~= nil and civil.compare(r.start, r.finish) > 0)
	end, "is { start?, finish? } with start on or before finish")
	local minDate = legal("min", spec.min, optionalDate, "is a calendar date")
	local maxDate = legal("max", spec.max, optionalDate, "is a calendar date")
	local referenceDate = legal("referenceDate", spec.referenceDate, optionalDate, "is a calendar date")
	local enabled = ownedFormula(owner, function(use)
		return selection.read(spec.enabled, use) ~= false
	end)
	local readOnly = legal("readOnly", spec.readOnly, function(v)
		return (v == nil or type(v) == "boolean") and (v == true or proposer ~= nil)
	end, "cannot turn off without a change callback")
	local interactive = ownedFormula(owner, function(use)
		return use(enabled) and use(readOnly) ~= true
	end)
	-- the day part of the clock; its time part places the touch time list
	local today = Compose.cell(civil.dateOf(clock()))

	local disposed = false
	owner.own(function()
		disposed = true
	end)
	local function mayEdit(): boolean
		return not disposed and interactive:peek()
	end
	local function follow(source: any, fn: (any) -> ())
		(Compose.currentOwner() or owner).watchStatic(source, fn)
	end

	-- a day nobody may choose: outside the bounds, or the caller's own rule
	local function isDisabled(d: CivilDate, use: any?): boolean
		local lo = if use then use(minDate) else minDate:peek()
		local hi = if use then use(maxDate) else maxDate:peek()
		if not civil.within(d, lo, hi) then
			return true
		end
		return spec.isDateDisabled ~= nil and (spec.isDateDisabled :: any)(civil.dateOf(d)) == true
	end

	-- ===== the month on screen: pane two is always pane one + 1 ============
	local function monthOf(d: CivilDate): CivilDate
		return { year = d.year, month = d.month, day = 1 }
	end
	local function anchorDate(): CivilDate
		local v: any = if isRange then range:peek().start else value:peek()
		return v or referenceDate:peek() or today:peek()
	end
	local viewMonth = Compose.cell(monthOf(anchorDate()), civil.same)
	local function paneMonth(use: any, k: number): CivilDate
		return civil.addMonths(use(viewMonth), k - 1)
	end
	-- whether a second month shows (the offered width fits two); set below
	local dualNow: any = nil
	-- a month nobody may land in: wholly before `min` or wholly after `max`
	local function monthClosed(m: CivilDate, use: any?): boolean
		local lo = if use then use(minDate) else minDate:peek()
		local hi = if use then use(maxDate) else maxDate:peek()
		local last = { year = m.year, month = m.month, day = civil.daysIn(m.year, m.month) }
		return (lo ~= nil and civil.compare(last, lo) < 0) or (hi ~= nil and civil.compare(monthOf(m), hi) > 0)
	end
	-- paging stops before the month it would bring into view is closed
	local function canPage(delta: number, use: any?): boolean
		local read = use or function(r: any)
			return r:peek()
		end
		local panes = if dualNow ~= nil and read(dualNow) then 2 else 1
		local shown = civil.addMonths(read(viewMonth), if delta > 0 then delta + panes - 1 else delta)
		return not monthClosed(shown, use)
	end
	local function page(delta: number): boolean
		if not canPage(delta) then
			return false
		end
		viewMonth:set(civil.addMonths(viewMonth:peek(), delta))
		return true
	end

	-- ===== proposals, commits and the Cancel snapshot =====================
	local proposing = false
	local snapshot: any = nil
	local function current(): any
		return if isRange then range:peek() else value:peek()
	end
	local function takeSnapshot()
		snapshot = { v = current() }
	end
	takeSnapshot()
	follow(if isRange then range else value, function()
		if not proposing then
			takeSnapshot()
		end
	end)
	local function sameRange(a: any, b: any): boolean
		return civil.same(a.start, b.start) and civil.same(a.finish, b.finish)
	end
	local function propose(next: any): boolean
		if not mayEdit() then
			return false
		end
		proposing = true
		local ok, err = pcall(proposer, next)
		proposing = false
		if not ok then
			error(err, 0)
		end
		local now = current()
		return if isRange then sameRange(now, next) else civil.same(now, next)
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
		if disposed or snapshot == nil or not mayEdit() then
			return
		end
		local saved = snapshot.v
		local same = if isRange then sameRange(current(), saved) else civil.same(current(), saved)
		if not same then
			proposing = true
			pcall(proposer, saved)
			proposing = false
		end
	end

	-- ===== presentation =====================================================
	local openCell = Compose.cell(false)
	local presented = if spec.isPresented ~= nil
		then ownedFormula(owner, function(use)
			return selection.read(spec.isPresented, use) == true
		end)
		else openCell
	local overlay = style ~= "inline"
	local closeWhy: string? = nil
	local asked = false
	local popoverApi: any = nil
	local function requestPresented(next: boolean)
		if next and (not interactive:peek() or disposed) then
			return
		end
		if spec.onPresentedChange ~= nil then
			spec.onPresentedChange(next)
		elseif spec.isPresented == nil then
			openCell:set(next)
		end
	end
	local function close(why: string)
		closeWhy = why
		requestPresented(false)
	end
	follow(presented, function(on: boolean)
		if on then
			takeSnapshot()
			today:set(civil.dateOf(clock()))
			viewMonth:set(monthOf(anchorDate()))
		end
	end)

	-- ===== choosing =========================================================
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
			if day.month ~= viewMonth:peek().month or day.year ~= viewMonth:peek().year then
				-- a pick in a neighbouring month's grey days turns to that month
				if
					not (
						civil.same(monthOf(day), civil.addMonths(viewMonth:peek(), 1))
						and dualNow ~= nil
						and dualNow:peek()
					)
				then
					viewMonth:set(monthOf(day))
				end
			end
			if not draft then
				commit()
				if not withTime and overlay then
					close("activate")
				end
			end
			return
		end
		local r = range:peek()
		local next: Range
		if r.start == nil or r.finish ~= nil then
			next = { start = day, finish = nil }
		elseif civil.compare(day, r.start :: CivilDate) < 0 then
			next = { start = day, finish = r.start }
		else
			next = { start = r.start, finish = day }
		end
		if propose(next) and next.finish ~= nil and not draft then
			commit()
			if overlay then
				close("activate")
			end
		end
	end
	-- ===== the words a value is written in ================================
	local typedError = Compose.cell("")
	local function words(v: any): string
		if v == nil then
			return ""
		end
		return if spec.format ~= nil then (spec.format :: any)(v) else civil.format(v, locale)
	end
	local valueText = ownedFormula(owner, function(use)
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
		return `{locale.months[d.month]} {d.day}, {d.year}`
	end
	local typedEntry = ownedFormula(owner, function(use)
		if spec.format ~= nil or env == nil then
			return false
		end
		local classes = use(env:get("interactionClasses"))
		return type(classes) == "table" and (classes.keyboard == true or classes.pointer == true)
	end)

	-- ===== the calendar =====================================================
	local focusedPath = Compose.cell(nil :: string?)
	local graphRef: any = nil
	local cellPaths: { [number]: { string } } = {}
	local measured = Compose.cell(0)
	local function metric(use: any, path: string, fallback: number): number
		local metrics = if env ~= nil then use(env:get("themeMetrics")) else themeSnapshot.neutral()
		return themeSnapshot.resolveNumber(metrics or themeSnapshot.neutral(), path) or fallback
	end
	local gridWidth = function(use: any): number
		return 7 * metric(use, "targetSizes.minimum", 44)
	end
	-- a single date shows one month (the reference's own form); a range shows two
	-- wherever they fit, so a span can cross the month boundary in view
	dualNow = ownedFormula(owner, function(use)
		if not isRange then
			return false
		end
		local need = 2 * gridWidth(use) + metric(use, "l", 24)
		if not overlay then
			return use(measured) >= need
		end
		local view = if env ~= nil then use(env:get("viewportRect")) else nil
		local room = if type(view) == "table" then view.w - 6 * metric(use, "m", 16) else 0
		return room >= need
	end)

	local function dayCell(k: number, i: number): any
		local date = Compose.formula(function(use)
			local m = paneMonth(use, k)
			return civil.monthGrid(m.year, m.month, weekStart)[i]
		end, civil.same)
		local outside = Compose.formula(function(use)
			return use(date).month ~= paneMonth(use, k).month
		end)
		local disabled = Compose.formula(function(use)
			use(minDate)
			use(maxDate)
			return isDisabled(use(date), use)
		end)
		local chosen = Compose.formula(function(use)
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
		local banded = Compose.formula(function(use)
			if not isRange then
				return false
			end
			local r = use(range)
			local d = use(date)
			return not use(outside) and r.start ~= nil and r.finish ~= nil and civil.within(d, r.start, r.finish)
		end)
		-- THE BAND IS ONE PILL across the span: each cell paints the halves the span
		-- crosses (none past an endpoint), and a row's first or last column rounds
		-- its end with a disc-sized cap, so the pill wraps at the week's edge
		local column = (i - 1) % 7 + 1
		local function edge(side: string): any
			return Compose.formula(function(use)
				if not use(banded) then
					return true
				end
				local r = use(range)
				local d = use(date)
				local stop = if side == "leading" then r.start else r.finish
				return civil.compare(d, stop) == 0 or column == (if side == "leading" then 1 else 7)
			end)
		end
		local capped = Compose.formula(function(use)
			if not use(banded) or not use(edge("leading")) and not use(edge("trailing")) then
				return false
			end
			return not use(chosen)
		end)
		local isToday = Compose.formula(function(use)
			return civil.compare(use(date), use(today)) == 0
		end)
		local function hiddenUnless(flag: any): any
			return Compose.formula(function(use)
				return not use(flag)
			end)
		end
		local disc = { type = "fixed", px = "controlSizes.compact.height" }
		return UI.Button({
			id = `D{i}`,
			label = Compose.formula(function(use)
				local d = use(date)
				return longName(d) .. (if use(disabled) then ", unavailable" else "")
			end),
			surface = "plain",
			padding = 0,
			width = { type = "fixed", px = "targetSizes.minimum" },
			height = { type = "fixed", px = "targetSizes.minimum" },
			enabled = interactive,
			-- a neighbouring month's day is that month's: tappable, never a stop
			focusable = Compose.formula(function(use)
				return not use(outside)
			end),
			onActivate = function()
				choose(date:peek())
			end,
			children = {
				UI.ZStack({
					id = "Layers",
					width = UI.fill(),
					height = UI.fill(),
					alignH = "center",
					alignV = "center",
					children = {
						UI.HStack({
							id = "Band",
							width = UI.fill(),
							height = disc,
							gap = 0,
							hidden = hiddenUnless(banded),
							children = {
								UI.Box({
									id = "Leading",
									width = UI.fill(),
									height = UI.fill(),
									tint = { role = "controlSelected", blend = 1 },
									hidden = edge("leading"),
								}),
								UI.Box({
									id = "Trailing",
									width = UI.fill(),
									height = UI.fill(),
									tint = { role = "controlSelected", blend = 1 },
									hidden = edge("trailing"),
								}),
							},
						}),
						UI.corners(
							UI.Box({
								id = "Cap",
								width = disc,
								height = disc,
								tint = { role = "controlSelected", blend = 1 },
								hidden = hiddenUnless(capped),
							}),
							999
						),
						UI.corners(
							UI.Box({
								id = "Disc",
								width = disc,
								height = disc,
								-- a range's ends are the content colour (light on a dark
								-- theme) over the band; a single day is the accent
								tint = { role = if isRange then "content" else "accent", blend = 1 },
								hidden = hiddenUnless(chosen),
							}),
							999
						),
						UI.stroke(
							UI.corners(
								UI.Box({ id = "Today", width = disc, height = disc, hidden = hiddenUnless(isToday) }),
								999
							),
							{ color = "accent", thickness = "hairline" }
						),
						UI.Text({
							id = "Day",
							text = Compose.formula(function(use)
								return tostring(use(date).day)
							end),
							-- a day of this month is strong; a neighbour's is dim
							textSize = Compose.formula(function(use)
								return if use(outside) then "body" else "strong"
							end),
							textAlign = "center",
							tint = Compose.formula(function(use)
								return if use(chosen)
									then { role = if isRange then "surface" else "onAccent", blend = 1 }
									elseif use(outside) or use(disabled) then {
										role = "contentSecondary",
										blend = 1,
									}
									else nil
							end),
						}),
						UI.Path({
							id = "Strike",
							points = {
								{ x = 0.25, y = 0.5, inX = 0, inY = 0, outX = 0, outY = 0 },
								{ x = 0.75, y = 0.5, inX = 0, inY = 0, outX = 0, outY = 0 },
							},
							width = UI.fill(),
							height = UI.fill(),
							thickness = "strokes.hairline",
							tint = { role = "contentSecondary", blend = 1 },
							hidden = hiddenUnless(disabled),
						}),
					},
				}),
			},
		})
	end

	-- the landing day (on open, and wherever focus enters the grid): the chosen
	-- day, else today, else the first enabled day of the first month shown
	local function landing(): number
		local m = viewMonth:peek()
		local grid = civil.monthGrid(m.year, m.month, weekStart)
		local want: any = if isRange then range:peek().start else value:peek()
		for _, candidate in { want, today:peek() } do
			if candidate ~= nil then
				for i, d in grid do
					if civil.compare(d, candidate) == 0 and d.month == m.month and not isDisabled(d) then
						return i
					end
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

	local function pane(k: number): any
		local names: { any } = {}
		for c = 0, 6 do
			local dayIndex = (weekStart - 1 + c) % 7 + 1
			table.insert(
				names,
				UI.Text({
					id = `W{c + 1}`,
					text = locale.weekdays[dayIndex],
					textSize = "caption",
					textAlign = "center",
					role = "secondary",
					lineLimit = 1,
					width = { type = "fixed", px = "targetSizes.minimum" },
				})
			)
		end
		-- six declared week rows: navigation reads the rows the eye sees, even
		-- where grey days (no stop) leave a row short
		local weeks: { any } = {}
		for row = 1, CELLS // 7 do
			local cells: { any } = {}
			for c = 1, 7 do
				table.insert(cells, dayCell(k, (row - 1) * 7 + c))
			end
			table.insert(weeks, UI.GridRow({ id = `R{row}`, children = cells }))
		end
		-- seven cell-wide columns, never stretched across a wider pane
		local days = UI.Grid({
			id = "Days",
			gap = 0,
			width = Compose.formula(function(use)
				return { type = "fixed", px = gridWidth(use) }
			end),
			children = weeks,
		})
		return UI.VStack({
			id = `Pane{k}`,
			gap = "xs",
			children = {
				-- a pane names its month only beside a second one (and then takes room)
				UI.When({
					id = "Titled",
					condition = dualNow,
					thenView = function()
						return UI.Text({
							id = "Title",
							textSize = "label",
							text = Compose.formula(function(use)
								local m = paneMonth(use, k)
								return `{locale.months[m.month]} {m.year}`
							end),
						})
					end,
				}),
				UI.HStack({ id = "Weekdays", gap = 0, children = names }),
				-- the landing day takes focus when the calendar appears (pane one only)
				if k == 1 then UI.focusSection(days, { focusOnAppear = `D{landing()}` }) else days,
			},
		})
	end

	-- a header menu: the month's (or year's) plain words and a chevron, as a
	-- calendar header reads, opening a menu of every choice
	local function menu(menuId: string, options: any, get: (CivilDate) -> number, set: (number) -> ()): any
		local items: { any } = {}
		for _, option in options do
			table.insert(items, {
				id = tostring(option.value),
				label = option.label,
				onSelect = function()
					set(option.value)
				end,
			})
		end
		local words_ = Compose.formula(function(use)
			local now = get(use(viewMonth))
			for _, option in options do
				if option.value == now then
					return option.label
				end
			end
			return tostring(now)
		end)
		local record = require("./menu").build(Facet, core, {
			id = menuId,
			trigger = UI.Button({
				id = menuId,
				label = words_,
				surface = "plain",
				-- plain words need no plate's inset: month and year share one line
				padding = { left = "xs", right = "xs" },
				height = { type = "minMax", min = "targetSizes.minimum" },
				enabled = interactive,
				children = {
					UI.HStack({
						id = "Row",
						gap = "xs",
						align = "center",
						children = {
							UI.Text({ id = "Words", text = words_, lineLimit = 1 }),
							labelControl.icon(UI, "chevron.down", { id = "Chevron", size = "iconSizes.small" }),
						},
					}),
				},
			}),
			items = items,
			env = spec.env,
		})
		Compose.cleanup(function()
			record.dispose()
		end)
		return record.blueprint
	end

	local function header(): any
		local months = {}
		for m = 1, 12 do
			table.insert(months, { value = m, label = locale.months[m] })
		end
		local centre = viewMonth:peek().year
		local lo, hi = centre - YEAR_SPAN, centre + YEAR_SPAN
		if minDate:peek() ~= nil then
			lo = math.min(lo, minDate:peek().year)
		end
		if maxDate:peek() ~= nil then
			hi = math.max(hi, maxDate:peek().year)
		end
		local years = {}
		for y = lo, hi do
			table.insert(years, { value = y, label = tostring(y) })
		end
		local function arrow(arrowId: string, icon: string, name: string, delta: number): any
			return UI.Button({
				id = arrowId,
				icon = icon,
				label = name,
				shape = "circle",
				-- a bare chevron beside the month words
				surface = "plain",
				enabled = Compose.formula(function(use)
					return use(interactive) and canPage(delta, use)
				end),
				onActivate = function()
					page(delta)
				end,
			})
		end
		return UI.HStack({
			id = "Header",
			width = UI.fill(),
			gap = "xs",
			align = "center",
			children = {
				arrow("Previous", "chevron.leading", "Previous month", -1),
				-- a long month name wraps the year onto its own line rather than clip
				UI.HStack({
					id = "Choose",
					gap = "xs",
					wrap = true,
					width = UI.fill(),
					shrinkWeight = 1,
					children = {
						menu("Month", months, function(m)
							return m.month
						end, function(v)
							viewMonth:set({ year = viewMonth:peek().year, month = v, day = 1 })
						end),
						menu("Year", years, function(m)
							return m.year
						end, function(v)
							viewMonth:set({ year = v, month = viewMonth:peek().month, day = 1 })
						end),
					},
				}),
				arrow("Next", "chevron.trailing", "Next month", 1),
			},
		})
	end

	-- hour and minute: stepper fields everywhere, a time list on touch
	local function timeSection(): any
		-- the value a time edit starts from: the held one, or the anchor day at 0:00
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
			fieldId: string,
			words_: string,
			lo: number,
			hi: number,
			step: number,
			get: (CivilDate) -> number,
			with: (CivilDate, number) -> CivilDate
		): any
			local text = Compose.cell("")
			local number = Compose.cell(lo)
			local function resync()
				local v = value:peek()
				local n = if v ~= nil and v.hour ~= nil then get(v) else lo
				number:set(n)
				text:set(if v ~= nil then string.format("%02d", n) else "")
			end
			resync()
			follow(value, resync)
			local built = require("./text_input").buildNumber(Facet, core, {
				id = fieldId,
				label = words_,
				value = text,
				numericValue = number,
				min = lo,
				max = hi,
				step = step,
				precision = 0,
				stepButtons = true,
				enabled = interactive,
				env = spec.env,
				format = function(n: number): string
					return string.format("%02d", n)
				end,
				onCommit = function(n: any)
					if not propose(with(base(), n)) then
						resync()
					elseif not draft then
						commit()
					end
				end,
			})
			Compose.cleanup(function()
				built.dispose()
			end)
			return built.blueprint
		end
		local function withHour(d: CivilDate, h: number): CivilDate
			local out = table.clone(d)
			local pm = (d.hour :: number) >= 12
			out.hour = if hourCycle == 12 then (h % 12) + (if pm then 12 else 0) else h
			return out
		end
		local function withMinute(d: CivilDate, m: number): CivilDate
			local out = table.clone(d)
			out.minute = m
			return out
		end
		local children: { any } = {
			field("Hour", "Hour", if hourCycle == 12 then 1 else 0, if hourCycle == 12 then 12 else 23, 1, function(v)
				local h = v.hour :: number
				return if hourCycle == 12 then (if h % 12 == 0 then 12 else h % 12) else h
			end, withHour),
			-- the steps stay on the minute grid: the top step is the last one before 60
			field("Minute", "Minute", 0, 60 - minuteStep, minuteStep, function(v)
				return v.minute :: number
			end, withMinute),
		}
		if hourCycle == 12 then
			local half = Compose.cell("AM")
			follow(value, function(v: any)
				half:set(if v ~= nil and v.hour ~= nil and v.hour >= 12 then "PM" else "AM")
			end)
			local built = require("./picker").build(Facet, core, {
				id = "Half",
				options = { { value = "AM", label = "AM" }, { value = "PM", label = "PM" } },
				selected = half,
				style = "segmented",
				enabled = interactive,
				env = spec.env,
				onChange = function(word: any)
					local v = value:peek()
					if v == nil or v.hour == nil then
						return
					end
					local next = table.clone(v)
					next.hour = v.hour % 12 + (if word == "PM" then 12 else 0)
					if not propose(next) then
						half:set(if v.hour >= 12 then "PM" else "AM")
					elseif not draft then
						commit()
					end
				end,
			})
			Compose.cleanup(function()
				built.dispose()
			end)
			table.insert(children, built.blueprint)
		end
		local times = {}
		for minutes = 0, 24 * 60 - 1, minuteStep do
			table.insert(times, { hour = minutes // 60, minute = minutes % 60 })
		end
		local list = UI.When({
			id = "TouchTimes",
			condition = Compose.formula(function(use)
				local classes = if env ~= nil then use(env:get("interactionClasses")) else nil
				return type(classes) == "table" and classes.touch == true
			end),
			thenView = function()
				-- it opens at the held time, else now, else midnight
				local at: any = value:peek()
				if at == nil or at.hour == nil then
					at = clock()
				end
				local first = if at.hour ~= nil then (at.hour * 60 + at.minute) // minuteStep else 0
				local built = require("./virtual_list").build(Facet, core, {
					id = "Times",
					scrollNavigation = { position = Compose.cell(first * 44) },
					rows = Compose.formula(function()
						return times
					end),
					key = function(t: any): string
						return `{t.hour}:{t.minute}`
					end,
					itemExtent = 44,
					viewportExtent = 4 * 44,
					snap = "item",
					env = spec.env,
					-- the list is fixed, so a row's time is the item it was built for
					cell = function(t: any): any
						return UI.Button({
							id = "Time",
							label = civil.formatTime(
								{ year = 2000, month = 1, day = 1, hour = t.hour, minute = t.minute },
								hourCycle
							),
							width = UI.fill(),
							enabled = interactive,
							selected = Compose.formula(function(use)
								local v = use(value)
								return v ~= nil and v.hour == t.hour and v.minute == t.minute
							end),
							onActivate = function()
								local base = value:peek() or civil.dateOf(anchorDate())
								local next = civil.dateOf(base)
								next.hour, next.minute = t.hour, t.minute
								if propose(next) and not draft then
									commit()
								end
							end,
						})
					end,
				})
				Compose.cleanup(function()
					built.dispose()
				end)
				return built.blueprint
			end,
		})
		return UI.VStack({
			id = "Time",
			width = UI.fill(),
			gap = "s",
			children = {
				UI.HStack({
					id = "Fields",
					gap = "s",
					align = "end",
					wrap = true,
					width = UI.fill(),
					children = children,
				}),
				list,
			},
		})
	end

	local function presetRow(): any
		local chips: { any } = {}
		for _, p in presets do
			local clamped = Compose.formula(function(use)
				local raw = p.range(use(today))
				return civil.clampRange(raw, use(minDate), use(maxDate))
			end)
			local on = Compose.cell(false)
			follow(
				Compose.formula(function(use)
					local c = use(clamped)
					return c ~= nil and c.start ~= nil and sameRange(use(range), c)
				end),
				function(match: boolean)
					on:set(match)
				end
			)
			local chip = require("./chip").build(Facet, core, {
				id = `Preset-{p.id}`,
				label = p.label,
				controlSize = "compact",
				selected = on,
				enabled = Compose.formula(function(use)
					return use(clamped) ~= nil and use(interactive)
				end),
				onToggle = function()
					local c = clamped:peek()
					on:set(c ~= nil and sameRange(range:peek(), c))
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
			})
			Compose.cleanup(function()
				chip.dispose()
			end)
			table.insert(chips, chip.blueprint)
		end
		return UI.HStack({ id = "Presets", gap = "xs", wrap = true, width = UI.fill(), children = chips })
	end

	local function panelView(): any
		local children: { any } = {
			header(),
			UI.Divider({ id = "HeaderRule" }),
			UI.HStack({
				id = "Panes",
				gap = "l",
				align = "start",
				children = {
					pane(1),
					UI.When({
						id = "Second",
						condition = dualNow,
						thenView = function()
							return pane(2)
						end,
					}),
				},
			}),
		}
		-- the pad's month keys (the adjust route pages from any day), named while a pad is live
		local keyName = require("../input/key_names").label
		-- mounted only while a pad is live: a hidden row would keep its box and
		-- leave a band of empty panel under the months
		table.insert(
			children,
			UI.When({
				id = "PageHint",
				condition = Compose.formula(function(use)
					local classes = if env ~= nil then use(env:get("interactionClasses")) else nil
					return type(classes) == "table" and classes.gamepad == true
				end),
				thenView = function()
					return UI.HStack({
						id = "Keys",
						gap = "xs",
						align = "center",
						children = {
							require("./shortcut_hint").build(Facet, core, {
								id = "PageKeys",
								keys = { { keyName("ButtonL1") :: string }, { keyName("ButtonR1") :: string } },
								controlSize = "compact",
								env = spec.env,
							}).blueprint,
							UI.Text({ id = "Words", text = "Change month", textSize = "caption", role = "secondary" }),
						},
					})
				end,
			})
		)
		if withTime then
			table.insert(children, timeSection())
		end
		if #presets > 0 then
			table.insert(children, presetRow())
		end
		local actions: { any } = {}
		local function action(actionId: string, words_: string, fn: () -> (), look: string?): any
			return UI.Button({
				id = actionId,
				label = words_,
				onActivate = fn,
				enabled = interactive,
				-- Reset all is a text link; Apply, the primary action, wears the accent
				appearance = if look == "link" then "link" else nil,
				-- a text link carries no plate's inset, so it shares the row with both buttons
				padding = if look == "link" then { left = "xs", right = "xs" } else nil,
				surface = if look == "primary" then "accent" else nil,
			})
		end
		if draft then
			table.insert(
				actions,
				action("ResetAll", "Reset all", function()
					propose(if isRange then {} else nil)
				end, "link")
			)
			table.insert(
				actions,
				action("Cancel", "Cancel", function()
					restore()
					takeSnapshot()
					if overlay then
						close("cancel")
					end
				end)
			)
			table.insert(
				actions,
				action("Apply", "Apply", function()
					if isRange then
						local r = range:peek()
						if spec.onRangeCommit ~= nil then
							spec.onRangeCommit(r)
						end
					else
						commit()
					end
					takeSnapshot()
					if overlay then
						close("apply")
					end
				end, "primary")
			)
		elseif overlay and popoverApi ~= nil and popoverApi.route:peek() == "sheet" then
			table.insert(
				actions,
				action("Done", "Done", function()
					close("activate")
				end)
			)
		end
		if #actions > 0 then
			table.insert(children, UI.Divider({ id = "FooterRule" }))
			-- a draft's link leads and Cancel/Apply keep to the trailing edge; a
			-- sheet's lone Done sits at the trailing edge
			local row = actions
			if draft then
				row = {
					actions[1],
					UI.HStack({ id = "Commit", gap = "s", children = { actions[2], actions[3] } }),
				}
			end
			table.insert(
				children,
				UI.HStack({
					id = "Actions",
					gap = "s",
					wrap = true,
					width = UI.fill(),
					align = "center",
					distribute = if draft then "spaceBetween" else "end",
					children = row,
				})
			)
		end
		-- an overlay is as wide as its months; inline takes the width it is offered
		local width = if overlay
			then Compose.formula(function(use)
				local one = gridWidth(use)
				return { type = "fixed", px = if use(dualNow) then 2 * one + metric(use, "l", 24) else one }
			end)
			else UI.fill()
		local panel = UI.VStack({ id = "Calendar", gap = "m", width = width, children = children })
		local panelOwner = Compose.currentOwner() or owner

		-- which pane and index a focused path is, or nil
		local function cellAt(path: string?): (number?, number?)
			if path == nil then
				return nil, nil
			end
			for k, list in cellPaths do
				for i, p in list do
					if p == path then
						return k, i
					end
				end
			end
			return nil, nil
		end
		local function focusCell(k: number, i: number): boolean
			local list = cellPaths[k]
			return graphRef ~= nil and list ~= nil and list[i] ~= nil and graphRef.focusOn(list[i])
		end
		local function peekPane(k: number): CivilDate
			return paneMonth(function(r)
				return r:peek()
			end, k)
		end
		-- the cell showing `d` inside its own month on a shown pane, or nil
		local function cellFor(d: CivilDate): (number?, number?)
			for k in cellPaths do
				local m = peekPane(k)
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
		-- a day that just paged into view is focusable once the grid re-syncs
		local pendingDay: CivilDate? = nil
		local function focusDay(d: CivilDate)
			local k, i = cellFor(d)
			pendingDay = if k ~= nil and i ~= nil and focusCell(k, i) then nil else d
		end
		-- the last navigation position, for "focus just entered the grid"
		local lastNav: string? = nil
		-- days per arrow: a row's neighbour, or the same weekday a week away
		local STEPS = { ["left"] = -1, ["right"] = 1, up = -7, down = 7 }
		return contribution.attach(panel, {
			syncGeometry = function(rectOf: (string) -> any, node: any?)
				if node == nil then
					return
				end
				cellPaths = {}
				local function walk(n: any)
					local k = if n.id ~= nil then string.match(n.id, "^Pane(%d)$") else nil
					if k ~= nil then
						local list = {}
						local function cells(c: any)
							local i = if c.class == "Button" and c.id ~= nil
								then string.match(c.id, "^D(%d+)$")
								else nil
							if i ~= nil then
								list[tonumber(i) :: number] = c.path
								return
							end
							for _, child in c.children or {} do
								cells(child)
							end
						end
						cells(n)
						cellPaths[tonumber(k) :: number] = list
						return
					end
					for _, child in n.children or {} do
						walk(child)
					end
				end
				walk(node)
				if pendingDay ~= nil then
					focusDay(pendingDay)
				end
				if not overlay then
					local own = rectOf(node.path)
					if own ~= nil and own.w ~= measured:peek() then
						measured:set(own.w)
					end
				end
			end,
			bindFocusGraph = function(graph: any)
				graphRef = graph
				panelOwner.watchStatic(graph.focused, function(path: any)
					focusedPath:set(path)
				end)
			end,
			-- L1/R1 and Comma/Period page the month from any day; no axis, so the
			-- arrows stay with navigation
			adjustTargets = function(_root: any): { [string]: boolean }
				local out: { [string]: boolean } = {}
				for _, list in cellPaths do
					for _, p in list do
						out[p] = true
					end
				end
				return out
			end,
			handleAdjust = function(path: string, direction: number): boolean
				local k = cellAt(path)
				if k == nil then
					return false
				end
				page(if direction > 0 then 1 else -1)
				return true
			end,
			-- the arrows walk DAYS: ±1 and ±7 from the focused day, onto whichever
			-- pane shows it in its own month. ←/→ page when no pane does; ↑/↓ past
			-- the shown months leave the grid from its edge row (the grid's own
			-- up/down exits reach the header and whatever follows). A page the
			-- bounds refuse hands the arrow back to navigation too.
			navigateIntercept = function(direction: string): boolean
				local here = focusedPath:peek()
				local k, i = cellAt(here)
				local step = STEPS[direction]
				if k == nil or i == nil or step == nil then
					lastNav = here
					return false
				end
				lastNav = here
				local target = civil.addDays(civil.monthGrid(peekPane(k).year, peekPane(k).month, weekStart)[i], step)
				if cellFor(target) == nil and math.abs(step) == 7 then
					local m = peekPane(if step > 0 then #cellPaths else 1)
					local ek, ei = cellFor({
						year = m.year,
						month = m.month,
						day = if step > 0 then civil.daysIn(m.year, m.month) else 1,
					})
					if ek ~= nil and ei ~= nil then
						focusCell(ek, ei)
						lastNav = focusedPath:peek()
					end
					return false
				end
				if cellFor(target) == nil and not page(if step > 0 then 1 else -1) then
					return false
				end
				focusDay(target)
				return true
			end,
			-- ONE Tab stop: Tab leaves from the grid's last day, Shift+Tab from its
			-- first, so traversal steps straight out of it
			handleTraverse = function(from: string, direction: number): boolean
				lastNav = from
				local k = cellAt(from)
				if k ~= nil then
					local last = #cellPaths
					local m = peekPane(if direction > 0 then last else 1)
					local edge = if direction > 0 then civil.daysIn(m.year, m.month) else 1
					focusDay({ year = m.year, month = m.month, day = edge })
				end
				return false
			end,
			-- navigation that ENTERS the grid lands on the landing day
			focusMoved = function(path: string): boolean
				local entering = cellAt(path) ~= nil and cellAt(lastNav) == nil
				lastNav = path
				if entering then
					focusCell(1, landing())
					lastNav = focusedPath:peek()
					return true
				end
				return false
			end,
		})
	end

	-- ===== the closed form ==================================================
	local chrome = Compose.withOwner(owner, function()
		return fieldChrome.new({
			UI = UI,
			control = "UI.DateTimePicker",
			spec = {
				label = spec.label,
				requiredMark = spec.requiredMark,
				hint = spec.hint,
				errorText = spec.errorText,
				appearance = spec.appearance,
				controlSize = spec.controlSize,
			},
			internalMessage = typedError,
		})
	end)

	-- the calendar icon, inside the field's plate at its trailing edge
	local function calendarButton(): any
		return UI.Button({
			id = "Open",
			icon = "calendar",
			label = "Choose a date",
			shape = "circle",
			-- an accessory inside the field's own plate: no second plate of its own
			surface = "plain",
			enabled = interactive,
			onActivate = function()
				requestPresented(not presented:peek())
			end,
		})
	end

	local function typedField(): any
		local text = Compose.cell(valueText:peek())
		follow(valueText, function(s: string)
			text:set(s)
			typedError:set("")
		end)
		local built = require("./text_input").build(Facet, core, {
			id = "Entry",
			value = text,
			placeholder = spec.placeholder,
			-- the editable field IS the plate (its own field skin), so the row
			-- around it paints none: one plate, never a box in a box
			appearance = spec.appearance,
			controlSize = spec.controlSize,
			enabled = interactive,
			env = spec.env,
			trailing = if overlay then calendarButton() else nil,
			-- a refused or caller-flagged entry borders the field in the danger role
			invalid = chrome.hasError,
			onCommit = function(typed: any)
				if typed == valueText:peek() then
					return
				end
				local function parseOne(s: string): (CivilDate?, string?)
					local d, why = civil.parse(s, locale, withTime)
					if d ~= nil and isDisabled(d) then
						return nil, "That date is not available."
					end
					return d, why
				end
				local next: any, why: string?
				if isRange then
					-- the words' own separator (an en dash, three bytes) or a spaced
					-- hyphen: never a byte class, and never a date's own "-"
					local at, stop = string.find(typed, "–", 1, true)
					if at == nil then
						at, stop = string.find(typed, " - ", 1, true)
					end
					local a = if at ~= nil then string.sub(typed, 1, at - 1) else nil
					local b = if stop ~= nil then string.sub(typed, stop + 1) else ""
					if a == nil and string.match(typed, "^%s*$") ~= nil then
						next = {}
					elseif a == nil then
						why = "Enter two dates, like "
							.. civil.format({ year = 2026, month = 1, day = 2 }, locale)
							.. " – "
							.. civil.format({ year = 2026, month = 1, day = 9 }, locale)
					else
						local s, f
						s, why = parseOne(a)
						if s ~= nil then
							f, why = parseOne(b)
						end
						if s ~= nil and f ~= nil then
							next = if civil.compare(s, f) <= 0
								then { start = s, finish = f }
								else { start = f, finish = s }
						end
					end
				elseif string.match(typed, "^%s*$") ~= nil then
					-- clearing the words proposes an empty value
					if propose(nil) and not draft then
						commit()
					end
					text:set(valueText:peek())
					return
				else
					next, why = parseOne(typed)
				end
				if next == nil then
					-- the typed words stay; nothing is committed
					typedError:set(why or "")
					return
				end
				typedError:set("")
				if propose(next) then
					if not draft then
						commit()
					end
					local anchor: any = if isRange then next.start else next
					if anchor ~= nil then
						viewMonth:set(monthOf(anchor))
					end
				else
					text:set(valueText:peek())
				end
			end,
		})
		Compose.cleanup(function()
			built.dispose()
		end)
		return built.blueprint
	end
	local function displayField(): any
		local shown = Compose.formula(function(use)
			local s = use(valueText)
			return if s ~= "" then s else (spec.placeholder or "")
		end)
		return UI.Button({
			id = "Show",
			label = shown,
			surface = "plain",
			width = UI.fill(),
			enabled = interactive,
			onActivate = function()
				requestPresented(true)
			end,
			-- the words read from the field's leading edge, as a typed field's do
			children = {
				UI.Text({
					id = "Words",
					text = shown,
					width = UI.fill(),
					lineLimit = 1,
					disclose = true,
					-- a placeholder reads as one
					role = Compose.formula(function(use)
						return if use(valueText) == "" then "secondary" else "content"
					end),
				}),
			},
		})
	end

	local root: any
	if not overlay then
		root = Compose.withOwner(owner, function()
			local panel = panelView()
			local wrapped = chrome.wrap(panel, id)
			return if wrapped == panel then UI.VStack({ id = id, width = UI.fill(), children = { panel } }) else wrapped
		end)
	else
		local pop = require("./popover").build(Facet, core, {
			id = id,
			isPresented = presented,
			onPresentedChange = function(next: boolean)
				if not next then
					asked = true
				end
				requestPresented(next)
			end,
			onDismiss = function(reason: string)
				local mine = closeWhy
				closeWhy = nil
				local proposed = asked
				asked = false
				-- a draft closed any way but Apply discards; otherwise every change
				-- already committed and the close keeps it
				if mine == nil and proposed and draft then
					restore()
				end
				if spec.onDismiss ~= nil then
					spec.onDismiss(mine or reason)
				end
			end,
			-- the calendar hangs from the whole FIELD (below, start-aligned, flipping
			-- only when there is no room), never from the icon inside it
			source = { path = "/Field" },
			content = panelView,
			edge = "bottom",
			align = "start",
			tail = false,
			env = spec.env,
		}, { tenFoot = true, hug = true })
		popoverApi = pop.api
		owner.own(function()
			pop.dispose()
		end)
		root = Compose.withOwner(owner, function()
			local row = UI.HStack({
				id = "Field",
				width = UI.fill(),
				align = "center",
				surface = Compose.formula(function(use)
					return if use(typedEntry) then "plain" else selection.read(chrome.surface, use)
				end),
				-- the shown field's own danger border (a typed field draws its own)
				stroke = Compose.formula(function(use)
					return if use(chrome.hasError) and not use(typedEntry)
						then UI.strokeData({ color = "danger", thickness = "focusRing", transparency = 0 })
						else nil
				end),
				height = chrome.height,
				padding = Compose.formula(function(use)
					return if use(typedEntry) then 0 else selection.read(chrome.padding, use)
				end),
				gap = 0,
				children = {
					UI.When({ id = "Words", condition = typedEntry, thenView = typedField, elseView = displayField }),
					-- a typed field carries the icon in its own trailing slot
					UI.When({
						id = "Icon",
						condition = Compose.formula(function(use)
							return not use(typedEntry)
						end),
						thenView = calendarButton,
					}),
					pop.blueprint,
				},
			})
			local wrapped = chrome.wrap(row, id)
			return if wrapped == row then UI.VStack({ id = id, width = UI.fill(), children = { row } }) else wrapped
		end)
	end

	local function dump()
		local m = viewMonth:peek()
		return {
			schema = DUMP_SCHEMA,
			id = id,
			selection = mode,
			style = style,
			value = if isRange then nil else value:peek(),
			range = if isRange then range:peek() else nil,
			text = valueText:peek(),
			typedError = typedError:peek(),
			month = { year = m.year, month = m.month },
			dual = dualNow:peek(),
			today = today:peek(),
			presented = presented:peek(),
			route = if popoverApi ~= nil then popoverApi.route:peek() else "inline",
			cellPaths = table.clone(cellPaths),
			draft = draft,
			weekStart = weekStart,
			diagnostics = table.clone(diagnostics),
		}
	end

	return {
		blueprint = root,
		api = {
			diagnostics = function(): { string }
				return table.clone(diagnostics)
			end,
		},
		dump = dump,
		dispose = function()
			owner.dispose()
		end,
	}
end

function date_time_picker.build(Facet: any, core: any, spec: Spec)
	return ownedBuild(core, function(owner)
		return build(Facet, core, spec, owner)
	end)
end

return date_time_picker
