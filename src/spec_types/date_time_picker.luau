--!strict
-- The `date_time_picker` control's types, apart from its implementation: reading a
-- type must not load the control.
local blueprint = require("../blueprint")
local publicEnv = require("../env/environment")
local civilDate = require("../controls/civil_date")

export type CivilDate = civilDate.CivilDate
export type Range = civilDate.Range
export type Locale = civilDate.Locale
export type Preset = { id: string, label: string, range: (today: CivilDate) -> Range }
export type DismissReason = "activate" | "outside" | "cancel" | "anchorLost" | "apply"

export type Spec = {
	id: string?,
	selection: ("single" | "range")?, -- construction-only; default single
	-- single: the caller's date (with hour/minute when `time = true`); nil = empty
	value: blueprint.Bound<CivilDate?>?,
	onChange: ((value: CivilDate?) -> ())?,
	onCommit: ((value: CivilDate?) -> ())?,
	-- range: { start?, finish? }, inclusive
	range: blueprint.Bound<Range>?,
	onRangeChange: ((range: Range) -> ())?,
	onRangeCommit: ((range: Range) -> ())?,
	time: boolean?, -- single only: an hour and minute beside the calendar
	minuteStep: number?, -- divides 60; default 5
	hourCycle: number?, -- 12 or 24; default from `locale`
	min: blueprint.Bound<CivilDate?>?, -- inclusive
	max: blueprint.Bound<CivilDate?>?, -- inclusive
	isDateDisabled: ((date: CivilDate) -> boolean)?,
	weekStart: number?, -- 1 = Sunday … 7 = Saturday; default 1
	locale: Locale?,
	clock: (() -> CivilDate)?, -- today; default the engine clock at UTC
	referenceDate: blueprint.Bound<CivilDate?>?, -- the month an empty picker opens on
	presets: { Preset }?, -- range only
	draft: boolean?, -- Apply/Cancel/Reset all; only Apply commits
	style: ("automatic" | "inline")?, -- construction-only; automatic = a field opening the calendar
	format: ((value: CivilDate) -> string)?, -- the field's words; typed entry needs the default
	placeholder: string?,
	isPresented: blueprint.Bound<boolean>?,
	onPresentedChange: ((next: boolean) -> ())?,
	onDismiss: ((reason: DismissReason) -> ())?,
	enabled: blueprint.Bound<boolean>?,
	readOnly: blueprint.Bound<boolean>?,
	label: blueprint.Bound<string>?,
	requiredMark: ("required" | "optional")?,
	hint: blueprint.Bound<string>?,
	errorText: blueprint.Bound<string>?,
	controlSize: blueprint.Bound<("compact" | "regular" | "large")?>?,
	appearance: blueprint.Bound<("standard" | "contrast" | "utility")?>?,
	corners: ("pill" | "square")?,
	env: publicEnv.Env?,
}

return nil
