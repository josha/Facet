# NavigationSplitView.resizable

Set `resizable = false` to keep a one-pixel separator without dragging or a
divider focus stop. The pane size cell still controls the layout. The default
is `true`. Set `alwaysShowResizeHandle = true` to keep the grip visible without
hovering. Its default is `false`; it has no effect when resizing is disabled
or the layout is compact. Both options accept reactive values.

Drag the divider with a pointer or touch. The pointer shows a resize cursor.
The thin separator has a small handle on hover, during a drag, and for touch
or gamepad input. With focus on the divider, use L1/R1
or comma/period to resize. The arrows and left stick move focus. Crossing
between panes stops on the divider; its focus ring surrounds the grip. Left/Right
cross side-by-side panes; Up/Down cross stacked panes. The
native drag detector yields to gamepad navigation. On a compact layout,
B or Escape returns from detail to sidebar before an enclosing navigation
stack handles Back. Put a NavigationStack in a pane for deeper navigation.
