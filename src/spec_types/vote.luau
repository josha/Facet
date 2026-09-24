--!strict
-- The `vote` control's types, apart from its implementation: reading a type must
-- not load the control.
local blueprint = require("../blueprint")
local publicEnv = require("../env/environment")

export type Value = "up" | "down" | "none"

export type Spec = {
	id: string?,
	value: blueprint.Bound<Value>, -- required; the caller's accepted vote
	-- required unless readOnly: a proposal ("none" when the chosen side is pressed)
	onChange: ((next: Value) -> ())?,
	summary: blueprint.Bound<string>?, -- the caller's aggregate, one line, disclosed
	readOnly: blueprint.Bound<boolean>?, -- informational: normal paint, nothing to press
	controlSize: blueprint.Bound<("xsmall" | "compact" | "regular" | "large")?>?,
	enabled: blueprint.Bound<boolean>?,
	env: publicEnv.Env?,
}

return nil
