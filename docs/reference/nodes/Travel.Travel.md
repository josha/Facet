# Travel.Travel

`UI.Travel(spec) -> Frame` uses one model: an item has a slot. When its
`destination` changes, the same visual moves to that slot. `content()` returns
the visual once. Travel owns its position and size and sets `AutomaticSize` to
`None`, including text content. The return value is an empty ownership anchor.

Travel measures the shared container, clipping and scale boundaries at the
change. With a safe common container, it moves in place. The parent stays the
same. A clip, scale or native layout boundary routes through the overlay,
then lands in the new slot. The consumer sets no route flag. Keep slots mounted.
Clipping ancestors above the shared container also require the overlay. Content
is promoted at once, including while it waits for a stagger delay, so a hidden
old slot cannot hide a waiting tile. The start callback still follows the delay.
Slots are borrowed. Compose owns the visual and the anchor in one child owner.
Destroying the current slot, visual or anchor ends Travel and releases its
frame lease. Later destination changes cannot restart that destroyed visual.
Keep the current slot mounted for an item that must remain available.

- `destination`: a GuiObject, readable or body. The first placement is immediate.
- `content`: a factory that returns a GuiObject. It runs once. The visual is
  the reusable carrier. There is no clone or new instance per move.
- `path`: `straight` (default) or `arc`.
- `motion`: `ease` (default) or `spring`. Timed motion uses
  `motion.durations.travel` and `motion.easing.travel`. Spring motion uses
  `motion.springs.travel`, with the same period and damping shape as navigation.
  A spring interrupt keeps its position and velocity.
- `transparency`: an optional number or readable for CanvasGroup content.
  It uses `motion.durations.travelFade`. This supports retiring items.
- `stagger`: a nonnegative zero-based ripple index, or a function that returns
  it at each slot change. Delay is that index times `motion.durations.travelStagger`.
  An interrupted flight retargets at once. Reduced motion ignores the delay.
- `lift`: true scales the whole visual around its centre during flight. The
  peak is `motion.scales.travelLift`. Use it with `path = "arc"` for a shuffle.
- `onStarted(destination)`: reports the start after the delay. On interruption
  it reports the new destination. The game can play its own sound here.
- `onLanded(destination)`: reports placement, including the immediate initial
  placement. It can run during construction, before the returned anchor is
  assigned. The callback may change `destination`. It does not change game state.
