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
A `shadow` on a native recipe still adds a `UIShadow`. The `panel` slot
applies to Dialog, Alert and a stack with `surface = "panel"`, so
`chrome.panel = { kind = "native", shadow = "raised" }` gives HUD panels a
shadow.

By default the `barFill` art is the size of the whole track, and the fill
clips it. Set `span = "fill"` on the `barFill` recipe to size the art to the
filled length. Then art with tapered ends shows both ends at every value.

State-dependent assets select the art for the hover, pressed, disabled and
selected behavior. Native rules still style the content and the engine
properties.

Callout and Popover can use theme arrow artwork. Declare `chrome.panelTail`
with `kind = "fill"`, an `asset`, `size = { w = 64, h = 64 }`, and
`overhang = 24`. The image points up. `overhang` is its depth outside the
panel; the rest overlaps the frame to cover the join. Draw the join into the
image, with the same edge bands and fill as the panel. Leave the outer area
transparent. Do not use a nine-slice asset for this slot.

Facet rotates the complete image onto each panel edge. It uses its width
when it clamps the arrow away from corners and its depth for anchor spacing.
The image follows panel scale and fade. On a short edge, it scales down
without changing its proportions. It receives the panel's `artTint` and the
theme's pixel rendering mode. Theme and palette changes update it live.
Fantasy Ornate, Fantasy Parchment and Pixel Quest include this artwork.
The arrow supplies its own border, so no native tail outline is drawn.

Without `panelTail`, the arrow uses a native shape. Use theme rules for
`.facet-tail-floating` (`BackgroundColor3`) and `.facet-outline-floating`
(`Color3`) to match a panel's artwork. With a panel skin, the native outline
draws only the two exposed tail edges. The artwork supplies the box frame.
With a native panel, the outline runs around the panel and its tail.
These rules do not change tooltip paint; help tails and outlines use
`.facet-tail-tooltip` and `.facet-outline-tooltip`. Without overrides, tails
use `surfaceStrong` and outlines use the theme's hairline color.

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
