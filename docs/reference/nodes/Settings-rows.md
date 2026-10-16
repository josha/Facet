### Settings rows

The `row` form of Button, Toggle and Slider is one list row. The row has the
`facet-list-row` tag and one `Content` frame. `Content` holds the
`LeadingIcon`, then a `Captions` column that fills the width, then the
trailing parts. `Captions` holds the `Title` and the `Description`. The
description is secondary text. The trailing part is the value and chevron of
a Button, the switch of a Toggle, or nothing on a Slider. A Slider puts its
value next to its title and its track below the description.

A row fills its width. Its minimum height is the `controlSize` height, and it
grows with its content. The row takes the `facet-size-<step>` tag of its
`controlSize`, or no size tag for `regular`. Its left and right padding is
the `paddingX` of the step. Its top and bottom padding is half of the step
height minus its `iconSize` and the `xs` space, so a one-line row keeps the
step height. When the `control` chrome of the theme has a larger inset, the
row uses the inset.
A row draws no separator. Put a `Divider` between rows when a list needs one.
