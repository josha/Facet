# Button.appearance

Button.appearance option values and behavior.

- `appearance`, `role`, `selected`, `name`, `hint` and `pop`. `appearance` is
  `standard`, `emphasis`, `soft`, `utility`, `link` or `inverse`. `inverse` is a
  light plate on a dark theme, and a dark plate on a light theme. It uses the
  `inverseSurface` and `onInverse` colors of the palette. Without them it uses
  `contentStrong` with `surface` text. The button has the
  `facet-appearance-inverse` tag. A `utility` or `link` Button has no plate:
  a theme's `control` chrome art paints only the other appearances. A Button
  whose `BackgroundTransparency` is 1 has no plate art either, so a
  transparent hit target never covers the content beneath it. A bound
  `nil` appearance restores `standard`.
  A destructive or `emphasis` Button keeps its role on skinned art. When the
  label (`onDanger` or `onAccent`) is lighter than the fill (`danger` or
  `accent`), the art is tinted with the fill. When `onAccent` is darker than
  `accent` in any palette and the `control` slot has `selected` art, every
  `emphasis` plate of that package shows the selected art with an
  `onSelected` label instead (Pixel Quest, Fantasy Ornate, Fantasy Parchment).
  Only a package without selected art falls back to the flat fill, so the
  label always meets its palette contrast. Skin images have the
  `facet-skin-art` tag.
- `controlSize`: `xsmall`, `compact`, `regular` or `large`. `xsmall` is one
  step below `compact` unless the theme package declares
  `metrics.controlSizes.xsmall`. With the neutral values it is 28 pixels high,
  with a `paddingX` of 4 and an `iconSize` of 12. The native button is its hit
  area. When the device has touch or a gamepad, a `TargetFloor`
  `UISizeConstraint` keeps a button with a smaller step at least
  `targetSizes.minimum` (44 pixels in the neutral package) on both axes, so a
  player can still tap it. On a mouse-only device an `xsmall` button stays a
  28 pixel target. Use `xsmall` for dense pointer rows. A named step adds the `facet-size-<step>` tag. The theme
  StyleSheet then sets the left and right padding to
  `controlSizes.<step>.paddingX`. Without `controlSize`, the button has no
  size tag and keeps the padding of 12. On skinned `control` art, the art's
  carve (`chrome.control.contentInsets`) is added to that padding on each
  side, so the label and a Menu or Picker disclosure icon sit inside the
  frame. A framed TextInput adds the `field` carve the same way.
- `target`: `hit` (the default), `thumb` or `inline`. On touch, a `thumb` Button has a
  `TargetFloor` of `UI.environment().thumbTarget` on both axes, with any
  `controlSize`. Use it for primary game actions that the player presses with
  a thumb while playing, such as Jump, Drift or Fire.
  With another input, it keeps the usual floor.
  Use `inline` for adjacent choices within a compact horizontal control, such as
  page indicators. It keeps the usual minimum height and uses
  `metrics.targetSizes.inline` as the minimum width (24 pixels by default).
  Keep the targets separate. This option does not enlarge or overlap hit areas.
  The inline width must be at least 24 and no larger than `targetSizes.minimum`.
- `textSize`: a type role (`caption`, `label`, `body`, `heading`, `title`,
  `control`, `strong` or `numeral`) or a number of pixels, or a readable of
  one. A role adds the `facet-type-<role>` tag to the label, and a number sets
  `TextSize`. It reaches the label of a plain text button and the `Title` label
  next to an icon.
