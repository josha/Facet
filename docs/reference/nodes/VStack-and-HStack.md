### VStack and HStack

<!-- aliases: VStack and HStack | vstack-and-hstack -->

`UI.VStack(spec) -> Frame` stacks its children vertically. `UI.HStack(spec) ->
Frame` stacks them horizontally. Both hug their content by default. Options:
`gap`, `padding`, `align`, `distribute`, `wrap`, `width` and `height`. `wrap`
sets `UIListLayout.Wraps`. The shared props type is `StackProps`.

A stack with `padding` has an edge, so it keeps its children's shadows inside
it. Each side of its `UIPadding` grows by the farthest a direct child's
`UIShadow` reaches past that child on that side (offset, spread and blur). A
themed Button's drop plate is such a shadow. Hidden children and disabled
shadows take no room. A stack without `padding` is not changed.
