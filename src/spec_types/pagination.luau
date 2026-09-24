--!strict
-- The `pagination` control's types, apart from its implementation: reading a type
-- must not load the control.
local blueprint = require("../blueprint")
local publicEnv = require("../env/environment")

export type Spec = {
	id: string?,
	page: blueprint.Bound<number>, -- required; the caller's accepted page
	onChange: (nextPage: number) -> (), -- required; a proposal, never a write
	pageCount: blueprint.Bound<number?>?, -- absent = an unknown count
	hasNext: blueprint.Bound<boolean>?, -- unknown count only (default false)
	hasPrevious: blueprint.Bound<boolean>?, -- unknown count only (default false)
	siblingCount: number?, -- construction-only, 0..20, default 1
	boundaryCount: number?, -- construction-only, 0..20, default 1
	showFirstLast: boolean?, -- construction-only, default false
	form: ("numbers" | "arrows" | "label")?, -- construction-only, default numbers
	direction: ("ltr" | "rtl")?, -- construction-only, default ltr
	controlSize: blueprint.Bound<("compact" | "regular" | "large")?>?,
	enabled: blueprint.Bound<boolean>?,
	width: blueprint.Bound<blueprint.Dim>?,
	env: publicEnv.Env?,
}

return nil
