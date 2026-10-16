# Editable-collections.rowActions

With touch or gamepad input, a Table with the Edit toolbar accepts cell edits
only while editing; otherwise its editor cells accept edits at all times.
`rowActions` are independent of edit mode.

`sort` is `nil` or `{ column, direction = "ascending" | "descending" }`.
`widths` is a map of column widths. A pointer drags a heading's divider to
resize the column. With a keyboard, focus the divider: Left and Right resize,
Up and Down sort by the column, and Escape returns focus to the heading. Comma
and Period resize the column whose heading or divider has focus.

With a gamepad, the divider is not a selection stop. The D-pad and the left
stick move from one heading to the next heading. While a heading is selected,
L1 makes its column narrower and R1 makes its column wider. Each press changes
the width by 8 pixels, and the width stays between the column's `minWidth` and
`maxWidth`. A column with `resizable = false` has no divider and no resize
action.

`selection` is a key-set map.
`selectionMode` is `single`, `multiple` or `none`. When you supply
`onSortChange`, `onWidthsChange` or `onSelectionChange`, it is a controlled
request. Otherwise the control updates the writable cells.

In `multiple` mode, the selection keys are the same in Table, VirtualList and
VirtualGrid:

- A plain mouse click selects only that row.
- Ctrl-click or Cmd-click adds the row to the selection or removes it.
- Shift-click selects the rows from the anchor to the clicked row. The anchor
  is the last row that a click without Shift selected. A second Shift-click
  makes the range again from the same anchor. Rows that you added with
  Ctrl-click before the anchor stay selected.
- A touch tap, a gamepad press and a plain Return select only that row.
  With `editing = true`, they add the row to the selection or remove it,
  without activating it. Return with Ctrl, Cmd or Shift follows the click rules.
- Shift with an arrow key, Home or End moves the focus and selects the range
  from the anchor to the focused row. Without an anchor, the focused row
  becomes the anchor.
- An arrow key without Shift moves the focus and does not change the
  selection.

`selectionMode = "multiple"` permits multiple selected keys; it does not make
every tap additive. On touch and gamepad, offer an Edit or Select command that
sets `editing` to true, and Done that sets it to false. Done preserves the
selection; the next plain activation selects only its row. For a persistent
multi-choice picker, use `selectionMode = "multiple"` with `editing = true`.
This does not require rename, reorder or delete actions.
