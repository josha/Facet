# ZoomView.ZoomView

<!-- aliases: ZoomRect | Facet.ZoomRect -->

`UI.ZoomView(spec) -> ScrollingFrame` wraps one stable content tree. Required:
`contentSize` (a Vector2 in layout pixels, or a readable) and `content()` (a
factory that returns a GuiObject). The factory runs once. Native `Size` sets
the viewport. The control uses one UIScale and native scrolling.

- `zoom`: an optional writable number cell. Scale 1 is the authored size.
  Without it, the view starts at fit. A zoom must be positive and finite.
- `focus`: an optional content point, or a readable. A change centres that
  point. Zoom keeps the current point fixed on screen until an edge stops it.
- `minZoom`: a positive finite scale. Without it, the minimum is fit.
  `maxZoom` is 4 by default. `minZoom` cannot exceed `maxZoom`.
- `doubleTapZoom`: the closer scale for a double tap. The default is twice
  fit, bounded by `maxZoom`. Double tap toggles fit and that scale around the
  contact point. Text boxes, nested scrollers and active child surfaces own their
  taps. A button on the board activates on the first tap of a double tap and the
  second tap zooms. Set the `FacetOwnsTaps` attribute to true on a button whose
  second tap has its own meaning, such as inspect then buy; rapid taps on it
  activate it and do not zoom.
- `enabled`: a boolean or readable, default true.
- `followTransition`: true scales the shown board with the zoom of the page
  transition around it, so a `transition = { scale = 0.5 }` page grows the
  board from half size as it fades in and shrinks it as it leaves. The zoom
  state and gestures are unchanged.
- `controls`: an optional `ZoomControls` table. The control sets `fit()` and
  `zoomTo({ x, y, w, h })` and `zoomAt(scale, screenPoint?)`. These calls return false while disabled or locked
  by a child drag, except for one call inside its `onStart` capture scope.
  The rectangle uses content pixels. `zoomAt` holds a point in screen pixels.
  `fit()` and `zoomTo()` also return false while either viewport dimension is
  zero. They leave the current zoom unchanged; call again after layout measures
  the viewport.
  Without a point, it uses the captured pointer or armed source centre; outside
  capture it uses the viewport centre. Call `zoomAt(2)` in `onStart` to zoom at
  pickup, and `fit()` in `onEnd` to reverse after release. The functions are
  cleared when the owner ends.

Mouse pan follows native MouseMovement events while the original button is
held. Pointer pan and wheel pan apply in that input callback. Ctrl-wheel uses
the pointer in the inset viewport; ZoomView converts GetMouseLocation with
GuiService.GetGuiInset. Pinch Begin captures the focus without changing scale.
A positive Change scale updates the complete content transform at once.

While the pointer is over the visible board, ZoomView holds native wheel
scroll on its own ScrollingFrame and its scroll ancestors. Plain wheel pans
the board vertically; Shift-wheel pans horizontally. Ctrl-wheel zooms.
Pointer exit, focus loss, disable and disposal release these holds. A clipped
board, an overlaid control or a nested scroller does not claim this wheel.
