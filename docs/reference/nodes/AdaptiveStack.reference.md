### AdaptiveStack

<!-- aliases: AdaptiveStack | adaptivestack -->

`UI.AdaptiveStack(spec) -> Frame` is a stack that changes its axis. The
children stay mounted when it turns, so they keep their state, focus and
scroll position. Options: `axis`, `gap`, `padding`, `align`, `distribute`,
`width`, `height`, `maxWidth` and `maxHeight`. The props type is `AdaptiveStackProps`.
The maximum dimensions accept bound finite numbers of pixels, zero or more,
and set a native `UISizeConstraint`. An omitted maximum leaves that axis
unbounded. These limits cap the frame; they do not scroll its children.

- `axis` is `"x"` or `"y"` and can be bound. The stack then turns when the
  value changes. Any other value causes an error.
- Without `axis`, the stack is a row while the row fits its width and a column
  when it does not. It fills the width and hugs the height by default.
- The row width is the sum of the widths of the visible children and the
  gaps. The stack measures it the same way as a row and as a column. A child
  with a `UIFlexItem` or a scale width, such as a `Spacer` or a `Divider`,
  counts as no width, because it takes only the room that is left.
- The stack turns into a column when the row width is more than its width. It
  turns back into a row only when the row fits with 8 pixels to spare. So a
  width that changes on every frame, such as during a window resize, turns
  the stack at most once in each direction.
- When a column turns into a row that does not fit, it turns back and keeps
  the row width that it measured. It stays a column until its width holds
  that row or its children change.
- With `align = "stretch"` a column keeps the row width that it last measured,
  because stretched children fill the column. It measures the row again when a
  child is added or removed.
- With `width = "hug"` the stack is always as wide as its row, so it never
  turns. It warns once. Give it a bounded width, or set `axis`.
- With `padding`, the stack grows it to hold its children's shadows, as
  VStack and HStack do.
- The stack compares against its width inside its `padding`. Directly in a
  `ScrollView` that scrolls horizontally, the width is unbounded and the stack
  stays a row.
- `align` stays on the cross axis and `distribute` on the main axis when the
  stack turns. `Divider` and `Spacer` children turn with it.

```luau
UI.AdaptiveStack "Actions" { gap = "s", save, cancel, help }
```

Use it for two or three actions. As a column, every child takes a row. Put
many short choices, such as swatches, chips or filters, in
`HStack { wrap = true }` instead.
