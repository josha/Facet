# Selection.SelectionGroup

Selection.SelectionGroup option values and behavior.

- Grids and lanes. The engine walks a grid in two dimensions. Use the native
  properties for the rest: `SelectionGroup = true` on a container keeps the
  arrows inside it, and `SelectionBehaviorUp`, `Down`, `Left` and `Right`
  (`Stop` or `Escape`) choose per direction whether the arrows may leave it.
  `NextSelectionUp`, `Down`, `Left` and `Right` name an explicit neighbour.
  A `UI.Grid` whose last line is short sets `NextSelectionDown` (`Right` for
  `flow = "column"`) on the cells of the line before it that have no cell
  below, so the move lands on the last cell. A neighbour that you set wins.
  `UI.focusSection` chooses where the selection lands when it enters a
  region.
- Removal. When the selected control goes away, the selection moves to the
  nearest control that remains. A following control comes before a
  preceding control. A collection keeps the selection on its rows by key: it
  selects the next row, or the previous row when the removed row was the last.
- Scroll containers. A scroll container is not a stop. When the engine selects
  one, the selection moves to the child nearest to the entry edge. A TabView
  strip gives the selected tab. A container that has no controls passes the
  selection to the next control in the direction of travel.
- Value controls. While a Slider, Stepper, Rating, LevelPicker or
  `UI.adjustable` node has the selection, Left and Right (Up and Down for a
  vertical control; the D-pad, the arrow keys and the left stick) change the
  value. A held or repeating press stops at the minimum or maximum; a new press
  toward a limit the value is already at moves the selection to the next control
  that way, if there is one (the control's own `NextSelection*` link in that
  direction when it has one). L1, R1, Comma and Period also change the value
  and never move the selection. Only a navigation gamepad's stick adjusts
  (`UserInputService:GetNavigationGamepads`; restrict it with
  `SetNavigationGamepad`). The control claims the
  axis only while it is the selected object itself, never while a part inside
  it is. Its root has the tag `facet-adjustable`, the attribute `axis`
  (`horizontal` or `vertical`) and the attribute `disabled`. A disabled value
  control is not a selection stop; a busy one stays a stop and ignores presses.
  The root listens for `SelectionGained` (the engine's D-pad ranks listened
  objects first), and a Slider's drag detectors are off while the gamepad is
  the preferred input.
  A range Slider's Return does nothing while a TextBox has the keyboard. A table column grip and a reorder move also
  take Left and Right (Up and Down for a vertical list) while they have the
  selection, from the D-pad and the arrow keys only. A Menu row with a submenu
  opens it on Right, and Left returns to the parent row. The other axis still
  moves the selection.
