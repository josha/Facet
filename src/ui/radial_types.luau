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
export type ContentFit = "both" | "radial" | "angular" | "none"
export type CompassSlot = "N" | "NE" | "E" | "SE" | "S" | "SW" | "W" | "NW"
export type AnchorPoint = { x: number, y: number, visible: boolean?, clearance: number? }
export type Anchor = GuiObject | AnchorPoint
export type SkinImages = { default: string?, pressed: string?, hover: string?, selected: string? }
export type RadialItemBase<V> = {
	id: string,
	label: Types.Value<string>,
	description: Types.Value<string>?,
	icon: Types.Value<string>?,
	compactLabel: { prefer: boolean?, icon: Types.Value<string>? }?,
	labelStyle: ("icon" | "text")?,
	slot: CompassSlot?,
	enabled: Types.Value<boolean>?,
	hidden: Types.Value<boolean>?,
	completion: Completion?,
	navigation: Navigation?,
	expansion: Expansion?,
	dismiss: boolean?,
	children: Types.Value<{ RadialItem<V> }>?,
	onSelect: (() -> ())?,
}
export type RadialItem<V = string> =
	(
		RadialItemBase<V>
		& { checked: ComposeTypes.Cell<boolean>, selected: nil?, value: nil?, onChange: ((boolean) -> ())? }
	)
	| (RadialItemBase<V> & { checked: nil?, selected: ComposeTypes.Cell<V>, value: V, onChange: ((V) -> ())? })
	| (RadialItemBase<V> & { checked: nil?, selected: nil?, value: nil?, onChange: nil? })
export type RadialMenuSpec<V = string> = Types.FrameProps & {
	items: Types.Value<{ RadialItem<V> }>,
	label: Types.Value<string>?,
	icon: Types.Value<string>?,
	launcher: boolean?,
	preset: Preset?,
	appearance: Appearance?,
	buttonSurface: ("native" | "none")?,
	distribution: Distribution?,
	navigation: Navigation?,
	expansion: Expansion?,
	center: Center?,
	centerLabel: Types.Value<string>?,
	centerContent: GuiObject | (() -> GuiObject)?,
	centerPassThrough: boolean?,
	completion: Completion?,
	anchor: Types.Value<Anchor>?,
	follow: Follow?,
	clearance: Types.Value<number>?,
	ringWidth: Types.Value<number>?,
	contentFit: ContentFit?,
	gestureSelection: ("bounded" | "direction")?,
	enabled: Types.Value<boolean>?,
	holdAction: InputAction?,
	skin: { item: SkinImages?, center: SkinImages?, launcher: SkinImages?, background: SkinImages? }?,
	onOpen: (() -> ())?,
	onClose: (() -> ())?,
	isPresented: ComposeTypes.Cell<boolean>?,
	transition: boolean?,
}
export type RadialMenuBuilder = <V>(RadialMenuSpec<V>) -> Frame
export type RadialMenuConstructor = RadialMenuBuilder & ((string) -> RadialMenuBuilder)
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
