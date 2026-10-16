# draggable-and-dropTarget.collectionId

Escape/B, focus loss, owner disposal, or invalid source/target state cancels
without committing. Collection sessions and preview snapshots outlive a
recycled visual row. Native detectors own ordinary pointer gestures; captured
input continues a drag only after its visual source is recycled. Touch uses
native long-press recognition and captured touch continuation so an ordinary
pan remains available to the ScrollingFrame. Edit handles use native detectors.

Lists, grids, outlines, and tables accept `collectionId`, `drag(items, keys)`,
`drop`, and `rowDrop(current, key)`.
`drag` returns a draggable spec; `drop` uses the target spec above. Use the same
`collectionId` in linked views and carry `{ collection, keys, items }` in the
payload. A move of items present in the destination view calls `onReorder` once. Other accepted drops
call `drop.onDrop` with insertion metadata. The game creates IDs for copies and
new records, preserves IDs for moves, and updates both models together.
Sorted views reject positional insertion until sorting is cleared.

`rowDrop(current, key)` returns a drop target spec, or nil for no destination.
Facet owns its lifetime, row highlight, and native focus target. In a collection
that accepts insertion, the middle half of a row accepts a drop onto the item;
the leading and trailing quarters route to collection insertion. Grids use
horizontal cell edges. Armed touch and gamepad drops target the whole row.
`passThrough` routes payloads that belong in the collection instead of the item.
Disabled rows reject item drops. The model still validates folder cycles and
permissions in `accepts` and applies moves in `onDrop`.

A collapsed folder can accept an item without opening. During an armed drag,
use Y to choose a destination, then Right/Left to expand or collapse an outline
folder. A drops into the focused folder; B cancels. Sibling insertion stays on
the collection's reorder path. Use `UI.dropTarget` in a cell renderer only for
a separate destination within the cell, such as a color well.

`UI.focusSection(group, { focusOnAppear?, returnFocus? })` also says where the
selection goes when a branch appears and leaves. Call it in the component that
builds the branch, such as the content of a `Compose.show` or a detail page.
