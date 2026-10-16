# RowActions.editing

With `editing = true`, the swipe overlay is hidden so embedded fields and
buttons receive native input. Visible edit actions and the context menu remain
available. `swipeEnabled = false` suppresses swipe capture without showing edit
actions. Collection `rowActions` use that option while the collection is editing.
An action factory can still supply `editing` to show its own edit actions.

`content` is native content or a factory. `leading` and `trailing` contain
`{ id, label, icon, enabled, role, onActivate }` actions. `open` is `nil`,
`leading` or `trailing`. `onOpenChange` is controlled.

The item-actions button reserves trailing space by default.
`actionPlacement = "bottom"` reserves space below the content instead.
VirtualGrid uses bottom placement and includes this area in measured item
heights. Its button uses a circular utility appearance so a theme does not
add a large framed button inside the card. Lists and tables use trailing
placement. Fixed-size items must have room for their content and actions.

`actionWidth` has a minimum default of `88`. Native label bounds can make the
action tray larger. Each action is as wide as its painted label, plus its icon
and gap when it has an `icon`, plus 32 pixels. Full swipe is on by default. You can set it for each edge.
A row with no measured width does not open or run an action from a swipe.
A shared `coordinator` cell lets only one row be open. When a row opens,
through a gesture or a write to its `open` cell, the other rows close.

Native swipe, context, and keyboard and gamepad actions reach the same
commands. In a collection row, these actions also apply when the row itself
has the selection. A destructive action runs exactly once, after its Compose
departure animation. If the owner is removed, an unfinished departure is
cancelled. If the owner keeps the row, for example when the server refuses the
delete, the row returns to its full height on the next frame, and the action
can run again. A full swipe commits or opens a tray only after the row has a
measured width.
`reducedMotion`, `enabled` and `editing` stay explicit control options.
