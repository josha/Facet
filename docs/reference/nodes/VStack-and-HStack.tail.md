# VStack-and-HStack.tail

<!-- aliases: stack tail | speech bubble -->

How a panel VStack or HStack draws a tail.

A stack with `surface = "panel"` can set `tail` to point from one edge, as
on a speech bubble. `tail` is `"top"`, `"bottom"`, `"left"` or `"right"`, or
a table such as `{ side = "bottom", at = 0.3 }`, where `at` (0 to 1, default
0.5) is the place along that edge. The tail stays clear of the rounded
corners; on an edge too short to hold it beside them, such as the side of a
pill, Facet draws no tail. Facet draws one outline around the plate and the
tail with the stroke that the theme gives a panel (the finish edge or a
`.facet-panel::UIStroke` rule), and no outline when the panel has no stroke.
It uses the theme's `panelTail` art when it has one, and a `status` tints the
tail with the plate. The tail is drawn outside the box of the stack, so give
the part beside it room. `tail` without `surface = "panel"` causes an error.

```luau
UI.VStack "Speech" {
  surface = "panel", padding = "s", tail = { side = "bottom", at = 0.3 },
  UI.Text { text = "Is it snack time?", textRole = "strong" },
}
```

Back to [VStack and HStack](VStack-and-HStack.md).
