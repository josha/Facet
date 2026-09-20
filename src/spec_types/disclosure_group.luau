--!strict
-- The `disclosure_group` control's types, apart from its implementation: reading a type must
-- not load the control.
local coreContract = require("../core/contract")
local blueprint = require("../blueprint")
export type BooleanCell = coreContract.Cell<boolean>
export type Spec<V = BooleanCell> = {
	id: string?,
	label: string, -- required: the header IS the control
	expanded: V, -- the caller's writable cell of a boolean
	content: () -> blueprint.Blueprint, -- () -> Blueprint, mounted only while expanded
	enabled: blueprint.Bound<boolean>?,
	onToggle: ((expanded: boolean) -> ())?,
	presenter: any?,
}
return nil
