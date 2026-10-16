# Composition.layout.step-down

Form selection, zone fallback, fit warnings and resize motion.

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
- A `top` or `bottom` zone can remain too wide for the space between its row's
  corner zones after no region can give way. It then moves below the top
  corners, or above the bottom corners, and uses the full width.
  The composition resolves again from the richest forms.
  The `left` and `right` zones that the moved zone covers give way first.
- A region can still fail to fit at its last form when nothing else can give
  way. The composition then warns once in the output and names the region.
  Give that region a smaller form, `mayDrop = true` or a higher rank number.
- The decision uses only the measured sizes and the size of the composition.
  Thus a rotation, a resize or a text size change gives the same forms as a
  new mount of the same size.
- When the size of the composition changes, for example on a rotation, a
  region that changes form scales from 0.94 to 1 in 0.15 seconds, Cubic
  Out, from the edge of its zone. The first layout after a mount does not
  move. Its measurement holds until the motion ends,
  so the motion cannot change the decision. Reduced motion removes the motion.
