## Path shapes

`Facet.pathShapes` makes the normalized points that `UI.Path` strokes. The points
are in a unit box, with the angle 0 at 12 o'clock and positive angles clockwise.

- `pathShapes.arc(startDeg, sweepDeg, { segments?, radius? })` makes a circular
  arc.
- `pathShapes.ring({ radius? })` makes a full circle from four exact quarters.
- `pathShapes.needle(angleDeg, { innerRadius?, radius? })` makes one straight
  segment from `innerRadius` to `radius` at `angleDeg`.
- `pathShapes.MAX_CONTROL_POINTS` is 100, the limit of the engine `Path2D`.
  A shape that needs more points is refused when you make it.

```luau
local speed = Compose.cell(0.5)
UI.Path "Needle" {
	points = function(use)
		return Facet.pathShapes.needle(use(speed) * 270 - 135, { innerRadius = 0.2 })
	end,
	role = "accent",
	thickness = 3,
	width = 64,
}
```
