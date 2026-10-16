# Path

| Control | Main contract |
|---|---|
| `Path` | A stroked vector path on a native `Path2D`, for simple vector icons, arcs and gauge needles. `points` is required: a list, or a readable of a list, of normalized points from `Facet.pathShapes`, at most 100. A new list moves the same stroke. `role` is `content` (the default), `secondary` or `accent`, and the StyleSheet colours the stroke from the active palette. `tint` sets a colour that no role names. `thickness` is pixels or a theme metric name; without it the engine default applies. `closed` joins the last point to the first. `width` and `height` set a square or rectangular box in pixels. The engine strokes a path and does not fill it, and a path has no transparency of its own. |
