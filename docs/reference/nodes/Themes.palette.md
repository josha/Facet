# Themes.palette

Optional semantic colors and their defaults.

- `controlHover` and `controlPressed`: the control plate on hover and on
  press.  When a palette sets `control` and not these roles, `define` makes
  them from `control`.  They keep the contrast step of the neutral Dark or
  Light states, for a dark or light `surface`.
- `selection` and `onSelection`: the color of an on or chosen mark and the
  color on it. The switch track and knob, the checkbox box and tick, the slider
  fill and the tab and segment underline (`facet-selection-indicator`) use
  them. Without them they are `accent` and `onAccent`. When a palette of the
  package declares `selection`, a chosen Chip and a selected `link` Button also
  use it.
- `voice`: the color of the `voice` status. Without it, it is halfway between
  `warning` and `danger`.
- `scrim`: the color of a modal backdrop. `scrimOpacity` sets how much it
  dims. Without it the backdrop is black.
- `inverseSurface` and `onInverse`: the plate and text of
  `appearance = "inverse"`. Without them they are `contentStrong` and
  `surface`.
- `tableHeader`, `tableRow` and `tableRowAlternate`: the Table header band,
  its rows and its alternate rows. Without them they are `control`, `control`
  and `controlHover`.
- By default a disabled Button fades its plate through `BackgroundTransparency`.
  `dimDisabledPlates = false` keeps the plate. `dimDisabledPlates = true`: a disabled Button fades its plate toward
  `surface` by `disabledContentOpacity`, in addition to its text. This applies
  to the standard, selected, emphasis, soft, inverse and destructive plates and
  to the Toggle indicator. Without it only the text dims.
- `artTint`: multiplies the `control`, `field` and `panel` chrome art of
  that palette, so one art set serves a light and a dark palette. Fantasy
  Parchment Candlelight darkens its parchment to 0.3 so cream text reads on
  it. Without it the art is untinted. A selected, emphasis or destructive
  plate keeps its own tint.
- `strongHairlineOpacity`: the transparency of `facet-divider-strong`. Without
  it, the strong divider is three times as visible as the hairline (0.76 with
  the neutral 0.92).

Two tags need no control. `facet-pane` paints the `surfaceStrong` fill with no
corner and no stroke, for a sidebar or a split pane. Add
`facet-divider-strong` next to `facet-divider` for a heavier rule, such as a
pane edge.

The `focus` chrome slot is the focus look that `UI.focusRing` hands to the
engine:
