# ZoomView.onStart

Pinch zooms around the contact centre. Wheel pans; Ctrl-wheel zooms around the
pointer. An empty view is a selection stop: Plus and Minus or the bumpers zoom,
WASD or the right stick pan, and Home or Y fits. A view that holds a visible
selectable control is not a stop. Selection that enters it goes to the control
nearest to the entry edge, or to the descendant that the view's `FacetEntry`
attribute names. While a control in the view has the selection, the same keys
act on the view, except inside a nested selection owner such as a Collection.
A game command bound to the same key, such as a letter or Y in a
`commandScope`, has a higher priority and still wins. At the edge of the view, each
direction goes to the nearest control outside the view in that direction. An
authored `NextSelection` link on the control is kept. The
engine uses the right trigger to start a drag detector, so the triggers do not
zoom. The arrow keys and D-pad keep native selection. Child controls keep
activation.
A pending child drag or a captured child drag holds the camera. An external
zoom write waits until release. One camera request from the captured child's
`onStart` can finish its motion. Later requests and pan wait until release.
The same grant works for an external collection source. In VirtualGrid.drag,
set onStart to call camera.zoomAt(2, boardScreenPoint) or camera.zoomTo(rect).
Set onEnd to call camera.fit(). The granted camera holds until that source
releases, even when the rack is outside the view.
Targets are hit-tested again after each camera write. Native scrolling clamps each edge and has no
elastic overscroll. Fit centres margins on an axis smaller than the viewport.

Zoom uses `motion.durations.zoom` and `motion.easing.zoom`. Reduced motion
removes interpolation. Content instances stay mounted at every scale.
Text stays in ordinary native Frames under UIScale. It is not captured in a
CanvasGroup texture. Roblox draws text at its native scaled size.
Fractional-scale text and phone frame timing need native verification.

```luau
local zoom = Compose.cell(0.5)
local camera: Facet.ZoomControls = {}
local function Board(): GuiObject
    return Host.Frame { Size = UDim2.fromOffset(780, 780) }
end
UI.ZoomView {
    contentSize = Vector2.new(780, 780),
    zoom = zoom,
    controls = camera,
    content = Board,
}
```
