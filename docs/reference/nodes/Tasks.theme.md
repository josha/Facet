# Tasks.theme

<!-- aliases: themePackage | ThemeDefinition | custom theme | theme definition | visual identity | art direction | native theme -->

Use [use-facet](Design.guide.md) to choose the visual direction first. The
[Proof Press example](../../../skills/use-facet/assets/native-direction.luau)
shows a complete theme and mounted task. This small letterpress game uses
native type as its subject, with warm paper, a serif specimen and a square
proof. Its draft selection and printed ink change independently.

Copy the example into a LocalScript in `StarterPlayerScripts` with Facet
installed. In Studio, read the source in Edit under
`ServerStorage.FacetDocs.skills["use-facet"].assets["native-direction.luau"]`.

`define` starts from Facet Neutral when you omit `base`. Check the returned
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
and [Themes.art](Themes.art.md). For example, set
`metrics.motion.distances.parallax = 0` to keep covered pages still in the
theme's default stacks.
