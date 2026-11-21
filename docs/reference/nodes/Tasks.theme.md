# Tasks.theme

<!-- aliases: themePackage | ThemeDefinition | custom theme | theme definition | visual identity | art direction | native theme -->

Choose the visual direction before any screen; [use-facet](Design.guide.md)
has the full method. When you cannot make or see a concept image, write the
card in words first, as a comment: the lead idea from the game's world, the
palette by role, the display and reading type, the corner and edge, and the
finish. Then make each theme value follow the card. Facet Neutral is a base,
not a look: a game that ships it reads as unfinished. The
[Proof Press example](../../../skills/use-facet/assets/native-direction.luau)
shows a complete theme and mounted task.

`define` starts from Facet Neutral when you omit `base`. State the edge and
the depth of the plates in [the finish block](Themes.finish.md). Check the returned
theme and repair any reported errors. Inspect `report.advice` against the task.
Pass the result to `Facet.app({ theme = theme })` and use `app.UI`. The theme
supplies both the stylesheet paint and the control metrics and chrome.

This excerpt shows a type role; the linked example mounts the full task:

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local definition: Facet.ThemeDefinition = {
    metrics = { typography = {
        title = { size = 42, font = { family = "Merriweather", weight = "Bold" } },
    } },
}
local theme, report = Facet.themes.define(definition)
assert(theme, report.errors[1] and report.errors[1].message)
```

A Text's role picks its font and size from the theme. A Button uses the
`control` role by default. Check the rendered hierarchy, selection, focus and
pressed state after changing the type and surfaces.

For other options, see [Theme-identity](Theme-identity.md),
[Themes.definition](Themes.definition.md), [Themes.tokens](Themes.tokens.md)
and [Themes.art](Themes.art.md). For a game HUD, keep `caption` at 16 or
more and `label` and `body` at 18 or more: smaller text is hard to read.
