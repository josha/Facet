# Editable-collections.single

In `single` mode, each activation selects only that row, and the modifiers
have no effect. A selected Table row carries the `facet-selected` tag, so the
theme paints it in `controlSelected`. Rows that `selectable` or `disabled` refuse are never selected.

`selectable(item)`, `disabled(item)`, `onActivate(item, key, input, clickCount)`
and `rowActions(current, key)` specialize rows. `onActivate` receives the same
native activation facts as in VirtualList. The insertion slot of `onReorder` is zero-based among the remaining rows.

Sizes:

- The header height starts at 40.
- Rows follow a ladder by viewing distance (`itemSize` pins the minimum on
  every rung):
  - Near (pointer, keyboard, or a gamepad at a desk): one line, at the larger
    of 40 and the regular control height (44 with a gamepad).
  - Touch: cells wrap, and a row starts at two lines of body text plus 16, at
    least `targetSizes.minimum`.
  - Ten-foot (`ctx.tenFoot()`: a TV interface, or a Large display with no
    touch and no mouse): one line, at least the large control height.
- The native touch and gamepad minimum header height is `44`.
- Native text bounds can make rows and the header larger.

The header band and each row paint a rounded band (`radii.control`) through
the theme tags `facet-tablehead` and `facet-tablerow`; a 1 pixel inner
`surface` stroke separates adjacent rows, and a selected row is the same band
in `controlSelected`.
`alternatingRows = true` also tags every second row `facet-tablerow-alternate`.
The palette roles are `tableHeader`, `tableRow` and `tableRowAlternate`. Each
heading is a standard Button without a plate (`facet-tableheading`) on the
band, so a skinned theme paints its `control` art on it.

`header = false` removes the header band. `scrolls = false` mounts all rows and
sizes the table to its content. Otherwise, `mode` selects the Compose windowed
or all lifetime. The collection measurement, status, controls, focus and
follow options also apply.
