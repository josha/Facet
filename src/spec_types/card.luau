--!strict
-- The `card` control's types, apart from its implementation: reading a type must
-- not load the control.
local blueprint = require("../blueprint")
local menuTypes = require("./menu")
local publicEnv = require("../env/environment")

export type PrimaryAction = {
	label: blueprint.Bound<string>,
	icon: string?, -- semantic icon name, construction-only
	onActivate: () -> (),
	enabled: blueprint.Bound<boolean>?,
	busy: blueprint.Bound<boolean>?,
}

export type Spec = {
	id: string?,
	image: blueprint.Bound<string>, -- required, nonempty
	title: blueprint.Bound<string>, -- required, nonempty
	caption: blueprint.Bound<string>?, -- may be empty
	imageAspectRatio: number?, -- construction-only, positive finite (default 16:9)
	imageFraming: any?, -- the Button image framing contract
	-- the body's one activation; absent, the body is informational
	onActivate: (() -> ())?,
	primaryAction: PrimaryAction?,
	-- the More menu; `label` is its semantic name (default "More")
	menu: { items: { menuTypes.Item }, label: string? }?,
	reveal: ("automatic" | "always")?, -- construction-only, default automatic
	-- the external browse stop that counts as engagement: returns its current
	-- focus path (a VirtualGrid cell's Hit), or nil while it has none
	browseTarget: (() -> string?)?,
	enabled: blueprint.Bound<boolean>?,
	width: blueprint.Bound<blueprint.Dim>?,
	env: publicEnv.Env?,
}

return nil
