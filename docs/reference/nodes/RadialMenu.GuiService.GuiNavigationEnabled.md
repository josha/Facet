# RadialMenu.GuiService.GuiNavigationEnabled

A finger held still on an item for 0.4 seconds names it and does not pick
it: that release does nothing, and a second tap picks the item. A press that
slides more than 14 pixels is a gesture, and its release picks the item under
the finger.

Nothing is highlighted when the ring opens, until the player points at an
item, presses a direction or moves the stick. With a gamepad as the preferred
input, the first item is selected, because the console needs a focused
control. When a submenu replaces the level, the selection moves to the first
item of the new level. While any ring is open, `GuiService.GuiNavigationEnabled`
is false, because the engine's pad navigation otherwise takes the left stick
from the ring; the ring binds its own D-pad, A and B. On the ring, a D-pad
direction pointing back across the centre goes to the centre control, and the
next press on to the item on the other side; from the centre each direction
goes to the item nearest that direction; any other direction moves to the
neighbouring item along the ring, so every item can be reached. The value before the
first ring opened comes back when the last one closes, unless the game turned
it on at any point while a ring was open; then the game's current value stays.
Setting it to false while it is already false is not a change the engine
reports, so a game that wants it off after the rings close sets it after the
last close. The ring blooms out of its centre: the items and wedges travel from a
fifth of their distance to their places as they fade in. Reduced motion places
them at once.

Without an `anchor`, the ring opens centred on its launcher. It is placed on
the measured presentation layer from the first frame. Before the
launcher has a size, and with `launcher = false`, the `preset` sets the
position. A full ring (`donut` or `circle`) then moves inward until its inner
radius plus `ringWidth` (or 44 pixels) fits inside the presentation area. The
ScreenGui keeps that area inside the safe area. Corner presets are not moved.
