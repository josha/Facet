--!strict
local Shared = require("./types")

export type Rect = { x: number, y: number, w: number, h: number }
export type ZoomControls = {
	fit: (() -> boolean)?,
	zoomTo: ((Rect) -> boolean)?,
	zoomAt: ((number, Vector2?) -> boolean)?,
}
export type ZoomViewOptions = {
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
export type TravelOptions = {
	destination: Shared.Value<GuiObject>,
	content: () -> GuiObject,
	path: ("straight" | "arc")?,
	motion: ("ease" | "spring")?,
	transparency: Shared.Value<number>?,
	stagger: (number | (() -> number))?,
	lift: boolean?,
	onStarted: ((GuiObject) -> ())?,
	onLanded: ((GuiObject) -> ())?,
}

return {}
