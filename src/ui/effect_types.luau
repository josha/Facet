--!strict
local Shared = require("./types")
export type SequenceStep = {
	delay: string?,
	duration: string?,
	easing: string?,
	parallel: { SequenceStep }?,
	onStart: (() -> ())?,
	sample: ((number) -> ())?,
	onEnd: (() -> ())?,
}
export type SequenceSpec = { steps: { SequenceStep }, onCompleted: (() -> ())? }
export type Sequence = {
	play: () -> (),
	cancel: () -> (),
	finish: () -> (),
	running: Shared.ReadOnlyValue<boolean>,
	completed: Shared.ReadOnlyValue<boolean>,
}
export type FlashOptions = {
	target: Shared.GuiInstance | Shared.Input<GuiObject>,
	progress: Shared.Input<number>,
	color: Shared.Input<Color3>?,
	mode: ("pulse" | "sweep")?,
}
export type ShakeOptions = { intensity: number? }
export type Controls = {
	sequence: (SequenceSpec) -> Sequence,
	countUp: (Shared.Input<number>) -> Shared.ReadOnlyValue<number>,
	follow: <T>(Shared.ReadOnlyValue<T> | (Shared.Use) -> T, string) -> Shared.ReadOnlyValue<T>,
	toward: (Shared.Value<number>, number) -> (number) -> (),
	shake: (Shared.Input<{ GuiObject }>, ShakeOptions?) -> Sequence,
}
return {}
