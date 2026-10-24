# Stage

Stage.reference option values and behavior.

| Control | Main contract |
|---|---|
| `Stage` | A native ViewportFrame. A `camera` CFrame or a borrowed Camera, `fieldOfView`, `content(runtime, world, live)` for 3D content that Compose owns, and `lazy`. |

Size the UI area and frame the 3D subject separately. For inspection, bound
the parent in both axes and set the Stage's `Size = UDim2.fromScale(1, 1)`.
A `ZStack` with fill dimensions allocates room but does not resize its
children. `UI.fill()` allocates remaining space beside stack siblings.
Keep identity, decisive facts and commitment outside the preview area.

Card sizes its `artwork` result to the thumbnail frame. A detail pane does
not apply that policy. Each artwork factory must create a new GUI object;
do not share one Instance between the thumbnail and inspection areas.
See [Card artwork](Card.imageAspectRatio.md) and [collection/detail](Tasks.collection-detail.md).

Set `camera` and `fieldOfView` to show the actual subject at a useful scale.
Check its silhouette and important details at the area's wide, narrow and
short aspect ratios. A larger UI area does not correct a distant camera.
Use consistent framing across comparable thumbnails; use a different camera
when inspection needs detail. Keep camera and scene changes in the same
Compose owner. No separate render loop is needed for a static preview.

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
