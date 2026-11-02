--!strict
local Shared = require("./types")

type Input<T> = Shared.Input<T>
export type Mode = "swatches" | "spectrum" | "sliders" | "brick"
export type Style = "automatic" | "inline"
export type DismissReason = "activate" | "outside" | "cancel" | "anchorLost" | "apply"
export type Swatch = Color3 | { read color: Color3, read label: string? }
export type SwatchItem = { color: Color3, label: string?, key: string }
export type ColorValue = Input<Color3?>
export type NumberValue = Shared.ValueNumber
export type FlagValue = Shared.ValueBoolean
export type WordsValue = Shared.ValueString
export type SizeValue = Input<Shared.ControlSize?>
export type SwatchesValue = Input<{ Swatch }>
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

return {}
