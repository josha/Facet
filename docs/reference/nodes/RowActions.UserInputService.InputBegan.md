# RowActions.UserInputService.InputBegan

A mouse click or a touch outside an open row closes its tray. The row observes
`UserInputService.InputBegan` only while its tray is open, and it does not
consume the input. Thus the control under the pointer also receives the press.
A transparent `SwipeGrip` button covers the row content while the row has
actions. It holds the native UIDragDetector, so a drag that starts on a
content Button also opens the tray. A press and release that moves less than
8 pixels is a tap. In a selectable Table, VirtualList or VirtualGrid row, the
grip sends the tap to the row, so the tap selects the row with the click rules
of the collection, and a reorder handle or a cell Button does not activate.
Otherwise the grip sends a tap to the first Facet Button in the content, and
that Button activates as if the player pressed it. The grip is
not a selection stop, so keyboard and gamepad selection still stop on the
content. With touch input, the grip turns its UIDragDetector off and uses the
native `TouchPan` gesture. Thus a vertical pan scrolls the list, and a
horizontal pan opens the tray. The final native pan translation and velocity
are included when deciding whether a full swipe runs the first action.
A touch tap reaches the content Button through the grip.

A tap or a click on the content of the open row closes the tray, and the
content does not activate. While the tray is open, a transparent
`DismissTray` button covers the row content and receives that press. A press
on another row closes the open row, and that other row activates. A press on
the open tray does not close the tray, and its action runs once. A
press during a destructive commit does not stop the commit. The check uses the
row bounds on a ScreenGui, with the top bar inset when the ScreenGui ignores
it. A row on a SurfaceGui or a BillboardGui does not close from an outside
press.
