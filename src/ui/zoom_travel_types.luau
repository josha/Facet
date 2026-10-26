--!strict
local Shared = require("./types")

export type Rect = { x: number, y: number, w: number, h: number }
export type ZoomControls = {
	fit: (() -> boolean)?,
	zoomTo: ((Rect) -> boolean)?,
	zoomAt: ((number, Vector2?) -> boolean)?,
}
export type ZoomViewOptions = {
	contentSize: Shared.Input<Vector2>,
	content: () -> GuiObject,
	zoom: Shared.Value<number>?,
	focus: Shared.Input<Vector2>?,
	minZoom: number?,
	maxZoom: number?,
	doubleTapZoom: number?,
	enabled: Shared.ValueBoolean?,
	controls: ZoomControls?,
}
export type TravelOptions = {
	destination: Shared.Input<GuiObject>,
	content: () -> GuiObject,
	path: ("straight" | "arc")?,
	motion: ("ease" | "spring")?,
	transparency: Shared.Input<number>?,
	stagger: (number | (() -> number))?,
	lift: boolean?,
	onStarted: ((GuiObject) -> ())?,
	onLanded: ((GuiObject) -> ())?,
}

return {}
