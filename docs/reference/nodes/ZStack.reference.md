### ZStack

<!-- aliases: ZStack | zstack -->

`UI.ZStack(spec) -> Frame` puts its children on top of each other. It has no
layout object. A later child gets a higher `ZIndex`. A child that sets its own
`ZIndex` keeps it. `alignH` and `alignV` (`start`, `center` or `end`) set the
`AnchorPoint` and the scale `Position` of each child. On an axis that hugs
its content, the stack aligns each child by offset against the largest child on
that axis, so the stack keeps its size. Options: `padding`,
`alignH`, `alignV`, `width`, `height`, `maxWidth` and `maxHeight`.
The maximum dimensions accept bound finite numbers of pixels, zero or more,
and set a native `UISizeConstraint`. An omitted maximum leaves that axis
unbounded. These limits cap the frame; they do not scroll its children.
