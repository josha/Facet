### AdaptiveStack

`UI.AdaptiveStack(spec) -> Frame` is a stack that changes its axis. The
children stay mounted when it turns, so they keep their state, focus and
scroll position. Options: `axis`, `gap`, `padding`, `align`, `distribute`,
`width` and `height`. The props type is `AdaptiveStackProps`.

- `axis` is `"x"` or `"y"` and can be bound. The stack then turns when the
  value changes. Any other value causes an error.
- Without `axis`, the stack is a row while the row fits its width and a column
  when it does not. It fills the width and hugs the height by default.
- The row width is the `AbsoluteContentSize` of its `UIListLayout` while it is
  a row. As a column it adds the widths of the visible children and the gaps.
  A child with a `UIFlexItem` or a scale width, such as a `Divider`, counts
  as no width.
- When a column turns into a row that does not fit, it turns back and stays a
  column until its width or its children change. So the stack never flips on
  every frame.
- With `align = "stretch"` a column keeps the row width that it last measured,
  because stretched children fill the column. It measures the row again when a
  child is added or removed.
- The stack compares against its width inside its `padding`. Directly in a
  `ScrollView` that scrolls horizontally, the width is unbounded and the stack
  stays a row.
- `align` stays on the cross axis and `distribute` on the main axis when the
  stack turns. `Divider` and `Spacer` children turn with it.

```luau
UI.AdaptiveStack "Actions" { gap = "s", save, cancel, help }
```
