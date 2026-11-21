# Themes.character

<!-- aliases: look | feel | finish look | motion feel | character | shadow | glow | animation -->

Two names give a theme its edge, its depth and its motion. Use them when you
cannot make or see a concept image: take each name from the lead idea of the
direction card.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local definition: Facet.ThemeDefinition = {
    identity = { id = "night-garage" },
    finish = { look = "glow" },
    motion = { feel = "crisp" },
}
local theme, report = Facet.themes.define(definition)
assert(theme, report.errors[1] and report.errors[1].message)
```

| `finish.look` | What shows | Fits |
| --- | --- | --- |
| `flat` | No line and no shadow. Color and type carry the plates. | A quiet tool, a serious or minimal game |
| `raised` | A soft shadow under the plates and the controls, a faint line, and a wash of the content color from the top. | Cozy, casual, farm, shop; most light palettes |
| `glow` | A line and a halo in the accent color, with an accent wash. | Sci-fi, neon, night, racing, magic; a dark palette |
| `hard` | A thick line in the content color and a solid shadow with no blur, on the plates and the controls. | Cartoon, arcade, comic, pixel, party |

| `motion.feel` | What changes | Fits |
| --- | --- | --- |
| `calm` | Longer times and slower springs. | Cozy, story, puzzle |
| `crisp` | Shorter times, tight springs and small scale changes. | Competitive, tactical, sci-fi, racing |
| `lively` | Springs that pass their target and return, and larger pops. | Cartoon, arcade, party, young players |

Without `motion`, the theme has the motion of Facet Neutral.

A stated value replaces the value of the name. For the edge and the depth,
state it beside the look: `finish = { look = "raised", depth = { lift = 12 } }`.
A stated `lift` on a look with a glow replaces the glow, and a stated `glow`
replaces a lift. [Themes.finish](Themes.finish.md) lists each value. For
motion, state the token in `metrics.motion`;
[Motion.metrics.motion](Motion.metrics.motion.md) lists each token. Reduced
motion still removes the motion.

A look gives only the edge and the depth. State the palette, the type and
the corner of the direction also. Do not take a look or a feel from another
game: a night racing garage and a farm stall do not share one.
