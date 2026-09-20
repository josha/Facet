--!strict
-- The `navigation_stack` control's types, apart from its implementation: reading a type must
-- not load the control.
local Compose = require("../vendor/compose/core")
local blueprintLib = require("../blueprint")
local environment = require("../env/environment")
export type Entry = { id: string, value: any? }
export type Destination = {
	title: blueprintLib.Bound<string>?,
	content: (owner: Compose.Owner, entry: Entry?) -> blueprintLib.Blueprint,
}
export type Spec = {
	id: string?,
	path: Compose.Cell<{ Entry }>,
	root: Destination,
	destinations: { [string]: Destination },
	backLabel: string,
	env: environment.Env?,
	transition: blueprintLib.TransitionSpec?,
}
return nil
