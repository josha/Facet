### WorldMarker

<!-- aliases: WorldMarker | worldmarker | world marker -->

`UI.WorldMarker(spec: WorldMarkerProps) -> Frame` shows its children at a
world target. When the target is off screen or behind the camera, the marker
stays at the edge of its parent and an arrow points toward the target.

| Option | Meaning and default |
|---|---|
| `anchor` | Required. The `anchor` readable of a `UI.worldAnchor` binding. Use `offscreen = "retain"` so that the marker knows the direction of a target off screen. |
| `edge` | `"clamp"` (the default) keeps the marker at the parent's edge while the target is off screen. `"hide"` hides the marker instead. |
| `margin` | The space between the marker and the parent's edge: a theme space, a number, or sides such as `{ top = "xl" }` to keep the marker clear of a HUD row. A side that is not given and the default are `"m"`. |
| `arrow` | `false` hides the arrow at the edge. The default is `true`. |

The marker is centred on the target. Its parent is the area that the marker
can use: put it in a frame that covers the screen, or the safe area of the
screen. The marker hugs its children; give it one child, such as a Badge.
The root's `Clamped` attribute is `true` while the marker is at the edge. The
arrow is the `Arrow` chip in the `Pointer` folder. An invisible anchor hides
the marker.

Make the marker critical information about the world, such as a goal that
the player looks for. It can cover the focus area, so remove it when the
player reaches the target. The game owns the target, its lifetime and the
proximity rules; dispose the `worldAnchor` binding with its owner.
