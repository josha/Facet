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
	showValue: boolean?, -- render the formatted value beside the bar
	height: number?, -- the BAR's track thickness; refused for a spinner
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
