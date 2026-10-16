#### Shared models and views

<!-- aliases: Shared models and views | shared-models-and-views -->

Shared-models-and-views contract and option values.

All three containers accept `from`, stable `key`, `selection`, `selectionMode`,
`editing`, `disabled`, `selectable`, `rowActions`, `onActivate`, and model-owned
delete/reorder callbacks. List and grid use `render`; Table columns can use the
same render function. Table also forwards `focusPolicy`, `initialFocus`,
`autoFocus`, `wrapFocus`, `maxRetained` and `onReachEnd` to its virtual body.

When `from` is a filtered projection, supply `selectionFrom = allRecords` to
every view sharing the selection. Facet then preserves hidden selected IDs and
prunes only IDs absent from the authoritative records. Without `selectionFrom`,
it prunes against `from`. Use stable record IDs, not projection indices.
Use `measure = true` with content-sized custom list or grid cells. Measurement
follows the original rendered cell through selection and row-action wrappers.
Tables measure custom cells that use native automatic height or a fixed height.
`UI.CellEditor` uses compact utility text and number fields for inline edits.
Idle and active fields reserve the same space. `label` names the field for
accessibility; it does not add a second caption inside the cell.
It grows with validation messages and text size, and keeps larger targets for
touch and gamepad. Vertical lists and tables use flat themed row highlights;
grid cards retain their control skin. Prefer content-sized cells so theme changes can reflow
the collection. An explicitly fixed outer layout still needs room to scroll.

Delete commands also use `selectionFrom`, so selected records hidden by a
filter remain part of the operation. Apply model commands such as color labels
to selected IDs in the authoritative model. A row action on a selected item
should use that selection; on an unselected item, it should use only that item.
Renaming remains a single-record edit.

On desktop, use click, Command/Ctrl-click and Shift-click with row highlights.
Edit selection marks appear for touch and gamepad. Keep an Edit/Done command
available for those inputs and bind its state to `editing`.

`selectionIndicator = false` hides edit selection marks when composing your own
indicator; it does not change selection behavior.

Keep records and durable drafts in the model. Share selection or editing when
wanted. Keep each view's sort, filter, column widths, scroll and focus separate.
Create records through an application command that allocates a stable ID and
updates `from`. Use the same command from a toolbar or a later drop handler.
The Showcase File library demonstrates that recipe, including model-owned Undo.
