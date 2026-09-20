--!strict
-- The `slider` control's types, apart from its implementation: reading a type must
-- not load the control.
local coreContract = require("../core/contract")
local blueprint = require("../blueprint")
export type NumberCell = coreContract.Cell<number>
export type Spec<V = NumberCell> = {
	row: { description: blueprint.Bound<string>?, icon: blueprint.Bound<string>? }?,
	id: string?,
	label: blueprint.Bound<string>?,
	value: V, -- the caller's writable cell of a number
	min: number,
	max: number,
	-- nil = continuous. A Readable<number> or a `function(use)` drives the grid
	-- live, so a setting beside the slider can change the step it snaps to.
	step: (number | any)?,
	format: ((value: number) -> string)?,
	enabled: blueprint.Bound<boolean>?, -- boolean | Readable<boolean>
	tapToPosition: boolean?, -- default true
	onChange: ((value: number) -> ())?,
	onCommit: ((value: number) -> ())?,
	thumbImage: (string | { [string]: any })?,
	trackImage: (string | { [string]: any })?,
}
return nil
