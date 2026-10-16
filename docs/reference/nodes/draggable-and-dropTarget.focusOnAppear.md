# draggable-and-dropTarget.focusOnAppear

- `focusOnAppear = true` selects the first selectable item in `group`
  (`GuiService:Select(group)`) when `group` arrives in a ScreenGui.
  `focusOnAppear = "Save"` selects the descendant with that name. The claim
  happens only while the player navigates by selection: something is
  selected, or the preferred input is a gamepad. A pointer or touch player
  gets no selection.
- `returnFocus = true` remembers what was selected before the claim. When the
  owner ends and the selection is inside `group` or gone, the selection
  returns there. When that item has left the screen, the first selectable item
  of the screen gets the selection, so the ring never goes blank. A selection
  that the player moved outside `group` stays.

An unknown option causes an error.
