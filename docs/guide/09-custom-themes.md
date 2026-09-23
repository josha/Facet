# Custom themes

A game-owned theme package supplies semantic colors, typography, metrics, icons and optional artwork. Facet compiles it into native StyleRules; a StyleLink applies those rules to the target tree. Change the package rather than adding repeated screen-specific paint overrides.

## Define and validate

Start from the neutral package, change named values, then validate the complete definition. RGB package values use normalized channel tables. Native code still uses Roblox datatypes for explicit properties.

```luau
local definition = Facet.themes.neutralPackage()
definition.identity.id = "my-game"
definition.identity.displayName = "My Game"
definition.metrics.controlSizes.regular.height = 48
definition.metrics.typography.title.size = 28
local package, report = Facet.themes.define(definition)
assert(report.ok, "Invalid game theme")
```

`define` returns `nil` with a report when validation fails. It validates RGB channels and semantic foreground/background contrast pairs. A successful numeric contrast check is not proof that every image background or selected state is readable; inspect the actual controls in Studio.

Packages contain:

| Field | Content |
|---|---|
| `identity` | Stable id, display name, version/schema metadata. |
| `style` | `defaultTheme` and named palette array `themes`. |
| `metrics` | Typography, spacing, corner radii, control sizes and control-specific measures. |
| `icons` | Semantic icon names mapped to image content or declared assets. |
| `assets` | Art declarations with content ids and optional slice geometry. |
| `chrome` | Native or image-based skin recipes for semantic control slots. |
| `rules` | Additional native `{ selector, properties }` rules. |

Each palette has `name`, `colors` and `extra`. The main roles include surfaces, content, accent and semantic success/warning/danger pairs. Extras carry hover, pressed, selected and secondary-content values. Required type roles are caption, label, body, heading, title, control, strong and numeral.

## Apply and switch

Use the same package readable for controls and the StyleSheet. `controls` uses it for metrics, icons and artwork; the StyleSheet supplies native paint. Construct and parent the sheet inside the screen owner; a StyleLink reference alone does not parent it.

```luau
local selectedPackage = Compose.cell(package)
local selectedPalette = Compose.cell(package.style.defaultTheme)
local UI = Facet.controls(runtime, { theme = selectedPackage })
local function Screen()
    local sheet = Facet.themes.createStyleSheet(runtime, selectedPackage, {
        theme = selectedPalette,
    })
    return Host.ScreenGui {
        sheet,
        Host.StyleLink { StyleSheet = Compose.static(sheet) },
        UI.Button { label = "Continue", onActivate = onContinue },
    }
end
```

Explicit Instance paint properties override native stylesheet paint. Set them only when the screen needs that override. Keep native sizing in the screen's layout; controlSizes and typography feed control measurements and paint. Spacing values are package data for native layout declarations; changing space.m alone does not rewrite a screen's UIPadding or UIListLayout.

## Coverage and icons

`checkCoverage(package, needs)` accepts a list of requirements. For example, `{ kind = "color", name = "accent" }` checks each palette, and `{ section = "metrics.typography", name = "body", fields = { "size" } }` checks numeric fields. The report lists covered and missing entries.

Icons resolve through `themes.resolveIcon`. Supply real image/vector image assets; do not substitute arbitrary text glyphs for interface icons. An image declaration is not evidence of ownership or successful loading. Keep asset provenance with the package, and verify images at native scale in the running application.

See [rich skinning](10-rich-skinning.md) for artwork and [theme catalog](13-theme-catalog.md) for maintained packages.
