--!strict
local Compose = require("../vendor/compose/core")
local Shared = require("./types")

type Value<T> = Shared.Value<T>
type Constructor<P, N> = Shared.Constructor<P, N>

export type ValueBinding<T> =
	{ value: Compose.Cell<T>, onChange: ((T) -> ())? }
	| { value: Value<T>, onChange: (T) -> () }
export type EnabledOptions = { enabled: Value<boolean>?, disabled: Value<boolean>?, busy: Value<boolean>? }
export type Row = { title: Value<string>?, description: Value<string>? }
export type Shortcut = { keyCode: string, modifiers: { shift: boolean? }? }
export type ButtonRole = "default" | "cancel" | "destructive" | "onIndicator"
export type ButtonVisualOptions = EnabledOptions & {
	label: Value<string>?,
	name: Value<string>?,
	compactLabel: Value<string>?,
	pop: boolean?,
	appearance: Value<string>?,
	controlSize: Value<Shared.ControlSize>?,
	corners: ("pill" | "square")?,
	shape: ("rect" | "circle")?,
	role: Value<ButtonRole>?,
	icon: Value<string>?,
	trailingIcon: Value<string>?,
	image: Value<string>?,
	imageAspectRatio: number?,
	imageFraming: ("fit" | "crop")?,
	subtitle: Value<string>?,
	hint: Value<string>?,
	row: Row?,
}
export type ButtonInputOptions = {
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
export type CommitReason = "submit" | "focusLost"
export type ClearButtonMode = "never" | "always" | "whileEditing" | "unlessEditing"
export type TextInputOptions = {
	enabled: Value<boolean>?,
	disabled: Value<boolean>?,
	placeholder: Value<string>?,
	multiline: boolean?,
	validate: ((string) -> string?)?,
	maxLength: number?,
	invalid: Compose.Readable<boolean>?,
	clearButton: boolean?,
	clearButtonMode: ClearButtonMode?,
	onCommit: ((string, CommitReason) -> ())?,
	onCancel: (() -> ())?,
	min: number?,
	max: number?,
	parse: ((string) -> number?)?,
	format: ((number) -> string)?,
}
export type TextInputPresentation =
	{ presentation: ("plain" | "search")?, numericValue: nil? }
	| { presentation: "number", numericValue: Compose.Cell<number> }
export type TextInputImplementationProps = Shared.TextBoxProps & TextInputOptions & {
	value: Value<string>,
	onChange: ((string) -> ())?,
	presentation: ("plain" | "search" | "number")?,
	numericValue: Compose.Cell<number>?,
}
export type TextInputProps = TextInputImplementationProps & ValueBinding<string> & TextInputPresentation
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
export type SliderImplementationProps = StepperImplementationProps & {
	onCommit: ((number) -> ())?,
	tapToPosition: boolean?,
	thumbImage: Value<string>?,
	trackImage: Value<string>?,
	row: Row?,
}
export type SliderProps = SliderImplementationProps & ValueBinding<number>
export type LevelSize = "small" | "medium" | "large"
export type Glyphs = { filled: string, empty: string }
export type Images = { filled: string, empty: string }
export type Tint = { filled: Value<Color3>?, empty: Value<Color3>? }
export type LevelBinding =
	{ value: Compose.Cell<number>, onChange: ((number) -> ())?, readOnly: boolean? }
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
	{ selected: Compose.Cell<boolean>, onToggle: ((boolean) -> ())? }
	| { selected: Value<boolean>, onToggle: (boolean) -> () }
	| { selected: nil?, onToggle: nil?, onRemove: () -> () }
export type ChipImplementationProps = Shared.TextButtonNativeProps & ButtonVisualOptions & ButtonInputOptions & {
	ref: ((TextButton | Frame) -> ())?,
	selected: Value<boolean>?,
	onToggle: ((boolean) -> ())?,
	onRemove: (() -> ())?,
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
	TextInput: Constructor<TextInputProps, TextBox>,
	Stepper: Constructor<StepperProps, Frame>,
	Slider: Constructor<SliderProps, Frame>,
	Rating: Constructor<RatingProps, TextButton>,
	LevelPicker: Constructor<LevelPickerProps, TextButton>,
	Chip: Constructor<ChipProps, TextButton | Frame>,
	ShortcutHint: Constructor<ShortcutHintProps, TextLabel | Frame>,
}

return {}
