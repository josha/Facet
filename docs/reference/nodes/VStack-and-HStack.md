### VStack and HStack

<!-- aliases: VStack and HStack | vstack-and-hstack -->

`UI.VStack(spec) -> Frame` stacks its children vertically. `UI.HStack(spec) ->
Frame` stacks them horizontally. Both hug their content by default. Options:
`gap`, `padding`, `align`, `distribute`, `wrap`, `width` and `height`. `wrap`
sets `UIListLayout.Wraps`. The shared props type is `StackProps`.

Bound a form or collection body with `width = "fill"`. A fill-width field
needs a parent with a defined width; placing two such fields in a hugging
HStack does not divide the available width. Stack fields vertically, or give
each a bounded width and use native flex through [fill](fill.md) to share a row.
Use [AdaptiveStack](AdaptiveStack.reference.md) for short intrinsic-width actions
that should turn into a column when they cannot fit.

A stack with `padding` has an edge, so it keeps its children's shadows inside
it. Each side of its `UIPadding` grows by the farthest a direct child's
`UIShadow` reaches past that child on that side (offset, spread and blur). A
themed Button's drop plate is such a shadow. Hidden children and disabled
shadows take no room. A stack without `padding` is not changed.

A stack with `surface` can set `corners` to `"pill"`, `"square"`, the theme
radius `"control"` or `"panel"`, or a number of pixels; `corners` without
`surface` causes an error.  A pill is fully round at each height, as on a
Button with `corners = "pill"`, and the padding on its long sides grows to
half of its short side.
