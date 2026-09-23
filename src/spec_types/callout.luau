--!strict
-- The `callout` control's types, apart from its implementation: reading a type must
-- not load the control.
local blueprint = require("../blueprint")
local overlayParts = require("./overlay_parts")
export type Media = overlayParts.Media
export type Action = overlayParts.Action
export type Spec = {
	id: string?,
	isPresented: blueprint.Bound<boolean>?,
	anchor: blueprint.Blueprint, -- Blueprint, required: the node the plate points at
	-- optional when title, media, steps or actions draw something
	content: (blueprint.Blueprint | (() -> blueprint.Blueprint))?,
	dismissLabel: string?,
	title: blueprint.Bound<string>?,
	media: Media?, -- construction-only
	steps: { index: number, count: number }?,
	actions: { Action }?, -- at most two; they replace the bottom dismiss
	closeButton: boolean?, -- a top close affordance (default false)
	edge: string?,
	align: string?,
	tail: boolean?,
	priority: number?,
	-- the CALLER'S state, read and never written (see the header)
	seen: blueprint.Bound<boolean>?, -- boolean | Readable<boolean>
	sessions: blueprint.Bound<number>?, -- number | Readable<number>
	afterSessions: number?,
	featureUsed: blueprint.Bound<boolean>?, -- boolean | Readable<boolean>
	-- required: the ONLY thing this construct reports back
	onRetire: (reason: string) -> (),
	onShow: (() -> ())?,
	onHide: ((reason: string) -> ())?,
}
return nil
