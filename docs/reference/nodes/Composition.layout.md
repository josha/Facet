# Composition.layout

Region measurement, authored sizes and layout boundaries.

- A zone is a native Frame with an `AnchorPoint` and a scale `Position` at
  its edge or corner. A corner, side or `center` zone hugs its regions and
  stacks them in declaration order with a `UIListLayout`.
- The `top` and `bottom` zones put their regions side by side in declaration
  order, in rows that are centred. A region goes to a new row only when it
  does not fit beside the regions before it in the room of the zone. The zone
  is as wide as its widest row. Its height is the height of its rows and the
  `gap` between them. A native `UIListLayout` with `Wraps` makes the rows.
  Landed `topbar` regions are one column at the start of the `top` row.
- A region whose content measures zero, such as a scoreboard that shows only
  in a match, takes no room and no `gap`. When another region of its zone has
  content, the empty region is hidden. A presented control in it, such as a
  Sheet, still shows.
- The screen has three lanes of equal width: left, center and right. A side
  zone stays at its edge. In the top and bottom rows, when the center zone of
  that row is empty, a corner zone can use the width that the other corner
  leaves, minus `gap`. Otherwise, and always in the middle row, which keeps
  the view clear, a side zone must fit its third.
- A center-lane zone (`top`, `center`, `bottom`) can also use the width that
  the side zones of its row leave free. Its width must not exceed the full
  width minus twice the wider side zone of that row and twice `gap`. When
  both side zones of its row are empty, it can use the full width. Thus a
  wide `top` or `bottom` region fits on a phone when the corners of its row
  are empty or narrow. When the side zones of its row squeeze a center zone
  that fits the row alone, the side regions that are wider than the room the
  center leaves also count as not fitting. Thus rank decides: a rank 3 corner
  steps down before a rank 1 race bar, and a rank 1 corner keeps its form
  while a rank 2 center region steps down.
- The `bottomLeft`, `bottom` and `bottomRight` zones share one baseline.
  Content that hangs below a bottom region, such as a Button `caption` or
  the shortcut hint on a circle, takes no room in the layout. Facet measures
  the largest overhang in the bottom row and lifts all three zones by that
  amount. Thus a captioned circle and a Button of the same height line up on
  their centres, and the captions stay above the bottom padding. The fit
  rules count this room as part of the bottom row. A hidden region adds no
  room.
- The center-lane zones draw above the side zones (`ZIndex` 2).
  Thus a side region cannot hide a center callout.
- The zones of one lane must not overlap vertically. The `center` zone stays centred and keeps `gap` from the
  zones above and below it.
- At ten feet, a Composition that is the root of its ScreenGui keeps every
  zone inside the TV safe area: it adds the environment's `overscanInsets` to
  its padding. A Composition inside `UI.Screen` uses the margins of the Screen.
  Do not offset a zone by hand.

Open [Composition.layout.step-down](Composition.layout.step-down.md) for form selection,
zone fallback, fit warnings and resize motion.
Open [Composition.adaptation](Composition.adaptation.md) for `topbar` layout.
