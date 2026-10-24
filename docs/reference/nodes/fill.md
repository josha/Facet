### fill

<!-- aliases: fill | fill -->

`UI.fill(weight?) -> UIFlexItem` makes a child grow along the main axis of its
stack. Put the result in the children of the control:
`UI.Text { text = "Name", UI.fill() }`. Without a weight, the item uses
`UIFlexMode.Fill`. With a weight, it uses `UIFlexMode.Custom` with that
`GrowRatio` and `ShrinkRatio`. The weight must be a positive number. For the
cross axis, use `align = "stretch"` on the stack or `width = "fill"` on a
container. Fill also shrinks: use it in a row that has a bounded width. In a
hugging stack or a Region form, a filled Button can shrink below its label.
There, give the Button a fixed width, or set `align = "stretch"` on a VStack.
