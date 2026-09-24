--!strict
-- The `step_indicator` control's types, apart from its implementation: reading a
-- type must not load the control.
local blueprint = require("../blueprint")
local publicEnv = require("../env/environment")

export type Step = {
	id: string, -- nonempty and unique; labels may repeat
	label: string, -- nonempty
	description: string?,
	-- absent derives current or upcoming from `current`; "current" must agree with it
	state: ("complete" | "current" | "upcoming" | "error")?,
	navigable: boolean?, -- default false
	enabled: boolean?, -- default true
}

export type Spec = {
	id: string?,
	steps: blueprint.Bound<{ Step }>, -- required
	current: blueprint.Bound<string?>, -- the sole current step id; nil = unavailable
	onSelect: ((id: string) -> ())?, -- a proposal for a navigable, enabled step
	sizing: ("fill" | "hug")?, -- construction-only, default fill
	listLabel: string?, -- the summary's list button, default "Steps"
	controlSize: blueprint.Bound<("compact" | "regular" | "large")?>?,
	enabled: blueprint.Bound<boolean>?,
	env: publicEnv.Env?,
}

return nil
