### Spacer

<!-- aliases: Spacer | spacer -->

`UI.Spacer(spec) -> Frame` takes the free space along the main axis of its
stack. It is a transparent Frame with a `UIFlexItem` in `Fill` mode.
`minLength` is a number of pixels or a spacing step, such as `"m"`, and can be
bound. It is the length that the spacer keeps when there is no free space. The
default is 0. The spacer gets its axis from the stack that holds it. A native
`Size` replaces the computed size. Use `UI.fill()` to make an existing child
grow instead.
