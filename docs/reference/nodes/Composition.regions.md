# Composition.regions

Region zones, ranking, stacking and stable HUD layout.

- `zone` is required: `topLeft`, `top`, `topRight`, `left`, `center`,
  `right`, `bottomLeft`, `bottom`, `bottomRight` or `topbar`.
- `rank` is required: a whole number, 1 or more. Rank 1 is the most
  important region.
- `mayDrop`: when `true`, the region can hide completely after its last form.
- `form`: a writable cell. The composition writes the index of the form that
  shows, or 0 when the region is hidden. Read it to offer the hidden content in
  another place, such as a sheet.
- `leading`: a boolean. The default is `false`. Only a `topbar` region can lead.
  A leading region sits at the start of the strip, beside the Roblox buttons.
  The other strip regions stay centred in the remaining space.
- `reveal`: a boolean, default `true`. While the region shows a reduced form,
  a tap, click or `A` on that form opens the richest form in a Popover
  anchored at the region (`compact = "popover"`, so a phone keeps it in
  context too). The target is a transparent button under the forms, at least
  the hit floor in size, so a control inside a reduced form keeps its own
  press. A region with `mayDrop` steps to one more form before it hides: a
  small `Reveal` badge with a "…" icon in the same place, which opens the same
  Popover. The Popover hosts the region's own form 1 node, so its state and
  selection carry over, and puts it back when it closes or the region returns
  to its richest form. When not even the badge fits, the region hides and the
  zone shows one `ZoneReveal<Zone>` "…" button beside the zone, outside its
  list flow and at least the hit floor in size, while any of its regions is
  hidden. It opens one Popover that hosts each hidden region's own form 1
  node. `false` turns the affordance and the badges off, for a region whose
  reduced forms lose nothing. The badge is the last form, so
  `form` reads one past the authored forms while it shows.
- `expand`: an optional function that returns content for the Popover in
  place of the region's own form 1.
- The children are the forms of the region, richest first. At least one form
  is necessary. Give each form a pixel or `hug` size. A form that fills its
  parent has no size of its own.

See [Composition.layout](Composition.layout.md) for layout rules.
