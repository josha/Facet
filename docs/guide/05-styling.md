# Styling

Facet uses native StyleSheets. A theme helper creates Compose-owned StyleSheet and
StyleRule Instances. Construct the sheet inside the mounted component and parent
it under the target root alongside the StyleLink. A StyleLink reference alone
does not parent its sheet.

```luau
local sheet = Facet.themes.createStyleSheet(runtime, package)
return Host.ScreenGui {
    sheet,
    Host.StyleLink { StyleSheet = Compose.static(sheet) },
    UI.Button { label = "Continue", onActivate = onContinue },
}
```

Controls publish semantic tags and attributes. Default colors, fonts and decoration
belong in native rules. Explicit native instance properties intentionally take
precedence over stylesheet values; avoid them for default theme paint.

Theme inputs may be Compose readables. Native rules and control metrics respond
to the same selected definition. Image skins use real image assets and native
children; icons are images rather than substitute text glyphs.

Theme color and opacity changes animate through native StyleRule transitions using
`metrics.motion.normal`. A palette change updates the existing rules, so Roblox
retargets an interrupted switch from the displayed colors. Layout and typography
changes apply directly.

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

The transition override and reduced-motion input may be Compose readables. Use
`transition = false` for immediate paint; reduced motion also disables transitions.
With no reduced-motion input, the helper observes GuiService. Keep custom screen
paint in StyleRules so it follows the same theme transition as the controls.
