### gestureArbiter

`UI.gestureArbiter(surface) -> GestureBinding` shares the pointer decision with
`UI.draggable`, collection drags and ScrollView. Call it inside a Compose owner.
The binding stops its contacts when that owner ends. Control factories on the
same UserInputService share one arbiter.

- `begin(pointer, position, options)` captures `surface` and the screen point.
  It returns false when another surface already owns that InputObject.
- `options` contains `pickup` (`immediate` or `longPress`, absent for pan),
  `axis` (`X`, `Y` or `XY`), `scroll` and `threshold` (default 6 screen pixels).
- `move(pointer, position)` returns the final gesture after the threshold.
  Immediate pickup wins on its axis. Across the axis, or before long press,
  movement wins as `scroll` when `scroll` is true, otherwise `pan`.
- `claim(pointer, kind)` accepts a native long-press `drag` only while pending.
  It cannot change a final decision. Pan and scroll must pass through `move`.
- `get(pointer)` returns `{ owner, origin, kind }` or nil. The copy cannot
  change the arbiter. `kind` is `pending`, `drag`, `pan`, `scroll`, `press`,
  `doubleTap` or `cancelled`.
- `finish(pointer, cancelled?)` releases only this surface's contact. It returns
  `press` for a pending contact, or `cancelled` when requested.

A zoom surface must read the decision before starting pan or double-tap. Keep
its camera fixed while a child source is pending or dragging. Drop targets are measured
and hit-tested each frame and again at release through a moving camera. Use native
activation click counts for double-tap. A moved or cancelled contact cannot
supply a double-tap. The arbiter creates no input connection or Instance.
