# Composition.layout

Region measurement, authored sizes and layout boundaries.

- A zone is a native Frame with an `AnchorPoint` and a scale `Position` at
  its edge or corner. It hugs its regions and stacks them
  in declaration order with a `UIListLayout`.
- The screen has three lanes of equal width: left, center and right. A side
  zone stays at its edge and must fit its third.
- A center-lane zone (`top`, `center`, `bottom`) can also use the width that
  the side zones of its row leave free. Its width must not exceed the full
  width minus twice the wider side zone of that row and twice `gap`. Thus a
  wide `top` or `bottom` region fits on a phone when the corners of its row
  are empty or narrow. When the side zones of its row squeeze a center zone
  that fits the row alone, the side regions that are wider than the room the
  center leaves also count as not fitting. Thus rank decides: a rank 3 corner
  steps down before a rank 1 race bar, and a rank 1 corner keeps its form
  while a rank 2 center region steps down.
- The center-lane zones draw above the side zones (`ZIndex` 2).
  Thus a side region cannot hide a center callout.
- The zones of one lane must not overlap vertically. The `center` zone stays centred and keeps `gap` from the
  zones above and below it.

Open [Composition.layout.step-down](Composition.layout.step-down.md) for form selection,
zone fallback, fit warnings and resize motion.
Open [Composition.adaptation](Composition.adaptation.md) for `topbar` layout.
