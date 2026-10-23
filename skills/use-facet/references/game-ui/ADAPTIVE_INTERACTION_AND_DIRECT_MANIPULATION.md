# Adaptive manipulation

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

Define the operation first: move, copy, apply, reorder, resize or adjust.
Keep source identity, eligibility and accepted result common across inputs.
Direct manipulation helps when position or movement explains the task. When
the player only needs a destination or a precise value, a command or value
control can be easier. For example, dragging equipment onto a slot and choosing
"Equip to slot" can invoke the same model operation.

## Choose the route before the gesture

Give the player a way to discover the operation, select its target, inspect
the proposed result, commit and cancel. Preserve these stages with touch,
pointer, keyboard and gamepad; the physical gesture can differ. The
alternative must work without precise movement or a sustained hold. Do not
require the player to learn dragging before the command route appears.

Use the owning Facet behavior rather than adding a second drag system.
Collections provide `drag`, `drop` and `rowDrop`. Use a separate `dropTarget`
for a distinct subtarget. `draggable` uses native UIDragDetector recognition
and provides pickup and drop through native selection. Custom adjusters can
use `adjustable`; commands on selected targets can use `commandScope`.
Read their API nodes before implementation. Native selection, scrolling and
drag detection supply mechanisms; the game owns what a move means.

## Avoid competing gestures

Touch pickup must coexist with scrolling. `draggable` waits for a long press;
movement first allows scrolling. Use an explicit edit mode
or the documented `armOnTap` route when a hold is unsuitable. In that route,
a tap picks up, scrolling remains available, and a target tap drops. Explain
the active mode and its cancellation. Keep source and destination feedback
visible around the held finger. Pointer movement should track directly,
without easing behind the cursor.

Give gamepad an explicit pickup, destination, commit and cancel path or an
equivalent command. Collection `onActivate` can take precedence over pickup
outside Edit mode; adding `drag` alone does not make one activation do both.
Show whether the next activation opens, picks up or commits. A press that
became a drag must not also activate the source or a control behind it.

Inspection input belongs to its preview. A press that opens or buys an object
must not also zoom or rotate its camera. Use ZoomView for a spatial board and
its documented pan, zoom and fit commands. Keep global actions outside zoomed
content. Provide discrete commands for any required adjustment that would
otherwise need continuous analog input.

Keep spatial bounds and scale stable as content appears. Reveal an offscreen
selection only as needed; do not recenter on every selection. If input,
viewport or source availability changes during manipulation, retain a clear
candidate or cancel safely. Never infer a committed drop from that change.

## Validate the destination

Show source identity, candidate destination and the proposed operation before
commitment. Distinguish valid, rejected and pending targets beyond color.
Give a useful rejection reason near the target or in stable task feedback.
Keep cancel available without losing the source.

`accepts` checks eligibility during targeting and release; it must not mutate
records or spend resources. A rejected visible target blocks a drop unless
`passThrough` explicitly permits it. Do not silently pass a destructive action
to something behind it. World targets need a reachable `focusTarget` for
non-pointer placement.

For pending drops, call `info.complete(true)` before changing the presentation
model, and apply that change only if it returns true. Complete refusal with
`info.complete(false, reason)`. Canceled or late completion cannot commit the
same UI operation twice. Reconcile durable server results independently.

The built-in drag feedback uses Travel. Preserve a return destination where
needed instead of creating unrelated copies of the carried object. Preserve
the same accepted result and cancellation when motion is reduced.

Test valid, invalid, occupied and disappearing targets; scrolling and recycling;
cancel; pending acceptance and rejection; and the equivalent command route.
Change input and viewport during an operation. Verify that neither cancellation
nor a delayed reply moves the wrong item or activates the source.
