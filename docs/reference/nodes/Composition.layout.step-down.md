# Composition.layout.step-down

Form selection, zone fallback, fit warnings and resize motion.

- Every form stays mounted in its own `Form<n>` Frame. Roblox measures each
  form, also a hidden one. Only the Frame of the chosen form is visible, so a
  form keeps its own `Visible`. The region has the `FacetForm` attribute.
- When a lane does not fit, the region with the highest rank in the zones
  that do not fit shows its next form. After its last form, a region with
  `mayDrop` hides. With equal ranks, the later region gives way first.
- When a zone is too wide, only its regions that are wider than the room of
  the zone give way. A narrow region cannot make the zone narrower. A `top`
  or `bottom` zone first wraps a region to a new row. Its regions give way
  only when a single region is too wide or the rows are too tall.
- The composition repeats this until every lane fits or no region can give
  way. It never scales content down.
- A `top` or `bottom` zone can remain too wide for the space between its row's
  corner zones after no region can give way. When only one corner zone of
  that row has content, the zone first moves beside that corner. It is
  centred in the width that the corner and one `gap` leave, and the
  composition resolves again from the richest forms. Thus a readout beside
  the wallet column stays in the top row on a portrait phone.
- When both corner zones of the row have content, or the zone is still too
  wide beside its corner, it moves below the top corners, or above the bottom
  corners, and uses the full width.
  The composition resolves again from the richest forms.
  The `left` and `right` zones that the moved zone covers give way first.
- When a top corner at its last form is over the touch controls, or the two
  top corners are too wide for one row, `top` moves below the corners and
  the corners share the row. A narrow `top` then sits at the left.
  When the corners are still too wide, `topRight` moves below `topLeft`.
  Each time, it resolves again.
- When a zone still covers another zone, a region of those zones hides
  behind the "…" control of its zone, highest rank number first.
  `reveal = false` keeps a region in view. A region that is only too large
  for its lane or the screen stays in view, with one warning that names it.
  Give that region a smaller form or `mayDrop = true`.
- On a screen larger than a phone, the composition also resolves its
  measured forms for a 358 by 812 and an 812 by 358 phone area. The
  `FacetUnfit` boolean attribute marks a fit failure at the size it has now
  or at a phone area; the root's `FacetUnfitDetails` StringValue names the
  size and the regions. A region that opens its fullest form in a Popover
  also fails when that form is wider than the area. `Facet.review` reports
  it as `composition-unfit`.
- A visible "…" mark for a region with no `label` and no `icon` carries the
  `FacetReveal` attribute with the region names. `Facet.review` reports it as
  `unnamed-reveal` (medium).
- Each Composition lays out only its own regions. Two Compositions are on
  one screen when their layers are the same or have the same parent. When
  two Compositions on one screen place visible regions in the same zone for
  two seconds, the composition warns once for that pair and zone. A disabled
  layer and a region in the top bar strip do not count. Put the HUD in one
  Composition.
- The decision uses only the measured sizes and the size of the composition.
  Thus a rotation, a resize or a text size change gives the same forms as a
  new mount of the same size.
- The composition measures each form with its scale. To animate part of a
  region with `UIScale`, put it on an inner frame inside a holder of fixed
  size. This keeps the animation from changing the region's size or form.
- When the size of the composition changes, a region that changes form
  scales from 0.94 to 1 in 0.15 seconds, Cubic Out, from the edge of its
  zone. The first layout after a mount does not move. Its measurement holds
  until the motion ends. Reduced motion removes the motion.
