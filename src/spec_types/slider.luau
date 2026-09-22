--!strict
-- The `slider` control's types, apart from its implementation: reading a type must
-- not load the control.
local coreContract = require("../core/contract")
local blueprint = require("../blueprint")
export type NumberCell = coreContract.Cell<number>
-- the two-number value a `range` Slider carries
export type Range = { lower: number, upper: number }
export type RangeCell = coreContract.Cell<Range>
-- which thumb moved: the optional second callback argument of a range Slider
export type ChangeInfo = { thumb: "lower" | "upper" }
-- what `thumbContent` is told, once per thumb: readables only
export type ThumbInfo = {
	thumb: "value" | "lower" | "upper",
	value: coreContract.Readable<number>,
	fraction: coreContract.Readable<number>,
	dragging: coreContract.Readable<boolean>,
	enabled: coreContract.Readable<boolean>,
}
export type Spec<V = NumberCell> = {
	row: { description: blueprint.Bound<string>?, icon: blueprint.Bound<string>? }?,
	id: string?,
	label: blueprint.Bound<string>?,
	value: V, -- the caller's writable cell: a number, or a Range with `range = true`
	min: number,
	max: number,
	-- nil = continuous. A Readable<number> or a `function(use)` drives the grid
	-- live, so a setting beside the slider can change the step it snaps to.
	step: (number | any)?,
	format: ((value: number) -> string)?,
	enabled: blueprint.Bound<boolean>?, -- boolean | Readable<boolean>
	tapToPosition: boolean?, -- default true
	-- the scalar form reports a number; the range form a Range plus ChangeInfo
	onChange: ((value: any, info: ChangeInfo?) -> ())?,
	onCommit: ((value: any, info: ChangeInfo?) -> ())?,
	-- construction-only shape words
	axis: ("x" | "y")?, -- "y" runs bottom to top; the arrows follow this axis
	range: boolean?, -- two thumbs over one track; `value` holds a Range
	minGap: number?, -- least distance between the thumbs, in value units
	thumb: ("always" | "auto" | "none")?, -- when the handle is painted
	thumbContent: ((info: ThumbInfo) -> any)?, -- the caller's knob, once per thumb
	rotation: blueprint.Bound<number>?, -- paint-only degrees about the track's centre
	controlSize: blueprint.Bound<("compact" | "regular" | "large")?>?,
	thumbImage: (string | { [string]: any })?,
	trackImage: (string | { [string]: any })?,
}
return nil
