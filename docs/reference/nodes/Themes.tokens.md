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

These `extra` entries are optional. A palette that does not declare them keeps
the base paint:
