# Themes.plates

<!-- aliases: plate | plates | named plate | row plate | inner panel | button shadow | button lip | shade | control shadow -->

`finish` gives every panel one line and one shadow. Two options state the
parts that a direction draws differently: a named plate for some panels,
such as the rows in a panel, and a shadow for the controls.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local definition: Facet.ThemeDefinition = {
    identity = { id = "boba-stand" },
    finish = {
        look = "hard",
        depth = { controls = { lift = 6, side = 0, shade = 0.45 } },
        plates = {
            row = { edge = { width = 2 }, depth = { lift = 4, side = 0 } },
        },
    },
}
local theme, report = Facet.themes.define(definition)
assert(theme, report.errors[1] and report.errors[1].message)
local app = Facet.app({ name = "BobaStand", theme = theme })
local UI = app.UI
app.mount(function()
    return UI.VStack "Menu" {
        surface = "panel", padding = "m", gap = "s",
        UI.HStack "TaroMilk" {
            surface = "panel", plate = "row", padding = "s",
            UI.Text { text = "Taro Milk", textRole = "strong" },
        },
    }
end)
```

## A named plate

`finish.plates` is a table of names. A name starts with a letter and has
letters and digits. A plate has `edge = { width, role, transparency }`,
`depth = { lift, blur, side, glow, strength, role }`, or both, with the
meanings of [Themes.finish](Themes.finish.md). Other keys cause an error.
State only the values that differ; a value left out is that of the theme.

- `edge.width = 0` is a plate with no line.
- A stated `lift` without `blur` or `side` keeps the proportions of the
  theme's shadow. `lift = 0` is a plate with no shadow.
- On a theme with a glow, a stated `lift` replaces the glow for that plate,
  and `glow = 0` is a plate with no glow.

A VStack or an HStack with `surface = "panel"` takes the plate with
`plate = "row"`. The stack keeps the corner and the sheen of a panel. Give
it its own fill with `BackgroundColor3`: a row with the fill of the panel
around it reads as part of that panel. A name that the theme does not
have, `plate` without `surface = "panel"`, or `plate` with `tail`, causes
an error. A game that changes its theme names the same plates in each
theme; under a theme without the name, the stack has the panel finish.
On a theme with panel art in `chrome`, a plate keeps that art and has no
shadow of its own.

Use a plate when the direction shows two kinds of panel. Do not use it to
make one panel different: one plate that stands out reads as an error.

## The shadow of the controls

`depth.controls` gives Buttons and other controls a shadow. `true` is the
shadow of the panels. A table states their own; it does not need a shadow
on the panels:

| Value | Meaning |
| --- | --- |
| `lift` | Pixels that the shadow falls below the control. Left out: the value of the look, or the lift of the panels. 0: no shadow. |
| `side` | Pixels that it falls to the right. Left out: the side of the panels, in proportion to the lift. |
| `shade` | 0 to 1. The shadow takes the fill of its control, made darker by this share: a green Button has a dark green shadow, and a pink one a dark pink shadow. Left out: the shadow color of the panels. |

A hard shadow with a `shade` reads as the lower edge of a solid key. Values
from 0.3 to 0.5 show on a saturated fill. The shadow follows the fill when
the control is disabled or selected. A theme with a glow gives the controls
that glow, and ignores `lift`, `side` and `shade`.

Related: [Themes.character](Themes.character.md),
[VStack and HStack](VStack-and-HStack.md).
