# Data, space and feedback

## Comparison and hierarchy

Use **Table** when players compare the same attributes across records. Align
values in shared columns, put identity first and give the deciding attribute
enough room. Repeated cards make this comparison harder. Columns collapse only
when given numeric `priority`; higher numbers collapse first, and the first
column remains. Preserve access to hidden facts in detail. Horizontal scrolling
can be preferable to hiding essential comparison data. Route: `Table.sort`.

Use **Outline** for a real hierarchy, such as folders or part assemblies, not
decorative grouping. Expansion, selection and activation are separate actions.
Keys are unique across the tree. `nil` children mean a leaf; an empty array means
an empty folder. `onExpansionChange` requests the change; update the accepted
expansion state. Test collapsed selection, removed records and keyboard/controller
movement. Routes: `Outline.Outline`, `Outline.onActivate`, `Collections`.

## Row actions

Use **RowActions** for commands on one record, such as favorite, rename or remove.
Keep the row's subject and deciding facts prominent; use the item-actions button
and tray for secondary commands instead of giving every row a strip of large
buttons. Keep a frequent primary action directly visible. Selection, opening
detail and acting on a record are different operations.

In a collection, use its `rowActions` integration. Keep actions reachable without
a swipe through the item-actions button/context and keyboard/controller paths.
Default trailing placement reserves space; `actionPlacement = "bottom"` reserves
space below, as VirtualGrid does. Fixed-size rows/cards must budget for that area.
Let actual labels determine tray width; do not clip translated action names.

`leading` and `trailing` contain stable action IDs, labels, optional icons,
enabled state, roles and callbacks. `onOpenChange` is controlled; accept the new
open side in the model. A shared `coordinator` cell keeps only one tray open.
Full swipe is on by default and can run the first action. Disable it on the
relevant edge when a consequential action requires deliberate review.

Swipe capture can intercept embedded field/button input. Use `editing = true`
to expose fields and visible edit actions; `swipeEnabled = false` suppresses
capture without showing edit actions. A tap on an open row closes its tray
without activating the content. Test vertical scroll, horizontal swipe, row
activation, direct commands and controller selection separately.

A destructive callback runs after the departure animation, once; removing the
owner cancels an unfinished departure. Do not treat that animation as server
acceptance. If the model retains the row after a rejected delete, the row
returns; show the rejection and allow retry. Check cancellation, refusal and
successful deletion with focus moving to a useful surviving target.
Routes: `RowActions.editing`, `RowActions.UserInputService.InputBegan`.

## Editing and placement

**CellEditor** and **Table.editor** support editing a record in place. Keep row
identity visible and distinguish reading, editing, pending, rejected and accepted
states. `onChange`/`onCellChange` proposes a value; update the model explicitly.
Keep drafts per record AND field outside recycled rows. External changes preserve
dirty text and can report conflicts. Return/blur commits the edit; Escape/B
cancels to the latest model value; unmount never commits. Collection editing mode
does not grant permission to change a field. Prefer a normal form when the task
requires one Save for the whole draft. Routes: `CellEditor.CellEditor`,
`CellEditor.draft`, `Table.editor`, `Editable-collections`, `Shared-models-and-views`.

For **reorder and transfer**, use the collection's own gestures, stable keys and
model state. Do not attach another draggable to the same row. `onReorder` proposes
keys and a zero-based insertion slot among the remaining items. Sorted views
reject positional insertion. `collectionId`, `drag`, `drop` and `rowDrop` give
collection and row destinations. Routes: `Editable-collections`,
`VirtualList-and-VirtualGrid.selection`.

Use **draggable/dropTarget** for individual slots or UI-to-world transfer. Show
the item being carried, valid destinations and a useful rejection reason. Keep
an equivalent select-destination-confirm path; no required action should be
drag-only. Touch defaults to long press; immediate horizontal pickup can coexist
with vertical scrolling when configured with `touchDragAxis = "X"`. World
targets need a `focusTarget` for selection-based interaction. Previewing a large
cloned tree can be expensive; provide a simpler preview where appropriate.

The game owns validation and atomic updates. For pending approval, return
`"pending"`, then call `info.complete(true)` before changing the model; commit
only if it returns true. A late or canceled operation can return false. Keep
server reconciliation separate: canceling the local gesture does not roll back
an accepted server transaction. Reconcile authoritative revisions through the
durable game model even if that local completion was canceled. Check
rejection, cancellation, removed source/target, overlaps, scrolling and return
focus. Visible UI and world occlusion affect target picking. Routes:
`draggable-and-dropTarget.draggable`, `draggable-and-dropTarget.collectionId`,
`draggable-and-dropTarget.operation`, `draggable-and-dropTarget.payload`.

Use **SpatialGrid** when the footprint and position have meaning, as in packing
or equipment boards. Use VirtualGrid for an ordered collection of equal tiles.
Placements use positive integer cells with no overlap. Mounted row/column counts
are fixed; keys stay stable as items move. The control validates the full
footprint; the game still owns inventory rules and accepted updates. A move may
overlap its old cells; a copy may not. Touch tap, Return or A can arm an item;
select a cell and confirm, or Escape/B to cancel. It mounts every cell/item, so
keep the board bounded. Scroll when needed instead of shrinking input targets.
Route: `SpatialGrid.reference`.

## Inspection and maps

Use **Stage** to make a real object the subject of inspection. Allocate decisive
space to the object, then fit its camera; a large container with a tiny subject
does not create hierarchy. Keep the name, deciding attributes and main action
near it. Bound both axes, pause inactive animation through `live`, and avoid
eagerly constructing many animated previews in a scrolling collection. Route:
`Stage.reference`; see the [inspection example](../examples/inspection.luau).

Use **ZoomView + Path** for a map, blueprint or relationship board whose spatial
relationships matter. Keep identity, zoom/reset actions and the selected detail
readable outside the canvas. Do not miniaturize a normal form to make it fit.
ZoomView creates content once. `contentSize` and `zoomTo` rectangles use content
pixels; `zoomAt` uses a screen point. Camera calls can fail before measurement or
during a child drag. Wheel pans and Ctrl-wheel zooms; child controls retain input.
Path draws strokes, not fills, with at most 100 normalized control points. Test
bounded navigation, reset, selection, child drag and reachable controller commands.
Routes: `ZoomView.ZoomView`, `ZoomView.onStart`, `Path.reference`, `Path-shapes`.

## World information

Use **worldAnchor + WorldMarker** to relate a teammate, objective or destination
to the scene. Keep only useful markers, with clear priority; do not cover every
object. Offscreen arrows need `offscreen = "retain"` on worldAnchor; the default
hides offscreen targets. The marker clamps to its parent, so give it the intended
safe-area bounds. The game owns proximity, permissions and target lifetime.
Dispose the projection binding; optional occlusion adds a raycast. Remove fulfilled
objectives. Routes: `worldAnchor`, `WorldMarker.reference`.

Use **DiegeticScreen** when presenting an existing interface on a world surface
helps the task, such as a terminal. It moves existing ScreenGui layers and
preserves state; do not mount a second copy of the app. Include the complete
backdrop. While pulled back, the surface is a return target, not an interactive
miniature app. Resize returns to screen mode; provide an `onUnavailable` fallback.
The game owns camera and scene framing. For an object preview, use Stage instead.
Route: `DiegeticScreen.reference`.

## Feedback and continuity

Use **Travel** when one item moves between persistent slots and that continuity
helps explain equip, transfer or an accepted reward. Content runs once. Its
returned Frame is an ownership anchor; destroying the anchor, visual or current
slot ends Travel permanently. `onLanded` includes initial placement and may run
during construction, so it cannot mean the game accepted an action. Reduced
motion lands immediately. Routes: `Travel.Travel`, `Travel.ZIndexBehavior`.

Use **ProgressView/Timer** for measured progress, **Notice** for information that
must remain available, and **Toast** for brief results. A disappearing toast is
not the sole record of an important failure. **Skeleton** can preserve layout
while loading; it is not a recovery state. **ErrorBoundary** can contain a render
failure; it does not replace game request validation. Keep a readable retry or
return path. Retrieve their cards/references through `Controls` or search.

Use **Flash/Typewriter** only when they explain an event or support the game's
voice. Required meaning must survive skipped or reduced motion. Own effect
lifetimes, stop inactive work, and verify after successful returns that frame
time and retained memory do not grow. Routes: `Effect-sequences`, `Custom-transitions`.
