--!strict
-- The `dialog` control's types, apart from its implementation: reading a type must
-- not load the control.
local blueprint = require("../blueprint")
local publicEnv = require("../env/environment")
local overlayParts = require("./overlay_parts")

export type Media = overlayParts.Media
export type Action = overlayParts.Action

-- why a presentation ended, as `onDismiss` reports it
export type DismissReason = "close" | "outside" | "cancel" | "action"

export type Spec = {
	id: string?,
	-- the CALLER'S accepted fact; the dialog renders it and never writes it
	isPresented: blueprint.Bound<boolean>,
	-- a proposal; required while `closeButton` is true (the default)
	onPresentedChange: ((next: boolean) -> ())?,
	-- an actual closure, once, after its cleanup
	onDismiss: ((reason: DismissReason) -> ())?,
	title: blueprint.Bound<string>?,
	content: (() -> blueprint.Blueprint)?, -- one body, scrolled between pinned regions
	hero: Media?, -- construction-only
	actionLabel: blueprint.Bound<string>?, -- wraps above the pinned actions
	actions: { Action }?, -- no invented OK button when absent
	actionLayout: ("automatic" | "row" | "stacked")?,
	closeButton: boolean?, -- default true
	width: ("automatic" | "narrow" | "wide")?,
	-- default true: an overflowing plain body is one focus stop that scrolls
	contentSelectable: boolean?,
	env: publicEnv.Env?,
}

return nil
