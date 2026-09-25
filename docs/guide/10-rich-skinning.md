# Rich skinning

A skin changes the artwork of a control. The control keeps its input, focus and
state behavior. Declare skins in the `chrome` slots of a theme package. Facet
makes their native image children through the same Compose runtime. There is no
separate renderer and no separate skin lifetime.

## Recipes

- Use a `nineSlice` recipe for stretchable artwork. Declare the actual image in
  `assets`, with its slice rectangle.
- Use `layered` for a fill or frame, a tiled center, corners, edges or a
  plaque.

Native ImageLabel scaling does the drawing.

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

`ownedPanelAsset` must identify an asset that the experience can use. A valid
recipe with unavailable art still fails visually. Keep the source images, the
upload manifests and the provenance with the theme package.

## Slots and states

The semantic slots include `control`, `field`, `panel`, `badge`, `barTrack` and
`barFill`. A slot with a native or none recipe makes no extra image layers.

State-dependent assets select the art for the hover, pressed, disabled and
selected behavior. Native rules still style the content and the engine
properties.

## The skin helper

Control authors can use `themes.skin(runtime, package, slot, options)` for a
declared artwork slot. The options include a state readable, a target, a label,
a ZIndex and injected datatypes. Ordinary consumers configure the theme package.
They do not call the helper for each button.

## Checks

Keep artwork transparent where content must show through. Verify these cases:

- the smallest and the largest control sizes,
- long labels,
- selected and disabled states,
- clipping,
- text insets,
- theme switching.

Pixel artwork must declare its pixel rendering and resampling deliberately. Do
not duplicate hit testing, drag handling or state logic in the skin.
