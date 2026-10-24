# HUD-actions

Group related HUD actions and protect the game view.

The example in [Tasks.hud](Tasks.hud.md) puts a wallet and a Garage Button in
the top bar strip and a race readout in `topLeft`, in one Composition. This is
one arrangement.
Choose zones from the player's task and the sight lines that must stay clear.
Use labeled Buttons when an icon would be ambiguous. Keep related navigation
in one selection group and distinguish it from passive readouts.
Composition protects core UI and TV safe areas. Do not make a second
ScreenGui for the HUD.

## Size and position

Use `controlSize = "regular"` for primary navigation circles. Reserve
`compact` for secondary actions. In the top bar strip, `regular` matches
Roblox's 44 pixel buttons with every input. Size primary thumb actions from
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

A Composition is passive: the movement stick and the D-pad drive the game and
never select a HUD Button. Give each frequent HUD task a game action on a
gamepad button, and while the gamepad is the input show that action's glyph
on the Button with `UI.ShortcutHint { action = ..., cap = false }`, so the
glyph sits on the Button without a second plate. For the other Buttons,
set `GuiService.SelectedObject` to one from a game action. With
`GuiService.AutoSelectGuiEnabled` (the default), the engine's ButtonSelect
(View) does this too; the virtual cursor does not. ButtonB returns the
selection to the game, and so does pressing a HUD command that opens no
surface, so the player can press Boost and keep driving. Test each route in Studio with the Controller Emulator.

Check desktop, both phone orientations, tablet and console in Studio. Check
every label, icon, touch control and gamepad selection path. Do not infer live
engine behavior from a native engine double.

## Readouts

Put readouts on a stack with `surface = "panel"`, so they read over any scene.
Give a readout the height of the Buttons beside it and the same elevation:
all flat, or all with one shadow.
Give the main resource value `textRole = "numeral"`; use `caption` for its
currency label, rate or explanation. Keep the number separate from secondary
progress and status. Check that the value and action labels remain legible at the
full desktop viewport, as well as on a phone.
Use short numbers (`Facet.format.compact`, such as `1.18K`) on the HUD and full
numbers in panels. A bar `ProgressView` in a hug stack needs a width. Put a
timer in its action caption, such as "Offer 24:51". Set the HUD cells from the
server state when it changes, so the HUD and the panels show the same values.

Give a tall readout a shorter form, not only a narrower one. Keep the same
balance and progress readable in that form. Test portrait, landscape, then
portrait again while movement controls are visible. Core UI safe insets do
not describe gameplay touch-control bounds; see
[Tasks.safe-layout](Tasks.safe-layout.md).

- [Button.underline](Button.underline.md)
- [Composition.regions](Composition.regions.md)
