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
	running: Shared.Readable<boolean>,
	completed: Shared.Readable<boolean>,
}
export type FlashProps = Shared.FrameProps & {
	target: Shared.Value<GuiObject>,
	progress: Shared.Value<number>,
	color: Shared.Value<Color3>?,
	mode: ("pulse" | "sweep")?,
}
export type Controls = {
	sequence: (SequenceSpec) -> Sequence,
	countUp: (Shared.Value<number>) -> Shared.Readable<number>,
	Flash: Shared.Constructor<FlashProps, Frame>,
}
return {}
