--!strict
local Shared = require("./types")

type Value<T> = Shared.Value<T>
export type Mode = "swatches" | "spectrum" | "sliders" | "brick"
export type Style = "automatic" | "inline"
export type DismissReason = "activate" | "outside" | "cancel" | "anchorLost" | "apply"
export type Swatch = Color3 | { color: Color3, label: string? }
export type SwatchItem = { color: Color3, label: string?, key: string }
export type ColorValue = Value<Color3?>
export type NumberValue = Value<number>
export type FlagValue = Value<boolean>
export type WordsValue = Value<string>
export type SizeValue = Value<Shared.ControlSize>
export type SwatchesValue = Value<{ Swatch }>
export type ColorPickerOptions = {
	value: ColorValue,
	onChange: ((color: Color3) -> ())?,
	onCommit: ((color: Color3) -> ())?,
	alpha: NumberValue?,
	onAlphaChange: ((alpha: number) -> ())?,
	allowEmpty: boolean?,
	placeholder: string?,
	modes: { Mode }?,
	swatches: SwatchesValue?,
	onSaveSwatch: ((color: Color3) -> ())?,
	onRemoveSwatch: ((item: SwatchItem) -> ())?,
	style: Style?,
	draft: boolean?,
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
export type ColorPickerProps = Shared.FrameProps & ColorPickerOptions
export type ColorPickerControls = {
	ColorPicker: Shared.Constructor<ColorPickerProps, Frame>,
}

return {}
