# HUD-actions

Keep HUD actions in one horizontal selection row at the top-right safe edge.

Use the row in [Tasks.hud](Tasks.hud.md). Each action is a circle `Button` with
an icon and a `caption`. Put the row and the readouts in `topRight` regions of
one Composition: the row first, the readouts below it. The Composition keeps
both inside the core UI safe area and the TV safe area, so the row never sits
under the Roblox top bar. Do not make a second ScreenGui for the HUD.

## Size and position

Use `controlSize = "regular"` for primary navigation circles. Reserve
`compact` for secondary actions. Size primary thumb actions from
`UI.environment().thumbTarget`. Give the row a bottom
padding, such as `padding = captionRoom` with
`local captionRoom: Facet.Sides = { bottom = "l" }`. A caption takes no space
in the layout, so this padding keeps it clear of the readouts below. Set the
row `gap` to at least the widest caption minus the circle width.

Use theme colors with at least 3:1 icon contrast against the circle. Keep the
3D view clear: the corner zones hold the HUD and the centre stays open.

## Selection and input

Make only Buttons selectable. Give each Button its name with `caption`. The
caption is a label inside the Button, so the name and the action stay one
control. A separate Text below the circle is not part of the Button. Set
`SelectionGroup` on the row. Keep activation in `onActivate`. Sheet, Dialog
and Menu own Back and Cancel.

Check desktop, both phone orientations, tablet and console in Studio. Check
every label, icon, touch control and gamepad selection path. Do not infer live
engine behavior from a native engine double.

## Readouts

Put readouts on a stack with `surface = "panel"`, so they read over any scene.
Give the main resource value `textRole = "title"`; use `caption` for its rate
or explanation. Check that the value and action labels remain legible at the
full desktop viewport, as well as on a phone.
Use short numbers (`Facet.format.compact`, such as `1.18K`) on the HUD and full
numbers in panels. A bar `ProgressView` in a hug stack needs a width. Put a
timer in its action caption, such as "Offer 24:51". Set the HUD cells from the
server state when it changes, so the HUD and the panels show the same values.

- [Button.underline](Button.underline.md)
- [Composition.regions](Composition.regions.md)
