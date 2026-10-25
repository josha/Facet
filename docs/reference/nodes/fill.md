### fill

<!-- aliases: fill | fill -->

`UI.fill(weight?) -> UIFlexItem` makes a child grow along the main axis of its
stack. Put the result in the children of a Button or a stack:
`UI.Button { label = "Play", UI.fill() }`. Text and other hugging leaves
ignore it, because Roblox does not flex an automatic-size axis; put
`UI.Spacer()` beside them instead. Without a weight, the item uses
`UIFlexMode.Fill`. With a weight, it uses `UIFlexMode.Custom` with that
`GrowRatio` and `ShrinkRatio`. The weight must be a positive number. For the
cross axis, use `align = "stretch"` on the stack or `width = "fill"` on a
container. Fill also shrinks: use it in a row that has a bounded width. In a
hugging stack or a Region form, a filled Button can shrink below its label.
There, give the Button a fixed width, or set `align = "stretch"` on a VStack.
