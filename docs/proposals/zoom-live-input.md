# Zoom input repair

The player pans a board with the mouse and uses the wheel on that board.
A pinch must start without a jump. A zoom keeps the pointed content fixed.

The public ZoomView contract stays the same. Check UIDragDetector.DragStart
and DragContinue first. They are scoped to their parent hit area. A board
child can cover that area. UserInputService supplies a separate MouseMovement
InputObject; the held MouseButton1 object does not follow the pointer.
Use that native event for continuation and the shared arbiter for ownership.
Do not wait for a motion clock before applying pointer pan.

GetMouseLocation includes the top inset. GuiBase2d.AbsolutePosition and
InputObject.Position use the inset viewport. Use GuiService.GetGuiInset once
at the conversion boundary. TouchPinch begin initializes the gesture; it
must not request a zero zoom. Only a positive change scale moves the camera.

ScrollingFrame owns touch scroll, CanvasPosition and canvas limits. Native
wheel routing can choose the surrounding page. While the pointer is over
this view, hold its native scroll and its scroll ancestors with the existing
scroll_lock mechanism. Apply wheel pan once in the input callback. Release
the holds on pointer exit, focus loss, disable and disposal. Child drag
arbitration still blocks camera changes. Keep hit order and clipping.

Compose runtime.connect and cleanup own input and scroll holds. runtime.ramp
keeps time-based zoom on the existing shared clock. No new input scheduler
or motion clock is required.

Before code, add Verify cases for separate mouse objects, zero-scale pinch
begin, a 56 pixel inset, competing native wheel writes and ancestor restore.
Sample focus and direct position before the next frame. Keep the existing
live pointer and gamepad checks. Native hit order still needs Studio.
