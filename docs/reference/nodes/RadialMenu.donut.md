# RadialMenu.donut

RadialMenu.donut option values and behavior.

- A full ring (`donut` or `circle`) with `center = "back"` (the default) has
  one control in the centre hole. It is Close at the root and Back in a
  submenu; Back goes up one level and Close closes.
- A full ring with `center = "empty"`, `"content"`, `"root"` or `"close"`
  puts Back/Close on the ring, as a wedge (or button) of the deepest open
  level. An even ring turns so that this wedge sits at the lower left. A
  compass ring gives it the first free slot of `SW`, `S`, `SE`, `NW`, `W`,
  `E`, `NE`, `N`. `root` also shows Home in the centre, which returns to the
  root, and `close` shows Close there. With `empty` or `content` the centre
  holds no control, except on a compass ring with no free slot: then Back/Close
  sits in the centre.
- A corner preset never puts it on the arc: the default control on
  the corner, over the launcher, is Close at the root and Back in a submenu.
  It grows out of the launcher, which it hides while the ring shows: it opens
  at the launcher's size with the launcher's glyph, and shrinks to its own size as that glyph crossfades to
  Close or Back. As the ring closes it grows back into the launcher the same
  way.
- A corner preset with `center = "empty"` and `centerPassThrough = true`
  leaves the centre free for the caller's toggle. It hides both the small
  centre button and its extra hit target. The caller supplies a named,
  accessible close action. Outside taps and Cancel still close the menu.
  When `anchor` is a GuiObject, that anchor remains interactive in the centre
  while the rest of the page stays blocked. The list fallback keeps its
  Back/Close control and blocks the anchor.
- The list fallback has one round Back/Close control at the top right, above
  the list, for every preset and `center`.

The centre control is a small round `utility` button, 32 pixels across, with
no plate and no theme control art. A transparent `CenterHit` target around it
is one touch target (`targetSizes.minimum`) across and does the same thing. It
shows a close, back or up-chevron (Home) icon. The word is its accessible name,
and a `centerLabel` replaces that name; it is never shown as text. Cancel (the B button) and the
Back/Close control do the same thing. On touch, an icon item's temporary name
follows the held contact and prefers a position above the finger, with room
for the fingertip. If it cannot fit above, it moves beside or below the
contact within the safe area. The name wraps in an arrowless, tooltip-styled
plate. Pointer and gamepad names sit outside the ring in the item's direction. In the list fallback, the path heads the list beside Back/Close.

A tap on the launcher opens the menu and keeps it open. The release does not
pick an item, even if the ring moves an item under the finger to fit the screen.
The opening contact and small tap movements do not highlight an item.
A press on the launcher that slides at least 14 pixels can pick an item on release.
