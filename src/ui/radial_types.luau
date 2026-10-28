--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./engine_types")
local Shapes = require("./nav_path_shapes")

export type Appearance = "wedges" | "buttons"
export type Preset = "donut" | "top-left" | "top-right" | "bottom-left" | "bottom-right"
export type Distribution = "even" | "compass"
export type Navigation = "replace" | "expand"
export type Expansion = "fan" | "ring"
export type Center = "back" | "root" | "close" | "content" | "empty"
export type Completion = "close" | "back" | "root" | "stay"
export type Follow = "idle" | "always" | "fixed"
export type RingWidth = "narrow" | "regular" | "wide"
export type ContentFit = "both" | "radial" | "angular" | "none"
export type CompassSlot = "N" | "NE" | "E" | "SE" | "S" | "SW" | "W" | "NW"
export type AnchorPoint = { x: number, y: number, visible: boolean?, clearance: number? }
export type Anchor = GuiObject | AnchorPoint
export type SkinImages = { default: string?, pressed: string?, hover: string?, selected: string? }
export type RadialItemBase<V> = {
	id: string,
	label: Types.ValueString,
	description: Types.ValueString?,
	icon: Types.ValueString?,
	compactLabel: { prefer: boolean?, icon: Types.ValueString? }?,
	labelStyle: ("icon" | "text")?,
	slot: CompassSlot?,
	enabled: Types.ValueBoolean?,
	hidden: Types.ValueBoolean?,
	completion: Completion?,
	navigation: Navigation?,
	expansion: Expansion?,
	dismiss: boolean?,
	children: Types.Input<{ RadialItem<V> }>?,
	onSelect: (() -> ())?,
}
export type RadialCheck<V = string> = {
	id: string,
	label: Types.ValueString,
	description: Types.ValueString?,
	icon: Types.ValueString?,
	compactLabel: { prefer: boolean?, icon: Types.ValueString? }?,
	labelStyle: ("icon" | "text")?,
	slot: CompassSlot?,
	enabled: Types.ValueBoolean?,
	hidden: Types.ValueBoolean?,
	completion: Completion?,
	navigation: Navigation?,
	expansion: Expansion?,
	dismiss: boolean?,
	children: Types.Input<{ RadialItem<V> }>?,
	onSelect: (() -> ())?,
	checked: ComposeTypes.Value<boolean>,
	selected: nil?,
	value: nil?,
	onChange: ((boolean) -> ())?,
}
export type RadialChoice<V = string> = {
	id: string,
	label: Types.ValueString,
	description: Types.ValueString?,
	icon: Types.ValueString?,
	compactLabel: { prefer: boolean?, icon: Types.ValueString? }?,
	labelStyle: ("icon" | "text")?,
	slot: CompassSlot?,
	enabled: Types.ValueBoolean?,
	hidden: Types.ValueBoolean?,
	completion: Completion?,
	navigation: Navigation?,
	expansion: Expansion?,
	dismiss: boolean?,
	children: Types.Input<{ RadialItem<V> }>?,
	onSelect: (() -> ())?,
	checked: nil?,
	selected: ComposeTypes.Value<V>,
	value: V,
	onChange: ((V) -> ())?,
}
export type RadialAction<V = string> = {
	id: string,
	label: Types.ValueString,
	description: Types.ValueString?,
	icon: Types.ValueString?,
	compactLabel: { prefer: boolean?, icon: Types.ValueString? }?,
	labelStyle: ("icon" | "text")?,
	slot: CompassSlot?,
	enabled: Types.ValueBoolean?,
	hidden: Types.ValueBoolean?,
	completion: Completion?,
	navigation: Navigation?,
	expansion: Expansion?,
	dismiss: boolean?,
	children: Types.Input<{ RadialItem<V> }>?,
	onSelect: (() -> ())?,
	checked: nil?,
	selected: nil?,
	value: nil?,
	onChange: nil?,
}
export type RadialItem<V = string> = RadialCheck<V> | RadialChoice<V> | RadialAction<V>
export type RadialMenuOptions<V = string> = {
	items: Types.Input<{ RadialItem<V> }>,
	label: Types.ValueString?,
	icon: Types.ValueString?,
	launcher: boolean?,
	preset: Preset?,
	appearance: Appearance?,
	buttonSurface: ("native" | "none")?,
	distribution: Distribution?,
	navigation: Navigation?,
	expansion: Expansion?,
	center: Center?,
	centerLabel: Types.ValueString?,
	centerContent: GuiObject | (() -> GuiObject)?,
	centerPassThrough: boolean?,
	completion: Completion?,
	anchor: Types.Input<Anchor>?,
	follow: Follow?,
	clearance: Types.ValueNumber?,
	ringWidth: Types.Input<number | RingWidth>?,
	iconSize: Types.ValueNumber?,
	contentFit: ContentFit?,
	gestureSelection: ("bounded" | "direction")?,
	enabled: Types.ValueBoolean?,
	holdAction: InputAction?,
	skin: { item: SkinImages?, center: SkinImages?, launcher: SkinImages?, background: SkinImages? }?,
	onOpen: (() -> ())?,
	onClose: (() -> ())?,
	isPresented: ComposeTypes.Value<boolean>?,
	transition: boolean?,
	scrim: ("dark" | "light" | "none")?,
}
export type SectorShape = {
	angle: number,
	span: number,
	inner: number,
	outer: number,
	x: number,
	y: number,
	size: number,
	gap: number?,
}
export type Sector<V = string> = {
	angle: number,
	span: number,
	inner: number,
	outer: number,
	x: number,
	y: number,
	size: number,
	gap: number?,
	id: string,
	item: RadialItem<V>,
	path: { string },
	key: string,
	index: number,
	list: boolean,
	-- True when another item on the same level shows the same icon, so the
	-- icon does not tell the items apart and cannot stand in for the label.
	sharedIcon: boolean?,
}
export type Layout<V = string> = { sectors: { Sector<V> }, list: boolean, inner: number, path: { string } }
export type Paint = {
	x: number,
	y: number,
	w: number,
	h: number,
	points: { Shapes.PathPoint },
	outline: { Shapes.PathPoint },
}
return {}
