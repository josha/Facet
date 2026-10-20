# SpatialGrid.reference

Use SpatialGrid when an item occupies several cells and the player chooses
its position. Use VirtualGrid for an ordered collection of equal-sized items.

`placement(item)` returns `{ column, row, width, height }` in cells. All four
values are positive integers. Coordinates start at 1. Items must stay inside
the grid and must not overlap. Keys keep the rendered item alive when it moves.

`columns` and `rows` are fixed for the mounted grid. `cellSize` and `gap` can
change. The cell size is at least the theme's minimum target size. The grid
uses its intrinsic size by default. Put it inside a ScrollView when it does
not fit. Do not shrink cells below usable input targets.

To place items, supply `drag(current, key) -> DraggableSpec`, `drop`, and
`footprint(payload) -> Vector2?`. The vector gives the incoming width and
height in cells. Return nil to reject an unsupported payload.

The existing [draggable and dropTarget](draggable-and-dropTarget.draggable.md)
contract applies. `drop.onDrop(payload, info)` receives
`info.placement = { column, row, width, height }`. The grid checks the full
footprint before it calls the consumer's `accepts`, and checks again before
commit. A move can overlap the source item's old cells; a copy cannot.
The consumer updates its model. Return `"pending"` and use `info.complete`
when a server must approve the move. Inventory rules, equip slots, stacking,
rotation commands and transfers between models belong to the consumer.

Pointer and held-touch placement preserve the pickup point. A touch tap arms
the item by default. Keyboard Return and gamepad A also arm it. Native cell
targets become selectable during the carry; select a cell and confirm.
Escape or gamepad B cancels. The preview outlines the full footprint and the
shared drag status gives a rejection reason.

See the SpatialGrid lab page for a two-container inventory. This control
mounts all cells and items; it is for bounded inventory boards, not world maps.
