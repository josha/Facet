--!strict
-- The `snackbar` control's types, apart from its implementation: reading a type
-- must not load the control.
local blueprint = require("../blueprint")

-- why an accepted presentation ended, as `onDismiss` reports it
export type DismissReason = "action" | "close" | "timeout" | "superseded" | "cancel"

export type Action = {
	label: blueprint.Bound<string>,
	onActivate: () -> (),
}

export type Spec = {
	id: string?,
	-- the CALLER'S accepted fact; the snackbar reads it and never writes it
	isPresented: blueprint.Bound<boolean>,
	message: blueprint.Bound<string>,
	-- construction-only: a semantic icon name or an explicit image source
	icon: string?,
	action: Action?,
	closeButton: boolean?, -- construction-only, default true
	-- a proposal; required while closeButton is true or a duration is set
	onPresentedChange: ((next: boolean) -> ())?,
	onDismiss: ((reason: DismissReason) -> ())?,
	-- construction-only: nil is persistent; otherwise positive finite seconds
	-- of READABLE time, never below the 2.5 s floor
	duration: number?,
	priority: number?, -- construction-only, default 0; higher goes first
}

return nil
