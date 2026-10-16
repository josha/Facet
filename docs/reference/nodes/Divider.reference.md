### Divider

`UI.Divider(spec) -> Frame` is a hairline that separates the items of a stack.
It gets its direction from the stack that holds it. In a `VStack` it is a
horizontal line that fills the width. In an `HStack` it is a vertical line that
fills the height. When the stack changes its `FillDirection`, the line turns
with it. `axis = "y"` makes a horizontal line and `axis = "x"` makes a vertical
line, whatever the parent is. A native `Size` replaces the computed size.

- `thickness` is a number of pixels or a theme metric name, such as
  `"strokes.hairline"` or a spacing step. The default is the `strokes.hairline`
  metric of the theme package.
- `appearance` is `"standard"` (the default) or `"strong"`, and can be bound.
  The line has the `facet-divider` tag. The theme paints it in the hairline
  colour at `extra.hairlineOpacity`. `"strong"` adds the `facet-divider-strong`
  tag, which paints at `extra.strongHairlineOpacity` for a pane edge.
