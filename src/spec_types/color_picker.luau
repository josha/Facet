--!strict
-- The `color_picker` control's types, apart from its implementation: reading a type
-- must not load the control.
local blueprint = require("../blueprint")
local publicEnv = require("../env/environment")

-- a Color3. Spelled `any` because the standard-platform analyzer the public types
-- are checked under has no engine datatypes; the control refuses anything else.
export type Color = any
export type Swatch = Color | { color: Color, label: string? }
export type DismissReason = "activate" | "outside" | "cancel" | "anchorLost" | "apply"

export type Spec = {
	id: string?,
	value: blueprint.Bound<Color?>, -- the caller's colour; nil only with allowEmpty
	onChange: ((color: Color) -> ())?, -- a live proposal; required unless readOnly
	onCommit: ((color: Color) -> ())?, -- once per gesture, or on Apply with draft
	alpha: blueprint.Bound<number>?, -- 0..1; its presence mounts the opacity control
	onAlphaChange: ((alpha: number) -> ())?,
	allowEmpty: boolean?,
	placeholder: string?, -- the empty value's words
	-- construction-only: the techniques, in tab order, each of "swatches" |
	-- "spectrum" | "sliders" | "brick" (default the first three); refused at build
	modes: { string }?,
	swatches: blueprint.Bound<{ Swatch }>?, -- absent = a generated standard grid
	style: ("automatic" | "inline")?, -- construction-only; automatic = a well opening the panel
	draft: boolean?, -- Apply/Cancel; only Apply commits
	isPresented: blueprint.Bound<boolean>?, -- optional: the well owns its open state
	onPresentedChange: ((next: boolean) -> ())?,
	onDismiss: ((reason: DismissReason) -> ())?,
	enabled: blueprint.Bound<boolean>?,
	readOnly: blueprint.Bound<boolean>?,
	-- the shared field furniture
	label: blueprint.Bound<string>?,
	requiredMark: ("required" | "optional")?,
	hint: blueprint.Bound<string>?,
	errorText: blueprint.Bound<string>?,
	controlSize: blueprint.Bound<("compact" | "regular" | "large")?>?,
	appearance: blueprint.Bound<("standard" | "contrast" | "utility")?>?,
	corners: ("pill" | "square")?,
	env: publicEnv.Env?,
}

return nil
