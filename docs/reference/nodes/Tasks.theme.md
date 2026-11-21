# Tasks.theme

<!-- aliases: themePackage | ThemeDefinition | custom theme | theme definition | visual identity | art direction | native theme -->

Choose the visual direction before any screen; [use-facet](Design.guide.md)
has the full method. When you cannot make or see a concept image, write the
card in words first, as a comment: the lead idea from the game's world, the
palette by role, the display and reading type, the corner, the look, the
motion feel, and an icon or a glyph for each thing. Then make each theme
value follow the card; [Themes.character](Themes.character.md) has the looks
and the feels. Facet Neutral is a base, not a look: a game that ships it
reads as unfinished. The
[Proof Press example](../../../skills/use-facet/assets/native-direction.luau)
shows a complete theme and mounted task.

`define` starts from Facet Neutral when you omit `base`. State `finish` and
`motion`, by name or by [value](Themes.finish.md). Repair any reported
errors. Inspect `report.advice` against the task. Pass the result to
`Facet.app({ theme = theme })` and use `app.UI`.

This excerpt shows a type role; the linked example mounts the full task:

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local definition: Facet.ThemeDefinition = {
    finish = { look = "raised" }, motion = { feel = "calm" },
    metrics = { typography = {
        title = { size = 42, font = { family = "Merriweather", weight = "Bold" } },
    } },
}
local theme, report = Facet.themes.define(definition)
assert(theme, report.errors[1] and report.errors[1].message)
```

A Text's role picks its font and size from the theme. A Button uses the
`control` role by default.

For other options, see [Theme-identity](Theme-identity.md),
[Themes.definition](Themes.definition.md), [Themes.tokens](Themes.tokens.md)
and [Themes.art](Themes.art.md). For a game HUD, keep `caption` at 16 or
more and `label` and `body` at 18 or more: smaller text is hard to read.
