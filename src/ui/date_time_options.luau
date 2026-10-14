--!strict
local civil = require("./civil_date")
local fieldChrome = require("./field_chrome")
local Shared = require("./types")
local DTP = require("./date_time_picker_types")
local CivilTypes = require("./civil_date_types")
local InputProps = require("./input_props")

type CivilDate = DTP.CivilDate
type Range = DTP.Range
type Spec = InputProps.DateTimePickerProps
export type Options = {
	isRange: boolean,
	withTime: boolean,
	draft: boolean,
	proposeSingle: DTP.DateCallback?,
	proposeRange: DTP.RangeCallback?,
	hasProposer: boolean,
	minuteStep: number,
	weekStart: number,
	months: { string },
	weekdays: { string },
	locale: CivilTypes.Locale,
	hourCycle: number,
	overlay: boolean,
	presets: { DTP.Preset },
	clock: () -> CivilDate,
}

local LOCALE_KEYS = { months = true, weekdays = true, order = true, separator = true, hourCycle = true }
local PRESET_KEYS = { id = true, label = true, range = true }
local ORDERS = { mdy = true, dmy = true, ymd = true }

return function(ctx: Shared.Context, chrome: fieldChrome.Chrome, spec: Spec): Options
	local read = ctx.read
	local function refuse(message: string): never
		error(`Facet UI.DateTimePicker: {message}`, 0)
	end
	local raw = (spec :: unknown) :: { [string]: unknown }
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

	return {
		isRange = isRange,
		withTime = withTime,
		draft = draft,
		proposeSingle = proposeSingle,
		proposeRange = proposeRange,
		hasProposer = hasProposer,
		minuteStep = minuteStep,
		weekStart = weekStart,
		months = months,
		weekdays = weekdays,
		locale = locale,
		hourCycle = hourCycle,
		overlay = overlay,
		presets = presets,
		clock = clock,
	}
end
