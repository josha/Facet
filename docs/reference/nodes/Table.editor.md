# Table.editor

Editable cells. A column with `editor = "text"`, `"number"`, `"toggle"` or
`"menu"` supplies a text value, a number value, a plain checkbox Toggle or a menu
Picker in each cell. Text and number values appear as labels until the user
starts editing that field. The column `value(item)`, or the field named by `id`, is the
raw value: a string, a number, a boolean or the value of a menu option. `options`
(`{ { value, label } }`) configures a menu. `min`, `max` and `step` configure a
number. Each accepted edit calls the `onCellChange(rowKey, columnId, value)` of
the table, which an editor column requires. The caller updates its rows, and a
row change updates the cell. An edit that does not change the value proposes
nothing. Table uses the same `CellEditor` as custom list and grid cells.
A rejected edit keeps the draft and shows an error. Supply `draft(key)` on a
text or number column to keep its draft outside recycled cells, and
`validate(value)` to return an error message or nil. Without a supplied draft,
the draft lasts only as long as the mounted cell. A column can supply
`editable(item)` to permit or lock that field for each record. It defaults to
true. A disabled row blocks every field. Collection `editing` controls the
collection interaction mode; it does not change field permissions. Use
`editLabel` on the column to name its edit action. Native Return or blur
commits; Escape or B cancels to the latest model value. Unmounting never commits.
An editor with `render`, an unknown editor word, a menu without
`options`, editor settings on a column without `editor`, and an editor column
without `onCellChange` cause an error.
