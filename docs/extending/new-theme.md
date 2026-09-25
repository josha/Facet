# Adding a theme package

Start from the neutral theme package or from a maintained game-owned theme
package. Give the new theme package:

- a stable identity,
- named palettes,
- complete typography,
- semantic foreground and background pairs.

Keep real icon coverage and the asset provenance.

```luau
local definition = themes.neutralPackage()
definition.identity.id = "harbor"
definition.identity.displayName = "Harbor"
definition.metrics.controlSizes.regular.height = 48
local package, report = themes.define(definition)
assert(report.ok)
return package
```

Declare additional native rules only when the semantic palette and metrics
cannot express the requirement. Explicit Instance paint competes with
StyleSheet rules. Do not make default control paint an explicit override.

Use `themes.checkCoverage` for the concrete needs of a custom control. Check
the colors, typography and artwork of each palette. Apply the theme package as
[custom themes](../guide/09-custom-themes.md#apply-and-switch) describes.

Exercise the theme package in the actual gallery and in the reference
applications. Examine:

- small and large controls,
- long and expanded labels,
- hover, pressed, disabled and selected states,
- visible focus,
- native text input,
- virtual rows,
- modal surfaces.

Pixel and nine-slice assets need checks at native scale. Source inspection is
not sufficient.

Document the assets and the requirements of the theme package in the catalog.
Publishing or uploading artwork is a separate, authorized release action. The
local change must build and verify without invented live asset ids.
