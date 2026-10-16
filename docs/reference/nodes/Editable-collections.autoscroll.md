# Editable-collections.autoscroll

Editable-collections.autoscroll option values and behavior.

- Pointer: drag a row, or one of the selected rows to move them all, more than
  6 pixels along a list, or in either direction in a grid. There is no handle.
  The drag shows native copies of the selected cells, stacked up to three deep.
  Grid previews retain tile dimensions and insertion positions use both axes.
  The drag scrolls the collection near its
  edges unless `autoscroll = false`. Once the list can move no further that
  way, the nearest enclosing ScrollingFrame whose own 40 pixel edge band holds
  the pointer scrolls instead (innermost first), so a list inside a page hands
  the drag to the page. Delete or Backspace removes the selected
  rows.
- Touch: hold a finger still on a row for a third of a second to pick it up
  and move it; a finger that moves first scrolls the list or swipes the row.
- Touch and gamepad, and a keyboard with no mouse on a reorderable Table: a
  Table without a supplied `editing` shows a toolbar with an `Edit` button (`Done` while editing; its width fits the wider word).
  Edit mode shows, inside each row band, a round red minus at the leading
  edge (deletable, unless `selectionMode = "multiple"`) and a move handle at
  the trailing edge (reorderable); the row content slides to make room
  (instantly with reduced motion). Grid edit controls sit in a top strip,
  preserving the full content width; measured tiles include the strip height.
  Grid handles use native `UIDragDetector` plane movement. The minus reveals a `Delete` button at the
  trailing edge, which confirms. A handle
  drags, or Return or the A button starts a move that the arrows or D-pad
  place and Return, A or `Drop` ends. The X
  button removes the selected rows, and L1 and R1 move them by one slot. A
  VirtualList reads the `editing` cell that you supply and show your own
  Edit control.
- Without a readable input class the edit controls always show.
- A selectable collection (`selectionMode` other than `"none"`) that is not
  `deletable`, and any `selectionMode = "multiple"` collection, marks each
  row's selection at the leading edge while `editing` is true: a ring
  (`facet-radio-mark`) with a filled dot on a selected row. The mark is paint
  and takes no focus. A Table with a supplied `editing` shows it even when it
  is neither reorderable nor deletable.
- While `editing` is true, a tap, a click, Return or the A button on a row of
  a selectable collection toggles that row's selection and does not run
  `onActivate`. With `selectionMode = "single"` the row becomes the one
  selected row, and a second press on it clears the selection. A deletable
  Table's own
  toolbar shows a `DeleteSelected` button (`Delete`) beside `Edit` while it
  edits, except with a gamepad, whose X button does the same; it removes the
  selected rows through `onDelete` and is disabled while nothing is selected.
