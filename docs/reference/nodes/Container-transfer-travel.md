### Container transfer travel

<!-- aliases: Container transfer travel | container-transfer-travel -->

`DraggableSpec.hitArea` is an optional GuiObject for bounded pickup. Its measured
screen rectangle includes its leading edges and excludes its trailing edges.
Use the cell's fixed hit node when tile paint grows on hover. The contact keeps
one source through release, even when the pointer passes another tile.
A captured draggable holds all scroll ancestors until the session ends.
A transfer collection opens a slot while a valid item hovers over it. Neighbours
move between measured slots with the theme Travel spring. Leave restores their
positions. The model changes only on placement. A reserved-key return uses its
existing gap. Hit tests use stable slot geometry while paint moves.
Inside `onStart`, an external rack can call `ZoomControls.zoomAt` for its board.
The capture scope grants one request per camera. Later requests and pan stay
locked until release. The rack does not need to be a child of ZoomView.
Set source `returnTravel = true` to keep its recess through a cancelled return.
Return travel uses the shared Travel engine, `motion.durations.travel` and
`motion.easing.travel`. Without this
option, return feedback keeps its positional return and accepted shrink, driven by
the shared Travel engine. The recess clears immediately without returnTravel.

`DropTargetSpec.travel = true` moves the preview to the destination before
calling `onDrop`. `landing(info)` can return `{ x, y, w, h }` in screen pixels
for an insertion slot. Without it, a GUI target uses its own measured rectangle.
Travel uses the shared Travel engine, `motion.durations.travel` and
`motion.easing.travel`. Reduced motion
commits immediately. The preview follows the pointer directly while captured;
travel begins only after release. The source stays an empty slot during travel.
The destination is revalidated at arrival. Cancellation or a removed destination
prevents the drop handler. Existing targets without `travel` keep their immediate
drop contract. A world target needs `landing` for screen travel.

Use `contentOverflow = "clip"` for bounded collection cells. Existing collection
`drop`, `rowDrop`, `onReorder` and insertion metadata support linked containers.
The game updates both models together in `onDrop`. Return or A picks up and
places, Tab or native directional selection chooses a destination, Y changes
between collection insertion and destination navigation, and Escape or B cancels.
