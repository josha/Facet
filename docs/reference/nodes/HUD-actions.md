# HUD-actions

Group related HUD actions and protect the game view.

The example in [Tasks.hud](Tasks.hud.md) puts an active objective, progress and
primary command together, with a resource in the opposite corner. Its short
form keeps the same command and meaningful progress. Choose zones from the
task and the sight lines that must stay clear. Use labeled Buttons when an
icon would be ambiguous. Keep related navigation in one selection group and
distinguish it from passive readouts.
Composition protects core UI and TV safe areas. Do not make a second
ScreenGui for the HUD.

## Size and position

Give primary navigation circles `controlSize = "regular"`. Reserve `compact`
for secondary actions. Size primary thumb actions from
`UI.environment().thumbTarget`. A caption takes no space in the layout.
Facet reserves room for captions under the bottom row of a Composition, so
all bottom regions share one baseline. Do not pad the row for captions. Set
the row `gap` to at least the widest caption minus the circle width.

Use theme colors with at least 3:1 icon contrast against the circle. Keep the
centre of the 3D view open.

In the top bar strip (`zone = "topbar"`), match Roblox's row of icon buttons:
use an icon circle with a familiar glyph and a `name`, or an icon with a short
value. `controlSize = "regular"` is 44 pixels tall with every input, as Roblox's
buttons are; `compact` is 36 pixels with a pointer. Composition `padding = "m"`
(16 pixels) lines the HUD edge up with Roblox's first button.

## Selection and input

Make only interactive controls selectable. Give each Button a `name`. A
circle with a familiar glyph, such as a bag for Shop, needs no `caption`; add
one only when the glyph alone is ambiguous. Do not caption a Button that has a
`label`. A caption is part of the Button and reads over a bright sky; a
separate Text is not. Set `SelectionGroup` on the row. Keep activation in `onActivate`. Sheet, Dialog
and Menu own Back and Cancel.

A Composition is passive: the movement stick and the D-pad drive the game and
never select a HUD Button. Give each frequent HUD task a game action on a
gamepad button, and set `shortcutHint` to that action:

```luau
UI.Button "Shop" { icon = "bag", shape = "circle", name = "Shop", shortcutHint = shopAction, onActivate = openShop }
```

The Button shows the action's glyph on its rim while the device has a binding
for it, and hides it on touch. For the other Buttons,
set `GuiService.SelectedObject` to one from a game action. With
`GuiService.AutoSelectGuiEnabled` (the default), the engine's ButtonSelect
(View) does this too; the virtual cursor does not. ButtonB returns the
selection to the game, and so does pressing a HUD command that opens no
surface, so the player can press Boost and keep driving. Test each route in Studio with the Controller Emulator.

Check desktop, both phone orientations, tablet and console in Studio: every
label, icon, touch control and gamepad selection path.

## Readouts

Put readouts on a stack with `surface = "panel"`, so they read over any scene.
Give the main resource value `textRole = "numeral"`; use `caption` for its
currency label, rate or explanation. Keep the number separate from secondary
progress and status. Check that the value and action labels stay legible on desktop and on a phone.
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
