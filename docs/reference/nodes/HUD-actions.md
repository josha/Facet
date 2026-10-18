# HUD-actions

Keep HUD actions in one horizontal selection row at the top-right safe edge.

Use the row in [Tasks.hud](Tasks.hud.md). Each action has a circle, an icon
and a readable label directly below it. Use the theme's body role or a larger
role. Keep the action name visible. Put the offer time in a separate badge or
below its name. The server owns the expiry time and wallet balance.

## Size and position

`GuiService.TopbarInset` gives the free top-bar rectangle, not menu button
bounds. Read `UI.environment().topbarControlDiameter` for a derived diameter in
physical pixels. It rounds the band height times 0.75, or times 0.5 when
`GuiService:IsTenFootInterface()` reports native console UI. Bands of 58 and
87 pixels both give 44. An empty band uses the theme's compact control height.
This rule derives the size; the engine does not expose exact menu bounds.

Use `ScreenInsets.TopbarSafeInsets` on the app ScreenGui. Anchor the row's right
edge to the free band's right edge. Align each circle's bottom with the band
bottom minus the theme's small border gap. The neutral gap is 2 physical pixels.
The observed native menu uses that gap on desktop and console. Recheck it when
native UI changes. The circle centers then match the menu center. Observe the
band and viewport so the row follows native UI changes and rotation.

Use a native UIListLayout for the row. `Button.shape = "circle"` supplies
UICorner and UIAspectRatioConstraint. Keep the diameter in physical pixels:
divide authored offsets by any parent UIScale. Labels can need wider holders;
keep all circles on the same vertical center. Do not shrink text to fit.
Use theme colors with at least 3:1 icon contrast against the circle.

Keep labels, timers, the wallet and phase text in separate bounds. Reserve the
row's full label height before placing other HUD content. Keep the 3D view
clear. Use CoreUISafeInsets for other HUD groups. `GuiService:GetInsetArea()`
converts safe rectangles to core-safe coordinates. Do not add the inset twice.
The sample uses no parent UIScale. Its native top-bar group uses near metrics
so the gamepad target floor does not enlarge the circles. Use the normal
distance and overscan policy for other HUD content.

Composition's topbar regions place commands beside the native controls, but
center trailing regions and use their own strip padding. For this row's exact
right edge and circle alignment, use the native top-bar safe ScreenGui and a
stack. Use Compose.portal for separate modal layers. Put Sheet and Dialog
outside the action stack.

## Selection and input

Make only Buttons selectable. Give each Button its name with `caption`. The
caption shows below the circle and is part of the Button: a tap or click on
the caption activates the Button. A separate Text below the circle does not
activate it. Place each caption fully below the strip, in the core UI safe
area. Keep the
Button's own rectangle fully inside the strip and do not clip its descendants.
No painted rectangle may cross the strip's bottom edge. Set
SelectionGroup on the row. Use native left and right selection links when
needed. Leave boundary links open so native top-bar controls remain reachable.
Keep activation in onActivate. Sheet, Dialog and Menu own Back and Cancel.

Check desktop, both phone orientations, tablet and console in Studio. Compare
circle diameter and center with the native menu. Check every label, icon,
More menu, touch control and native top-bar selection path. Do not infer live
engine behavior from a native engine double.

- [Button.underline](Button.underline.md)
- [Composition.regions](Composition.regions.md)
