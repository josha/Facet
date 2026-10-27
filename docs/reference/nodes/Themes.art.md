# Themes.art

<!-- aliases: skin recipe | image theme | theme assets -->

Define image artwork in `ThemeDefinition.assets` and reference it from
`ThemeDefinition.chrome`. The controls keep their input, focus and state behavior.
Do not call the runtime skin helper for each control.

## Assets

An asset record has `contentId` (or `content`), optional `assetName`, `tintRole`,
`sliceCenter = {x0, y0, x1, y1}`, `sliceScale`, `resample`, `preload` and `fallback`.
Use the real image's slice coordinates. `resample` is `"default"` or `"pixelated"`.
StyleSheets preload package assets except those marked `preload = "lazy"`.
The experience must have access to each asset; schema validation does not prove
availability or readable text over its artwork.

An asset reference is a name or
`{asset = name, rotation = 180, tint = {r = 1, g = 1, b = 1}}`.
Rotation supports 0 or 180; RGB components are normalized from 0 to 1. A state
map can supply `default`, `hover`, `pressed`, `selected` and `disabled` references.

## Recipes

| `kind` | Use |
| --- | --- |
| `native`, `none` | No extra image layers; a declared native shadow can still apply |
| `nineSlice` | Stretchable artwork using the asset's slice rectangle |
| `fill`, `frame` | A filled area or frame |
| `tile` | Repeating center artwork; `tileSize` uses `{w, h}` |
| `corners`, `edges`, `plaque` | Pieces around or beside content |
| `layered` | A `layers` list combining recipes |

Recipes use `asset`, not native `Image`, `ImageColor3` or `SliceCenter` fields.
`contentInsets` and `textInsets` use `left`, `right`, `top`, `bottom`. Choose them
from the artwork. See the installed `ThemeDefinition`/`SkinLayerPatch` declaration
for each recipe's fields. Focus recipes are described in [Themes.chrome](Themes.chrome.md).

Supply `ownedPanelAsset` with a real, accessible content ID. The slice numbers
below demonstrate a 12-pixel border on a 64-pixel image; replace them with the
coordinates from the actual source image:

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local definition: Facet.ThemeDefinition = {
    base = Facet.themes.neutralPackage(),
    assets = {
        panel = {
            contentId = ownedPanelAsset,
            sliceCenter = { x0 = 12, y0 = 12, x1 = 52, y1 = 52 },
        },
    },
    chrome = {
        panel = { kind = "nineSlice", asset = "panel" },
    },
}
local theme, report = Facet.themes.define(definition)
assert(report.ok and theme, "Invalid game art theme")
```

## Slots and boundaries

Common slots include `control`, `field`, `panel`, `badge`, `barTrack` and `barFill`.
`panel` styles Dialog, Alert and stacks with `surface = "panel"`.
`barFill` defaults to track-sized art clipped by progress; `span = "fill"`
fits art to the filled length. `panelTail` uses an unsliced upward image for
Popover/Callout tails, not a nine-slice panel image.

Native TextBox targets do not receive skin image children over their text;
framed inputs use a separate plate. Ten-foot metric scaling does not scale all
art geometry. Check small/large controls, long labels, clipping, focus, disabled
and selected states, theme switching, missing art and actual contrast.

For standalone subject art use [Image.reference](Image.reference.md) or
[AsyncImage.reference](AsyncImage.reference.md). RadialMenu's separate `skin`
option uses simpler state images, not these recipes. For the complete theme
definition and validation flow, read [Themes.definition](Themes.definition.md).
