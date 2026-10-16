# Editable-collections.reorderable

Outline, Table, VirtualList and VirtualGrid take the same model.
`reorderable = true` with `onReorder(keys, insertionSlot)` moves rows, and
`deletable = true` with `onDelete(keys)` removes them; both only propose, and
the caller changes its rows. `movable(item)` and `rowDeletable(item)` refuse
single rows. In these containers, a row that `rowDeletable` refuses also loses its
destructive `rowActions`, so no swipe, menu or key can remove it. The paths per
input:
