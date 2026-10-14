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
property. `facet-panel` paints a rounded panel surface with content padding of at least
the theme’s `space.m` on each side (or larger skin content insets), `facet-pane` paints a
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
transitions. The duration is `metrics.motion.normal`, except that `:Press` rules
use `metrics.motion.press` and `:Hover` rules use `metrics.motion.hover` (each no
slower than `normal`). The easing style is `metrics.motion.styles.paint` (Quad
Out in Facet Neutral). A palette change updates
the existing rules. If a switch is interrupted, Roblox retargets it from the
colors on screen. Layout and typography changes apply immediately.

```luau
local selectedPalette = Compose.cell("dark")
local motionLevel = Compose.cell("normal")
local sheet = Facet.themes.createStyleSheet(runtime, package, {
    theme = selectedPalette,
    transition = TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    motionLevel = motionLevel,
})
return Host.ScreenGui {
    sheet,
    Host.StyleLink { StyleSheet = Compose.static(sheet) },
    UI.Button { label = "Continue", onActivate = onContinue },
}
```

The transition override and the reduced-motion input can be Compose readables.

- Set `transition = false` for immediate paint.
- Motion level `none` also disables transitions. Level `limited` (the
  engine's Reduce Motion) keeps these colour fades.
- If you do not supply a reduced-motion input, the helper observes GuiService.

Keep custom screen paint in StyleRules. Then it follows the same theme
transition as the controls.

The [API reference](../reference/api.md#themes) has the full `createStyleSheet`
contract. [Custom themes](09-custom-themes.md) explains how to make a
game-owned theme package.

## Game-specific rules

Use Roblox styling first. Facet's theme compiler only resolves palette roles
and metric references before it emits native rules. For example, add these
rules to a game theme with `metrics.strokes.outline = 3`:

```luau
local definition = Facet.themes.neutralPackage()
definition.metrics.strokes.outline = 3
definition.rules = {
    {
        selector = ".toy-button::UIStroke",
        properties = {
            Color = { role = "content" },
            Thickness = { metric = "strokes.outline" },
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        },
    },
    {
        selector = ".facet-dialog >> .facet-role-cancel",
        properties = { BackgroundColor3 = { role = "surfaceStrong" } },
    },
}
```

The outline becomes 4.5 pixels at ten feet and follows a theme replacement.
A literal `Thickness = 3` remains 3. A metric reference must resolve to a finite
number; it cannot construct a `UDim`, `UDim2` or sequence. Use native values for
those types. Dialog actions already carry Button role tags, including
`facet-role-default`, `facet-role-cancel` and `facet-role-destructive`.
An action's `id` becomes its native `Name`; use `#RaceAgain` for one action.

Roblox creates the pseudo-instances targeted by `::UIStroke`, `::UICorner`,
`::UIGradient` and `::UIPadding`. Do not add another decoration just to make
those rules work. Facet also mirrors authored `::UIStroke` rules onto its real
`facet-fade-stroke` child so the stroke can follow a control fade. Facet enables
that child during the fade. To remove a stroke in both states, set
`Thickness = 0`; `Enabled = false` alone does not suppress that fade child.
This is Facet's fade policy, not a limitation of native `UIStroke.Enabled`.
Native corner, stroke and gradient rules also decorate `kind = "native"`
skins; no separate skin fields are needed for these mechanisms.

## Press effects and game state

Use native `:Press` selectors for visual press state. A composite Button can
contain native children; keep one Button as the activation target. A child
`UIScale` named `FaceScale` can be selected by
`.toy-button:Press >> #FaceScale`. Scale a visual face inside a stable hit target
when a press effect must not change the pointer hit area.

Roblox's `StyleRule:SetPropertyTransitions` supports native property
transitions. Put geometry transitions on game-owned rules in the same sheet;
Facet only installs automatic transitions for color and transparency. For
example, create a rest rule and a press rule for that `UIScale`:

```luau
local theme = Compose.cell(package)
local sheet = Facet.themes.createStyleSheet(runtime, theme)
local rest = Host.StyleRule { Selector = ".toy-button >> #FaceScale", Parent = Compose.static(sheet) }
local pressed = Host.StyleRule { Selector = ".toy-button:Press >> #FaceScale", Parent = Compose.static(sheet) }
rest:SetProperties({ Scale = 1 })
pressed:SetProperties({ Scale = 0.94 })
local environment = UI.environment()
Compose.watch(function(use)
    local motion = use(theme).metrics.motion
    local duration = if use(environment.reducedMotion) then 0 else motion.press or motion.normal
    local transitions = { Scale = TweenInfo.new(duration) }
    rest:SetPropertyTransitions(transitions)
    pressed:SetPropertyTransitions(transitions)
end)
local button = UI.Button {
    label = "",
    name = "Drift",
    Size = UDim2.fromOffset(120, 64),
    Host.Frame "Face" {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Host.UIScale "FaceScale" {},
        UI.Text { text = "DRIFT", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center },
    },
}
button:AddTag("toy-button")
return Host.ScreenGui {
    sheet,
    Host.StyleLink { StyleSheet = Compose.static(sheet) },
    button,
}
```

Author a transition on both the entered and the exited state. The example uses the selected
theme’s motion timing. Prefer a child scale to animating a layout-owned `Size` or `Position`. If game logic needs
`GuiState`, read the Button's native property and observe
`GetPropertyChangedSignal("GuiState")`; register the connection's disconnect
with `Compose.cleanup`. Do not mirror pointer events merely to paint a press.

For a semantic game tag, use a Compose watch and native tag methods inside the
mounted component. The owner stops the watch when the control is removed:

```luau
local hasItem = Compose.cell(false)
local button = UI.Button { label = "Item" }
Compose.watch(function(use)
    if use(hasItem) then
        button:AddTag("has-item")
    else
        button:RemoveTag("has-item")
    end
end)
return button
```

For motion that needs a spring, use `runtime.spring` with
`theme.metrics.motion.springs[name]` and the public reduced-motion fact.
Motion metrics do not scale with viewing distance, and the internal
`ctx.motionSpring` only reads the theme; it adds no reduced-motion policy.
A new app-level wrapper would not remove the game's policy decision.

Checked native APIs: [UI styling](https://create.roblox.com/docs/ui/styling),
[StyleRule](https://create.roblox.com/docs/reference/engine/classes/StyleRule),
[GuiObject](https://create.roblox.com/docs/reference/engine/classes/GuiObject),
and [UIStroke](https://create.roblox.com/docs/reference/engine/classes/UIStroke).
These provide selectors, transitions, press state and decorations; Compose
provides their reactive bindings and lifetime.
