--!strict
-- The `label` control's types, apart from its implementation: reading a type must
-- not load the control.
local blueprint = require("../blueprint")
export type Spec = {
	id: string?,
	title: blueprint.Bound<string>, -- required: the current nonempty semantic text
	icon: string?, -- semantic name or asset URL; absent => title-only, no empty slot
	presentation: string?, -- "titleAndIcon" (default) | "titleOnly" | "iconOnly"
	-- each accepts a literal number (theme-independent) or a theme metric name
	iconSize: (number | string)?,
	textSize: (number | string)?,
	gap: (number | string)?,
}
return nil
