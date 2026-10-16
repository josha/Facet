# Themes.chrome

| Field | Meaning |
|---|---|
| `kind` | `"ring"` (the default): a stroke just outside the control. `"glow"`: a native `UIShadow` halo, which the engine paints over the control. `"nineSlice"`: the `asset` art, sliced around the control. `"brackets"`: a square stroke masked by a `UIGradient` to its two ends, like `[ ]`. |
| `color` | An RGB or a `$Role` palette token such as `"$FocusGlow"`. The default is `accent`. |
| `thickness` | The ring stroke (2) or the bracket bar (4), in pixels. |
| `size` | How far each bracket reaches along the top and bottom, in pixels (12). |
| `outset` | Pixels that art and brackets stand outside the control (0). |
| `sliceScale` | The art `SliceScale`; the asset's own value by default. |
| `blurRadius`, `transparency`, `zIndex` | The glow (24 pixels, 0.25, -1). |
| `corner` | `"square"` or `"pill"` for every control; otherwise the selected control's shape. |
| `pulse` | `true`: the look breathes slowly while it shows. Reduced motion stops it. |

The engine draws only the selection object itself and its UI components
(`UIStroke`, `UIGradient`, `UICorner`, `UIShadow`), never a child GuiObject,
so every look is one `ImageLabel` with those components. Facet Neutral uses
the default thin ring. Pixel Quest draws square brackets, Fantasy Ornate its
gold frame with a slow pulse, and Fantasy Parchment a gold ring.

A chrome slot names its art with `asset`: one asset name, or one name per
state (`default`, `hover`, `pressed`, `selected`, `disabled`). A state can also
be `{ asset, rotation, tint }`. `rotation = 180` turns the art over, so a
nine-slice frame with a centred slice rect shows its bevel pressed in. `tint`
is an RGB that multiplies the art (`ImageColor3`). When the `control` slot has
`selected` art, every skinned selected plate shows that art and never a flat
fill: a segment, a Picker row or card, a Chip, a Toggle button, a menu row and a
pill tab. The plate keeps the size of its unselected siblings, and its label is
`onSelected`. Each shipped skinned package has a selected piece. Pixel Quest
turns its wood plate over and tints it green. Fantasy Ornate turns its jewelled
selection plate over, so it sits inset in its gold trim. Fantasy Parchment turns
its parchment plate over and inks it dark brown, with a vellum label. Glossy
Touch uses its blue gel selection plate. Compact Pointer uses its pressed button
tinted blue.

The metrics also have optional entries:
