--!strict
-- The `progress_view` control's types, apart from its implementation: reading a type must
-- not load the control.
local coreContract = require("../core/contract")
local blueprint = require("../blueprint")
export type Spec = {
	segments: number?,
	trail: { delay: number?, duration: number? }?,
	diameter: (number | string)?,
	id: string?,
	value: blueprint.Bound<number>?, -- number | Readable<number> | nil
	label: string?,
	min: number?, -- default 0
	max: number?, -- default 1
	format: ((value: number) -> string)?,
	endLabel: blueprint.Bound<string>?,
	-- a ring's/spinner's size, or a bar's track thickness (small rungs thin)
	controlSize: blueprint.Bound<"xsmall" | "compact" | "regular" | "large" | nil>?,
	showValue: boolean?, -- the formatted value beside a bar; on a ring needs diameter or controlSize "large"
	height: number?, -- the BAR's track thickness (or controlSize, not both); refused for a spinner
	presentation: string?, -- "bar" (default) | "spinner" (indeterminate only)
	scope: coreContract.Owner?,
	motionClock: any?,
}
export type Capability = {
	indeterminate: boolean,
	determinate: boolean,
	hasTrack: boolean,
	valueLabel: boolean,
	sizeMetric: string?,
	modeAlt: string?,
	valueLabelAlt: string?,
}
return nil
