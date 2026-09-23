# Adding a theme package

Start from a neutral or maintained game-owned package. Give the new package a stable identity, named palettes, complete typography and semantic foreground/background pairs. Preserve real icon coverage and asset provenance.

```luau
local definition = themes.neutralPackage()
definition.identity.id = "harbor"
definition.identity.displayName = "Harbor"
definition.metrics.controlSizes.regular.height = 48
local package, report = themes.define(definition)
assert(report.ok)
return package
```

Declare additional native rules only when the semantic palette/metrics cannot express the requirement. Explicit Instance paint competes with StyleSheet rules; do not make default control paint an explicit override.

Use `themes.checkCoverage` for the concrete needs of a custom control. Check every palette's colors, typography and artwork. Apply the same package readable to controls and `createStyleSheet`; mount the sheet and a native StyleLink in the target tree.

Exercise the package in the actual gallery and reference applications. Inspect small/large controls, long/expanded labels, hover/pressed/disabled/selected states, visible focus, native text input, virtual rows and modal surfaces. Pixel and nine-slice assets need native-scale checks, not just source inspection.

Document the package's assets and requirements in the catalog. Publishing or uploading artwork is a separate authorized release action. The local change must build and verify without inventing live asset ids.
