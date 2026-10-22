# Stage

Stage.reference option values and behavior.

| Control | Main contract |
|---|---|
| `Stage` | A native ViewportFrame. A `camera` CFrame or a borrowed Camera, `fieldOfView`, `content(runtime, world, live)` for 3D content that Compose owns, and `lazy`. |

The content callback mounts into the Stage's WorldModel and can return cleanup.
Use native constructors from its runtime. The third argument, `live`, is a
readable boolean. Pause scene animation while it is false: the nearest
ScrollingFrame is moving, has moved in the last 0.15 seconds, or the Stage
does not have enough visible area. Without a ScrollingFrame it stays true.
Visibility requires half the Stage's area or half the scroll window's height.

With `lazy = true`, content builds within half a scroll window of the visible
area, including while scrolling. Stages in one control set build one per frame.
Animation stays paused until `live` is true; the last frame stays visible.
`FacetLive` and `FacetBuilt` attributes expose these states. This is a 3D view
inside a UI rectangle; its scene does not provide 3D UI layout.
