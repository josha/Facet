# A theme for this game

Design from the game's world, objects, audience and tone. Choose a few concrete
relationships: the type that carries identity, quiet surfaces for reading, an
accent for the main action, and art or materials that belong to the subject.
For an existing game, extend its identity. A stock package is a usable base, not
the visual brief. A field journal, sports broadcast and workshop can use the
same controls while having different typography, materials and compositions.

Build the theme alongside one representative complete task. Establish first,
second and third attention through subject scale, type, grouping and space.
Do not compensate for weak hierarchy with more gradients, textures or borders.
Use distinct task layouts under a coherent theme; not every page needs a panel.

## Theme contracts

Start with `Tasks.theme`, then retrieve only the contract needed from
`Themes.definition`, `Themes.palette`, `Themes.art` and `Themes.chrome`.
Define one game package with `Facet.themes.define`; inspect its returned package
and report. Set semantic palette roles, typography roles, spacing, targets,
icons and motion there. Use `textRole` in controls so access adjustments work.
Avoid scattered native paint overrides that defeat the live StyleSheet.

Motion should explain the relationship. A child page can shift its parent;
a task opened over gameplay can leave the HUD still. `Tasks.theme` shows
`metrics.motion.distances.parallax = 0` for that second choice. It affects all
default navigation stacks in the theme. Check both directions, interruption
and reduced motion; a settled capture cannot show an unwanted background slide.

Theme contrast validation covers semantic color pairs. It does not prove text
contrast over an image or the scene. Test focus, selected, disabled, pressed and
error states against actual backgrounds. Use text or shape as well as color.
Keep target sizes, readable labels and visible focus while changing the style.

## Three ways to use images

| Need | Use | Responsibility |
| --- | --- | --- |
| Reusable control surfaces and states | Theme `assets` and `chrome` recipes | Stretch/tile geometry, content insets, state paint and readable focus |
| Subject art, portraits or illustrations | Image or AsyncImage | Fit/crop, useful scale, loading/failure state and an accessible label |
| Game-specific framing or decoration | Host image/frame composition | Bounds, clipping, layering and input clearance; it does not replace a control |

Use `Themes.art` for asset and recipe definitions, `Themes.chrome` for focus and
state treatment. `Themes.skin` describes the runtime helper for control authors;
ordinary game authors configure the package instead of calling it per control.

For image skins, keep edge art away from text and give the reading area a quiet
center. Nine-slice preserves corners while the surface changes size. Tiles suit
repeating materials; layered recipes can combine an edge and a fill. Choose the
recipe from the art, rather than stretching an entire ornate image over each
button. Assets need usable permissions and real content IDs; do not invent IDs.

The following is an asset/chrome fragment for a `ThemeDefinition`, not a complete
theme. `ownedAsset` is the game's accessible image, and the four slice coordinates
must come from that image's border geometry:

```luau
assets = {
    panel = {
        contentId = ownedAsset,
        sliceCenter = { x0 = left, y0 = top, x1 = right, y1 = bottom },
        sliceScale = 1,
        resample = "default",
    },
},
chrome = {
    panel = { kind = "nineSlice", asset = "panel" },
},
```

Skin patches use `asset`, not native `Image`, `ImageColor3` or `SliceCenter`
properties. Asset references can supply tint and rotation. Theme skin states
include default, hover, pressed, selected and disabled. Read the recipe contract
for content insets and focus treatment; do not assume an image supplies them.
RadialMenu's separate `skin` API accepts simpler images and states, not the
ThemeDefinition skin recipe or arbitrary image-shaped hit targets.

For standalone Image, choose fit/fill/crop/stretch/tile/slice deliberately.
Bound `scaleMode` cannot switch to tile/slice; circular images cannot use slice.
AsyncImage native fields belong in `imageProperties`; its loader can return
cancellation. Keep a useful placeholder or fallback and ignore stale loads.
Routes: `Image.reference`, `Image.props`, `AsyncImage.reference`, `AsyncImage.props`.

## Test the identity, not just the asset

Use the theme in a main task, a dense task and a temporary surface. Capture them
over the real world at wide and constrained sizes. Check translated text, large
text, controller focus, disabled actions, keyboard, missing/slow art and bright
and dark scene regions. Ten-foot metric scaling does not automatically scale
every art inset. Limited motion can retain paint transitions; use the actual
motion contract rather than assuming all animation stops.

Prefer a small reusable asset set. Theme stylesheets preload package assets
unless an asset is marked lazy; avoid loading unrelated large art for every
screen. Pause hidden live subjects, cancel obsolete loads and dispose owned
resources. Measure frame timing and retained memory after completed returns.
An image theme is optional: ship it only if it strengthens identity and remains
legible, responsive and within the game's performance budget.
