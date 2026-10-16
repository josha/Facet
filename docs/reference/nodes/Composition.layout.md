# Composition.layout

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
- The zones of one lane must not overlap vertically. The `center` zone stays centred and keeps `gap` from the
  zones above and below it.

Step-down:

- Every form stays mounted in its own `Form<n>` Frame. Roblox measures each
  form, also a hidden one. Only the Frame of the chosen form is visible, so a
  form keeps its own `Visible`. The region has the `FacetForm` attribute.
- When a lane does not fit, the region with the highest rank in the zones
  that do not fit shows its next form. After its last form, a region with
  `mayDrop` hides. With equal ranks, the later region gives way first.
- When a zone is too wide, only its regions that are wider than the room of
  the zone give way. A narrow region cannot make the zone narrower.
- The composition repeats this until every lane fits or no region can give
  way. It never scales content down.
- The decision uses only the measured sizes and the size of the composition.
  Thus a rotation, a resize or a text size change gives the same forms as a
  new mount of the same size.
- When the size of the composition changes, for example on a rotation, a
  region that changes form scales from 0.94 to 1 in 0.15 seconds, Cubic
  Out, from the edge of its zone. The first layout after a mount does not
  move. Its measurement holds until the motion ends,
  so the motion cannot change the decision. Reduced motion removes the motion.

`topbar`:
