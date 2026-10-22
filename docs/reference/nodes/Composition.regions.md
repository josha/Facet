# Composition.regions

Region zones, ranking, stacking and stable HUD layout.

Keep Region nodes as direct Composition children. Put `Compose.show` inside
a stable stack or frame form, not around the Region.

- `zone` is required: `topLeft`, `top`, `topRight`, `left`, `center`,
  `right`, `bottomLeft`, `bottom`, `bottomRight` or `topbar`. Give two
  readouts that share a sight line, such as level progress and a timed goal,
  their own regions in one `top` or `bottom` zone. They show side by side
  when the row has room.
- `rank` is required: a whole number, 1 or more. Rank 1 is the most
  important region.
- `mayDrop`: when `true`, the region can hide completely after its last form.
- `form`: a writable cell. The composition writes the index of the form that
  shows, or 0 when the region is hidden. Read it to offer the hidden content in
  another place, such as a sheet.
- `leading`: a boolean. The default is `false`. Only a `topbar` region can lead.
  A leading region sits at the start of the strip, beside the Roblox buttons.
- `trailing`: a boolean. The default is `false`. Only a `topbar` region can
  trail, and a region cannot both lead and trail. A trailing region sits at the
  end of the strip, at the far edge from the Roblox buttons.
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
  Each form must be a concrete GuiObject. Put `Compose.show` or other reactive
  children inside a stable stack or frame; do not pass a factory as a form.

A smaller form must keep routes to the richer form's tasks. Use passive text
or an icon for the built-in reveal, or make a button open all omitted choices.
A button that opens one destination consumes its press and does not open the
region's reveal Popover.

See [Composition.layout](Composition.layout.md) for layout rules and
[Composition.layout.step-down](Composition.layout.step-down.md) for fit warnings
and stable measurement during motion.
