# Themes.schema

`themes.SCHEMA` is `facet-theme/2`. `TYPE_ROLES` and `REQUIRED_TYPE_ROLES` list
`caption`, `label`, `body`, `heading`, `title`, `control`, `strong` and
`numeral`. The `caption` role also uses the `contentSecondary` color.
If a definition sets `body` and does not set `strong`, `define` makes `strong`
from `body` with the `SemiBold` weight. If a definition sets `control` and does
not set `numeral`, `define` makes `numeral` from `control` with the `Bold`
weight. The derived role keeps the family, style, size and line height.

Shake uses the number tokens `motion.durations.shake`,
`motion.distances.shakeAngle` and `motion.materialize.shakeCycles`, and the
Compose easing name `motion.easing.shake`. These tokens use the duration,
distance, materialize and easing validation rules. A theme definition inherits
them from Neutral unless it supplies replacements.
