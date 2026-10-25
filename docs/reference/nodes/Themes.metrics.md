# Themes.metrics

Optional theme metrics for tabs, control sizes, targets and shortcuts.

- `controls.typography.minimumSize`: the smallest text role size, at least 14
  pixels. `define` raises smaller sizes and preserves the order of distinct
  sizes. The resolved scale then follows viewing distance and preferred text size.

- `radii.tab`: the corner radius for filled top tabs. Their track adds 2 pixels
  to a positive radius. A value of 0 makes both square. Facet Neutral uses 999
  for pills. Sidebar and bottom tabs keep their usual corners.
- `controlSizes.xsmall = { height, paddingX, iconSize }`. Without it, each
  field is `2 * compact - regular`, and not less than 0. `define` refuses an
  `xsmall` entry that does not have all three numbers.
- `targetSizes.thumb` and `targetSizes.thumbLarge`: primary on-screen action
  sizes for the thumb on a phone and on a larger screen.
  The neutral values are 70 and 120. `define` refuses a value below
  `targetSizes.minimum`.
- `targetSizes.pointer`: a row height from 24 to `targetSizes.minimum`. Floating
  Menu and Picker menu rows use it while the input is pointer-only. `define`
  refuses a value outside that range.
- `strokes.utility`: a number of pixels. When it is more than 0, a
  `utility` Button draws a hairline outline of that width. Without it, a
  utility Button has no outline.
- `controls.shortcutHint.capStroke`: a number of pixels for the ShortcutHint
  cap outline. Without it, the outline is `strokes.hairline`. A value of 0 draws
  no outline.
- `controls.shortcutHint.capGap`: a number of pixels. `define` accepts it for
  packages that also target main. The native ShortcutHint draws each chord as
  one label, so it has no gap between caps to set.
- `controls.button.captionStroke`: a number of pixels for the outline of a
  Button `caption` and of the rim hint of a circle Button. The neutral package
  sets 1.5 pixels, which scales at ten feet; a package without it gets 1.5. A value of 0 draws no outline.
  `controls.button.captionStrokeOpacity` (0.7) sets its opacity.

StyleSheet rules own ordinary paint. Explicit Instance properties override
native styling intentionally. Give the same theme package readable to
`Facet.controls(runtime, { theme = package })` and to
`createStyleSheet(runtime, package)`. Mount the resulting sheet and a native
StyleLink in the target tree. See [custom themes](../../guide/themes.md)
and [skins](../../guide/skinning.md).
