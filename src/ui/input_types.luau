--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")

export type Input<T> = Shared.Input<T>

export type CellBinding<T> = { read value: ComposeTypes.Value<T>, read onChange: ((T) -> ())? }
export type RequestBinding<T> = { read value: Input<T>, read onChange: (T) -> () }
export type ValueBinding<T> = CellBinding<T> | RequestBinding<T>
export type EnabledOptions = {
	read enabled: Shared.ValueBoolean?,
	read disabled: Shared.ValueBoolean?,
	read busy: Shared.ValueBoolean?,
}
export type EnabledState = {
	read enabled: Shared.ValueBoolean?,
	read disabled: Shared.ValueBoolean?,
	read busy: Shared.ValueBoolean?,
}
export type Row = {
	read title: Shared.ValueString?,
	read description: Shared.ValueString?,
	read value: string?,
	read icon: string?,
}
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
	read label: Shared.ValueString?,
	name: Shared.ValueString?,
	pop: boolean?,
	appearance: (Shared.ValueString | Shared.Input<string?>)?,
	read controlSize: Input<Shared.ControlSize?>?,
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
		read value: Shared.ValueBoolean,
		read onChange: ((boolean) -> ())?,
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
	read label: TextValue?,
	requiredMark: RequiredMark?,
	hint: TextValue?,
	errorText: TextValue?,
	read controlSize: SizeValue?,
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
	read presentation: ("plain" | "search")?,
	read numericValue: nil?,
	read onCommit: ((string, TextCommitReason) -> ())?,
}
export type NumberPresentation = {
	read presentation: "number",
	read numericValue: NumberCell,
	read onCommit: ((number, CommitReason) -> ())?,
}
export type TextInputPresentation = TextPresentation | NumberPresentation
export type TextInputImplementationProps = Shared.TextBoxProps & FieldChrome & TextInputOptions & NumberOptions & {
	read value: TextValue,
	read onChange: ((string) -> ())?,
	read onCommit: (((string, TextCommitReason) -> ()) | ((number, CommitReason) -> ()))?,
	presentation: ("plain" | "search" | "number")?,
	read numericValue: ComposeTypes.Value<number>?,
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
	read enabled: Shared.ValueBoolean?,
	read label: Shared.ValueString?,
	repeatDelay: number?,
	repeatInterval: number?,
}
export type StepperImplementationProps = Shared.FrameProps & ValueOptions & StepperOptions & {
	read value: Shared.ValueNumber,
	read onChange: ((number) -> ())?,
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
	read enabled: Shared.ValueBoolean?,
	read label: Shared.ValueString?,
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
	read controlSize: SizeValue?,
	contained: boolean?,
}
export type SliderImplementationProps = Shared.FrameProps & ValueOptions & SliderOptions & {
	read range: boolean?,
	read value: Shared.ValueNumber | RangeValue,
	read onChange: (((number, SliderChange?) -> ()) | ((SliderRange, SliderChange) -> ()))?,
	read onCommit: (((number, SliderChange?) -> ()) | ((SliderRange, SliderChange) -> ()))?,
}
export type RangeValue = Input<SliderRange>
export type SliderCellBinding = {
	read range: false?,
	read value: ComposeTypes.Value<number>,
	read onChange: ((number) -> ())?,
	read onCommit: ((number) -> ())?,
}
export type SliderRequestBinding = {
	read range: false?,
	read value: Shared.ValueNumber,
	read onChange: (number) -> (),
	read onCommit: ((number) -> ())?,
}
export type SliderRangeBinding = {
	read range: true,
	read value: RangeValue,
	read onChange: ((SliderRange, SliderChange) -> ())?,
	read onCommit: ((SliderRange, SliderChange) -> ())?,
}
export type SliderBinding = SliderCellBinding | SliderRequestBinding | SliderRangeBinding
export type LevelSize = "small" | "medium" | "large"
export type Glyphs = { read filled: string, read empty: string }
export type Images = { read filled: string, read empty: string }
export type Tint = { read filled: Input<Color3>?, read empty: Input<Color3>? }
export type LevelCellBinding = {
	read value: ComposeTypes.Value<number>,
	read onChange: ((number) -> ())?,
	read readOnly: boolean?,
}
export type LevelRequestBinding = {
	read value: Shared.ValueNumber,
	read onChange: (number) -> (),
	read readOnly: boolean?,
}
export type LevelReadOnlyBinding = {
	read value: Shared.ValueNumber,
	read readOnly: true,
	read onChange: ((number) -> ())?,
}
export type LevelBinding = LevelCellBinding | LevelRequestBinding | LevelReadOnlyBinding
export type LevelOptions = {
	count: number?,
	allowZero: boolean?,
	readOnly: boolean?,
	enabled: Shared.ValueBoolean?,
}
export type RatingImplementationProps = Shared.TextButtonProps & LevelOptions & {
	read value: Shared.ValueNumber,
	read onChange: ((number) -> ())?,
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
	read value: Shared.ValueNumber,
	read onChange: ((number) -> ())?,
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
		read selected: Shared.ValueBoolean?,
		read onToggle: ((boolean) -> ())?,
		read onRemove: (() -> ())?,
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
	read action: InputAction?,
	read keys: Input<{ { string } }>?,
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
export type ButtonGuideImplementationProps = Shared.FrameProps & ButtonGuideOptions
export type HapticKind = Shared.HapticKind
export type AdjustmentState = EnabledState & {
	read value: Shared.ValueNumber?,
	read onChange: ((number) -> ())?,
	read repeatDelay: number?,
	read repeatInterval: number?,
}
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
