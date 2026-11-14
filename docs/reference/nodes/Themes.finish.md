# Themes.finish

Themes.finish option values and behavior.

`finish` states the edge and the depth of every plate as values. `define`
writes them into the theme's rules, shadows and gradients, so one block
replaces a stroke rule, a shadow table and a plate gradient. State it in
every new theme. A quiet interface states zeros:

```luau
local definition: Facet.ThemeDefinition = {
    identity = { id = "ledger" },
    finish = { edge = { width = 0 }, depth = { lift = 0, glow = 0, sheen = 0 } },
}
```

Without `finish` the plates are those of the base theme, and `report.advice`
has a `finish` entry. A `finish` with a part missing is an error.

Take each value from the direction of the product, not from another theme.

| Value | Meaning |
| --- | --- |
| `edge.width` | Pixels of line around every panel and Sheet, drawn inside the box, so it takes no room from a gap. 0 is no line. With `metrics.radii.panel = 0` the corners of the line are square. |
| `edge.role` | The palette color of the line. The default is `hairline`. |
| `edge.transparency` | 0 to 1. The default is 0. |
| `edge.controls` | `true` draws the same line on Buttons and Stepper keys. `{ width?, role?, transparency? }` draws their own line; a value left out is that of the plates. A disabled control has 0.6 transparency or more. `bare`, `link` and `utility` Buttons keep none. The default is `false`. |
| `depth.lift` | Pixels that a shadow falls below the plate. 0 is no shadow. |
| `depth.blur` | Pixels of softness of that shadow. The default is twice the lift. 0 is a hard shadow. |
| `depth.side` | Pixels that the shadow falls to the right. The default is 0. |
| `depth.glow` | Pixels of halo around the plate, with no offset. A plate has one shadow: give `lift` or `glow`, and 0 for the other. |
| `depth.sheen` | 0 to 1. The opacity at the top of a wash of the role color that fades down the plate. |
| `depth.role` | The palette color of the glow, the sheen and the shadow. The default is `accent` with a glow. Without one, the sheen is `content` and the shadow is black. |
| `depth.strength` | 0 to 1, the opacity of the shadow or the glow. The defaults are 0.35 and 0.55. |
| `depth.controls` | `true` gives controls the same shadow as panels. The default is `false`. |

These are sample measures on a screen of 1080 lines, with a saturated color.
They are not limits: the ground and the color move them.

| Value | What shows |
| --- | --- |
| `edge.width = 1` | A hairline. With a transparency over 0.5 it is hard to find. |
| `edge.width = 2`, then 3 or 4 | A clear line, then a frame that leads the plate. |
| `glow` under 8, or `strength` under 0.4 | Usually nothing. `report.advice` has a `finish.depth.glow` entry. |
| `glow` 12 to 16 at 0.5 to 0.7 | A soft light around the plate, on a dark ground. |
| `glow` 24 or more at 0.7 to 1 | A lit plate. A bright ground usually needs this range. |

`controls = true` with a line of 2 pixels or more gives a
`finish.edge.controls` entry in `report.advice`: equal lines on a plate and
on each control in it compete. Give the controls a quieter line when the
direction shows one. Write the definition in a local of type
`Facet.ThemeDefinition`, as above; a table for `controls` written straight
into the `define` call does not type-check.

Check the values in a capture over the real ground, not on a plain backdrop.

The roles are read from the default palette for the shadow, and from each
palette for the sheen. A panel or a control with art chrome keeps its art:
the shadow applies to `native` chrome only. A light shadow does not show on
a dark ground; use a glow or an edge there.

`app.specimen(parent?)` mounts one screen of the theme: the type roles with
a readout, the actions in each state, a field, and records. It returns
`stop, screen`, as `app.mount` does. Capture it beside the concept before
the first screen, and call `stop()` after the capture.

Related: [edge rules](Themes.stylesheet.md), [chrome](Themes.chrome.md),
[palette](Themes.palette.md).
