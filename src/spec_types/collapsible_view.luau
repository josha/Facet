--!strict
-- The `collapsible_view` control's types, apart from its implementation: reading a type must
-- not load the control.
local coreContract = require("../core/contract")
local blueprint = require("../blueprint")
export type BooleanCell = coreContract.Cell<boolean>
export type Spec<V = BooleanCell> = {
	id: string?,
	label: blueprint.Bound<string>,
	icon: blueprint.Bound<string>?,
	image: blueprint.Bound<string>?,
	content: blueprint.Blueprint | (() -> any),
	expanded: V,
	env: any?,
	width: blueprint.Bound<blueprint.Dim>?,
	initialFocus: string?,
	dismissButton: string?,
	enabled: blueprint.Bound<boolean>?,
}
return nil
