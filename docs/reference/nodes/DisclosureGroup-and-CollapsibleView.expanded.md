# DisclosureGroup-and-CollapsibleView.expanded

Both require a writable `expanded` and `content`. DisclosureGroup expands its
content in the document flow. The content is in a clipped Frame named
`Reveal` that holds a Frame named `RevealFade`, which fades. The height of `Reveal`
opens with the motion, and then follows the content with `AutomaticSize`.
The chevron keeps its `chevron.trailing` and `chevron.down` art and turns
between them. For outer layout, use the native properties on their returned
roots. See [Motion](Motion.md).

CollapsibleView returns its trigger, a pill Button (`corners = "pill"` unless
you pass `corners`).

- Collapsed, the trigger shows `label` on one line. The label truncates at
  the end (`TextTruncate.AtEnd`) and shrinks in the row (a `UIFlexItem` in
  `Shrink` mode). A `chevron.down` trailing icon is the More affordance. Pass
  `trailingIcon` to replace it.
- When `expanded` is true, a panel named `Expanded` grows out of the trigger:
  its rectangle moves from the trigger's rectangle to its open rectangle on
  the page's layer, and it clips its content. The open panel is at least
  `controls.popup.panelWidth` wide (or the trigger's width), as tall as its
  content, and stays inside the layer by `space.s`. A taller content scrolls
  in a `ScrollingFrame` named `ExpandedScroll`. The content is laid out once at
  the open size in a Frame named `ExpandedFade`, which fades in, so the text
  does not rewrap while the panel grows. The page does not move and is not
  dimmed.
- The panel is on the modal layer, so the selection moves into it: to
  `initialFocus` if you give it, otherwise to the first selectable node.
- The trigger (A, Return or a tap), a tap outside the panel, the Close button
  and Cancel (Escape or ButtonB) collapse it. The selection goes back to the
  trigger.
- `outsideDismiss` defaults to `true`. Set it to `false` to ignore outside
  clicks and taps. It accepts a boolean, cell or formula. Close and Cancel
  still collapse the panel.
- `dismissButton = false` hides Close unless the preferred input is a gamepad.
- Reduced motion opens and closes the plate at once.
- The panel is on the modal layer and is not clipped by the trigger’s ancestors.
