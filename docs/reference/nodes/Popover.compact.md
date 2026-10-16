# Popover.compact

`compact` is `sheet` (the default) or `popover`. With `sheet`, a touch player
on a layer narrower than 600 pixels gets the Sheet route. A live change of
input or width switches the route without a proposal. Only one content owner
exists at a time, and the selection returns to the same content node. The
sheet uses the `hug` detent, so its height fits the content. `title` (a string
or a bound string) shows in the sheet header beside Done. Without `title`, the
header shows only Done.

The trigger keeps its own `onActivate`. The panel scales and fades from the
edge nearest to its source. See [Motion](Motion.md).
