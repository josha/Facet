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
export type StackProps = Engine.FrameProps & {
	padding: Types.Value<Padding>?,
	width: Types.Value<Extent>?,
	height: Types.Value<Extent>?,
	gap: Types.Value<Space>?,
	align: Types.Value<Align>?,
	distribute: Types.Value<Distribute>?,
	wrap: Types.Value<boolean>?,
}
export type ScreenProps = Engine.FrameProps & {
	padding: Types.Value<Padding>?,
	width: Types.Value<Extent>?,
	height: Types.Value<Extent>?,
	gap: Types.Value<Space>?,
	align: Types.Value<Align>?,
	distribute: Types.Value<Distribute>?,
}
export type ZStackProps = Engine.FrameProps & {
	padding: Types.Value<Padding>?,
	width: Types.Value<Extent>?,
	height: Types.Value<Extent>?,
	alignH: Types.Value<Edge>?,
	alignV: Types.Value<Edge>?,
}
export type ScrollViewProps = Engine.ScrollingFrameProps & {
	padding: Types.Value<Padding>?,
	width: Types.Value<Extent>?,
	height: Types.Value<Extent>?,
	axis: Axis?,
	gap: Types.Value<Space>?,
	align: Types.Value<Align>?,
	distribute: Types.Value<Distribute>?,
}
export type GridProps = Engine.FrameProps & {
	padding: Types.Value<Padding>?,
	width: Types.Value<Extent>?,
	height: Types.Value<Extent>?,
	columns: Types.Value<number>,
	flow: ("row" | "column")?,
	gap: Types.Value<Space>?,
	rowGap: Types.Value<Space>?,
	cellHeight: Types.Value<number>?,
	aspectRatio: Types.Value<number>?,
	align: Types.Value<Edge>?,
}
export type ErrorBoundaryProps = Engine.FrameProps & {
	view: () -> Types.Child,
	fallback: (failure: unknown, retry: () -> ()) -> Types.Child,
	onError: ((failure: unknown) -> ())?,
	width: Types.Value<Extent>?,
	height: Types.Value<Extent>?,
}
export type DividerProps = Engine.FrameProps & {
	axis: ("x" | "y")?,
	thickness: (number | string)?,
	appearance: Types.Value<"standard" | "strong">?,
}
export type SpacerProps = Engine.FrameProps & {
	minLength: Types.Value<Space>?,
}
export type LayoutControls = {
	Screen: Types.Constructor<ScreenProps, Frame>,
	VStack: Types.Constructor<StackProps, Frame>,
	HStack: Types.Constructor<StackProps, Frame>,
	ZStack: Types.Constructor<ZStackProps, Frame>,
	ScrollView: Types.Constructor<ScrollViewProps, ScrollingFrame>,
	Grid: Types.Constructor<GridProps, Frame>,
	ErrorBoundary: Types.Constructor<ErrorBoundaryProps, Frame>,
	Divider: Types.Constructor<DividerProps, Frame>,
	Spacer: Types.Constructor<SpacerProps, Frame>,
	fill: (weight: number?) -> UIFlexItem,
}
return {}
