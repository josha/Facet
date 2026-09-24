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
	description: blueprint.Bound<string>?,
	icon: string?,
	chevronPosition: ("leading" | "trailing")?,
	-- "outline": a tree row — no header plate and no expanded wash
	appearance: ("plain" | "contained" | "divided" | "outline")?,
	textSize: (string | number)?, -- the header's type role; default "control"
	indent: (string | number)?, -- the content's leading inset: a space step or px
	controlSize: blueprint.Bound<"xsmall" | "compact" | "regular" | "large" | nil>?,
}
return nil
