# Gesture arbitration and container transfer

## Player tasks

Move one tile from a rack to a board. Move it back. Change its rack position.
Pan or scroll empty space. Press a tile without moving it. Double-tap a surface
to change zoom. Each contact must keep one item and one gesture.

## Shared contract

Use one arbiter per UserInputService. The shared implementation is
`src/ui/gesture_arbitration.luau`; `src/ui/gesture_service.luau` shares it across
control factories. `UI.gestureArbiter(surface)` exposes the same typed contract to a
zoom control. The shared module has `begin`, `move`, `claim`, `get`, `finish` and `cancelOwner`.
The public binding owns cancellation through Compose cleanup.
The pointer is its InputObject identity. The owner is the native source node.
`begin` freezes the owner and screen contact point. A second begin cannot replace
that owner. `get` returns a copy of the decision. All positions are screen pixels.

| Event | Decision |
|---|---|
| Down inside a draggable hit rectangle | Pending drag or press, with one source. |
| Down on empty surface | Pending pan, scroll or press. |
| First movement of at least 6 pixels, immediate drag on its allowed axis | Drag. Equal axis movement belongs to drag. |
| First movement of at least 6 pixels across that axis, or before long press | Scroll when a scroll ancestor exists; otherwise pan. |
| Native TouchLongPress Begin before threshold | Drag for long-press pickup. |
| Release below threshold | Press through native activation. |
| Second native activation on the same surface | Double-tap when the preceding contact did not move or cancel. |
| Cancel, lost window focus or owner disposal | Cancel. No press or drop. |

A decision holds until release or cancel. Later movement, a neighbour, a long
press or a zoom request cannot replace it. The source hit rectangle uses
inclusive leading edges and exclusive trailing edges. Collection content must
stay clipped to its cell. Paint can grow; the pickup rectangle cannot grow into
another slot. Native GUI hit order chooses overlapping surfaces.

A drag locks every scroll ancestor before pickup callbacks run. It restores
only the values that it held. ScrollView consults the arbiter before boundary
handoff. A zoom control must consult it before pan and double-tap, and freeze
its camera while a source contact is pending or captured. A second finger must
not turn a captured single-pointer drag into a pinch.

## Engine and Compose review

Checked local Roblox references: UIDragDetector.DragStart, DragContinue,
DragEnd, DragStyle, ResponseStyle and SetDragStyleFunction; GuiObject.InputBegan,
TouchLongPress and TouchPan; GuiButton.Activated; ScrollingFrame.ScrollingEnabled
and CanvasPosition; PlayerGui.GetGuiObjectsAtPosition; GuiService.SelectedObject.
Use these for detection, scrolling, hit order and selection. They do not give
linked drag, pan and scroll controls a common final decision or item identity.
The arbiter adds only that control policy. Native long press supplies its time.
The 6-pixel threshold keeps the existing draggable contract.

Checked pinned Compose: cleanup, currentOwner, createSlot, portal,
runtime.mount, runtime.connect, runtime.tween and OrderedCollection placement.
Use them for ownership, a screen preview, travel and insertion. They do not
choose which Facet gesture can use a contact. No vendor change is needed.

Word Amigos currently freezes tile identity and zoom in CaptureInput and
Capture, finds DragGhost in DragOrigin, calculates rack insertion itself, and
runs separate flights in RenderFlight. Facet should own this UI policy. The
game must still validate a move and update both models in one transaction.

## Transfer API

Extend existing `UI.draggable` and `UI.dropTarget`. Add a source `hitArea` for a
bounded pickup node. Add target `landing(info)` for a screen rectangle and
`travel = true` for theme-timed travel on accepted drops. Source `returnTravel = true` keeps the recess during return or cancel travel.
Existing sources keep positional return and accepted shrink feedback. These
now use the same shared Travel engine. Keep existing drop and pending confirmation rules. Keep the source
recess and destination slot until travel ends. The preview receives the current
screen contact directly in the input callback. There is no tween during capture.

Use existing VirtualGrid and VirtualList insertion for target slot feedback,
Compose placement for rack reflow, and native selection for destination moves.
Return/A picks up and places; arrows, D-pad and Tab move between slots and
containers; Escape/B cancels. The Lab task has a 7-slot rack and a 5 by 5 board.
Controls options include pickup policy, bounded hits and rejection. Variants
include scaled and scrolled parents. States include held, valid, rejected and
cancelled.

## Proof

Register headless cases with Verify and the committed test plan. Prove immutable
capture, exact threshold, axis ties, early scroll then long press, pan refusal,
cancellation and distinct pointers. Sample preview contact on every frame under
scale and scroll. Sample every travel frame, including first and final position.
Check both model directions, rack order, invalid return, tap and controller input.
Live pointer and gamepad suites must repeat these cases with native layout.
A real phone must prove at most one pixel of contact error and no board pan
under capture. Headless geometry is not native evidence.

## Capture camera request

The private arbiter runs the source onStart callback in a capture scope.
claimCamera(surface) grants one request per ancestor surface in that scope.
The accepted camera motion can finish. A pending contact, pan, or later request
cannot obtain that grant. Keyboard and gamepad pickup use the same scope.
Drag hit testing reads measured screen targets each frame and again at release.
Timed return and landing use the shared Travel engine and travel theme metrics.
The default drag and drop timing stays unchanged; these travel options are opt-in.
