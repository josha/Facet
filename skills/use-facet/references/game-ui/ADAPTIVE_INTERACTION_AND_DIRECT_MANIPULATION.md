# Direct manipulation

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

Direct manipulation helps when position or movement explains the task: placing furniture, arranging a loadout, sorting a hand of cards.  When the player only needs a destination or a precise value, a command or a value control is easier.  Dragging equipment onto a slot and choosing "Equip to slot" can call the same model operation.

Define the operation first: move, copy, apply, reorder, resize or adjust.  Keep the source identity, the eligibility and the accepted result the same for every input.

## Choose the route before the gesture

Give the player a way to discover the operation, select its target, inspect the proposed result, commit and cancel.  Keep these stages with touch, pointer, keyboard and gamepad; only the physical gesture differs.  The alternative route works without precise movement or a sustained hold, and it is available before the player learns to drag.

Facet: use the owning behavior instead of adding a second drag system.  Collections provide `drag`, `drop` and `rowDrop`.  Use a separate `dropTarget` for a distinct subtarget.  `draggable` uses native UIDragDetector recognition and provides pickup and drop through native selection.  Custom adjusters can use `adjustable`, and commands on selected targets can use `commandScope`.  Native selection, scrolling and drag detection supply the mechanisms; the game decides what a move means.  Read their API nodes before you build.

## Avoid competing gestures

Touch pickup coexists with scrolling.  `draggable` waits for a long press, and moving first scrolls.  When intentions conflict, give the object a drag handle, or use a long press or a deliberate manipulation mode.  Where a hold is unsuitable, use an explicit edit mode or the documented `armOnTap` route: a tap picks up, scrolling stays available and a tap on a target drops.  Explain the active mode and how to cancel it.  Keep the source and destination feedback visible around the held finger.  Pointer movement tracks the cursor directly, without easing behind it.

Give gamepad an explicit pickup, destination, commit and cancel, or an equivalent command.  Collection `onActivate` can take precedence over pickup outside Edit mode; adding `drag` alone does not make one activation do both.  Show whether the next activation opens, picks up or commits.  A press that became a drag never also activates the source or a control behind it.

Inspection input belongs to its preview.  A press that opens or buys an object never also zooms or rotates its camera.  Use ZoomView for a spatial board, with its documented pan, zoom and fit commands, and keep global actions outside the zoomed content.  Provide discrete commands for any required adjustment that would otherwise need continuous analog input.

Keep spatial bounds and scale stable as content appears.  Reveal an offscreen selection only when needed; do not recenter on every selection.  When the input, the viewport or the source changes during a manipulation, keep a clear candidate or cancel safely.  Never infer a committed drop from that change.

## Validate the destination

Show the source, the candidate destination and the proposed operation before commitment.  Distinguish valid, rejected and pending targets beyond color.  Give a useful rejection reason near the target or in stable task feedback, and keep cancel available without losing the source.

Facet:

- `accepts` checks eligibility during targeting and release.  It never mutates records or spends resources.
- A rejected visible target blocks a drop unless `passThrough` explicitly permits it.  Never pass a destructive action silently to something behind the target.
- World targets need a reachable `focusTarget` for placement without a pointer.
- For a pending drop, call `info.complete(true)` before you change the presentation model, and apply the change only if it returns true.  Refuse with `info.complete(false, reason)`.  A canceled or late completion cannot commit the same UI operation twice.  Reconcile durable server results separately.
- The built-in drag feedback uses Travel.  Keep a return destination where needed instead of creating copies of the carried object.  Reduced motion keeps the same accepted result and cancellation.

## Check

Test valid, invalid, occupied and disappearing targets; scrolling and recycling; cancellation; pending acceptance and rejection; and the equivalent command route.  Change the input and the viewport during an operation.  Confirm that neither a cancellation nor a delayed reply moves the wrong item or activates the source.
