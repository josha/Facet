--!strict
local Types = require("./types")
local Media = require("./media_types")
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
export type StackCorners = number | "pill" | "square" | "control" | "panel"
export type StackOptions = {
	padding: Types.Input<Padding>?,
	surface: ("surface" | "panel" | "pane")?,
	corners: Types.Input<StackCorners>?,
	status: Types.Input<Media.Status?>?,
	width: Types.Input<Extent>?,
	maxWidth: Types.ValueNumber?,
	height: Types.Input<Extent>?,
	gap: Types.Input<Space>?,
	align: Types.Input<Align>?,
	distribute: Types.Input<Distribute>?,
	wrap: Types.ValueBoolean?,
}
export type ScreenOptions = {
	chrome: ("device" | "band" | "edge")?,
	surface: ("surface" | "panel" | "pane")?,
	padding: Types.Input<Padding>?,
	width: Types.Input<Extent>?,
	maxWidth: Types.ValueNumber?,
	height: Types.Input<Extent>?,
	gap: Types.Input<Space>?,
	align: Types.Input<Align>?,
	distribute: Types.Input<Distribute>?,
}
export type ZStackOptions = {
	padding: Types.Input<Padding>?,
	width: Types.Input<Extent>?,
	maxWidth: Types.ValueNumber?,
	height: Types.Input<Extent>?,
	alignH: Types.Input<Edge>?,
	alignV: Types.Input<Edge>?,
}
export type ScrollViewOptions = {
	padding: Types.Input<Padding>?,
	width: Types.Input<Extent>?,
	maxWidth: Types.ValueNumber?,
	height: Types.Input<Extent>?,
	axis: Axis?,
	gap: Types.Input<Space>?,
	align: Types.Input<Align>?,
	distribute: Types.Input<Distribute>?,
}
export type GridOptions = {
	padding: Types.Input<Padding>?,
	width: Types.Input<Extent>?,
	maxWidth: Types.ValueNumber?,
	height: Types.Input<Extent>?,
	columns: Types.ValueNumber,
	flow: ("row" | "column")?,
	gap: Types.Input<Space>?,
	rowGap: Types.Input<Space>?,
	cellHeight: Types.ValueNumber?,
	aspectRatio: Types.ValueNumber?,
	align: Types.Input<Edge>?,
}
export type AdaptiveStackOptions = {
	padding: Types.Input<Padding>?,
	width: Types.Input<Extent>?,
	maxWidth: Types.ValueNumber?,
	height: Types.Input<Extent>?,
	gap: Types.Input<Space>?,
	align: Types.Input<Align>?,
	distribute: Types.Input<Distribute>?,
	axis: Types.Input<"x" | "y">?,
}
export type ViewThatFitsOptions = {
	width: Types.Input<Extent>?,
	maxWidth: Types.ValueNumber?,
	height: Types.Input<Extent>?,
}
export type ErrorBoundaryOptions = {
	view: () -> Types.Child,
	fallback: (failure: unknown, retry: () -> ()) -> Types.Child,
	onError: ((failure: unknown) -> ())?,
	width: Types.Input<Extent>?,
	maxWidth: Types.ValueNumber?,
	height: Types.Input<Extent>?,
}
export type DividerOptions = {
	axis: ("x" | "y")?,
	thickness: (number | string)?,
	appearance: Types.Input<"standard" | "strong">?,
}
export type SpacerOptions = {
	minLength: Types.Input<Space>?,
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
	| "action"
export type RegionOptions = {
	zone: Zone,
	rank: number,
	mayDrop: boolean?,
	form: Types.Value<number>?,
	expand: (() -> Instance)?,
	reveal: boolean?,
	leading: boolean?,
	trailing: boolean?,
}
export type CompositionRows = "match" | "fit"
export type CompositionOptions = {
	gap: Space?,
	padding: Padding?,
	topbar: Engine.ValueBoolean?,
	rows: Engine.Input<CompositionRows>?,
	passive: boolean?,
}
return {}
