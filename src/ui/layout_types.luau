--!strict
local Types = require("./types")
local Engine = require("./engine_types")

export type SpaceStep = Types.SpaceStep
export type Space = Types.Space
export type Sides = Types.Sides
export type Padding = Types.Padding
export type Extent = Types.Extent
export type Align = Types.Align
export type Distribute = Types.Distribute
export type Edge = Types.Edge
export type Axis = "x" | "y" | "xy"
export type StackOptions = {
	padding: Types.Value<Padding>?,
	width: Types.Value<Extent>?,
	maxWidth: Types.ValueNumber?,
	height: Types.Value<Extent>?,
	gap: Types.Value<Space>?,
	align: Types.Value<Align>?,
	distribute: Types.Value<Distribute>?,
	wrap: Types.ValueBoolean?,
}
export type ScreenOptions = {
	chrome: ("device" | "band" | "edge")?,
	padding: Types.Value<Padding>?,
	width: Types.Value<Extent>?,
	maxWidth: Types.ValueNumber?,
	height: Types.Value<Extent>?,
	gap: Types.Value<Space>?,
	align: Types.Value<Align>?,
	distribute: Types.Value<Distribute>?,
}
export type ZStackOptions = {
	padding: Types.Value<Padding>?,
	width: Types.Value<Extent>?,
	maxWidth: Types.ValueNumber?,
	height: Types.Value<Extent>?,
	alignH: Types.Value<Edge>?,
	alignV: Types.Value<Edge>?,
}
export type ScrollViewOptions = {
	padding: Types.Value<Padding>?,
	width: Types.Value<Extent>?,
	maxWidth: Types.ValueNumber?,
	height: Types.Value<Extent>?,
	axis: Axis?,
	gap: Types.Value<Space>?,
	align: Types.Value<Align>?,
	distribute: Types.Value<Distribute>?,
}
export type GridOptions = {
	padding: Types.Value<Padding>?,
	width: Types.Value<Extent>?,
	maxWidth: Types.ValueNumber?,
	height: Types.Value<Extent>?,
	columns: Types.ValueNumber,
	flow: ("row" | "column")?,
	gap: Types.Value<Space>?,
	rowGap: Types.Value<Space>?,
	cellHeight: Types.ValueNumber?,
	aspectRatio: Types.ValueNumber?,
	align: Types.Value<Edge>?,
}
export type AdaptiveStackOptions = {
	padding: Types.Value<Padding>?,
	width: Types.Value<Extent>?,
	maxWidth: Types.ValueNumber?,
	height: Types.Value<Extent>?,
	gap: Types.Value<Space>?,
	align: Types.Value<Align>?,
	distribute: Types.Value<Distribute>?,
	axis: Types.Value<"x" | "y">?,
}
export type ViewThatFitsOptions = {
	width: Types.Value<Extent>?,
	maxWidth: Types.ValueNumber?,
	height: Types.Value<Extent>?,
}
export type ErrorBoundaryOptions = {
	view: () -> Types.Child,
	fallback: (failure: unknown, retry: () -> ()) -> Types.Child,
	onError: ((failure: unknown) -> ())?,
	width: Types.Value<Extent>?,
	maxWidth: Types.ValueNumber?,
	height: Types.Value<Extent>?,
}
export type DividerOptions = {
	axis: ("x" | "y")?,
	thickness: (number | string)?,
	appearance: Types.Value<"standard" | "strong">?,
}
export type SpacerOptions = {
	minLength: Types.Value<Space>?,
}
export type Zone =
	"topLeft"
	| "top"
	| "topRight"
	| "left"
	| "center"
	| "right"
	| "bottomLeft"
	| "bottom"
	| "bottomRight"
	| "topbar"
export type RegionOptions = {
	zone: Zone,
	rank: number,
	mayDrop: boolean?,
	form: Types.Cell<number>?,
	expand: (() -> Instance)?,
	reveal: boolean?,
}
export type CompositionOptions = { gap: Space?, padding: Padding?, topbar: Engine.ValueBoolean? }
return {}
