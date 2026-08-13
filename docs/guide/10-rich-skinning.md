# 10. Rich skinning — when the art IS the interface

Chapter 9 built a theme package: colours, type, metrics, and one picture behind
a button. This chapter is for the game where **every visible part of the UI is
artwork** — a frame with corner ornaments and a title plaque, a health bar whose
track *and* fill are images, a switch whose ON state is a different picture, a
pixel-art skin that stays nearest-neighbour crisp, and one view tree that
re-skins itself when the player docks a phone to a monitor.

It is also the chapter about **how far you have to climb**. LuauUI copies
SwiftUI's customization ladder, and the point of a ladder is that you stop at the
rung that solves your problem:

| Rung | What you do | When | Where it is taught |
|---|---|---|---|
| **1 — the theme owns it** | package recipes: layers, per-state art, bars, toggles, icons, pixel mode | almost always — one change restyles the whole game | §10.1–§10.9 |
| **2 — the view overrides it** | a per-view prop or style modifier that beats the theme *for that node only* | one control genuinely differs | §10.10 |
| **3 — a custom control** | a new control with its own art and its own namespaced theme roles | the look is not a variation of anything | §10.11, and [`../extending/skinned-control.md`](../extending/skinned-control.md) |

Everything below is shipped and proven on a running Roblox session. The worked
examples are real files you can read beside this page:

| Package | What it is the example of |
|---|---|
| [`examples/themes/fantasy_ornate.luau`](../../examples/themes/fantasy_ornate.luau) | the centerpiece: layers, per-state art, bars, toggle, icons |
| [`examples/themes/pixel_quest.luau`](../../examples/themes/pixel_quest.luau) | `rendering = "pixel"`, and "selection changes the whole style" |
| [`examples/themes/glossy_touch.luau`](../../examples/themes/glossy_touch.luau) + [`compact_pointer.luau`](../../examples/themes/compact_pointer.luau) | the platform pair, swapped by `selectBy` |
| [`examples/themes/ornate_gauge.luau`](../../examples/themes/ornate_gauge.luau) | rung 3: a custom control with its own art |

> **What is proven, and what is not.** Everything in this chapter is covered by
> the headless suite and by the `theme_authoring` Studio scenario, and every
> visual claim was read back off a running session. The physical phone pass and
> the director's readability review remain open rows
> (`artifacts/rich-skinning-v2/review-packet.md`, RS-P1–RS-P4). Cost numbers are
> Studio-derated. Do not quote them as device truth.

**The canonical documentation check for this chapter:**

```sh
lune run tools/lune/check_docs_cli      # read-only; exit 0 = the docs match the build
```

---

## 10.1 Layers: a slot can be a small stack, not one picture

> **In plain words.** Chapter 9 gave each slot ONE picture. That is not enough
> for a fantasy frame: you want a wood ground, a gilt border over it, four
> different corner ornaments, a rail down each edge and a title board hanging off
> the top. So a slot can name a short list of layers instead, and LuauUI draws
> them back to front. It is a *list*, not a drawing program — every layer is one
> of six kinds with a fixed set of numbers you may give it.

Any slot recipe may say `kind = "layered"` and carry a `layers` array:

```lua
panel = {
    kind = "layered",
    contentInsets = { top = 30, right = 30, bottom = 30, left = 30 },
    fallback = "native",
    layers = {
        { kind = "tile",  asset = "ornate_velvet_tile", tileSize = { w = 64, h = 64 } },
        { kind = "fill",  asset = "ornate_panel_fill" },
        { kind = "frame", asset = "ornate_panel_frame" },
        { kind = "edges", asset = "ornate_edge_rail",
          sides = { "top", "bottom" }, thickness = 12, margin = 44, tile = 64 },
        { kind = "corners", asset = "ornate_corner_tl", size = 30,
          topLeft = "ornate_corner_tl",   topRight = "ornate_corner_tr",
          bottomLeft = "ornate_corner_bl", bottomRight = "ornate_corner_br" },
        { kind = "plaque", asset = "ornate_plaque", size = { w = 176, h = 40 },
          edge = "top", overhang = 20, text = true,
          textInsets = { top = 8, right = 16, bottom = 6, left = 16 } },
    },
    shadow = "raised",
}
```

**Z-order IS array order.** Layer 1 is at the back. The chrome text lift (§9.4)
always paints above the whole ladder, so a plaque can never bury a button's
label.

**A plaque with `text = true` is a NAMEPLATE.** The decorated node's own text
moves *onto* the plaque instead of sitting in its content rect — it is the same
lifted label §9.4 already describes, given the plaque's rectangle. `textInsets`
is the padding inside the plate, in px, so a carved border never eats its own
title; it is only legal alongside `text = true`, and a typo'd side is a compile
error rather than padding that silently is not there. Nothing new is created:
the nameplate costs zero extra instances.

**`overhang` renders OUTSIDE the decorated rect, and a clipping ancestor will
cut it off.** The number is published as reservation metadata
(`chrome_slots.overhangFor`) and the solver leaves room for it inside the
screen, but `ClipsDescendants` is the engine's, not the framework's: a panel
whose plaque overhangs 20px into a `UI.ScrollView` (or any `clipChildren`
container) loses those 20px at the clip boundary, silently and only when the
panel happens to sit at the top of the region. Nothing detects this — the census
publishes the number, and no check compares it against an ancestor's clipping —
so if a layered slot with an overhanging plaque is used inside a scroll region,
give the region that much leading padding, or drop the overhang to zero for
that skin.

The six kinds and the *only* geometry each accepts:

| kind | what it is | its vocabulary |
|---|---|---|
| `fill` | the content-back | full-bleed, nine-sliced by its asset's `sliceCenter`; optional `inset = { x, y }`, `mask = "pill"` |
| `frame` | border art over the fill | full-bleed, sliced; optional `inset = { x, y }`, `mask = "pill"` |
| `corners` | four ornaments | `size = px`, plus optional `topLeft` / `topRight` / `bottomLeft` / `bottomRight` asset overrides |
| `edges` | rails | `sides ⊆ {top,bottom,left,right}`, `thickness = px`, `margin = px`, optional `tile = px` |
| `plaque` | a header board | `size = { w, h }`, `edge = "top"`, `overhang = px`, optional `text = true` + `textInsets = { top, right, bottom, left }` |
| `tile` | a repeating texture | `tileSize = { w, h }` in **image pixels**; optional `inset = { x, y }`, `mask = "pill"` |

A field borrowed from another kind is a compile error naming the field and the
kind — a `tileSize` on a `corners` layer would otherwise be accepted and never
read.

#### `inset` — when a full-bleed layer should stop short of the corners

> **In plain words.** "Full bleed" means the layer covers the whole rect,
> corner to corner. That is right for the layer that *is* the plate. It is wrong
> for a texture riding *on* the plate, because a rectangle of stripes has square
> corners and your plate probably does not.

```lua
layers = {
  { kind = "fill", asset = "bar_track" },                    -- the trough, full bleed
  { kind = "tile", asset = "stripe", tileSize = { w = 24, h = 24 },
    inset = { x = 10, y = 2 } },                             -- the hatch, held off the ends
},
```

`inset` shrinks the layer's box **symmetrically per axis**: `x` px in from each
end, `y` px in from each edge. Both are optional and non-negative; declaring
none — or `{ x = 0, y = 0 }` — is exactly full bleed, so nothing changes for a
stack that does not ask.

It is legal on `fill`, `frame` and `tile` (the three full-bleed kinds) and a
compile error on `corners`, `edges` and `plaque`, whose boxes are already
anchored by their own geometry.

**Take the numbers from your art, not from taste.** `glossy-touch`'s progress
trough carries a 1px hard rim and a 1px lit bottom lip — the two lines that make
the well read as inset — so its hatch declares `inset = { x = 2, y = 2 }` and
nothing more. Guessing those numbers gets you a bar that looks almost right at
one width.

#### `mask` — when the layer should follow the SILHOUETTE instead

> **In plain words.** An inset holds a layer *away* from the edges. A mask lets
> it run all the way to them and clips it to the plate's shape. Use an inset for
> breathing room; use a mask when the content should follow the curve.

```lua
{ kind = "tile", asset = "stripe", tileSize = { w = 24, h = 24 },
  mask = "pill", inset = { x = 2, y = 2 } },
```

`mask = "pill"` is a capsule silhouette: a corner radius of half the layer's
height, at every width, so it follows a stretched track instead of a fixed
radius. It is legal on the same three full-bleed kinds and a compile error on the
others. **`"pill"` is the only value** — the framework materializes a real
`CanvasGroup` per masked layer and only that shape has been measured
(`artifacts/rich-skinning-v2/feasibility/rs-m9-canvasgroup-mask.json`).

**They compose, and they answer different questions.** The mask decides the
silhouette; the inset decides how far the content is held off the rim. The
shipped bar uses both: the pill clips the hatch along the trough's arc, and the
2px inset keeps it off the trough's two lines.

**The cost, honestly.** A mask is one `CanvasGroup` per masked layer. rs-m9
measured **~7 KB and ~18 µs each**, Studio-derated, and the framework counts them
as `canvasMasks` in the chrome census so the number is visible rather than
assumed. That is cheap for a bar and not cheap for a masked layer on every row of
a long list — count before you reach for it. A layer that only needs to stop
short of the corners wants an `inset`, which costs nothing.

### The number that actually matters: declarations versus instances

> **In plain words.** The cap is eight *lines* of layers — but one line can be
> four objects. Count what you are really paying for before you decide the frame
> needs one more flourish.

A slot may declare at most **8 layers** (`chrome_slots.MAX_LAYERS`; more is a
compile error). But a layer is not an instance:

- a `corners` layer is **four** instances,
- an `edges` layer is **one per side** you list,
- every other kind is one.

The panel above is 6 declarations and **11 instances per decorated node**. The
census measures the real number, and it is the number to design against: Fantasy
Ornate's live census reads 60 declared layers against **139 actual layer
instances** across the gallery — roughly a 2.3× multiplier
(`artifacts/rich-skinning-v2/rs-a17-cost.json`). `adapter.chromeCensus()` breaks
it down per kind so "the ornate skin costs this much" is a measurement rather
than an impression, and a flat theme still creates exactly zero.

### Two slots that cannot take a stack

- **`scrollbar`** — a `ScrollingFrame`'s children live in canvas space, so the
  decoration would scroll away from the bar.
- **`barFill`** — a bar's fill is *clipped whole art* inside the adapter's
  percent window (§10.3), not a decorated node, so declared layers would paint
  **nothing at all**. Put the decoration on `barTrack` instead;
  `glossy_touch.luau` is the shipped precedent (its barber-pole stripe rides the
  track, over a plain sliced fill). Both are compile errors that name the slot,
  the reason and the fix.

## 10.2 Per-state art: one grammar, both rungs

> **In plain words.** Chapter 9's skin was one picture per slot, brightened on
> hover and darkened on press. Sometimes that is not what you want: a pixel-art
> menu's *selected* row is a different plate with jewels on it, not a lighter
> version of the same plate. So anywhere you can name a picture, you can name a
> small table of pictures instead — one per interaction state.

Everywhere an asset reference is legal — a recipe's `asset`, a layer's `asset`, a
per-corner override, a bar or toggle or stepper slot, **and the per-view props at
rung 2** — you may write either form:

```lua
asset = "ornate_button_default"                     -- same art in every state

asset = {                                           -- per state
    default  = "ornate_button_default",             -- REQUIRED
    hover    = "ornate_button_hover",
    pressed  = "ornate_button_pressed",
    selected = "ornate_selection_selected",
    disabled = "ornate_button_dim",
    error    = "ornate_button_alarm",
}
```

The rules, all of them checked when the package compiles:

- **`default` is required.** A map without it is a compile error — an unstated
  resting state is a slot that paints nothing before the player touches it.
- **Unknown state keys are a compile error** naming the slot and the legal set.
  The six states are `default / hover / pressed / selected / disabled / error`.
- **Unstated states fall back to `default`, and the tint rules still apply on
  top.** Supply exactly as much art as you have: a map with `default` and
  `pressed` still brightens on hover.
- **`disabled` keeps its accessibility floor.** No `disabled` art means the
  standard disabled treatment over `default`, never a state that looks enabled.
- **Focus is not a variant state.** Focus applies to whichever node has focus,
  not to a kind of surface: it stays `chrome.focus` plus the `selection` slot
  (§9.4). **The focus visual hugs the DRAWN ART.** When a node carries a
  decoration, the ring (or the glow) hangs off that instance rather than off the
  node — the node's own rect includes the padding the engine needs for its label,
  and a decoration is a child of it, so a ring on the node leaves a band of empty
  air on each side of the plate it is outlining. For a layer stack the plate is
  the back-most full-bleed layer; a corner ornament or an overhanging plaque is a
  detail *on* the plate, not the plate. A node with no art keeps the solved-rect
  ring exactly as before, and hit geometry never moves — the touch floor is the
  node's own size and its invisible expander, neither of which the focus path
  touches.
- **A variant may declare `contentInsets` only if they are identical across
  states on each axis** — otherwise it is a compile error naming the slot, the
  state and the axis. The reason is the one non-negotiable: art may change on
  hover, **geometry may not**. A reflow under the player's finger is a bug you
  cannot tint your way out of.

The same normalizer runs for recipes and for view props, so the two can never
drift into different grammars.

**Variants are paint, not layout.** A state swap is one `Image` write on a rule
the package already emitted: measured live, the new art paints on the first
styled frame with `AbsoluteSize` byte-stable. Variant assets join the package's
preload seam, and `PreloadAsync` is the default policy — Studio cannot reproduce
a retail cold CDN, so the belt-and-braces preload stays rather than being
optimized away on evidence that does not exist.

## 10.3 Bars: a track, a clipped fill, and ornaments that never move

> **In plain words.** A health bar made of pictures has a problem: if you scale
> the fill image to the percentage, the art squashes — a bevel gets thinner as
> the bar empties. So LuauUI never scales the fill. It draws the fill at **full
> width** and reveals part of it through a window. The art is byte-identical at
> 1 % and at 100 %; only the window moves.

Four slots make an image bar:

```lua
barTrack  = { kind = "nineSlice", asset = "ornate_bar_track", fallback = "native",
              contentInsets = { top = 0, right = 0, bottom = 0, left = 0 } },
barFill   = { kind = "nineSlice", asset = "ornate_bar_fill",
              direction = "ltr", fallback = "native" },
barCap    = { kind = "nineSlice", asset = "ornate_bar_cap_start",
              startAsset = "ornate_bar_cap_start", endAsset = "ornate_bar_cap_end",
              size = { w = 28, h = 36 }, fallback = "native" },
barCenter = { kind = "nineSlice", asset = "ornate_bar_center",
              size = { w = 36, h = 28 }, fallback = "native" },
```

- **`barTrack`** stretches, so it is sliced. It is a normal decorated node and
  **can** carry a layer stack.
- **`barFill`** is the clipped art. `direction` is declared data — `"ltr"`
  (default), `"rtl"`, `"ttb"`, `"btt"` — and chooses which axis and anchor the
  window uses. Because the fill takes the window branch, a `layers` stack here is
  a compile error (§10.1).
- **`barCap`** and **`barCenter`** are fixed-size ornaments anchored to the
  **track**, which is exactly why they are separate slots: a cap baked into the
  fill art would disappear at 10 %.

**The `spinner` slot** is the bar family's indeterminate cousin: one dot of the
ring an indeterminate `newProgressView` draws when it has no value to report
(`presentation = "spinner"`). It is whole-image by default and **round** by
default, exactly like `sliderThumb` — a dot is a fixed-size token, and slicing
one would smear its centre pixel. Like `barTrack` / `barFill` it carries its own
solid native paint (the accent) so an unskinned spinner still reads under a flat
package, and like every other value-control slot it refuses a gradient: a wash's
alpha over a value control is what made the slider thumb see-through.

```lua
spinner = { kind = "nineSlice", asset = "ornate_spinner_dot", sliced = false,
            fallback = "native" },
```

**The circular indicator has no slot at all, and that is deliberate.**
`presentation = "circular"` — the ring that fills to a value, and the rotating
one that has no value to report — is drawn as a *stroke* on `UI.Path`, not as a
picture. There is nothing to skin: a stroke has a colour and a thickness and
nothing else. So it takes its colour from the ordinary style roles (the arc is
`accent`, the unfilled capacity ring behind it is `secondary`) and its size from
two theme metrics, `controls.progress.circularSize` and
`controls.progress.circularThickness`. Both are **optional** in a package — leave
them out and the snapshot fills them from your own `space` scale, so an existing
package gains a correctly-sized ring without editing a line. Author them if you
want a chunkier ring; the thickness the snapshot fills is deliberately kept
inside a fifth of the diameter, because a Path stroke is centred on its curve and
a thicker one would paint outside the box the layout measured. One thing a
package cannot do is fade it: `Path2D` has no transparency at all. Fade the
container instead — put the control inside a `UI.ZStack({ canvasGroup = true })`
of your own, which is the same idiom the framework's own refusal names.

Measured live across the sweep 0 / 1 / 50 / 99 / 100 %: the fill art keeps the
same width, the same origin, the same `Image`, the same `ScaleType` and the same
`SliceCenter` at every stop, while the window reveals 0 / 12 / 598 / 1183 / 1195
px of it; the caps and the crown do not move by a pixel, and the adapter writes
nothing at all per value change.

**An ornament RESERVES the space it paints in, and you declare that by declaring
its `size`.** A cap is centred on the track's *edge* and the centrepiece on its
*centre line*, so a 40x40 cap on an 8 px track paints 20 px past each end and 16 px
past each edge. Those extents are derived — never authored twice — by
`chrome_slots.barReservation`, published on the snapshot as
`chromeOutsets.barTrack`, and added to the bar's **margin**, so the solver moves
the label, the readout and the rows above and below out of the way. (Contrast
`contentInsets`, which reserves *inward* for the node's own content.) A package
that declares neither ornament reserves nothing and its bar row is byte-identical
to a flat one. Before this existed, an ornate cap painted straight over the label
at one end and the value at the other — the reservation is what makes a big
ornament a design choice rather than a collision.

### Art has a minimum height, and that is a METRIC

> **In plain words.** A painted rail is not a coloured line: it has a carved edge
> at the top and another at the bottom, and if you draw it 6 px tall those two
> edges land on top of each other and it turns to mush. So when your bar is art,
> raise the metric that controls its height — that is what metrics are for.

Studio Neutral draws a 6 px progress track because a flat bar is a rectangle.
Fantasy Ornate's track PNG is 28 px tall with a 12 px slice border, so at 6 px
the two borders overlap and the carving smears. The package therefore raises the
numbers:

```lua
controls = {
    progress = { trackHeight = 28, rowMinHeight = 36 },
    slider   = { railHeight = 24, thumbSize = 28, readoutMinWidth = 44 },
},
```

`controls.progress.trackHeight`, `controls.slider.railHeight` and
`controls.toggle.minHeight` are the three that art most often outgrows. They are
metrics, so the solver honours them and the layout follows — never a hidden
minimum inside the adapter.

### Flat bars still pay nothing

A package with no bar recipes builds no instances: the two solved nodes are
painted solid by the `luau-slot-barTrack` / `luau-slot-barFill` rules, the same
own-paint family the slider rail and thumb belong to. And as with the slider, a
**gradient may never target them** — a wash's alpha would make the value show
through the glass — so declaring one is a compile error.

That solid paint is the *flat* guarantee. The moment a bar node is skinned — by
your recipe, by a layer stack, or by a per-view image override on a package that
declares nothing for the slot — the matching `Skinned — <slot>` rule takes the
plate, the corner and the hairline off underneath it, exactly as it does for a
button. The art is the element.

## 10.4 Toggles and steppers

> **In plain words.** The sliding ON/OFF switch, and the little plate behind a
> stepper's `+` and `−`.

```lua
toggleTrack = { kind = "nineSlice", fallback = "native",
                asset = { default = "ornate_toggle_track_off",
                          selected = "ornate_toggle_track_on" } },
toggleKnob  = { kind = "nineSlice", fallback = "native",
                asset = { default = "ornate_toggle_knob_default",
                          pressed = "ornate_toggle_knob_pressed" } },
```

**ON is a different picture, not a tint** — it rides the toggle's value tag, and
the knob's **travel stays solver-owned**: art never moves geometry, so a skinned
switch and a flat one travel the same 20 px. A package that declares neither slot
gets exactly today's palette-true switch (§9.4's `togglePalette` contract is
untouched).

**`stepperPlate` is a whole-image slot by default**, because a plate is a
fixed-size token like a thumb or a badge seal. If your plate is a *bordered*
piece meant to stretch, say so — this is two packages' worth of hard-won
experience in one flag:

```lua
stepperPlate = {
    kind = "nineSlice",
    asset = { default = "ornate_stepper_plate_default",
              pressed = "ornate_stepper_plate_pressed" },
    sliced = true,          -- <-- WITHOUT this the bordered plate renders STRETCHED
    contentInsets = { top = 4, right = 4, bottom = 4, left = 4 },
    fallback = "native",
}
```

`stepperPlate` also **falls back to the `control` recipe** when a package does
not declare it, so a theme published before this slot existed keeps painting its
steppers exactly as it always did. A new slot must never make an old theme worse.

## 10.5 Icons: ask for a meaning, never for an asset id

> **In plain words.** A control asks for "the trailing chevron", not for a
> picture. Your theme decides what that looks like. A theme that has no picture
> for it gets a plain typed character instead — never an empty box.

```lua
icons = {
    increment            = "ornate_icon_plus",
    decrement            = "ornate_icon_minus",
    ["chevron.trailing"] = "ornate_icon_chevron_right",
    ["chevron.down"]     = "ornate_icon_chevron_down",
    checkmark            = "ornate_icon_check",
    close                = "ornate_icon_cross",
    ["ornate:settings"]  = "ornate_icon_gear",   -- a namespaced name (§10.11)
},
```

- The value is an **asset name from your own `assets` table** (per-state variant
  maps are legal here too), never a raw content id.
- **Size rides the snapshot.** `metrics.iconSizes = { small, medium, large }`, so
  a metric package resizes every icon at once and an icon drawn at its authored
  size resamples not at all.
- **Tint rides the asset.** An asset's `tintRole` is what colours the picture, so
  a `+` glyph can be the accent colour while the plate behind it is not.
- **A name the framework does not know is a compile error** with a "did you
  mean", unless it is namespaced `ns:name` — the same convention
  `themes.checkCoverage` speaks.
- **No icon means a real character, never tofu.** The framework owns an
  ASCII-safe fallback glyph per semantic name (`> < ^ v x + - = ...`), drawn in
  your theme's own font. This is not theoretical, and the measurement is on
  file: the old disclosure carets were `U+25B8` and `U+25BE`, two
  GEOMETRIC-SHAPES characters that **Michroma does not contain**. A live glyph
  probe in the running client, drawing them in that package's own resolved face,
  measured both at the tofu placeholder's fixed 30x48 advance while the ASCII
  characters rendered as themselves
  (`artifacts/rich-skinning-v2/rs-a7-semantic-icons.json`). The failure was a
  present-in-some-faces character, not a private-use codepoint — and a
  package may name any font, so ASCII is the rule and `themes.isSafeGlyph` is
  falsifiable.

Fantasy Ornate deliberately leaves `menu` and `more` **unmapped**, so the
fallback path is exercised inside the centerpiece rather than only in a test.

## 10.6 Pixel mode

> **In plain words.** Pixel art has one requirement: never blur it. Say your
> package is pixel art and LuauUI stops smoothing your images, refuses to slice
> them by a fraction, and rounds the theme's own measurements onto your grid.

```lua
identity = {
    id = "pixel-quest",
    schemaVersion = themes.SCHEMA,
    version = "1.0.0",
    rendering = "pixel",     -- <-- the flag
    pixelUnit = 4,           -- integer >= 1: one design pixel is 4 image px
},
```

Three things happen, and each is checkable:

1. **Every image rule carries `ResampleMode = Pixelated`**, and the census
   publishes both counts so `pixelatedRules == imageRules` is an assertion rather
   than a hope (19 == 19 live).
2. **`SliceScale` locks to integers at compile.** A fractional slice scale under
   `Pixelated` stays hard-edged but *unevenly sized* — which still looks crisp in
   a screenshot and is wrong on the grid, the worst of the three failure modes.
3. **The snapshot's lengths snap UP to multiples of `pixelUnit`.** Up, never
   down, so a 44 px target floor becomes 48 at unit 6 rather than 42. Durations
   and ratios are not lengths and are left alone.

A non-pixel package is byte-unaffected — enforced by comparing a package's metric
dump before and after a pixel package is installed and swapped away.

**The authoring idiom that makes it correct** (from
`assets/themes/pixel-quest/provenance.md`): author every sliced source at
**`2 × border + 1` design pixels** on each sliced axis. The stretched centre is
then exactly one design pixel, so any target size replicates one uniform colour
and cannot produce an uneven cell. And the general slice rule still applies:
**`2 × border` must be strictly less than the shorter side of the art**, or
opposite slices overlap and the picture shears.

**The "nothing here" idiom.** The per-state grammar requires a `default`. When a
layer should exist *only* in one state — Pixel Quest's ruby corner jewels appear
on the selected row and nowhere else — point `default` at a fully transparent
PNG (`pixel_blank`, 24×24 of nothing). Saying "no art in this state" out loud
beats shipping a dimmed ornament nobody asked for.

## 10.7 `content`, and `contentId`

> **In plain words.** The field that holds "which picture". It has two spellings
> and they mean the same thing.

`content` is the canonical field name and `contentId` is a permanent alias. Both
normalize to one string when the package compiles, so there is exactly one
resolution path:

```lua
ornate_panel_fill = { content   = "rbxassetid://…", sliceCenter = …, preload = "install", fallback = "native" },
parchment_panel   = { contentId = "rbxassetid://…", sliceCenter = …, preload = "install", fallback = "native" },
```

Declaring **both** on one asset is an authoring error. Package data stays plain
strings end to end — the engine coerces a string onto an `ImageContent` property,
so there is no materialization machinery in the framework at all, and an exported
package is still serializable. Two packages identical except for which spelling
they use compile to the same 81 rules and paint byte-identically.

## 10.8 Profile-conditional packages: `selectBy`

> **In plain words.** One game, one screen description, two skins: glossy 44 px
> rows on the phone, compact 22 px controls with hairlines when the player docks
> to a monitor. You declare which package belongs to which kind of input and
> LuauUI does the rest — including swapping live, mid-session, when the player
> plugs in a keyboard.

```lua
local controller = theme_controller.install(adapter, glossyTouch, {
    env = env,
    core = core,
    selectBy = { touch = glossyTouch, pointer = compactPointer, gamepad = compactPointer },
})
```

- The vocabulary is exactly the input-paradigm classes LuauUI already publishes:
  `touch`, `pointer`, `gamepad`. Nothing new is detected.
- **The right package installs at install time.** It resolves from the live
  profile before the first paint, so a desktop never shows one frame of 44 px
  phone rows.
- **A profile change swaps once, after it settles** (0.25 s by default). A hybrid
  device that flaps produces one swap per settlement, not a swap storm, and a
  flap that returns home swaps nothing at all.
- **An unmapped profile falls back to the package you passed positionally** —
  the second argument — not to whichever mapped package happens to be first.
- **A manual `swapPackage` wins until the next profile change**, and warns once.
  Predictability beats cleverness.
- The subscription lives and dies with the controller. **The view tree never
  observes any of it.**

What a swap actually costs you: nothing structural. Measured live across four
forced flips, 110 of 112 mount-identity entries were byte-identical, focus held,
and no view-tree node changed identity — while real geometry moved (the action
button 202×63 → 202×45, the stepper row 203×55 → 181×45). The two entries that
changed are the adapter's own bar clip pair, which is rebuilt by design when the
fill art changes.

## 10.9 The image is the element

> **In plain words.** If a button is a picture, you do not want LuauUI's grey
> rounded rectangle showing around the edges of it. It does not draw one — and
> that now holds for every image-bearing slot and every layer stack.

Chapter 9 introduced the three `Skinned — <slot>` suppression rules. In v2 they
cover **every** image-bearing slot and layered nodes identically: the decorated
node's fill, corner radius and hairline all stop drawing, `GetStyled` is the
instrument that proves it (a plain property read is *blind* to sheet paint), and
the census counts the suppressions. The exceptions are deliberate: the value
controls' own chrome (slider rail and thumb, bar track and fill) keeps its solid
paint guarantee, because those nodes must be visible under a flat theme too.

**Layer paint is rule-owned from birth.** The adapter never writes a layer's
paint at create time, because an explicit write made before a rule matches
survives and defeats the rule permanently. Every layer's plain `.Image` reads
`""` while `GetStyled` resolves the package's value — which is exactly the
signature you should look for when a skin refuses to repaint.

## 10.10 Rung 2 — overriding one view

> **In plain words.** One slider in your game is special. You do not need a new
> theme and you do not need a new control: you hand *that* slider its own
> picture, and everything else about it stays on the theme.

The per-view props take the **same grammar as a recipe** — a bare string or a
per-state map:

```lua
local slider = LuauUI.newSlider(LuauUI, core, {
    id = "Power", label = "Power", value = power, min = 0, max = 100,
    trackImage = "rbxassetid://133629068271978",        -- one picture
    thumbImage = {                                       -- ...or per state
        default = "rbxassetid://101901876687967",
        hover   = "rbxassetid://127234850374967",
        pressed = "rbxassetid://90667263700535",
    },
})
```

**How it works, and why you should know:** the overridden decoration is
deliberately **not tagged** with its slot, so the package's `Image` rule can
never reach it and the adapter writes the image properties directly. A tagged
instance would keep taking the theme's value and yours would lose on the next
swap. `dump().skinRung` reports `"theme"` or `"view"` so a probe can see which is
in force. A bare content URI carries no slice geometry, so an overridden image is
painted whole.

That is the **standing opt-out rule** made concrete: an explicit local value opts
that property out of theme changes, visibly and on purpose — exactly as an
explicit pixel size opts out of the theme's space steps.

### Style modifiers, and how they compose

> **In plain words.** Three little functions you wrap a view in: a drop shadow, a
> colour wash, rounded corners. They are *yours*, on *that* node — the theme
> keeps painting everything else exactly as it did.

`UI.shadow`, `UI.gradient` and `UI.corners` are the shipped per-view style
modifiers, and they compose with the theme in one sentence: **the view modifier
wins on that node, and the theme's own treatments are untouched everywhere
else.**

```lua
local card = UI.shadow(
    UI.gradient(UI.corners(UI.Box({ id = "Card", surface = "raised" }), 12), {
        colors = { "surfaceStrong", "accent" },   -- 2-3 stops: tokens or { r, g, b }
        rotation = 90,                            -- degrees; 90 = top -> bottom
        transparency = { 0.1, 0.3 },              -- optional alpha ramp
    }),
    "raised"
)
```

They read outside-in as you wrote them, each returning a new blueprint, and all
three are pure paint — none of them enters the layout solver, so adding a wash
never moves a pixel.

**Why the gradient is an INSTANCE and the theme's gradients are RULES.** A
theme's gradients ride the palette (`style.themes[].extra.chromeGradient.<slot>`)
and compile to phantom `::UIGradient` rules with zero child instances — right for
a theme, because a rule matches a *class* of nodes. This one has to win on
exactly one node, so it follows `UI.shadow`'s architecture instead: bounded
normalized data under the style authority, materialized by the adapter as **one**
bespoke `UIGradient` child named `LuauUIGradient`. The child is reused rather
than re-created, which is what makes a **package swap safe**: measured live, the
view's ramp survives the swap on the same node object with no second ramp stacked
on it, while the theme's own gradients keep painting everywhere else.

**Two things `UI.gradient` refuses, at construction:**

- **a value control's own chrome** — `sliderTrack`, `sliderThumb`, `barTrack`,
  `barFill`. This is the same ruling `themes.define` enforces on a theme's
  `chromeGradient` (§10.3), and for the same measured reason: a wash's alpha
  makes the node see-through, and whatever the control draws behind it reads
  straight through the glass. A rung-2 modifier that walked around a shipped
  ruling would be a hole, not a feature.
- **a text-bearing node** — `Text`, `Button`, `Toggle`, `TextField`.
  `UIGradient` multiplies the parent's *entire* rendering, its engine-drawn
  glyphs included, so a wash on a Button darkens its label along with its fill.
  Put the gradient on the `UI.Box` behind the label; the error message says so.
  (`UI.shadow` needs no such rule because a shadow cannot touch a glyph.)

And the same alpha ceiling as the theme path: every `transparency` stop is capped
at **0.9**, because a near-1 stop ghosts the whole node instead of softening the
wash. A subtle ramp lives around 0.1–0.35. One number, two authoring paths, and a
test asserts the two are equal.

**A wash needs a fill to multiply — and §10.9 may have taken it away.** This is
the one composition rule that will surprise you, so it is measured rather than
guessed. A `UIGradient` multiplies the node's OWN rendering; it does not reach
children. On a flat or gradient-based package the node paints a real fill and the
wash lands on it. On a package that skins that slot with art, the
image-is-the-element suppression (§10.9) has already set the node's own
`BackgroundTransparency` to 1 and moved the paint into decoration CHILDREN — so
there is nothing left for the wash to multiply, and the art wins. Live, on one
unedited card carrying one `UI.gradient`, across three packages:

| Package | the node's styled fill | decoration children | the wash |
|---|---|---|---|
| `classic-desktop` (flat) | `0.941, 0.933, 0.910`, transparency **0** | 0 | paints |
| `glossy-mobile` (gradient chrome) | `1, 1, 1`, transparency **0** | 0 | paints |
| `fantasy-ornate` (layered art) | transparency **1** (suppressed) | 10 | the art wins |

The `UIGradient` child itself is byte-identical in all three — same instance,
same stops, one child, never duplicated. That is what "the view modifier wins on
that node" means here: the view keeps its property through every swap, and the
theme keeps everything it owns. If you want a wash under an art-driven package,
put it on a node the package does not skin, or make the wash part of the art.

One more consequence of eager normalization, and it is visible in the captures:
the ramp's colour TOKENS resolve when you build, against the style you built
under — not against whatever package is installed later. Pass explicit
`{ r, g, b }` values, or rebuild the blueprint, if a wash must follow the
palette.

**One honest note, because it will bite otherwise:** these modifiers **normalize
eagerly**. They are functions returning a new blueprint, not reactive props you
can hand a `Readable`, so their values are baked when you build. Changing a
shadow's colour or a gradient's stops on a theme swap means rebuilding that
blueprint. (Reactive props — `width`, `height`, `image`, `offsetX` — re-solve
live.)

## 10.11 Rung 3 — a custom control that ships its own art

> **In plain words.** Sometimes the thing you want is not a restyled anything. It
> is a boiler-pressure gauge. Write the control: bring your own pictures, declare
> the few values you want the *theme* to own, and ask a theme — before the game
> runs — whether it covers them.

The worked example is
[`examples/themes/ornate_gauge.luau`](../../examples/themes/ornate_gauge.luau):
a brass channel with a ruby needle, drawn from three PNGs the **control** owns
(`assets/themes/ornate-gauge/`, with its own provenance and upload manifest).
The full walkthrough is [`../extending/skinned-control.md`](../extending/skinned-control.md);
here is the shape of it.

**Declare what the theme owns.** Everything else is yours:

```lua
ornate_gauge.needs = table.freeze({
    { name = "gauge:dial",   kind = "controlSize", section = "metrics.controlSizes",
      fields = { "height", "paddingX", "iconSize" }, authority = "layout",
      capability = "none", fallback = { height = 44, paddingX = 12, iconSize = 18 } },
    { name = "gauge:needle", kind = "color", section = "style.themes[].extra",
      authority = "paint", capability = "none",
      fallback = { r = 0.75, g = 0.58, b = 0.23 } },
    { name = "gauge:ring",   kind = "number", section = "metrics.radii",
      authority = "paint", capability = "none", fallback = 6 },
})
```

Those are the three contribution kinds — `controlSize`, `color`, `number` — and
they go in the three places a package may carry a namespaced key: `controlSizes`,
a theme's `extra`, and a plain metric section such as `radii`.

**Ask, before play:**

```lua
local result = LuauUI.themes.checkCoverage(package, ornate_gauge.needs)
-- result.ok, result.covered, result.missing = { { name, message, fix } }
```

Under a package that covers it (`fantasy-ornate`, `pixel-quest`) that is
`ok = true` with three covered roles. Under one that does not
(`classic-desktop`) it is three messages that name the role, say what the player
would see, and give the exact line to add:

```
gauge:dial — package 'classic-desktop' declares no 'gauge:dial' control size; the
contributed control falls back to its built-in metrics and stops following the theme
  fix: add metrics.controlSizes["gauge:dial"] = { height = .., paddingX = .., iconSize = .. }
```

And the control still runs, on its declared fallbacks. Degrade, then tell
somebody — never crash, and never fail silently.

**Re-theming a custom control.** A framework control re-solves on a package swap
because it reads the snapshot. Yours can too, if you bind the values you resolved
to reactive props. Live, under two packages: the gauge's dial moved 56 px → 48 px
and its corner radius 8 → 4 on a `fantasy-ornate` → `pixel-quest` swap, with all
12 of its mount-identity entries byte-identical and **no rebuild** — one signal
write. Its needle *glow* did not change colour, because `UI.shadow` normalized it
at build time (§10.10). That is the seam, stated rather than hidden.

**What a control may NOT do.** Decoration slots are a closed framework
vocabulary; a control cannot invent `chrome.myThing`. What it can do is reach the
existing slots through the public `surface` prop (a `UI.Box` with
`surface = "raised"` gets your package's panel skin, layers and all — that is why
the gauge sits inside Fantasy Ornate's carved frame in the capture) and paint its
own art with `UI.Image`. `UI.Image` has no slice geometry and no tint on purpose:
those are theme-recipe authority. **Design the art for the authority you have** —
the gauge's channel is authored horizontally invariant so stretching it is
lossless, and its needle and end caps are drawn at a fixed px box and never
stretched at all.

## 10.12 Where to go next

- The contributor-side rules for changing the theme *system* — new slots, new
  recipe fields, migration duties — are in
  [`../extending/new-theme.md`](../extending/new-theme.md).
- The rung-3 playbook, step by step, is
  [`../extending/skinned-control.md`](../extending/skinned-control.md).
- The decisions behind everything above, and the engine measurements each one
  stands on, are in
  [`../adr/ADR-0020-rich-skinning-v2.md`](../adr/ADR-0020-rich-skinning-v2.md).
- The scenario that drives all of it live is
  [`../../examples/gallery/scenarios/theme_authoring.luau`](../../examples/gallery/scenarios/theme_authoring.luau);
  the steps this chapter's features add are `installLayered`, `layerCensus`,
  `barSweep`, `setToggle`, `iconProbe`, `pixelProbe`, `tileProbe`,
  `selectByPair`, `presentGaugeFixture`, `gaugeProbe` and `gaugeCoverage`.
