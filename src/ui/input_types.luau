--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")

export type Input<T> = Shared.Input<T>

export type CellBinding<T> = { value: ComposeTypes.Value<T>, onChange: ((T) -> ())? }
export type RequestBinding<T> = { value: Input<T>, onChange: (T) -> () }
export type ValueBinding<T> = CellBinding<T> | RequestBinding<T>
export type EnabledOptions =
	{ enabled: Shared.ValueBoolean?, disabled: Shared.ValueBoolean?, busy: Shared.ValueBoolean? }
export type Row = { title: Shared.ValueString?, description: Shared.ValueString?, value: string?, icon: string? }
export type Shortcut = { keyCode: string, modifiers: { shift: boolean? }? }
export type HelpSpec = {
	title: Shared.ValueString?,
	body: Shared.ValueString,
	shortcut: { { string } }?,
	edge: ("top" | "bottom" | "leading" | "trailing")?,
	align: ("start" | "center" | "end")?,
}
export type Help = Shared.ValueString | HelpSpec
export type ButtonCorners = "pill" | "square"
export type ButtonRole = "default" | "cancel" | "destructive" | "onIndicator"
export type ButtonVisualOptions = {
	label: Shared.ValueString?,
	name: Shared.ValueString?,
	pop: boolean?,
	appearance: (Shared.ValueString | Shared.Input<string?>)?,
	controlSize: Input<Shared.ControlSize?>?,
	corners: Input<ButtonCorners>?,
	shape: ("rect" | "circle")?,
	role: Input<ButtonRole>?,
	icon: Shared.ValueString?,
	trailingIcon: Shared.ValueString?,
	image: Shared.ValueString?,
	imageAspectRatio: number?,
	imageFraming: ("fit" | "crop")?,
	subtitle: Shared.ValueString?,
	hint: Shared.ValueString?,
	help: Help?,
	disclose: boolean?,
	row: Row?,
	textSize: Input<number | Shared.TextRole>?,
}
export type TextButtonOptions = {
	compactLabel: Shared.ValueString?,
	underline: ("always" | "hover")?,
}

export type ButtonInputOptions = {
	haptic: Input<boolean | Shared.HapticKind>?,
	repeatDelay: number?,
	repeatInterval: number?,
	shortcut: Shortcut?,
	dialogAction: ("default" | "cancel")?,
	onPointerDown: ((InputObject) -> ())?,
	onPointerUp: ((InputObject) -> ())?,
	onPointerCancel: (() -> ())?,
	target: ("hit" | "thumb" | "inline")?,
}
export type ButtonOptions = {
	caption: Shared.ValueString?,
	glyph: (() -> GuiObject)?,
	shortcutHint: InputAction?,
	selected: Shared.ValueBoolean?,
	onActivate: ((InputObject?, number?) -> ())?,
}
export type ButtonShape =
	Shared.TextButtonProps
	& EnabledOptions
	& ButtonVisualOptions
	& ButtonInputOptions
	& ButtonOptions
export type ToggleOptions = {
	presentation: ("switch" | "checkbox" | "button")?,
	mixed: Shared.ValueBoolean?,
	indicatorPosition: ("leading" | "trailing")?,
}
export type ToggleImplementationProps =
	Shared.TextButtonProps
	& EnabledOptions
	& ButtonVisualOptions
	& ButtonInputOptions
	& ToggleOptions
	& {
		value: Shared.ValueBoolean,
		onChange: ((boolean) -> ())?,
	}
export type TextCommitReason = "submit" | "focusLost"
export type CommitReason = TextCommitReason | "clamped"
export type ClearButtonMode = "never" | "always" | "whileEditing" | "unlessEditing"
export type SelectOnFocus = "none" | "all" | "end"
export type FieldAppearance = "standard" | "contrast" | "utility"
export type TextValue = Shared.ValueString
export type NumberValue = Shared.ValueNumber
export type TextBinding = ValueBinding<string>
export type NumberCell = ComposeTypes.Value<number>
export type FlagValue = Shared.ValueBoolean
export type SizeValue = Input<Shared.ControlSize?>
export type FieldAppearanceValue = Input<FieldAppearance>
export type SelectOnFocusValue = Input<SelectOnFocus>
export type RequiredMark = "required" | "optional"
export type FieldCorners = "pill" | "square"
export type FieldChrome = {
	label: TextValue?,
	requiredMark: RequiredMark?,
	hint: TextValue?,
	errorText: TextValue?,
	controlSize: SizeValue?,
	appearance: TextValue?,
	corners: FieldCorners?,
}
export type TextInputOptions = {
	enabled: FlagValue?,
	disabled: FlagValue?,
	readOnly: FlagValue?,
	placeholder: TextValue?,
	multiline: boolean?,
	visibleLines: number?,
	validate: ((string) -> string?)?,
	maxLength: number?,
	invalid: ComposeTypes.ReadOnlyValue<boolean>?,
	clearButton: boolean?,
	clearButtonMode: ClearButtonMode?,
	selectOnFocus: SelectOnFocusValue?,
	leading: Shared.Child?,
	trailing: Shared.Child?,
	onCancel: (() -> ())?,
	min: number?,
	max: number?,
	parse: ((string) -> number?)?,
	format: ((number) -> string)?,
}
export type NumberOptions = {
	step: number?,
	precision: number?,
	stepButtons: boolean?,
	prefix: TextValue?,
	suffix: TextValue?,
	scrub: FlagValue?,
}
export type TextPresentation = {
	presentation: ("plain" | "search")?,
	numericValue: nil?,
	onCommit: ((string, TextCommitReason) -> ())?,
}
export type NumberPresentation = {
	presentation: "number",
	numericValue: NumberCell,
	onCommit: ((number, CommitReason) -> ())?,
}
export type TextInputPresentation = TextPresentation | NumberPresentation
export type TextInputImplementationProps = Shared.TextBoxProps & FieldChrome & TextInputOptions & NumberOptions & {
	value: TextValue,
	onChange: ((string) -> ())?,
	onCommit: (((string, TextCommitReason) -> ()) | ((number, CommitReason) -> ()))?,
	presentation: ("plain" | "search" | "number")?,
	numericValue: ComposeTypes.Value<number>?,
}
export type NumberInputModel = {
	numericValue: NumberCell,
	onCommit: ((number, CommitReason) -> ())?,
}
export type ValueOptions = {
	min: number?,
	max: number?,
	step: Shared.ValueNumber?,
	format: ((number) -> string)?,
}
export type NumberInputOptions = ValueOptions & {
	enabled: Shared.ValueBoolean?,
	label: Shared.ValueString?,
}
export type StepperOptions = {
	enabled: Shared.ValueBoolean?,
	label: Shared.ValueString?,
	repeatDelay: number?,
	repeatInterval: number?,
}
export type StepperImplementationProps = Shared.FrameProps & ValueOptions & StepperOptions & {
	value: Shared.ValueNumber,
	onChange: ((number) -> ())?,
}
export type SliderRange = { lower: number, upper: number }
export type SliderThumb = "value" | "lower" | "upper"
export type SliderChange = { thumb: SliderThumb }
export type SliderKnob = {
	thumb: SliderThumb,
	value: ComposeTypes.ReadOnlyValue<number>,
	fraction: ComposeTypes.ReadOnlyValue<number>,
	dragging: ComposeTypes.ReadOnlyValue<boolean>,
	enabled: ComposeTypes.ReadOnlyValue<boolean>,
}
export type SliderOptions = {
	enabled: Shared.ValueBoolean?,
	label: Shared.ValueString?,
	tapToPosition: boolean?,
	thumbImage: TextValue?,
	trackImage: TextValue?,
	row: Row?,
	axis: ("x" | "y")?,
	minGap: number?,
	thumb: ("always" | "auto" | "none")?,
	thumbContent: ((SliderKnob) -> Instance)?,
	trackContent: (() -> Instance)?,
	rotation: NumberValue?,
	controlSize: SizeValue?,
	contained: boolean?,
}
export type SliderImplementationProps = Shared.FrameProps & ValueOptions & SliderOptions & {
	range: boolean?,
	value: Shared.ValueNumber | RangeValue,
	onChange: (((number, SliderChange?) -> ()) | ((SliderRange, SliderChange) -> ()))?,
	onCommit: (((number, SliderChange?) -> ()) | ((SliderRange, SliderChange) -> ()))?,
}
export type RangeValue = Input<SliderRange>
export type SliderCellBinding = {
	range: false?,
	value: ComposeTypes.Value<number>,
	onChange: ((number) -> ())?,
	onCommit: ((number) -> ())?,
}
export type SliderRequestBinding = {
	range: false?,
	value: Shared.ValueNumber,
	onChange: (number) -> (),
	onCommit: ((number) -> ())?,
}
export type SliderRangeBinding = {
	range: true,
	value: RangeValue,
	onChange: ((SliderRange, SliderChange) -> ())?,
	onCommit: ((SliderRange, SliderChange) -> ())?,
}
export type SliderBinding = SliderCellBinding | SliderRequestBinding | SliderRangeBinding
export type LevelSize = "small" | "medium" | "large"
export type Glyphs = { filled: string, empty: string }
export type Images = { filled: string, empty: string }
export type Tint = { filled: Input<Color3>?, empty: Input<Color3>? }
export type LevelCellBinding = { value: ComposeTypes.Value<number>, onChange: ((number) -> ())?, readOnly: boolean? }
export type LevelRequestBinding = { value: Shared.ValueNumber, onChange: (number) -> (), readOnly: boolean? }
export type LevelReadOnlyBinding = { value: Shared.ValueNumber, readOnly: true, onChange: ((number) -> ())? }
export type LevelBinding = LevelCellBinding | LevelRequestBinding | LevelReadOnlyBinding
export type LevelOptions = {
	count: number?,
	allowZero: boolean?,
	readOnly: boolean?,
	enabled: Shared.ValueBoolean?,
}
export type RatingImplementationProps = Shared.TextButtonProps & LevelOptions & {
	value: Shared.ValueNumber,
	onChange: ((number) -> ())?,
	glyphs: Glyphs?,
	starSize: LevelSize?,
}
export type RatingOptions = {
	count: number?,
	allowZero: boolean?,
	enabled: Shared.ValueBoolean?,
	glyphs: Glyphs?,
	starSize: LevelSize?,
}
export type LevelPickerImplementationProps = Shared.TextButtonProps & LevelOptions & {
	value: Shared.ValueNumber,
	onChange: ((number) -> ())?,
	segment: ("bar" | "glyph" | "image")?,
	segmentSize: LevelSize?,
	glyphs: Glyphs?,
	images: Images?,
	tint: Tint?,
}
export type LevelPickerOptions = {
	count: number?,
	allowZero: boolean?,
	enabled: Shared.ValueBoolean?,
	segment: ("bar" | "glyph" | "image")?,
	segmentSize: LevelSize?,
	glyphs: Glyphs?,
	images: Images?,
	tint: Tint?,
}
export type ChipCellSelection = {
	selected: ComposeTypes.Value<boolean>,
	onToggle: ((boolean) -> ())?,
	onRemove: (() -> ())?,
}
export type ChipRequestSelection = { selected: Shared.ValueBoolean, onToggle: (boolean) -> (), onRemove: (() -> ())? }
export type ChipRemoval = { selected: nil?, onToggle: nil?, onRemove: () -> () }
export type ChipSelection = ChipCellSelection | ChipRequestSelection | ChipRemoval
export type ChipOptions = {
	ref: ((TextButton | Frame) -> ())?,
	editing: FlagValue?,
	removeLabel: Shared.ValueString?,
	removeFocusFallback: Input<GuiObject?>?,
	leading: Shared.Child?,
	trailing: Shared.Child?,
}
export type ChipImplementationProps =
	Shared.TextButtonNativeProps
	& EnabledOptions
	& ButtonVisualOptions
	& ButtonInputOptions
	& ChipOptions
	& {
		selected: Shared.ValueBoolean?,
		onToggle: ((boolean) -> ())?,
		onRemove: (() -> ())?,
	}
export type ShortcutKeys = { keys: Input<{ { string } }>, action: nil? }
export type ShortcutAction = { action: InputAction, keys: nil? }
export type ShortcutHintSource = ShortcutKeys | ShortcutAction
export type ShortcutHintOptions = {
	ref: ((TextLabel | Frame) -> ())?,
	separator: Shared.ValueString?,
	controlSize: Input<Shared.ControlSize?>?,
	label: Shared.ValueString?,
	labelPosition: ("start" | "end")?,
	cap: boolean?,
}
export type ShortcutHintImplementationProps = Shared.TextLabelNativeProps & ShortcutHintOptions & {
	action: InputAction?,
	keys: Input<{ { string } }>?,
}
export type ButtonGuideEntry = {
	action: InputAction?,
	keyCode: (Enum.KeyCode | { Enum.KeyCode })?,
	keys: Input<{ { string } }>?,
	label: Shared.ValueString,
}
export type ButtonGuideOptions = {
	ref: ((Frame) -> ())?,
	entries: Input<{ ButtonGuideEntry }>,
	inputs: { string }?,
	controlSize: Input<Shared.ControlSize?>?,
}
export type ButtonGuideImplementationProps = Shared.FrameNativeProps & ButtonGuideOptions
export type HapticKind = Shared.HapticKind
export type AdjustmentState = { value: Shared.ValueNumber, onChange: ((number) -> ())? } | AdjustableOptions
export type AdjustableOptions = {
	enabled: Shared.ValueBoolean?,
	disabled: Shared.ValueBoolean?,
	busy: Shared.ValueBoolean?,
	onAdjust: (direction: number) -> (),
	axis: ("horizontal" | "vertical" | "none")?,
	repeats: boolean?,
	canAdjust: ((direction: number, use: ComposeTypes.Use?) -> boolean)?,
}

return {}
