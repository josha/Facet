# Composition.adaptation

Top-bar strip layout, fallback and overlays.

- A region with `zone = "topbar"` goes into the free strip of the Roblox top
  bar, level with the Roblox buttons. The composition puts these regions in a
  second ScreenGui with `ScreenInsets = TopbarSafeInsets`, in the parent of its
  own ScreenGui. That ScreenGui has the same `DisplayOrder` and links the same
  StyleSheet. It is enabled only while the host is `Enabled` and the
  composition and its ancestors are `Visible`. Thus a page that a
  NavigationStack pushes over the HUD page hides the strip. The regions sit side
  by side. Leading regions sit beside the Roblox buttons. Trailing regions
  (`trailing = true`) sit at the far end of the strip, such as a menu button.
  The other regions stay centred in the remaining space.
  Regions step down when their total width with the gaps does not fit the strip,
  or when a region is taller than the strip row. The middle lane, and a leading
  or trailing lane that a region declares, keeps its `gap` even when empty.
- When `topbar` is `false`, when `GuiService.TopbarInset` has no width (a
  console has no Roblox top bar), or when the composition is not in a
  ScreenGui, these regions come first in the `top` zone. A leading region goes
  first in the `topLeft` zone, and a trailing region
  goes first in the `topRight` zone instead, so a menu button keeps its corner.
- When the strip cannot hold a region at its last form, that region moves to
  the start of the `top` zone in its richest form. The highest rank moves first.
  With equal ranks, the later region moves first. The other regions stay in
  the strip. Thus a long row of chips on a portrait phone moves below the bar
  and does not cover the Roblox buttons.
- The strip ScreenGui stays in place while empty. The composition can measure
  it and return regions when the strip becomes wider, for example after a rotation.
- The strip row aligns with the Roblox buttons. It is 44 pixels high and sits
  2 pixels above the bottom of the band. Regions centre on the Roblox buttons.
  A region taller than 44 pixels does not fit the strip.
  The leading row starts one `gap` after the Roblox buttons.
  The strip's far end keeps the composition's own edge `padding`, or one `gap` when
  the padding is smaller, so trailing regions line up with the zones below.
  Give a button beside the Roblox buttons a 44 pixel height.
  A `regular` Button in the neutral theme has this height with every input;
  a `compact` Button is 36 pixels with a pointer.
- A Popover, Menu or other overlay from a strip region shows in the composition's
  ScreenGui. Thus the narrow strip does not clip it.
- In the strip, the `Topbar` Frame holds a `Leading` row for leading regions.
  Its `Middle` row centres the other regions, and its `Trailing` row holds the
  trailing regions at the end.
  In the `top` zone, a `Landed` Frame holds the regions that moved; in the
  `topRight` zone, `LandedTrailing` holds the trailing ones; in the `topLeft`
  zone, `LandedLeading` holds the leading ones, so a leading title keeps the
  start edge.
