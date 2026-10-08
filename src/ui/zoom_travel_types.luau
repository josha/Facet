--!strict
local Shared = require("./types")

export type Rect = { x: number, y: number, w: number, h: number }
export type ZoomControls = { fit: (() -> boolean)?, zoomTo: ((Rect) -> boolean)? }
export type ZoomViewProps = Shared.ScrollingFrameProps & {
	contentSize: Shared.Value<Vector2>,
	content: () -> GuiObject,
	zoom: Shared.Cell<number>?,
	focus: Shared.Value<Vector2>?,
	minZoom: number?,
	maxZoom: number?,
	doubleTapZoom: number?,
	enabled: Shared.ValueBoolean?,
	controls: ZoomControls?,
}
export type TravelProps = Shared.FrameProps & {
	destination: Shared.Value<GuiObject>,
	content: () -> GuiObject,
	path: ("straight" | "arc")?,
	motion: ("ease" | "spring")?,
	transparency: Shared.Value<number>?,
	onLanded: ((GuiObject) -> ())?,
}
export type Controls = {
	ZoomView: Shared.Constructor<ZoomViewProps, ScrollingFrame>,
	Travel: Shared.Constructor<TravelProps, Frame>,
}

return {}
