# Rich skinning

A skin changes a control's artwork while the control retains input, focus and state behavior. Declare skins in a theme package's `chrome` slots; Facet creates their native image children through the same Compose runtime. There is no separate renderer or skin lifetime.

Use a `nineSlice` recipe for stretchable artwork. Declare the actual image in `assets`, including its slice rectangle. Use `layered` for a fill/frame, tiled center, corners, edges or a plaque. Native ImageLabel scaling performs the drawing.

```luau
local definition = Facet.themes.neutralPackage()
definition.assets.panel = {
    contentId = ownedPanelAsset,
    sliceCenter = { x0 = 12, y0 = 12, x1 = 52, y1 = 52 },
}
definition.chrome.panel = {
    kind = "nineSlice",
    asset = "panel",
}
local package, report = Facet.themes.define(definition)
assert(report.ok)
```

`ownedPanelAsset` must identify an asset available to the experience. A valid recipe with unavailable art still fails visually. Keep source images, upload manifests and provenance with the package.

Semantic slots include `control`, `field`, `panel`, `badge`, `barTrack` and `barFill`. A slot with native/none recipe creates no extra image layers. State-dependent assets choose art for hover/pressed/disabled/selected behavior; native rules still style content and engine properties.

`themes.skin(runtime, package, slot, options)` is available to control authors for a declared artwork slot. Options include a state readable, target, label, ZIndex and injected datatypes. Normal consumers configure the package rather than invoking the helper for every button.

Keep artwork transparent where content must show. Verify the smallest and largest control sizes, long labels, selected/disabled states, clipping, text insets and theme switching. Pixel artwork should declare pixel rendering/resampling deliberately. Do not duplicate hit testing, drag handling or state logic in the skin.
