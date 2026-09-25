# Styling

Facet uses native StyleSheets. A theme helper makes StyleSheet and StyleRule
Instances that Compose owns.

## Install the StyleSheet

`Facet.app` installs the StyleSheet for you. Give the theme package one time:

```luau
local app = Facet.app({ theme = package })
app.mount(function()
    return app.UI.Button { label = "Continue", onActivate = onContinue }
end)
```

The controls and the sheet then use the same package. To install the sheet
yourself, for example in a SurfaceGui, do these steps:

1. Make the sheet inside the mounted component.
2. Parent the sheet under the target root.
3. Put a StyleLink that references the sheet next to it.

A StyleLink reference alone does not parent its sheet.

```luau
local sheet = Facet.themes.createStyleSheet(runtime, package)
return Host.ScreenGui {
    sheet,
    Host.StyleLink { StyleSheet = Compose.static(sheet) },
    UI.Button { label = "Continue", onActivate = onContinue },
}
```

## Where paint comes from

Controls publish semantic tags and attributes. Default colors, fonts and
decoration belong in native rules.

Explicit native Instance properties take precedence over stylesheet values.
This is intentional. Do not use them for default theme paint.

Screen content can use the same rules. Add the tag, and do not set the painted
property. `facet-panel` paints a rounded panel surface, `facet-pane` paints a
flush `surfaceStrong` pane with no corner or stroke, `facet-divider` paints a
hairline, `facet-divider-strong` next to it paints a heavier rule, and
`facet-path` paints a `Path2D` line in the accent color.
`facet-icon-neutral`, `facet-icon-info`, `facet-icon-success`,
`facet-icon-warning`, `facet-icon-error` and `facet-icon-accent` paint an image
in the status color.

Theme inputs can be Compose readables. The native rules and the control metrics
respond to the same selected definition. Image skins use real image assets and
native children. Icons are images, not substitute text glyphs.

## Theme transitions

Changes to theme color and opacity animate through native StyleRule
transitions. The duration is `metrics.motion.normal`. A palette change updates
the existing rules. If a switch is interrupted, Roblox retargets it from the
colors on screen. Layout and typography changes apply immediately.

```luau
local selectedPalette = Compose.cell("dark")
local reducedMotion = Compose.cell(false)
local sheet = Facet.themes.createStyleSheet(runtime, package, {
    theme = selectedPalette,
    transition = TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    reducedMotion = reducedMotion,
})
return Host.ScreenGui {
    sheet,
    Host.StyleLink { StyleSheet = Compose.static(sheet) },
    UI.Button { label = "Continue", onActivate = onContinue },
}
```

The transition override and the reduced-motion input can be Compose readables.

- Set `transition = false` for immediate paint.
- Reduced motion also disables transitions.
- If you do not supply a reduced-motion input, the helper observes GuiService.

Keep custom screen paint in StyleRules. Then it follows the same theme
transition as the controls.

The [API reference](../reference/api.md#themes) has the full `createStyleSheet`
contract. [Custom themes](09-custom-themes.md) explains how to make a
game-owned theme package.
