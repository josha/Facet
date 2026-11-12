# Themes.tokens

Native color tokens, metric rule values and palette changes.

- Palette color rules reference native `$FacetColor_<role>` tokens. The
  StyleSheet attributes hold the resolved colors. A palette change updates
  these attributes and keeps the color rules. `StyleRule:GetProperties()`
  returns the token strings for these properties. Read the matching attribute
  on the StyleSheet to inspect a resolved color. These attributes belong to
  Facet. Computed colors can remain direct rule properties.
- Reduced motion or `transition = false` sets zero-duration paint. If you omit
  reduced motion, the sheet follows GuiService.
- Explicit Instance paint still overrides stylesheet paint.


A theme package contains `identity`, `style = { defaultTheme, themes }`,
`metrics`, `chrome`, `assets`, `icons` and additional
`rules = { { selector, properties } }`. A palette contains `name`, `colors` and
`extra`. The main colors are `surface`, `surfaceStrong`, `content`,
`contentStrong`, `accent`, `onAccent`, `danger`, `onDanger`, `success`,
`onSuccess`, `warning` and `onWarning`. The extras include control states,
secondary content, hairlines and opacities.

An authored rule property can be a native value, `{ role = "content" }` for a
palette color, or `{ metric = "strokes.outline" }` for a numeric theme metric.
Metric paths start inside `metrics` and use dot-separated keys. They must name
one finite number; `themes.define` rejects missing paths, tables and nonnumeric
values. Resolution uses the effective package after `forDistance`, so a stroke
metric of 3 becomes 4.5 at ten feet. Literal numbers stay unchanged. Motion
metrics retain their existing distance policy and do not scale.

A rule property can also be a data table that Facet turns into a native value
when the theme compiles, so a theme module loads where Roblox datatype globals
are absent, such as under Lute:

- `{ udim = { scale, offset } }` for a UDim, such as a UICorner `CornerRadius`.
- `{ udim2 = { xScale, xOffset, yScale, yOffset } }` for a UDim2.
- `{ vector2 = { x, y } }` for a Vector2.
- `{ colorSequence = { { time = 0, color = "#ff8800" }, { time = 1, color = { role = "accent" } } } }`
  for a ColorSequence. A color is a `#hex` string, a palette role or
  `{ r = 0, g = 0.5, b = 1 }` with channels from 0 to 1, like palette colors.
- `{ numberSequence = { { time = 0, value = 0 }, { time = 1, value = 0.5 } } }`
  for a NumberSequence.

Keypoint times must rise from 0 to 1. `themes.define` rejects a table that names
no form or more than one. A form with the wrong shape raises an error that names
the property when the theme compiles.

These `extra` entries are optional. A palette that does not declare them paints
as before:
