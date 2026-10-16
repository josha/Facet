### fill

<!-- aliases: fill | fill -->

`UI.fill(weight?) -> UIFlexItem` makes a child grow along the main axis of its
stack. Put the result in the children of the control:
`UI.Text { text = "Name", UI.fill() }`. Without a weight, the item uses
`UIFlexMode.Fill`. With a weight, it uses `UIFlexMode.Custom` with that
`GrowRatio` and `ShrinkRatio`. The weight must be a positive number. For the
cross axis, use `align = "stretch"` on the stack or `width = "fill"` on a
container.
