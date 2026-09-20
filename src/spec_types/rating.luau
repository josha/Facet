--!strict
-- The `rating` control's types, apart from its implementation: reading a type must
-- not load the control.
local coreContract = require("../core/contract")
local blueprint = require("../blueprint")
export type NumberCell = coreContract.Cell<number>
export type Spec<V = NumberCell> = {
	id: string?,
	value: V, -- the caller's writable cell of a number
	count: number?, -- how many glyphs; default 5
	allowZero: boolean?,
	enabled: blueprint.Bound<boolean>?, -- boolean | Readable<boolean>
	readOnly: boolean?,
	glyphs: { filled: string, empty: string }?,
	starSize: ("small" | "medium" | "large")?,
	env: any?,
	onChange: ((value: number) -> ())?,
}
return nil
