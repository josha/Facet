# Camera at capture

The player lifts a tile. The game can call controls.zoomAt(2) in its
onStart callback. The camera holds the content point under the pointer.
One scoped request can finish within motion.durations.zoom. Further camera
commands and pan are blocked until release. External cell writes wait.
The game can call controls.fit() in onEnd to reverse the camera after release.
No idle timer is required when the game uses this call.

Use D's arbiter capture and claimCamera. Use Compose runtime.ramp and owned
frame subscriptions for timed motion. Pinch and pan still write in their
input callbacks. Native UIScale and ScrollingFrame own the transform. A drag
preview stays in the overlay in screen coordinates. After each camera write,
refresh native measured drop targets with the latest pointer position.
Re-hit-test once more at release. Do not add a second input or motion engine.

Measure every frame from fit to 2, the fixed content focus, preview contact
error, changed drawn targets and release selection. Prove reverse after
release. Native input, layout order and the feel of zoom need a phone check.

F-028 includes a collection outside the view. VirtualGrid.drag supplies the
onStart and onEnd callbacks. A capture callback can grant any requested
camera once. The camera records that source and holds until release. It
uses the same arbiter and measured targets as a child source. For an external
rack, the consumer can pass a board screen point to zoomAt, or use zoomTo.
Native InputObject, UIDragDetector and ScrollingFrame supply input and layout;
Compose supplies ownership and the ramp. No consumer frame loop is needed.
