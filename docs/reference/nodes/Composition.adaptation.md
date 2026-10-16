# Composition.adaptation

- A region with `zone = "topbar"` goes into the free strip of the Roblox top
  bar, level with the Roblox buttons. The composition puts these regions in a
  second ScreenGui with `ScreenInsets = TopbarSafeInsets`, in the parent of its
  own ScreenGui. That ScreenGui has the same `DisplayOrder`, follows the
  `Enabled` of the host and links the same StyleSheet. The regions sit side
  by side, centred in the strip. They step down when their total width with the
  gaps does not fit the strip, or when a region is taller than the strip.
- When `topbar` is `false`, when `GuiService.TopbarInset` has no width, or
  when the composition is not in a ScreenGui, these regions come first in the
  `top` zone.
