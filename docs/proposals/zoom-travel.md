# Zoom and travel

## Player tasks

The player inspects a large board, points at a cell, and returns to the full
board. The player moves one tile between rows and sees where it goes.
The proposed names are `ZoomView` and `PanZoomView`. Use `ZoomView`.
Use `Travel` for the second control.

## API

`UI.ZoomView { contentSize, content, zoom?, focus?, minZoom?, maxZoom?,
doubleTapZoom?, enabled?, controls? }` returns a ScrollingFrame.
`contentSize` is a Vector2 in layout pixels. `content()` runs once.
`zoom` is a writable number cell. Scale 1 is the authored content size.
`focus` is a readable content point. `controls.zoomTo(rect)` fits a content
rectangle in the viewport. `controls.fit()` restores the full board.
Native properties set the viewport size. Fit centres an axis smaller than the
viewport. Pan cannot add empty space beyond the content edges.

`UI.Travel { destination, content, path?, onLanded? }` returns an anchor Frame.
`destination` is a readable GuiObject. `content()` runs once. The same content
stays in one carrier. The carrier moves through the overlay and lands inside
the destination. `path` is `straight` or `arc`. A new destination interrupts
travel at its current position. The model owns the accepted tile move.

## Mechanisms checked

Roblox `UIScale.Scale` scales a complete native tree. `ScrollingFrame`
`CanvasSize`, `CanvasPosition`, `ScrollingEnabled`, `ElasticBehavior`, and
`ResetScrollVelocity` provide native pan, limits and inertia. They do not supply
focus-preserving zoom or a child-drag lock. `UIDragDetector` provides native
pointer capture and custom response. It does not arbitrate a board pan against
a captured tile drag. `UserInputService.TouchPinch` supplies a scale ratio and
contact points. `TouchPan` supplies translation and velocity. The view keeps
native scrolling for pan. `InputContext`, `InputAction` and `InputBinding`
provide scoped keyboard and controller commands.

Compose `runtime.tween`, `runtime.ramp`, `runtime.timeline`, `Compose.portal`,
`Compose.watch`, `Compose.cleanup` and native runtime subscriptions provide
motion, structure and lifetime. The pinned native animation clock is Heartbeat.
A PreRender subscription applies the current transform before each paint.
This pin does not offer a per-control render-clock tween. Time-based motion
uses this clock for this pull request. Direct pinch updates inside TouchPinch.
Mouse pan updates inside UIDragDetector.DragContinue. Do not add a second
animation scheduler. The separate Compose render-clock proposal records the
one-frame measurement.

Facet's overlay portal escapes container clips. Travel uses that portal and
one native carrier. It does not build a second scene or clone the tile.
Native text stays in ordinary Frames under UIScale, with no CanvasGroup
texture. Roblox renders the glyphs at the native scale. Crisp resting text
and fractional-scale raster rounding still need a live check.

## Gesture rules

Make one decision at touch-down or the movement threshold. Hold the decision
until release. A captured child drag beats pan and zoom, including an external
zoom write. Writer D owns the shared arbiter. Read its proposal and use its
module before qualification. Never change its drag implementation.

Pinch keeps its content point under the contact centre. Double tap toggles fit
and a closer scale around the tapped point. Ctrl-wheel zooms; wheel pans.
Triggers zoom while the view is selected. The right stick pans. Plus and Minus
zoom; WASD pan; Home fits. Child controls keep their selection and activation.
Reduced motion removes automatic travel and zoom interpolation. Direct pinch
and pan still track input. Motion duration, easing and arc height are theme
tokens. Zoom never creates or destroys content instances.

## Proof

Record the fast gate, types and formatting before code. Verify focus position
at each sampled zoom frame, clamp bounds, retargeting, drag locks, lifetime,
travel path and hand-off identity. Register cases in the committed Verify plan.
Add live pointer and gamepad cases. Sample PreRender, content identity and
instance additions and removals. Inspect pinch, double tap, wheel, triggers,
stick, clipped row travel and reduced motion on phone and desktop.
Headless geometry does not prove engine layout, text paint or phone smoothness.

Baseline: commit `6237c48`. The fast suite passes. The fast gate fails the
screen-key-bindings and screen-key-bindings-selftest producers because
`examples/facet-lab/src/lab_sweep.luau:288` reads `event.KeyCode`.
Types pass: 690 targets, zero diagnostics, 181 negative probes rejected.
Formatting passes. The first sandboxed type run failed at `lune setup`;
the authorized declaration-generation run completed.
