### ZStack

<!-- aliases: ZStack | zstack -->

`UI.ZStack(spec) -> Frame` puts its children on top of each other. It has no
layout object. A later child gets a higher `ZIndex`. A child that sets its own
`ZIndex` keeps it. `alignH` and `alignV` (`start`, `center` or `end`) set the
`AnchorPoint` and the scale `Position` of each child. On an axis that hugs
its content, the stack aligns each child by offset against the largest child on
that axis, so the stack keeps its size. When the box of the stack is larger
than its largest child on that axis, for example because of a native `Size`,
the stack aligns each child in its box. A one-line Text in an aligned ZStack
takes `alignH` as its text alignment unless it sets `textAlign`, and it
shrinks to fit the box as [Text](Text.reference.md) describes. Options: `padding`,
`alignH`, `alignV`, `width`, `height`, `maxWidth`, `maxHeight`, `corners` and `ground`
(see [VStack and HStack](VStack-and-HStack.md)).
`corners` rounds the stack's own frame with a native `UICorner` named
`Corners`. It takes the same values as the
[Group corners option](Group.reference.md). A Frame does not clip children to
a rounded shape, so use a Group when the content must follow the corners.
The maximum dimensions accept bound finite numbers of pixels, zero or more,
and set a native `UISizeConstraint`. An omitted maximum leaves that axis
unbounded. These limits cap the frame; they do not scroll its children.
