# 9. Custom themes

Chapter 5 covered how a screen gets its look from the built-in style. This
chapter is about replacing that look entirely — font, type scale, spacing,
control heights, corners, insets and ornate nine-slice chrome — **without
editing a single screen**.

The thing you build is a **theme package**: one frozen, versioned, plain-data
table. It carries no code and no component trees, so you can inspect it, diff
it, serialize it, and hand it to another project. Everything in this chapter
goes through the public `Facet.themes` surface and the client-side
`theme_controller`; nothing here requires an internal import.

The worked example is **Fantasy Parchment**, the repository's proof theme. Its
source is [`examples/themes/fantasy_parchment.luau`](../../examples/themes/fantasy_parchment.luau)
and every code block below is quoted from it. Read that file alongside this
chapter — it is one file, and it is the whole answer.

> **What is proven, and what is not.** Everything below is covered by the
> headless suite and by the `theme_authoring` Studio scenario. The physical
> phone pass, the human Style-Editor walkthrough, and low-end-device cost
> remain open rows (`artifacts/theme-packages-and-skinning/review-packet.md`,
> TP-P1–TP-P4). Do not quote theme-swap cost as device truth.

**The canonical documentation check for this chapter:**

```sh
lune run tools/lune/check_docs_cli      # read-only; exit 0 = the docs match the build
```

---

## 9.1 The shape of a theme package

> **In plain words.** A theme package is one big settings table. You fill in
> what your game should look like — the colours, the type, how big a button is,
> which picture to draw behind it — and hand it over. Nothing in it can run
> code, so it is safe to read, diff, and send to somebody else. This section is
> the map of what goes in the table.

A package has seven sections. Six you author; one (`base`) says where to start.

| Section | What it owns |
|---|---|
| `base` | another compiled package to derive from — values you omit are inherited |
| `identity` | `id` (a stable slug), `displayName`, `schemaVersion`, `version` (semver) |
| `style` | the palette: `defaultTheme` plus an ordered list of named colour themes |
| `metrics` | typography roles, space steps, control sizes, radii, strokes, target floor, per-slot insets, motion |
| `chrome` | one recipe per decoration slot: flat native paint, or a nine-slice image |
| `assets` | semantic name → content ID, slice geometry, preload policy, failure fallback |
| `compatibility` | the Facet schema and capabilities the package requires |

Two rules make a package safe to pass around:

- **A package is data, never code.** `themes.define` rejects a function found
  anywhere in the definition.
- **A theme may not move anything.** A theme rule can write paint (fills, text
  colour, `FontFace`, corners, strokes, gradients) and — inside a nine-slice
  recipe — the decoration image's properties. It can never write `Size`,
  `Position`, `Visible`, `Text`, `AnchorPoint`, `CanvasSize` or their kin;
  those belong to the solver, a data binding, or the presentation transform.
  This is checked when the package compiles, not discovered on a device. See
  [`../extending/new-theme.md`](../extending/new-theme.md) §1 for the full ruling.

## 9.2 Step 1 — derive from Studio Neutral

> **In plain words.** Do not start from an empty table; start from Facet's own
> theme and change only what you care about. Anything you leave out you simply
> inherit — including new things future versions of Facet add, which you would
> otherwise be missing without knowing it.

Never start from a blank table. Start from the library's own package, so core
roles that a future Facet version adds are inherited through a diagnosed
upgrade instead of being missing from your copy:

```lua
local Facet = require(ReplicatedStorage.Facet)
local themes = Facet.themes

local definition = {
    base = themes.neutralPackage(),          -- <-- start here, always
    identity = {
        id = "fantasy-parchment",
        displayName = "Fantasy Parchment",
        schemaVersion = themes.SCHEMA,
        version = "1.0.0",
    },
    -- …style, metrics, chrome, assets, compatibility…
}

local package, report = themes.define(definition)
```

`themes.define` returns **two** values. On success `package` is deeply frozen
and carries a deterministic content `stamp`; on failure it is `nil` and
`report.errors` names the offending field, the problem, and the fix:

```lua
if package == nil then
    for _, err in report.errors do
        print(err.field, err.message, err.fix)
    end
end
```

Rejections you will meet in practice: a missing core role, an unknown field
(with a "did you mean"), a colour pair below the 4.5:1 contrast floor, a target
size under 44 px, a nine-slice recipe with no declared `fallback` or naming an
asset the package never declared, and an incompatible `schemaVersion`.

### The palette

> **In plain words.** The colours. A "theme" here means one named colour scheme,
> and a package can carry several (Parchment ships a daylight one and a
> candlelit one). Every colour pair is contrast-checked when the package
> compiles, so you cannot ship text nobody can read.

`style.themes` is an ordered list. Fantasy Parchment ships two, so the package
can be re-themed *without* changing geometry:

```lua
style = {
    defaultTheme = "Daylight",
    themes = {
        { name = "Daylight", colors = DAYLIGHT.colors, extra = DAYLIGHT.extra },
        { name = "Candlelight", colors = CANDLELIGHT.colors, extra = CANDLELIGHT.extra },
    },
},
```

`colors` carries the contract pairs (`surface`/`content`,
`surfaceStrong`/`contentStrong`, `accent`/`onAccent`, `danger`/`onDanger`), each
gated for contrast. `extra` carries the non-contract interaction roles
(`control`, `controlHover`, `controlPressed`, `controlSelected`,
`contentSecondary`, `hairline`, the opacity scalars). `extra` is optional — any
role you leave out is derived from the contract colours with the same ramps the
library uses, so a palette-only package can be a dozen lines.

### The metrics

> **In plain words.** The measurements: type sizes, spacing steps, how tall a
> button is, how round its corners are. Controls ask for these by NAME
> ("body", "regular", "m") rather than by number, which is exactly why swapping
> a theme moves the layout without rebuilding a single screen.

This is the half that Chapter 5's Dark/Light swap could never touch. Parchment
changes all of it:

```lua
metrics = {
    typography = typography(),
    -- rounder rhythm than Neutral's 4/8/16/24/40: parchment breathes
    space = { xs = 4, s = 8, m = 16, l = 26, xl = 42 },
    -- taller controls: the carved border needs shoulder room, and the
    -- calligraphic face reads better with air above and below
    controlSizes = {
        compact = { height = 38, paddingX = 14, iconSize = 18 },
        regular = { height = 46, paddingX = 18, iconSize = 22 },
        large = { height = 58, paddingX = 22, iconSize = 26 },
    },
    radii = { control = 6, panel = 10, pill = 999 },
    strokes = { hairline = 1 },
    targetSizes = { minimum = 44 },
    motion = { fast = 0.14, normal = 0.24 },
    insets = { … },
},
```

The six typography roles are `caption`, `label`, `body`, `control`, `heading`,
`title`. Each is `{ font = { family, weight?, style? }, size, lineHeight }`:

```lua
local FAMILY = "rbxasset://fonts/families/Fondamento.json"
local TYPE_SIZES = { caption = 12, label = 14, body = 16, control = 17, heading = 22, title = 28 }

local function typography(): any
    local out: any = {}
    for role, size in TYPE_SIZES do
        out[role] = { font = { family = FAMILY }, size = size, lineHeight = 1.35 }
    end
    return out
end
```

**Why a screen never has to change.** Controls ask for a *role name*, not a
number. `textSize = "body"` and `gap = "m"` are legal wherever a number is, and
they resolve on every solve from the active theme. A literal number stays legal
too — and that is the point: writing `textSize = 15` explicitly opts that one
property out of theming.

**A view that names no size still gets your role.** Each text-bearing class has an
INTRINSIC role — `Text` and `Toggle` draw at `body`, `Button` and `TextField` at
`control` — and that role is resolved at the measure seam *and written at the paint
seam*, so moving `control` moves both the box the solver reserves and the size the
engine draws. Getting only half of that is a real bug and it shipped once: the
adapter drew a hardcoded 16 while the solver measured your `control` size, so a
package with a 13 px control role reserved 20 px for a one-word button label and
the engine then drew it 24 px wide — and it wrapped inside a box that was exactly
the right size for the size it was measured at.

## 9.3 Step 2 — edit tokens in the Style Editor

> **In plain words.** Once your theme is running, its values are sitting in a
> real Studio object you can open and edit while the game plays. Change a
> colour and it repaints instantly. Change a size and the screen re-lays-out
> instantly. When you are happy, one command writes your edits back into the
> Luau file — you never hand-edit the numbers in two places.

Once a package is installed (§9.7), its values live on a real `StyleSheet` in
the DataModel named **`FacetTheme <id>`** — for Parchment,
`FacetTheme fantasy-parchment` — with one child sheet per theme
(`Theme Daylight`, `Theme Candlelight`). That sheet is the authoring surface:
open Studio's Style Editor and edit it while the game runs.

**Seed once, then it is yours.** The committed Luau package seeds the sheet the
first time and then leaves your tokens alone. A framework upgrade only
*backfills* token names that did not exist before; it never overwrites a value
you set.

Three kinds of edit, three different behaviours — this table is the one to
remember:

| What you edit | What happens |
|---|---|
| A **colour token** on a theme sheet (`Surface`, `Accent`, `Control`, …) | **Immediate repaint**, entirely native — no Luau runs. Always survives regeneration and upgrades. |
| A **metric or font token attribute** on a theme sheet (`Space_m`, `Type_body_size`, `Type_body_font`, `ControlSizes_regular_height`, …) | **Re-solves live.** One `AttributeChanged` watcher per install re-resolves the snapshot and commits it, so the running screen re-lays-out with no remount and no Luau edit. Metric-derived paint (corner radii, stroke thickness) is pushed onto the live rules in the *same* commit, so paint and geometry never disagree. |
| A property on a **named rule** (`Raised panel`, `Control — hover`, `Chrome — panel`, …) | **Immediate**, and survives while the framework's rule model is unchanged. A framework upgrade changes the model stamp and **regenerates the rules** with a warning — put durable decisions in tokens, not rule literals. |

Attribute names are the metric path with dots turned into underscores and the
first segment capitalised: `space.m` → `Space_m`, `type.body.size` →
`Type_body_size`, `controls.slider.thumbSize` → `Controls_slider_thumbSize`.
`controller.inspect().tokens` lists every attribute the active package seeded.

An attribute the package does not know is **ignored, with exactly one warning**
naming the supported set — a typo in the Style Editor cannot silently become a
theme value.

> The old read-only "layout mirror" attributes described in
> [chapter 5 §5.7](05-styling.md) are **retired for packages**. When a package is
> installed the metric attributes *are* the source, not a mirror of one.

## 9.4 Step 3 — add nine-slice chrome

> **In plain words.** This is the step where the UI stops being coloured
> rectangles and starts being *artwork*. You give Facet a picture for a button,
> a picture for a panel, and it stretches them correctly at any size ("nine
> slice" just means: keep the corners crisp, stretch only the middle). The
> picture becomes the button — Facet turns off the plain rectangle it would
> otherwise have drawn underneath, so you do not get a border around your art.

A `StyleSheet` can repaint a `Frame`; it cannot turn a `Frame` into an
`ImageLabel`. So for image-backed skins Facet adds the smallest possible
substrate: **one non-interactive `ImageLabel` per skinned node**, named
`FacetChrome`, tagged `luau-chrome-<slot>`, painted entirely by the package's
own rules.

The **decoration slots** are a closed list. These nine are the ones this chapter
uses:

| Slot | The node it skins |
|---|---|
| `panel` | raised panels and modals (`surface = "raised"`) |
| `control` | buttons, chips, accent surfaces, Toggles |
| `field` | text fields (never `control` — an editable surface must read as editable) |
| `selection` | a selectable row (a node with a `selected` binding) |
| `divider` | the hairline |
| `scrollbar` | the scrolling host |
| `sliderTrack` | a Slider's rail |
| `sliderThumb` | a Slider's thumb |
| `badge` | the seal behind a badge's **count** (never an image badge — see below) |

Eight more ship for image value displays and are documented in
[chapter 10](10-rich-skinning.md): `barTrack`, `barFill`, `barCap`, `barCenter`,
`stepperPlate`, `toggleTrack`, `toggleKnob` and `spinner` (one dot of an
indeterminate ProgressView's ring). A package that declares none of them costs
exactly what it costs today.

`spinner` is the one slot that takes **no art**, and it is worth knowing why: the
dot's colour is not decoration, it is the loading animation. The control rewrites
each dot's tint every frame, that tint paints the dot's own plate, and any skin
hides that plate — so a dot image would be a spinner that never moves, which is
indistinguishable from a hung game. The compiler refuses it and names what does
retune a dot instead: `controls.progress.spinnerDotSize` for its size,
`radii.control` and `strokes.hairline` for its shape and edge, and `colors.accent`
for what the pulse travels through. The circular ring beside it is retuned the
same way, with `controls.progress.circularSize` and `circularThickness` — see the
API reference for the full table of what a stroked arc can and cannot be given.

Three of the nine above were added in the Step 3.5 director round. Two things
about them are worth knowing:

**A control can DECLARE its slot.** Nothing generic can look at a `Frame` and
work out that it is a slider rail — `surface = "control"` would have given it
the *button* skin, i.e. a button plate stretched into a groove. So `Slider`
declares `sliderTrack` and `sliderThumb` itself, on the blueprint's internal
metadata channel (the same one input contributions use — never a public prop).
Classification takes that declaration over everything else. If you write your
own control and want it skinnable, that is the seam.

**Some art does not stretch.** A thumb and a badge seal are fixed-size tokens,
not frames, and slicing them would smear their centre pixel across the middle.
Those slots therefore paint the image **whole** by default. Any recipe can say
so explicitly with `sliced = false` (or force slicing with `sliced = true`).

> **The badge slot costs nothing unless you use it.** A package with no `badge`
> recipe leaves badges exactly as they were — a flat circle with a number on it.
> Declare one and the number is lifted above your seal and centred on it.
> An **image** badge (an avatar headshot) is deliberately excluded: it is already
> art, and a decoration child draws *over* its parent, so a seal there would be a
> seal on top of the face.

**Authoring a badge.** The node a badge recipe skins is a `UI.Text` carrying
`surface = "badge"` — that is the whole public seam:

```lua
UI.Text({
    id = "Count", text = "3",
    surface = "badge",            -- <-- what the `badge` recipe skins
    textAlign = "center",         -- flat themes draw the label's OWN text
    textSize = 12,
    width = { type = "fixed", px = 28 },   -- match your seal's authored size
    height = { type = "fixed", px = 28 },
})
```

`surface` on a `UI.Text` accepts **`"badge"` and `"chip"` and nothing else** — a
label is not interactive, so the pressable surfaces (`control`, `accent`), the
panel surface (`raised`) and the backdrops (`base`, `scrim`) are refused at
construction; wrap the label in a `UI.Box` if you want one of those. See
[the API reference](../reference/api.md) for the full ruling.

Two sizing rules worth following, both learned from the fixture:

- **Size the node to the seal's authored size.** The recipe's `contentInsets` are
  subtracted from it to give the lifted count its box, so a 28px seal with a 5px
  inset leaves 18px — comfortable for a 12px digit. The same seal on a 24px node
  leaves 14px, which is *less* than the line box a 12px glyph needs, and the count
  clips.
- **Set `textAlign` yourself.** The lift centres a badge's value for you, but only
  when a package actually skins it. On a flat theme the label draws its own text
  with the alignment you gave it, and the default is start — which is how an
  unthemed "3" ends up against the left edge of its circle.

### Declare the art

> **In plain words.** Say where each picture lives and where its stretchable
> middle is. `sliceCenter` is the rectangle inside the image that is allowed to
> stretch; everything outside it — the corners and edges — stays pixel-exact at
> any size.

```lua
local ASSETS = {
    parchment_panel = {
        contentId = "rbxassetid://78012779616687",
        sliceCenter = { x0 = 40, y0 = 40, x1 = 104, y1 = 104 },
        sliceScale = 1,
        preload = "install",
        fallback = "native",
    },
    parchment_button = {
        contentId = "rbxassetid://87220434497053",
        sliceCenter = { x0 = 16, y0 = 16, x1 = 48, y1 = 48 },
        sliceScale = 1,
        preload = "install",
        fallback = "native",
    },
    parchment_field = {
        contentId = "rbxassetid://73053023436561",
        sliceCenter = { x0 = 16, y0 = 16, x1 = 48, y1 = 48 },
        sliceScale = 1,
        -- lazy: field skin loads when a screen with a field first mounts
        preload = "lazy",
        fallback = "native",
    },
}
```

**Slice geometry.** `sliceCenter` is in *image pixels*:
`Rect(border, border, size − border, size − border)`. Parchment's panel art is
144×144 with a 40 px border, so the centre is `(40, 40) → (104, 104)`; the
button and field art are 64×64 with 16 px borders. A missing `sliceCenter` on a
nine-slice asset is an error, not a default — a guessed slice centre looks
almost right at one size and wrong at every other.

**16 px borders are not arbitrary.** Two 16 px borders (32 px) must fit inside
the shortest control the theme draws — Parchment's `regular` height is 46 px —
or opposite slices overlap and the art shears.

The art itself, its generator, its seed, how to regenerate it, and how to upload
it and get your own content IDs are recorded in
[`assets/themes/fantasy-parchment/provenance.md`](../../assets/themes/fantasy-parchment/provenance.md);
the IDs this package uses are in
[`upload-manifest.json`](../../assets/themes/fantasy-parchment/upload-manifest.json)
beside it. Another project uploads the same PNGs under its own account and
substitutes its own IDs — there are no hidden assets.

### Declare the recipes

> **In plain words.** Now point each slot at a picture. A slot you leave as
> `native` keeps Facet's plain painted look and costs nothing at all.

A recipe has exactly four fields — `kind`, `asset`, `contentInsets`, `fallback`
— and nothing else is accepted:

```lua
chrome = {
    -- the ink rule sits ~14px inside the panel art's 40px border; 18px
    -- of content inset clears it at every panel size
    panel = {
        kind = "nineSlice",
        asset = "parchment_panel",
        contentInsets = { top = 18, right = 18, bottom = 18, left = 18 },
        fallback = "native",
    },
    control = {
        kind = "nineSlice",
        asset = "parchment_button",
        contentInsets = { top = 8, right = 12, bottom = 8, left = 12 },
        fallback = "native",
    },
    field = {
        kind = "nineSlice",
        asset = "parchment_field",
        contentInsets = { top = 8, right = 12, bottom = 8, left = 12 },
        fallback = "native",
    },
    -- ink-wash fills, no imagery: selection, dividers and scrollbars
    -- read best as flat paint on this material
    selection = { kind = "native" },
    divider = { kind = "native" },
    scrollbar = { kind = "native" },
},
```

`kind = "native"` costs **nothing**: no instance is created, and the slot is
painted by sheet rules. Gradients are native too — they render as phantom
`::UIGradient` modifiers with zero child instances — so a gradient-heavy theme
is still a zero-decoration theme. A gradient is *colour*, so it rides the
palette (`style.themes[].extra.chromeGradient.<slot>`), not the chrome recipe.
Its `alpha` ramp is engine `UIGradient.Transparency`, which fades the parent's
**entire** rendering — the control's own text included, not just its fill — so a
near-1 stop ghosts the whole control instead of softening the wash; `define`
rejects any stop above `0.9`, and a subtle ramp lives around `0.1–0.35`.

### States can be tints — or they can be more art

> **In plain words.** The cheap way is to draw one picture and let Facet
> brighten it on hover and darken it on press; that is what this section is
> about, and it is why the resting picture is drawn very slightly dimmed — there
> has to be somewhere brighter to go. If you want the *pressed* button to be a
> genuinely different picture, you can have that too: see
> [chapter 10 §10.2](10-rich-skinning.md), where `asset` takes a per-state map.
> The tint rules below still apply on top of whichever art a state resolved to.

The whole Parchment skin is **three images**. Interaction states modulate
`ImageColor3` over the one base image per slot:

- rest `0.90`, hover `1.0`, pressed `0.66` (the resting tint sits under white on
  purpose — `ImageColor3` can only multiply *down*, so a skin painted at full
  brightness would have no hover headroom);
- selected uses the palette's `$ChromeTintSelected`;
- disabled dims through the text and the tint together.

Those three numbers carry more weight than they look like they do. Once the
native plate is suppressed (below), the tint is the **only** interaction
feedback a skinned control has — there is no fill left to change — which is why
press is a full third darker than rest rather than a polite nudge.

### The image IS the button

> **In plain words.** If you give a button a picture, you do not want Facet's
> own rounded grey rectangle showing around the edges of it. It does not draw
> one.

For every slot you skin, the package emits three suppression rules against the
**decorated node** (the button itself, not the decoration child), keyed on a
`luau-skinned-<slot>` tag the adapter adds and removes with the decoration:

| Rule | What it turns off |
|---|---|
| `Skinned — <slot>` | the node's own fill (`BackgroundTransparency = 1`) |
| `Skinned — <slot> corner` | its `::UICorner` radius |
| `Skinned — <slot> outline` | its `::UIStroke` hairline |

They sit after every surface rule they have to beat and before the interaction
states — which only change *colour*, so an invisible plate stays invisible
through hover and press. A slot you leave `native` keeps every bit of its
Studio-Neutral chrome; a flat package emits none of these rules at all. On a
target with no `StyleSheet` support the adapter writes the same three
suppressions itself, so both paths look the same.

### Semantic roles tint the art

> **In plain words.** A "delete" button should look dangerous. When the button is
> a picture, that cannot mean painting a red rectangle behind the picture — it
> has to mean tinting the picture red.

Three role tints ride the same `ImageColor3` channel the interaction states do:

| Rule | Selector | Token |
|---|---|---|
| `Chrome role — destructive` | `.luau-role-destructive > .luau-chrome-control` | `$ChromeTintDanger` |
| `Chrome role — cancel` | `.luau-role-cancel > .luau-chrome-control` | `$ChromeTintCancel` |
| `Chrome role — accent` | `.luau-surface-accent > .luau-chrome-control` | `$ChromeTintAccent` |

Each token is derived per theme from that theme's own palette, and each is
lifted toward white before it multiplies — a raw danger colour multiplied into
mid-tone parchment lands almost black, and a warning nobody can read is not a
warning. `$ChromeTintDangerHover` / `$ChromeTintDangerPressed` keep the roled
states in the same family, and the role's *text* colours are unchanged (they are
the `Chrome text — destructive` / `— cancel` rules from the lift, above).

### A value control's chrome paints itself

> **In plain words.** A slider's knob and its rail are not buttons and not
> panels — they are parts *of* a control. They get their own plain colours from
> your theme, they are always solid, and a gloss or wash you put on your panels
> can never leak onto them.

The `sliderTrack` and `sliderThumb` slots are reached only through a control's
internal slot hint, never through a public `surface`, so nothing else paints them
and the sheet does. These rules are in **every** sheet Facet runs — every theme
package *and* the built-in default with no package installed at all:

| Rule | Selector | Paints |
|---|---|---|
| `Slot — sliderThumb` | `.luau-slot-sliderThumb` | `$SurfaceStrong`, **transparency 0** |
| `Slot — sliderTrack` | `.luau-slot-sliderTrack` | `$Control`, **transparency 0** |
| `Slot — <slot> corner` | `…::UICorner` | a circle for the thumb, your control radius for the rail |
| `Slot — <slot> outline` | `…::UIStroke` | `$Hairline` at your own stroke weight |

The colours come from the same map the asset-failure fallback uses, so "what a
flat slot looks like" is one decision rather than two that drift. The tag is
present whether or not you skin the slot — a slider has to be visible under
Studio Neutral too — and when you *do* skin it the `Skinned — <slot>` rules
above turn this plate off underneath the art, in that order.

Those `Skinned — <slot>` rules are emitted by **every** package, including one
that declares no recipe for the slot at all. That is deliberate: a *view* can
skin a value slot on its own (the per-view image override in
[chapter 10](10-rich-skinning.md)), and the plate has to come off then too. The
rule only ever matches a node that really is carrying art, so a flat slider is
byte-identical either way.

**A gradient may never target these**, and declaring one is a compile error
naming the reason. That restriction is the whole point of the section: the thumb
used to borrow `surface = "raised"` just to get a fill, which quietly subscribed
it to the entire panel treatment — and a panel gradient carrying alpha made the
thumb translucent, so the accent fill behind it read straight through. A wash
belongs on the surfaces an author opted into.

### Focus: a ring, or a glow

> **In plain words.** The highlight that shows which control the player is on. By
> default it is a thin outline in your accent colour. On a painted skin a hard
> outline can look like a UI element that wandered in from another game, so you
> can ask for a soft glow instead — and either way it now takes *your* colours.

`chrome.focus` is a reserved key in the chrome table — focus is not a decoration
slot, because it applies to whichever node currently has focus rather than to a
kind of surface:

```lua
chrome = {
    -- the default; every package that says nothing gets exactly this
    focus = { kind = "ring" },

    -- ...or a soft halo
    focus = {
        kind = "glow",
        color = "$FocusGlow",              -- a per-THEME token, or { r, g, b }
        blurRadius = { scale = 0, offset = 26 },
        transparency = 0.25,
        zIndex = -1,                        -- MUST be negative
    },
}
```

`"$Name"` resolves per theme against that theme's `colors` and then its `extra`,
so one recipe tints itself differently in each theme — the same place and the
same reason `chromeGradient` lives in `extra`. `themes.define` checks the token
resolves in **every** theme, because a glow whose token is missing paints nothing
and that is invisible until someone looks at a device. `"$Accent"` is the easy
answer when your accent is already the right colour.

**A glow is a `UIShadow` at a high blur with no offset.** Roblox has no glow
element, but that measures as one. Art would have meant an asset per theme, a
colour baked into each one, and a stretched radial gradient whose falloff *bands*
at sizes you never tried; a shadow is resolution-free, any colour, any control
size, and no assets at all. Shaped selection *art* remains the `selection` slot's
job.

**The ten-foot profile is derived, not authored.** The design's §8.4 requires to be unmistakable across a room. The ring answers that by
thickening; the glow answers it with more blur and less transparency, scaled from
your near values (`chrome_slots.FOCUS_TEN_FOOT`), so you tune the look once and
both distances follow.

**Two things happen even if you never touch this.** The ring's colour now comes
from the *active theme's* accent instead of a constant captured when the target
was built — it was blue under every package before, which is the defect this
section grew out of. And a package asking for a glow on an engine without
`UIShadow` falls back to the ring rather than to nothing, because focus is never
optional.

### Shadows

> **In plain words.** Depth. A card that sits *on* the surface instead of being
> printed into it. You ask for it per slot, and a theme that wants a flat look
> just does not.

Any recipe — nine-slice or native — may add a `shadow`:

```lua
panel   = { kind = "nineSlice", asset = "parchment_panel", …, shadow = "raised" },
control = { kind = "native", shadow = "raised" },
-- or explicit parameters, for a themed glow rather than a drop shadow:
panel = { kind = "native", shadow = {
    blurRadius = { scale = 0, offset = 18 },
    color = { r = 0.05, g = 0.42, b = 0.5 },
    transparency = 0.45,
    zIndex = -1,                        -- MUST be negative: a shadow is below
} },
```

`"raised"` and `"overlay"` are the two library presets. The spec is validated
when the package compiles, against the same contract the adapter materializes —
a positive `zIndex` is a compile error, not a runtime surprise on a device.

**Why this one is adapter-owned and not a rule.** `::UIShadow` rules are
silently accepted by the engine and paint *nothing* (feasibility m7); the
package compiler rejects the selector for exactly that reason. So the shadow is
deliberately materialized by the adapter, on the node the sheet does *not*
shadow, behind the same capability probe `UI.shadow` uses. There is no rule to
defeat and no dual authority. Shadows are counted by `chromeCensus()`
(`shadows`, `shadowsPerSlot`, `actualShadows`), so "a flat package pays zero" is
a measurement.

The decoration child is `Active = false` and can never report an interaction
state of its own, so every state rule reads the **parent's** state and reaches
the child through a child combinator
(`.luau-interactive:Hover > .luau-chrome-control`). All four such selectors are
engine-verified (`artifacts/theme-packages-and-skinning/feasibility/m8-render-order-combinators.json`).

### Two consequences you must design around

> **In plain words.** Two things change once art is involved, and both will
> confuse you if nobody warns you: a skinned button's text is drawn by a
> separate little label on top of the picture (so the rules that colour it are
> different ones), and a text field gets out of the way of its own art while
> you are typing in it.

**1. The chrome text lift.** Facet roots use `ZIndexBehavior = Sibling`, and
under Sibling a full-bleed child covers its parent's own engine-drawn text *at
any ZIndex* — including negative ones. So a text-bearing node with an active
decoration gets one managed `TextLabel` named `FacetChromeText`, tagged
`luau-chrome-text`, sitting above the decoration and mirroring the parent's
text. The parent keeps its `Text` for semantics and measurement; the lifted
label is what you see.

What this means for you: **a skinned button's label is painted by the chrome-text
rules**, not by the button's own text rules. The generated set covers the font
(`Chrome text — button font`, `— field font`) and the role variants
(`— accent`, `— destructive`, `— cancel`, `— secondary`, `— disabled button`,
`— disabled field`). If you want a different label colour on a skinned control,
that is where it goes. These rules are emitted **only** when a text-bearing slot
is actually skinned — a flat theme carries none of them.

The lifted label is **inset by the recipe's own `contentInsets`**, not
full-bleed. That is what keeps a value off the painted border: the solver had
already reserved that room for the parent's content, and before the Step 3.5
director round the lift ignored it, so every number under a skin sat on the art.
`TextLabel`s are lifted too — a badge is a `TextLabel`, and its count is exactly
the value the director could not read.

**2. A TextBox yields its chrome while editing.** The engine draws the caret at
the parent layer and that is non-negotiable, so while a field is being edited
the adapter adds `luau-chrome-editing`, the decoration flattens to the native
fill, and the lifted label hides. Design the field's *native* fallback paint to
be a usable editing surface, because that is what the player types into.

## 9.5 Step 4 — insets and fallbacks

> **In plain words.** Two safety nets. The first keeps your text off the painted
> border — you tell Facet how thick the border is and the layout engine leaves
> room for it. The second is what happens when a picture fails to load: the
> theme falls back to plain paint instead of showing nothing.

### Insets: two numbers that add

> **In plain words.** "How far in from the edge should the content start?" You
> give two numbers — one for the slot's own breathing room, one for the
> thickness of the painted border — and Facet adds them together.

Content must clear painted borders, and the **solver** has to know about it or
text will sit on the art. Two values compose:

```lua
-- the slot's own padding; each recipe's contentInsets are ADDED by
-- the snapshot so content always clears the painted border
insets = {
    panel = { top = 8, right = 8, bottom = 8, left = 8 },
    control = { top = 4, right = 8, bottom = 4, left = 8 },
    field = { top = 4, right = 8, bottom = 4, left = 8 },
    selection = { top = 4, right = 6, bottom = 4, left = 6 },
    divider = { top = 0, right = 0, bottom = 0, left = 0 },
    scrollbar = { top = 0, right = 0, bottom = 0, left = 0 },
},
```

`metrics.insets[slot]` is the padding the *slot* wants. The recipe's
`contentInsets` is the extra room the *art* needs. `themes.resolve` adds them:
the resolved snapshot exposes the sum at `snapshot.insets[slot]` and the
chrome-only portion separately at `snapshot.chromeInsets[slot]`, which is what
the renderer actually adds to a skinned node's padding. A flat package —
including Studio Neutral — has an empty `chromeInsets`, so existing geometry is
byte-identical.

### Fallbacks: what happens when the art does not arrive

> **In plain words.** Assets fail. A player on a bad connection, a moderated
> upload, a typo in a content ID. When that happens the skin quietly turns back
> into the plain painted look, in place, with nothing moving.

Every nine-slice recipe **must** declare `fallback = "native"`; compilation
rejects one that does not. A bad content ID still "styles" — the style system
has no idea an image failed — so failure detection rides the resource provider,
and the recovery is tag-driven:

1. the provider reports the asset failed (or the target's own grace deadline
   infers it from silence, which it may only do for art the engine was actually
   asked to decode — see
   [`docs/lessons/engine-never-decodes-invisible-images.md`](../lessons/engine-never-decodes-invisible-images.md));
2. the adapter adds `luau-chrome-fallback` to that slot's art, and
   `luau-chrome-mute` to every art instance of it EXCEPT the condemned asset's own
   undecoded picture;
3. the package's generated `Chrome — <slot> fallback` rule paints the slot's flat
   fill, corner radius and hairline, and `Chrome — <slot> fallback hide` turns the
   muted art fully transparent.

The condemned art is spared the hide on purpose: `ImageTransparency = 1` is the
engine's own "do not decode" signal, so hiding the picture that failed would
silence the one `IsLoaded` that could ever report it arriving late. It draws
nothing while it really is broken, and the moment it decodes the slot leaves
fallback by itself.

Hit geometry, focus and state are untouched — nothing is rebuilt, only
repainted. Recovery removes the tags exactly once. `preload = "install"` resolves
the asset when the package is installed; `preload = "lazy"` resolves it the
first time a screen claims that slot.

## 9.6 Step 5 — preview every control on every device profile

> **In plain words.** Never judge a theme from one screen. The repository ships
> a Studio place that puts every control Facet has on screen at once and lets
> you restyle the lot from the outside — that is the thing to look at.

Do not eyeball one screen. The repository ships a Studio fixture that mounts the
**whole** control gallery and restyles it from the outside:
[`examples/gallery/scenarios/theme_authoring.luau`](../../examples/gallery/scenarios/theme_authoring.luau).

**Swapping themes by hand.** The gallery place ships a small theme picker in the
top-right corner: Studio Neutral plus every package under
`ReplicatedStorage.FacetThemes`, with that package's themes underneath. Click a
row and the running screen re-themes — the same `install` / `swapPackage` /
`swap` calls §9.8 and §9.9 describe, driven by a UI instead of by an attribute
you had to set before pressing Play. It is a *passive* surface, so it never
steals focus from the fixture underneath it, and it re-themes itself along with
everything else — if the picker still reads after a swap, the swap worked. Set
the workspace attribute `Facet_ThemePicker = false` to hide it, and
`Facet_NativeStyle = true` to see the *full* swap: on a target painting through
the explicit-write path a swap moves metrics live but not the palette (§9.8), and
the picker warns once when it finds itself there. The source is
[`examples/gallery/client/theme_picker.luau`](../../examples/gallery/client/theme_picker.luau);
it is an example, not library code, and it goes through the public surface only,
so a game that wants one can copy the file.

Set the workspace attribute `Facet_Scenario = "theme_authoring"` before Play
(optionally `Facet_ThemePackage` and `Facet_ThemeName` to choose what it opens
under), then drive it through `workspace.FacetScenarioAPI.step`:

| Step | What it proves |
|---|---|
| `installPackage` | installs the ornate package on the mounted screen |
| `installFlat` | installs a flat package (zero decoration instances) |
| `swapTheme` | palette-only swap — returns before/after identity so you can see geometry did **not** move |
| `swapPackage` | a different package: metrics, fonts and chrome all change |
| `editMetricLive` / `restoreMetric` | sets `Space_m` on the live theme sheet — the same object the Style Editor writes — and re-solves |
| `exportDump` | the typed token dump `theme_sync` consumes |
| `failMissingAsset` / `recoverMissingAsset` | the fallback tag flips, and unflips, exactly once |
| `failMissingFont` | an unknown family measures conservatively: boxes grow, nothing clips |
| `failIncompatible` | a package this build cannot speak is refused; the screen stays mounted and usable |
| `customControl` | a namespaced control's needs, checked both ways |
| `inspect` | package identity, chrome recipes, preload lists, census, controller state |

Run it across the canonical five view rows from
[`../plans/studio-device-verification.md`](../plans/studio-device-verification.md):
`compact-phone-portrait`, `compact-phone-landscape`, `tablet-landscape`,
`desktop-standard`, `console-ten-foot`. Locale/long text, preferred text and
reduced motion are *fixture axes* — run them on the smallest subset that covers
their failure mode, not as a full product with every view.

The scenario's `report()` pairs geometry, snapshot identity, decoration census,
focus path, mount identity and the style-authority probe in one object, so a
capture is never the only evidence.

## 9.7 Step 6 — validate, export, and keep Luau and Studio in sync

> **In plain words.** The Studio edits you just made live in the game file, not
> in your source code. One command copies them back into the Luau package, and
> another command *checks* that the two agree and fails the build when they have
> drifted apart. That is the whole reason you can safely author in Studio.

Three surfaces, one direction of truth: **the sheet is authored, the Luau is
generated.**

1. **Validate** — `themes.define` already did it. Treat a non-empty
   `report.errors` as a build failure, and print `err.field`, `err.message` and
   `err.fix`.
2. **Dump** — `controller.dumpTokens()` returns the active theme sheet's tokens
   as typed records in deterministic order (numbers and fonts in v1; colours stay
   native sheet tokens). The scenario's `exportDump` step exposes it. Save that
   table as JSON.
3. **Sync** — write the dump back into the committed package:

```sh
# write the sheet's values into the committed package
lune run tools/lune/theme_sync_cli -- --dump <dump.json> --package examples/themes/my_theme.luau

# freshness gate: fails when the sheet and the committed package disagree
lune run tools/lune/theme_sync_cli -- --dump <dump.json> --package examples/themes/my_theme.luau --check
```

`--check` prints every drifted path with both values and the exact command that
fixes it, then exits 1. A package file that carries the `theme_sync` markers
keeps everything around them hand-authored — style, chrome and assets stay
yours — and has only the metrics region regenerated. There is never a second
hand-edited metric source.

**Your package has to be shaped for this**, and the worked example shows the
shape. In `examples/themes/fantasy_parchment.luau` the whole `metrics` section
lives in a marker region:

```lua
local GENERATED: any = {
-- theme_sync:begin metrics
	metrics = {
		space = { xs = 4, s = 8, m = 16, l = 26, xl = 42 },
		-- … every metric the package resolves, generator-written …
	},
-- theme_sync:end metrics
}
```

and `definition()` consumes it with `metrics = GENERATED.metrics`. The region is
a plain table field, so `--check` can load it on its own without evaluating the
rest of the file (which requires nothing, but a real package might). Anything
outside the markers — palette, chrome recipes, assets — is yours and is never
rewritten. The repository runs exactly this command against that file as a gate:

```sh
lune run tools/lune/theme_sync_cli -- \
  --dump artifacts/theme-packages-and-skinning/theme-sync/parchment-live-dump.json \
  --package examples/themes/fantasy_parchment.luau --check
```

Hand-edit one number inside the region and it exits 1 naming that token; put it
back and it exits 0. If your metrics are not in a marker region, the CLI treats
the whole file as generator-owned and rewrites it — which is the right behaviour
for a metrics-only module and the wrong one for a package that also carries
hand-authored art.

## 9.8 Step 7 — install at an application root

> **In plain words.** How you actually turn the theme on. One call, at the point
> where your UI is set up. It attaches the theme to one screen target — so two
> different windows can run two different themes without interfering.

The controller is **client-only** and **per-target**. Require it directly:

```lua
local theme_controller = require(ReplicatedStorage.Facet.client.theme_controller)

local controller = theme_controller.install(adapter, package, {
    env = env,                 -- REQUIRED: the metric snapshot rides it
    rootGui = rootHandle.gui,  -- the target's root ScreenGui
    theme = "Daylight",        -- optional; defaults to style.defaultTheme
})
```

- **`env` is mandatory.** The resolved snapshot is committed as the environment
  fact `themeMetrics` — one key, one signal, one downstream invalidation. That is
  what makes a swap a single atomic commit.
- **`rootGui` names the tree you are theming.** Per-target isolation is one sheet
  plus one `StyleLink` at that root: two independently hosted roots can hold
  different packages at once, and swapping one leaves the other byte-stable.
  `screen_target` exposes `adapter.themeRootGui()` (its base root), so `rootGui`
  is optional on that adapter; pass it explicitly when hosting your own roots.
  Roots the target creates *later* — modal and popup surfaces — inherit whatever
  sheet the base root links at that moment, so a themed screen never presents an
  untheme­d popup.
- **Installation is all-or-nothing.** Every capability check runs *before* the
  first mutation. A schema this build does not speak, an unknown or unprovided
  capability, or a missing root fails with an error naming exactly what is
  missing — and the target and the environment are left untouched. The
  capability vocabulary is closed: `themeMetrics` (always available),
  `nativeStyleSheets`, `styleTransitions`.

**On a target without native StyleSheets** the install still succeeds and you
get the whole *metric* half — every layout-affecting value swaps live, because
that is where those values live. The palette does not: today's `ScreenTarget`
takes its bespoke style at construction and exposes no runtime setter, so pass
`controller.inspect().style` to `screen_target.new({ style = … })` when you build
the target. `controller.inspect().fallback` and `.fallbackReason` report the
degradation honestly. Every shipping native path gets the full transaction.

`controller.inspect()` is the answer to "what is actually installed?" — package
identity and stamp, active theme, mode and fallback state, sheet name/seeded/
migrated/stamp, link state, the effective snapshot, the token attribute list,
per-font calibration state, live connection count and swap count.

## 9.9 Step 8 — swap live

> **In plain words.** Changing theme at runtime is one call, and nothing is torn
> down: the player keeps their focus, their scroll position, and whatever they
> were half-way through typing. Colours and sizes both change in the same frame.

```lua
controller.swap("Candlelight")          -- another theme of the same package
controller.swapPackage(otherPackage)    -- a different package entirely
controller.onChange(function(event) … end)
controller.uninstall()                  -- restores the pre-install link and snapshot
```

A swap is **one transaction in one invocation**: the snapshot is resolved first
(so a bad theme name or a bad override throws before anything is committed),
then `SetDerives` for paint and `env:set("themeMetrics", …)` for geometry happen
with no yield between them, and the surface re-solves immediately. New paint and
new geometry land in the **same engine frame**.

What survives, because nothing is rebuilt: mount identity, focus, selection,
scroll position, in-progress text entry, and resource ownership. A palette-only
swap does not churn a single decoration instance — the adapter compares the
chrome signature first and only re-sweeps when the recipes actually differ.

Paint may ride opt-in native transitions (`transitions = true` at install).
Geometry never animates independently of the solver.

## 9.10 Step 9 — upgrades

> **In plain words.** What happens to your theme when Facet itself moves
> forward. Short version: values you set are kept, things you never knew about
> are filled in for you, and anything genuinely incompatible is reported before
> the game runs rather than discovered on a device.

Three mechanisms, and you should know which one is protecting you:

- **Schema.** `identity.schemaVersion` (and `compatibility.requiresSchema`) are
  compared against `themes.SCHEMA` — currently `facet-theme/1` — before install
  or `swapPackage` touches anything. A mismatch is an error telling you to
  republish against this schema, and the installed package is unchanged.
- **Sheet stamp migration.** The sheet carries the model stamp it was seeded
  with. On a framework upgrade the generated *rules* regenerate (with a warning),
  while your **tokens are never overwritten** — an upgrade only backfills token
  names that did not exist before. `inspect().sheet.seeded` and
  `.sheet.migrated` tell you which happened.
- **Derivation.** Because your package names `base = themes.neutralPackage()`,
  a core role added by a future Facet version is inherited automatically. This
  is the single strongest reason not to hand-copy a package.

After any upgrade that touched metrics, re-run the freshness gate (§9.7) — it is
the check that catches a sheet and a committed package drifting apart.

## 9.11 Step 10 — profile what the ornate skin costs

> **In plain words.** Pretty is not free. Every picture-backed slot creates one
> extra object per node that uses it. This step is how you count them, so you
> find out here rather than on somebody's phone.

```lua
local census = adapter.chromeCensus()
```

You get `created` / `destroyed` / `live`, a `perSlot` breakdown,
`actualInstances` (an independent count of what is really in the tree, so the
ledger can be checked rather than trusted), `textLifts` (lifted labels are
decoration cost too), plus `fallbackSlots` and `failedAssets`. The scenario's
`inspect` step returns the same census.

The number that matters: **a flat theme creates zero decoration instances.**
Not "few" — zero. Native fills, corners, strokes and gradients are sheet paint
and phantom modifiers; materializing a child for them would actually *defeat*
the rules. So a game shipping a flat theme pays nothing for the ornate substrate
existing, and the ornate cost is exactly the count this census reports.

Record swap timing, instance counts and memory as **Studio-derated** numbers.
Low-end-device performance is not claimed by this stage.

## 9.11a The customization ladder

> **In plain words.** Three rungs, and you climb only as far as you need. Let the
> theme decide; or override one view; or, when the look is genuinely its own
> thing, write a control. Each rung is a normal amount of work — you should
> never feel you have to fight the framework to change one slider.

This is SwiftUI's shape, and Facet copies it deliberately.

| Rung | What you do | When |
|---|---|---|
| **1 — the theme owns it** | semantic roles plus the package recipes in this chapter | almost always: one change restyles the whole game |
| **2 — the view overrides it** | a per-view prop that beats the theme for *that node only* | one control genuinely differs |
| **3 — a custom control** | a new control with its own art and its own namespaced theme roles | the look is not a variation of anything |

**All three rungs are walked end to end in
[chapter 10, Rich skinning](10-rich-skinning.md)** — with layers, per-state art,
image bars, semantic icons, pixel mode and `selectBy` at rung 1, and a worked
custom control at rung 3. This section is the short version.

**Rung 2, concretely.** `Slider` takes `thumbImage` and `trackImage`:

```lua
local slider = Facet.newSlider(Facet, core, {
    id = "Power", label = "Power", value = power, min = 0, max = 100,
    thumbImage = "rbxassetid://102024273231445",   -- THIS slider only
})
```

Set one and that node's decoration is painted from your value instead of from
the theme's `sliderThumb` recipe — and it works whether or not a theme package
is installed at all, because the rung does not depend on one. The mechanism is
worth knowing, because it is the same one every per-view override uses: the
decoration is deliberately **not tagged** with its slot, so the package's
`Image` rule can never reach it, and the adapter writes the image properties
directly. A tagged instance would keep taking the theme's value and yours would
lose on the next swap.

That is the **standing opt-out rule** made concrete: an explicit local value opts
that property out of theme changes, visibly and on purpose — exactly as an
explicit pixel size opts out of the theme's space steps. Everything else about
the control (its sizes, its palette, the rest of the screen) stays on the theme.
`dump().skinRung` reports `"theme"` or `"view"` so a live probe can see which is
in force. A bare content URI carries no nine-slice geometry, so an overridden
image is painted whole.

**Rung 3** is [`../extending/skinned-control.md`](../extending/skinned-control.md)
(the theme-contribution and art half) plus
[`../extending/new-control.md`](../extending/new-control.md) (the control
contract) and §9.12 below: register namespaced roles, declare what your control
needs, and `themes.checkCoverage` tells you before play whether a theme covers
them.

## 9.12 Shipping a custom control with your theme

> **In plain words.** If you wrote your own control, it may need theme values
> nobody else does. Declare what it needs and Facet will tell you — before the
> game runs — whether a given theme actually covers them.

If you ship a control of your own, it can declare namespaced roles (`ns:role`)
and ask a package whether it is covered — *before* play, not on a device:

```lua
local result = Facet.themes.checkCoverage(package, myControl.needs)
-- result.ok, result.covered, result.missing = { { name, message, fix } }
```

The worked example is
[`examples/themes/ornate_gauge.luau`](../../examples/themes/ornate_gauge.luau) —
a control that ships its own art and contributes one need of each kind
(`controlSize`, `color`, `number`) — walked step by step in
[`../extending/skinned-control.md`](../extending/skinned-control.md). The smaller
Step 3.5 fixture [`custom_control.luau`](../../examples/themes/custom_control.luau)
is still there and still drives the `customControl` scenario step. The
contributor-side rules — declaration fields, fallbacks, authority, capabilities —
are in [`../extending/new-theme.md`](../extending/new-theme.md) §2.

---

## The other reference packages

> **In plain words.** Four more complete themes ship in the repository. They are
> the ones to read when you want to see a different taste solved end to end.

Four more packages ship as the compatibility corpus, each covering a different
theme class:

| Package | Class it proves |
|---|---|
| [`classic_desktop.luau`](../../examples/themes/classic_desktop.luau) | compact, square-edged, flat — metric-changing, zero decoration instances |
| [`glossy_mobile.luau`](../../examples/themes/glossy_mobile.luau) | different typography and control sizes, gradient chrome |
| [`scifi_hud.luau`](../../examples/themes/scifi_hud.luau) | gradients and strokes only — an ornate *look* that still creates zero decoration instances |
| [`fantasy_parchment.luau`](../../examples/themes/fantasy_parchment.luau) | asset-backed nine-slice, the full worked example |

Four more ship for the rich-skinning surface and are read alongside
[chapter 10](10-rich-skinning.md):

| Package | Class it proves |
|---|---|
| [`fantasy_ornate.luau`](../../examples/themes/fantasy_ornate.luau) | layered slots, per-state art, image bars, toggle art, semantic icons |
| [`pixel_quest.luau`](../../examples/themes/pixel_quest.luau) | `rendering = "pixel"`, and selection that changes the whole style |
| [`glossy_touch.luau`](../../examples/themes/glossy_touch.luau) | a touch-metric package with a tiled stripe layer |
| [`compact_pointer.luau`](../../examples/themes/compact_pointer.luau) | its pointer-metric twin — the pair `selectBy` swaps between |

They are capability references, not replicas of any operating system or game.

Next: [chapter 10, Rich skinning](10-rich-skinning.md), when you want the art to
BE the interface — or the contributor-side playbook,
[`../extending/new-theme.md`](../extending/new-theme.md), when you are changing
the theme system itself. The architecture decisions and the engine truths behind
them are in
[`../adr/ADR-0019-theme-packages.md`](../adr/ADR-0019-theme-packages.md) and
[`../adr/ADR-0020-rich-skinning-v2.md`](../adr/ADR-0020-rich-skinning-v2.md).
