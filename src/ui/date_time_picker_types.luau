--!strict
local Shared = require("./types")
local Civil = require("./civil_date_types")

export type CivilDate = Civil.CivilDate
export type Range = Civil.Range
export type Locale = Civil.Locale
export type Preset = { id: string, label: string, range: (today: CivilDate) -> Range }
export type DismissReason = "activate" | "outside" | "cancel" | "anchorLost" | "apply"
export type Selection = "single" | "range"
export type Style = "automatic" | "inline"
export type DateValue = Shared.Value<CivilDate?>
export type RangeValue = Shared.Value<Range>
export type FlagValue = Shared.Value<boolean>
export type WordsValue = Shared.Value<string>
export type SizeValue = Shared.Value<Shared.ControlSize>
export type DateCallback = (value: CivilDate?) -> ()
export type RangeCallback = (range: Range) -> ()
export type DateTimePickerOptions = {
	selection: Selection?,
	value: DateValue?,
	onChange: DateCallback?,
	onCommit: DateCallback?,
	range: RangeValue?,
	onRangeChange: RangeCallback?,
	onRangeCommit: RangeCallback?,
	time: boolean?,
	minuteStep: number?,
	hourCycle: number?,
	min: DateValue?,
	max: DateValue?,
	isDateDisabled: ((date: CivilDate) -> boolean)?,
	weekStart: number?,
	locale: Locale?,
	clock: (() -> CivilDate)?,
	referenceDate: DateValue?,
	presets: { Preset }?,
	draft: boolean?,
	style: Style?,
	format: ((value: CivilDate) -> string)?,
	placeholder: string?,
	isPresented: FlagValue?,
	onPresentedChange: ((next: boolean) -> ())?,
	onDismiss: ((reason: DismissReason) -> ())?,
	enabled: FlagValue?,
	readOnly: FlagValue?,
	label: WordsValue?,
	requiredMark: ("required" | "optional")?,
	hint: WordsValue?,
	errorText: WordsValue?,
	controlSize: SizeValue?,
	appearance: WordsValue?,
	corners: ("pill" | "square")?,
}
export type DateTimePickerProps = Shared.FrameProps & DateTimePickerOptions
export type DateTimePickerControls = {
	DateTimePicker: Shared.Constructor<DateTimePickerProps, Frame>,
}

return {}
