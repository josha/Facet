# VStack-and-HStack.edges

<!-- aliases: stack shadows | stack corners -->

How a VStack or HStack keeps the shadows of its children and rounds its corners.

A stack with `padding` has an edge, so it keeps its children's shadows inside
it. Each side of its `UIPadding` grows by the farthest a direct child's
`UIShadow` reaches past that child on that side (offset, spread and blur). A
themed Button's drop plate is such a shadow. Hidden children and disabled
shadows take no room. A stack without `padding` is not changed.

In a theme that draws plate or control shadows, a VStack or HStack with a
positive `gap` also widens the gap by the hard part (offset and spread) of
its direct children's shadows along its axis, so the authored gap stays
visible between them. A `gap` of 0 or less is not changed, and a wrapped row
does not widen the space between its lines.

A stack with `surface` can set `corners` to `"pill"`, `"square"`, the theme
radius `"control"` or `"panel"`, or a number of pixels; `corners` without
`surface` causes an error. A pill is fully round at each height, as on a
Button with `corners = "pill"`, and the padding on its long sides grows to
half of its short side. `"control"` and `"panel"` follow a theme change. When
the theme draws the `panel` plate with art, the art keeps its shape.

Back to [VStack and HStack](VStack-and-HStack.md).
