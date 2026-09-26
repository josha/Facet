--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")

type Value<T> = Shared.Value<T>
type Constructor<P, N> = Shared.Constructor<P, N>

export type ValueBinding<T> =
	{ value: ComposeTypes.Cell<T>, onChange: ((T) -> ())? }
	| { value: Value<T>, onChange: (T) -> () }
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
export type ButtonVisualOptions = EnabledOptions & {
	label: Shared.ValueString?,
	name: Shared.ValueString?,
	compactLabel: Shared.ValueString?,
	pop: boolean?,
	appearance: Shared.ValueString?,
	controlSize: Value<Shared.ControlSize>?,
	corners: Value<ButtonCorners>?,
	shape: ("rect" | "circle")?,
	role: Value<ButtonRole>?,
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
	textSize: Value<string | number>?,
	underline: ("always" | "hover")?,
}
export type ButtonInputOptions = {
	haptic: Value<boolean | Shared.HapticKind>?,
	repeatDelay: number?,
	repeatInterval: number?,
	shortcut: Shortcut?,
	dialogAction: ("default" | "cancel")?,
	onPointerDown: ((InputObject) -> ())?,
	onPointerUp: ((InputObject) -> ())?,
	onPointerCancel: (() -> ())?,
}
export type ButtonProps = Shared.TextButtonProps & ButtonVisualOptions & ButtonInputOptions & {
	selected: Shared.ValueBoolean?,
	onActivate: ((InputObject?, number?) -> ())?,
}
export type ToggleImplementationProps = Shared.TextButtonProps & ButtonVisualOptions & ButtonInputOptions & {
	value: Shared.ValueBoolean,
	onChange: ((boolean) -> ())?,
	presentation: ("switch" | "checkbox" | "button")?,
	mixed: Shared.ValueBoolean?,
	indicatorPosition: ("leading" | "trailing")?,
}
export type ToggleProps = ToggleImplementationProps & ValueBinding<boolean>
export type TextCommitReason = "submit" | "focusLost"
export type CommitReason = TextCommitReason | "clamped"
export type ClearButtonMode = "never" | "always" | "whileEditing" | "unlessEditing"
export type SelectOnFocus = "none" | "all" | "end"
export type FieldAppearance = "standard" | "contrast" | "utility"
export type TextValue = Shared.ValueString
export type NumberValue = Shared.ValueNumber
export type TextBinding = ValueBinding<string>
export type NumberCell = ComposeTypes.Cell<number>
export type FlagValue = Shared.ValueBoolean
export type SizeValue = Value<Shared.ControlSize>
export type FieldAppearanceValue = Value<FieldAppearance>
export type SelectOnFocusValue = Value<SelectOnFocus>
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
export type TextInputOptions = FieldChrome & {
	enabled: FlagValue?,
	disabled: FlagValue?,
	readOnly: FlagValue?,
	placeholder: TextValue?,
	multiline: boolean?,
	visibleLines: number?,
	validate: ((string) -> string?)?,
	maxLength: number?,
	invalid: ComposeTypes.Readable<boolean>?,
	clearButton: boolean?,
	clearButtonMode: ClearButtonMode?,
	selectOnFocus: SelectOnFocusValue?,
	leading: Instance?,
	trailing: Instance?,
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
export type TextInputPresentation =
	{ presentation: ("plain" | "search")?, numericValue: nil?, onCommit: ((string, TextCommitReason) -> ())? }
	| { presentation: "number", numericValue: NumberCell, onCommit: ((number, CommitReason) -> ())? }
export type TextInputImplementationProps = Shared.TextBoxProps & TextInputOptions & NumberOptions & {
	value: TextValue,
	onChange: ((string) -> ())?,
	onCommit: ((any, CommitReason) -> ())?,
	presentation: ("plain" | "search" | "number")?,
	numericValue: ComposeTypes.Cell<number>?,
}
export type TextInputBase = Shared.TextBoxProps & TextInputOptions & NumberOptions & {
	value: TextValue,
	onChange: ((string) -> ())?,
}
export type TextInputProps = TextInputBase & TextBinding & TextInputPresentation
export type NumberInputProps = TextInputBase & TextBinding & {
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
export type StepperImplementationProps =
	Shared.FrameProps
	& NumberInputOptions
	& { value: Shared.ValueNumber, onChange: ((number) -> ())? }
export type StepperProps = StepperImplementationProps & ValueBinding<number>
export type SliderRange = { lower: number, upper: number }
export type SliderThumb = "value" | "lower" | "upper"
export type SliderChange = { thumb: SliderThumb }
export type SliderKnob = {
	thumb: SliderThumb,
	value: ComposeTypes.Readable<number>,
	fraction: ComposeTypes.Readable<number>,
	dragging: ComposeTypes.Readable<boolean>,
	enabled: ComposeTypes.Readable<boolean>,
}
export type SliderOptions = {
	onCommit: ((any, SliderChange?) -> ())?,
	tapToPosition: boolean?,
	thumbImage: TextValue?,
	trackImage: TextValue?,
	row: Row?,
	axis: ("x" | "y")?,
	range: boolean?,
	minGap: number?,
	thumb: ("always" | "auto" | "none")?,
	thumbContent: ((SliderKnob) -> Instance)?,
	trackContent: (() -> Instance)?,
	rotation: NumberValue?,
	controlSize: SizeValue?,
	contained: boolean?,
}
export type SliderImplementationProps = Shared.FrameProps & ValueOptions & SliderOptions & {
	enabled: Shared.ValueBoolean?,
	label: Shared.ValueString?,
	value: Shared.ValueNumber | RangeValue,
	onChange: ((any, SliderChange?) -> ())?,
}
export type RangeValue = Value<SliderRange>
export type SliderBinding =
	{ range: false?, value: ComposeTypes.Cell<number>, onChange: ((number) -> ())?, onCommit: ((number) -> ())? }
	| { range: false?, value: Shared.ValueNumber, onChange: (number) -> (), onCommit: ((number) -> ())? }
	| {
		range: true,
		value: RangeValue,
		onChange: ((SliderRange, SliderChange) -> ())?,
		onCommit: ((SliderRange, SliderChange) -> ())?,
	}
export type SliderProps = Shared.FrameProps & ValueOptions & SliderOptions & {
	enabled: Shared.ValueBoolean?,
	label: Shared.ValueString?,
} & SliderBinding
export type LevelSize = "small" | "medium" | "large"
export type Glyphs = { filled: string, empty: string }
export type Images = { filled: string, empty: string }
export type Tint = { filled: Value<Color3>?, empty: Value<Color3>? }
export type LevelBinding =
	{ value: ComposeTypes.Cell<number>, onChange: ((number) -> ())?, readOnly: boolean? }
	| { value: Shared.ValueNumber, onChange: (number) -> (), readOnly: boolean? }
	| { value: Shared.ValueNumber, readOnly: true, onChange: ((number) -> ())? }
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
export type RatingProps = Shared.TextButtonProps & {
	count: number?,
	allowZero: boolean?,
	enabled: Shared.ValueBoolean?,
	glyphs: Glyphs?,
	starSize: LevelSize?,
} & LevelBinding
export type LevelPickerImplementationProps = Shared.TextButtonProps & LevelOptions & {
	value: Shared.ValueNumber,
	onChange: ((number) -> ())?,
	segment: ("bar" | "glyph" | "image")?,
	segmentSize: LevelSize?,
	glyphs: Glyphs?,
	images: Images?,
	tint: Tint?,
}
export type LevelPickerProps = Shared.TextButtonProps & {
	count: number?,
	allowZero: boolean?,
	enabled: Shared.ValueBoolean?,
	segment: ("bar" | "glyph" | "image")?,
	segmentSize: LevelSize?,
	glyphs: Glyphs?,
	images: Images?,
	tint: Tint?,
} & LevelBinding
export type ChipSelection =
	{ selected: ComposeTypes.Cell<boolean>, onToggle: ((boolean) -> ())? }
	| { selected: Shared.ValueBoolean, onToggle: (boolean) -> () }
	| { selected: nil?, onToggle: nil?, onRemove: () -> () }
export type ChipImplementationProps = Shared.TextButtonNativeProps & ButtonVisualOptions & ButtonInputOptions & {
	ref: ((TextButton | Frame) -> ())?,
	selected: Shared.ValueBoolean?,
	onToggle: ((boolean) -> ())?,
	onRemove: (() -> ())?,
	editing: FlagValue?,
	removeLabel: Shared.ValueString?,
	removeFocusFallback: Value<GuiObject?>?,
	leading: Instance?,
	trailing: Instance?,
}
export type ChipProps = ChipImplementationProps & ChipSelection
export type ShortcutHintSource = { keys: Value<{ { string } }>, action: nil? } | { action: InputAction, keys: nil? }
export type ShortcutHintImplementationProps = Shared.TextLabelNativeProps & {
	ref: ((TextLabel | Frame) -> ())?,
	action: InputAction?,
	keys: Value<{ { string } }>?,
	separator: Shared.ValueString?,
	controlSize: Value<Shared.ControlSize>?,
	label: Shared.ValueString?,
	labelPosition: ("start" | "end")?,
}
export type ShortcutHintProps = ShortcutHintImplementationProps & ShortcutHintSource
export type HapticKind = Shared.HapticKind
export type AdjustableOptions = EnabledOptions & {
	onAdjust: (direction: number) -> (),
	axis: ("horizontal" | "vertical" | "none")?,
	repeats: boolean?,
	canAdjust: ((direction: number, use: ComposeTypes.Use?) -> boolean)?,
}
export type InputControls = {
	Button: Constructor<ButtonProps, TextButton>,
	Toggle: Constructor<ToggleProps, TextButton>,
	TextInput: Constructor<TextInputProps, TextBox | Frame>,
	NumberInput: Constructor<NumberInputProps, TextBox | Frame>,
	Stepper: Constructor<StepperProps, Frame>,
	Slider: Constructor<SliderProps, Frame>,
	Rating: Constructor<RatingProps, TextButton>,
	LevelPicker: Constructor<LevelPickerProps, TextButton>,
	Chip: Constructor<ChipProps, TextButton | Frame>,
	ShortcutHint: Constructor<ShortcutHintProps, TextLabel | Frame>,
}

return {}
