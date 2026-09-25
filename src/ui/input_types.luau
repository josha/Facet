--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")

type Value<T> = Shared.Value<T>
type Constructor<P, N> = Shared.Constructor<P, N>

export type ValueBinding<T> =
	{ value: ComposeTypes.Cell<T>, onChange: ((T) -> ())? }
	| { value: Value<T>, onChange: (T) -> () }
export type EnabledOptions = { enabled: Value<boolean>?, disabled: Value<boolean>?, busy: Value<boolean>? }
export type Row = { title: Value<string>?, description: Value<string>?, value: string?, icon: string? }
export type Shortcut = { keyCode: string, modifiers: { shift: boolean? }? }
export type HelpSpec = {
	title: Value<string>?,
	body: Value<string>,
	shortcut: { { string } }?,
	edge: ("top" | "bottom" | "leading" | "trailing")?,
	align: ("start" | "center" | "end")?,
}
export type Help = Value<string> | HelpSpec
export type ButtonCorners = "pill" | "square"
export type ButtonRole = "default" | "cancel" | "destructive" | "onIndicator"
export type ButtonVisualOptions = EnabledOptions & {
	label: Value<string>?,
	name: Value<string>?,
	compactLabel: Value<string>?,
	pop: boolean?,
	appearance: Value<string>?,
	controlSize: Value<Shared.ControlSize>?,
	corners: Value<ButtonCorners>?,
	shape: ("rect" | "circle")?,
	role: Value<ButtonRole>?,
	icon: Value<string>?,
	trailingIcon: Value<string>?,
	image: Value<string>?,
	imageAspectRatio: number?,
	imageFraming: ("fit" | "crop")?,
	subtitle: Value<string>?,
	hint: Value<string>?,
	help: Help?,
	row: Row?,
	textSize: Value<string | number>?,
	underline: ("always" | "hover")?,
}
export type ButtonInputOptions = {
	haptic: Value<boolean>?,
	repeatDelay: number?,
	repeatInterval: number?,
	shortcut: Shortcut?,
	dialogAction: ("default" | "cancel")?,
	onPointerDown: ((InputObject) -> ())?,
	onPointerUp: ((InputObject) -> ())?,
	onPointerCancel: (() -> ())?,
}
export type ButtonProps = Shared.TextButtonProps & ButtonVisualOptions & ButtonInputOptions & {
	selected: Value<boolean>?,
	onActivate: ((InputObject?, number?) -> ())?,
}
export type ToggleImplementationProps = Shared.TextButtonProps & ButtonVisualOptions & ButtonInputOptions & {
	value: Value<boolean>,
	onChange: ((boolean) -> ())?,
	presentation: ("switch" | "checkbox" | "button")?,
	mixed: Value<boolean>?,
	indicatorPosition: ("leading" | "trailing")?,
}
export type ToggleProps = ToggleImplementationProps & ValueBinding<boolean>
export type TextCommitReason = "submit" | "focusLost"
export type CommitReason = TextCommitReason | "clamped"
export type ClearButtonMode = "never" | "always" | "whileEditing" | "unlessEditing"
export type SelectOnFocus = "none" | "all" | "end"
export type FieldAppearance = "standard" | "contrast" | "utility"
export type TextValue = Value<string>
export type NumberValue = Value<number>
export type TextBinding = ValueBinding<string>
export type NumberCell = ComposeTypes.Cell<number>
export type FlagValue = Value<boolean>
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
	step: Value<number>?,
	format: ((number) -> string)?,
}
export type NumberInputOptions = ValueOptions & {
	enabled: Value<boolean>?,
	label: Value<string>?,
}
export type StepperImplementationProps =
	Shared.FrameProps
	& NumberInputOptions
	& { value: Value<number>, onChange: ((number) -> ())? }
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
}
export type SliderImplementationProps = Shared.FrameProps & ValueOptions & SliderOptions & {
	enabled: Value<boolean>?,
	label: Value<string>?,
	value: Value<number> | RangeValue,
	onChange: ((any, SliderChange?) -> ())?,
}
export type RangeValue = Value<SliderRange>
export type SliderBinding =
	{ range: false?, value: ComposeTypes.Cell<number>, onChange: ((number) -> ())?, onCommit: ((number) -> ())? }
	| { range: false?, value: Value<number>, onChange: (number) -> (), onCommit: ((number) -> ())? }
	| {
		range: true,
		value: RangeValue,
		onChange: ((SliderRange, SliderChange) -> ())?,
		onCommit: ((SliderRange, SliderChange) -> ())?,
	}
export type SliderProps = Shared.FrameProps & ValueOptions & SliderOptions & {
	enabled: Value<boolean>?,
	label: Value<string>?,
} & SliderBinding
export type LevelSize = "small" | "medium" | "large"
export type Glyphs = { filled: string, empty: string }
export type Images = { filled: string, empty: string }
export type Tint = { filled: Value<Color3>?, empty: Value<Color3>? }
export type LevelBinding =
	{ value: ComposeTypes.Cell<number>, onChange: ((number) -> ())?, readOnly: boolean? }
	| { value: Value<number>, onChange: (number) -> (), readOnly: boolean? }
	| { value: Value<number>, readOnly: true, onChange: ((number) -> ())? }
export type LevelOptions = {
	count: number?,
	allowZero: boolean?,
	readOnly: boolean?,
	enabled: Value<boolean>?,
}
export type RatingImplementationProps = Shared.TextButtonProps & LevelOptions & {
	value: Value<number>,
	onChange: ((number) -> ())?,
	glyphs: Glyphs?,
	starSize: LevelSize?,
}
export type RatingProps = Shared.TextButtonProps & {
	count: number?,
	allowZero: boolean?,
	enabled: Value<boolean>?,
	glyphs: Glyphs?,
	starSize: LevelSize?,
} & LevelBinding
export type LevelPickerImplementationProps = Shared.TextButtonProps & LevelOptions & {
	value: Value<number>,
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
	enabled: Value<boolean>?,
	segment: ("bar" | "glyph" | "image")?,
	segmentSize: LevelSize?,
	glyphs: Glyphs?,
	images: Images?,
	tint: Tint?,
} & LevelBinding
export type ChipSelection =
	{ selected: ComposeTypes.Cell<boolean>, onToggle: ((boolean) -> ())? }
	| { selected: Value<boolean>, onToggle: (boolean) -> () }
	| { selected: nil?, onToggle: nil?, onRemove: () -> () }
export type ChipImplementationProps = Shared.TextButtonNativeProps & ButtonVisualOptions & ButtonInputOptions & {
	ref: ((TextButton | Frame) -> ())?,
	selected: Value<boolean>?,
	onToggle: ((boolean) -> ())?,
	onRemove: (() -> ())?,
	editing: FlagValue?,
	removeLabel: Value<string>?,
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
	separator: Value<string>?,
	controlSize: Value<Shared.ControlSize>?,
}
export type ShortcutHintProps = ShortcutHintImplementationProps & ShortcutHintSource
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
