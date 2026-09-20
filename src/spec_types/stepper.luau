--!strict
-- The `stepper` control's types, apart from its implementation: reading a type must
-- not load the control.
local coreContract = require("../core/contract")
local blueprint = require("../blueprint")
export type NumberCell = coreContract.Cell<number>
export type Spec<V = NumberCell> = {
	id: string?,
	label: string?,
	value: V, -- the caller's writable cell of a number
	min: number,
	max: number,
	step: number?, -- defaults to 1 (a Stepper is discrete by definition)
	format: ((value: number) -> string)?,
	enabled: blueprint.Bound<boolean>?, -- boolean | Readable<boolean>
	onChange: ((value: number) -> ())?,
}
return nil
