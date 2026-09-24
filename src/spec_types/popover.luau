--!strict
-- The `popover` control's types, apart from its implementation: reading a type must
-- not load the control.
local blueprint = require("../blueprint")
local publicEnv = require("../env/environment")

export type Source = { path: string } | { rect: { x: number, y: number, w: number, h: number } }

-- why a presentation ended, as `onDismiss` reports it
export type DismissReason = "cancel" | "outside" | "trigger" | "anchorLost"

export type Spec = {
	id: string?,
	-- the CALLER'S accepted fact. The popover renders it and never writes it.
	isPresented: blueprint.Bound<boolean>,
	-- a proposal: the popover asks, the caller decides by changing its fact.
	-- Required for any interactive open or close (trigger, Cancel, outside tap).
	onPresentedChange: ((next: boolean) -> ())?,
	-- reports an actual closure once, after its cleanup
	onDismiss: ((reason: DismissReason) -> ())?,
	-- exactly one of: a caller-authored trigger blueprint, or a source
	trigger: blueprint.Blueprint?,
	source: Source?,
	-- a component factory; each presentation builds and owns its own content
	content: () -> blueprint.Blueprint,
	edge: ("top" | "bottom" | "leading" | "trailing")?,
	align: ("start" | "center" | "end")?,
	gap: (number | string)?,
	crossOffset: number?, -- px along the alignment axis (default 0)
	tail: boolean?, -- never drawn for a rect source
	maxWidth: number?, -- px, the whole panel including its chrome
	maxHeight: number?, -- px, the whole panel including its chrome; the body scrolls
	-- "sheet" (default): a compact touch screen presents it as a sheet;
	-- "popover": always the anchored panel
	compact: ("sheet" | "popover")?,
	env: publicEnv.Env?,
}

return nil
