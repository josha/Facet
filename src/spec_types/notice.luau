--!strict
-- The `notice` control's types, apart from its implementation: reading a type must
-- not load the control.
local blueprint = require("../blueprint")
local publicEnv = require("../env/environment")
local overlayParts = require("./overlay_parts")

export type Action = overlayParts.Action

export type Spec = {
	id: string?,
	message: blueprint.Bound<string>, -- required
	title: blueprint.Bound<string>?,
	severity: ("info" | "success" | "warning" | "error")?, -- default info
	appearance: ("standard" | "emphasis")?, -- default standard
	-- inline (default): ordinary flow. affixed: fills the caller's safe root top
	-- and publishes its measured rect through presenter.reserveHud
	placement: ("inline" | "affixed")?,
	-- true (default): the severity's status icon; false: no artwork; a string:
	-- an explicit icon name or image source
	icon: (boolean | string)?,
	link: { label: blueprint.Bound<string>, onActivate: () -> () }?,
	actions: { Action }?, -- at most two; roles paint only
	-- its presence draws the close button; it reports the press, the caller unmounts
	onDismiss: (() -> ())?,
	controlSize: blueprint.Bound<("xsmall" | "compact" | "regular" | "large")?>?,
	env: publicEnv.Env?,
}

return nil
