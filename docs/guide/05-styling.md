# 5. Styling

This chapter covers how a screen gets its look: design tokens, the built-in
default appearance, surfaces and roles, drop shadows, rounded corners, and the
principle that styling is *data* until the very last moment.

> **How this chapter is arranged.** §5.1–5.6 describe the token and adapter
> styling every screen gets by default. Two layers sit on top of it. §5.7 moves
> runtime paint, native interaction states, Dark and Light themes and optional
> transitions to Roblox StyleSheets. §5.8 adds versioned theme packages, which
> own typography, metrics, insets and nine-slice chrome as well. The full
> walkthrough for building one is [chapter 9](09-custom-themes.md).

## 5.1 Tokens

A **token** is a named design value used instead of a raw number: a color, a
spacing step, a text size, a corner radius. `Facet.tokens` holds the token
tooling.

`tokens.compile(schema)` takes a game's design values and returns *(compiled,
report)*. Compilation does two useful things before it hands anything back:

- **Completeness check.** The schema must define every required value — the color
  pairs (`surface`/`content`, `surfaceStrong`/`contentStrong`, `accent`/`onAccent`),
  the spacing steps (`xs`, `s`, `m`, `l`, `xl`), the text roles (`body`, `label`,
  `heading`, `title`), a minimum touch-target size, and motion durations. Anything
  missing is listed in `report.missing`. (`strong` and `numeral` are optional and
  derived when absent — see *Typography* below.)
- **Contrast check.** Each surface/content color pair is checked for a text
  contrast ratio of at least 4.5:1 (the common readability threshold).
  `report.contrast` lists each pair's ratio and whether it passed.

If the schema is incomplete or any contrast pair fails, `compile` returns `nil`
for the compiled value and an explanatory report — a game's style is not allowed
to ship unreadable text. On success you get a **frozen** (immutable) token set.

```lua
local compiled, report = Facet.tokens.compile(mySchema)
assert(compiled ~= nil, "style failed its own contrast/completeness check")
```

### Typography: eight roles, and weight is one of them

`textSize` takes a px number **or a typography role name**. Six roles name a rung
on the reading ladder — `caption`, `label`, `body`, `heading`, `title`,
`control` — and two name a **weight**:

| Role | What it means | Studio Neutral |
|---|---|---|
| `strong` | emphasis at reading size: a name in a list, a label that has to win | `body`'s size, the family's SemiBold face |
| `numeral` | a figure read as a rank or a score, not as prose | `control`'s size, the family's Bold face |

```lua
UI.Text({ id = "Name", text = racer.name, textSize = "strong" })
UI.Text({ id = "Pos",  text = tostring(racer.place), textSize = "numeral" })
```

**There is no `weight` prop, and that is deliberate.** A typography role carries
its **font descriptor and line height** as well as its size, and the whole entry
travels to the layout solver *and* to the adapter that paints the glyphs. A prop
that set only the painted face would reserve a box for one family and draw
another — which is exactly what happened to the deprecated `UI.Text.font`, and
why it was removed rather than kept working. Weight is a style decision, styles
are theme-owned, and a role is the theme-owned channel.

`strong` and `numeral` are **optional** in a token schema and in a theme package.
Leave them out and they are derived from the ramp you did write (`strong` from
`body`, `numeral` from `control`-or-`heading`, changing only the weight), so
every theme answers all eight names and a display-face theme gets *its* face in
both weights. Author either one to override it — see
`docs/extending/new-theme.md` §2.

## 5.2 The Studio Neutral default

You do not have to write a token schema to get a good-looking interface. Facet
ships one, **Studio Neutral** (`src/tokens/default_style.luau`), and the client
render target uses it automatically when you do not pass your own. Its brief was
"a game UI system that is minimal but polished, with affordances always clear,
professional and neutral, and quick to render." Concretely:

- one cool near-black surface ramp with a single restrained blue accent;
- hairline strokes instead of heavy borders; generous corner radii;
- every interactive state states itself *without relying on color alone*:
  interactive surfaces are visibly raised, a pointer hovering a control gets a
  lightened **hover** fill (the `controlHover` role — wired only when a mouse
  is actually live, so a touch device never pays for it), focus is an accent
  ring, a press is a quick dip, and disabled is dimmed content — so the
  interface remains legible to players who cannot distinguish certain colors;
- on a **television-class display** (the environment reports a `Large`
  display, e.g. a console docked to a TV) the style automatically strengthens
  itself for viewing at a distance: the focus ring thickens
  (`tenFootFocusRingThickness`), the focused control scales up slightly
  (`tenFootFocusScale`), and content insets by TV-overscan-safe margins. The
  authored ten-foot text scale and the player's native preference compose without
  double application: the ten-foot factor rides both seams (measure and paint),
  while the preference is an ADDITIVE px offset the engine paints itself and the
  solver reserves exactly once (see the next bullet);
- the **player's preferred text size** (Roblox settings › Text size:
  `Medium`/`Large`/`Larger`/`Largest`) is a first-class layout input. The engine
  paints every text node at `TextSize + offset`, where the offset is a measured
  per-preference constant (0 / 4 / 10 / 14 px — uniform across font, weight, and
  size). Facet's adapter feeds that offset into the environment
  (`preferredTextOffset`), the solver reserves the exact painted box, and a
  mid-session change re-solves every mounted surface in place — mount identity,
  focus, scroll, and control state all survive. Screens declare content and
  layout candidates and never read the preference themselves: reflow comes from
  the same wrap/`lineLimit`/`ViewThatFits`/composition mechanisms as any other
  geometry change, in the plan's order — reflow first, scroll the containing
  region second, and truncation only for bounded secondary/identity text that
  keeps its full value reachable;
- cheap to render by default: flat fills, one stroke, no gradients, and shadows
  used only in the two depth presets described below.

To use your own look instead, compile a schema and pass it when creating the
render target: `screen_target.new({ style = compiled })`.

**If you stood your surface up with `client.host.new()`** — which is what
[chapter 3](03-getting-started.md#34-wiring-inside-roblox-studio) teaches, and
what builds the render target for you — pass the same value there instead:
`host.new({ style = compiled })`. The host forwards `style` verbatim to
`screen_target.new`, along with `nativeStyle`, `parent`, `autoLocalize`,
`themePackage` and `displayOrder`, so there is one place to say it either way
([api.md §Client entry points](../reference/api.md#client-entry-points)).

## 5.3 Surfaces and roles

Containers and controls opt into a visual treatment through two style props read
by the render target:

- **`surface`** — the background treatment of a container or row (for example a
  raised panel, an interactive control fill, or a modal scrim/backdrop).
- **`role`** — the treatment of text (for example a title versus body versus a
  secondary caption).

These are *hints*, not raw colors: they name the semantic role and the active
style resolves them to actual colors. That is what lets one blueprint look
correct under both the default style and a game's override — the blueprint says
"this is a title," and the style decides what a title looks like.

## 5.4 Shadows and per-corner rounding

Two visual modifiers let you add depth and shape. Each is a function that takes a
blueprint and returns a **new** blueprint (blueprints are immutable, so a modifier
never edits in place):

### `UI.shadow(blueprint, presetOrParams, style?)`

Adds a drop shadow. The second argument is either the **name of a preset** defined
in the active style, or an explicit parameter table. Studio Neutral ships two
presets:

- `"raised"` — a tight, subtle drop for raised interactive surfaces;
- `"overlay"` — a softer, wider halo for modals and overlay panels.

```lua
local card = UI.shadow(UI.Box({ id = "Card", surface = "raised" }), "raised")
```

The shadow parameters follow the real engine's shape: the blur radius is a
scale-plus-offset value, offset and spread are two-dimensional, and — enforced at
build time — a shadow's depth index must be negative, because a shadow renders
*below* its parent. These constraints are validated when you call `UI.shadow`, so
an invalid shadow is a clear error at authoring time rather than a silent visual
bug.

### `UI.corners(blueprint, radiusOrSpec, style?)`

Rounds corners. The second argument may be:

- a **number** of pixels (uniform on all four corners),
- the **name of a radius token** (for example the style's `control` or `panel`
  radius), or
- a **per-corner table** setting `topLeft`, `topRight`, `bottomLeft`,
  `bottomRight` individually.

**The one-form-per-node rule:** a single node must use *exactly one* of these
forms. You may not mix a uniform radius with individual corner keys on the same
node. This is not a stylistic preference — mixing the uniform alias with
per-corner values misbehaves in the engine, so `UI.corners` rejects the mix as a
build error.

### `UI.styleGroup({ shadow?, corners? }, blueprints, style?)`

Applies the same shadow and/or corner modifiers to *every* blueprint in a list at
once. It returns a new list of styled blueprints.

```lua
local styled = UI.styleGroup({ corners = "control" }, {
    UI.Button({ id = "A", label = "A" }),
    UI.Button({ id = "B", label = "B" }),
})
```

## 5.5 The style lint

Two engine-guidance limits are checked by a **style lint**
(`src/render/style_lint.luau`) that walks a mounted tree and reports warnings —
never hard errors, since these are quality and performance signals:

- **Jagged-corner caveat.** The engine's own release notes warn that a drop shadow
  can render jagged against a *large* corner radius. The lint flags any shadowed
  node whose corner radius exceeds 24 pixels. If you see this warning, either
  shrink the radius or drop the shadow on that node.
- **Shadow budget.** The engine guidance is roughly 100 on-screen shadows before
  performance suffers. The lint flags a tree with more than 100 shadowed nodes.

These thresholds are constants in the lint module; they are diagnostics you run
against a tree, not part of the public `Facet` table.

## 5.6 Why styling is data, then instances

Notice that everything above produces **data**. `UI.shadow` and `UI.corners`
store a normalized, validated table on the blueprint; `surface` and `role` are
string hints; tokens are plain frozen tables. None of it creates a Roblox object.
This has a concrete payoff:

- **Headless styling is fully testable.** Because a styled blueprint is just data,
  a headless test (or a layout dump) can assert that a node carries the right
  shadow parameters or corner radii without any Roblox process running. The
  "render" of a headless target is simply that data.
- **Instances appear only at the edge, and only if supported.** The client render
  target (`src/client/screen_target.luau`) is the one place that turns this data
  into real `UIShadow` and `UICorner` instances — and it does so behind
  **capability detection**. At startup it probes whether the running engine
  actually supports `UIShadow` and per-corner radii. If a capability is missing
  (an older client, or a headless run), the declaration stays as harmless data:
  shadows are simply not drawn, and per-corner radii fall back to a single uniform
  radius using the largest declared corner. Your blueprint never changes; the same
  description degrades gracefully on engines that cannot honor it.

This is the general shape of how Facet adopts any new engine visual feature:
express it as normalized data on a single declared authority, and let the one
edge adapter materialize it when — and only when — the platform can.

Next: [chapter 6](06-client-server.md) covers talking to the server.

## 5.7 Native stylesheets (the default): the Style Editor is the paint authority

A target hands its paint to a Roblox `StyleSheet` living in the DataModel, and
**that is what it does unless you say otherwise**
(`native_style.DEFAULT_ENABLED = true`):

```lua
local adapter = screen_target.new({})           -- sheet paint, the default
local explicit = screen_target.new({ nativeStyle = true })   -- the same thing, said out loud
local bespoke = screen_target.new({ nativeStyle = false })   -- THE OPT-OUT: explicit-write paint
```

The opt-out is per target and wins over everything. Reach for it when you need
the adapter to be the only writer of a property — a screen whose paint is driven
from game state that no rule can select on, or an A/B against the sheet path.

With the sheet path live (and the engine capability present), the adapter stops
explicit-writing every handed-off paint property and instead **classifies**
each instance — engine class plus `facet-*` CollectionService tags — under one
`StyleLink` per screen. A generated sheet named **`FacetStyle`** (under
`ReplicatedStorage` by default) owns:

- surface fills and transparency (`Base surface`, `Raised panel`, `Control
  fill`, `Chip`, `Badge`, `Primary button`, `Scrim backdrop`);
- corner radius and hairline strokes — as **phantom modifiers** the engine
  creates from `::UICorner`/`::UIStroke` rules (no `UICorner`/`UIStroke`
  instances exist in native mode);
- text paint (`Text default`, `Secondary text`, `Strong text`, field
  placeholder, scrollbar color, disabled text transparency);
- interaction-state paint via engine `GuiState` (`Control — hover/pressed`,
  `Disabled button`) and app-state paint via tags (`Selected row`);
- themes: `Theme Dark` / `Theme Light` child sheets swapped at runtime with
  `adapter.setNativeTheme(name)` — no remount, focus and scroll retained;
- optional per-rule transitions (progressive enhancement; reduced motion
  strips them live).

With `nativeStyle = false` — or on an engine without StyleSheets — the
explicit-write path runs unchanged, byte-equal on every mapped property. It is a
first-class path, not a legacy one: the native-stylesheets adoption evidence
measures the two against each other property by property, and the gallery's
`Facet_ForceStyleFallback` attribute forces it live so both arms stay exercised.

### What a Style Editor edit does (read this before editing)

| Edit in the Style Editor | Effect |
|---|---|
| A **color token** on `Theme Dark` / `Theme Light` (`Surface`, `Control`, `Accent`, …) | **Immediate.** Repaints every consumer on the running screen; **always survives** regeneration and framework upgrades (seed-once; upgrades only backfill missing tokens). |
| A property on a **named rule** (`Raised panel`, `Control — hover`, …) | **Immediate**, and survives while the framework's rule model is unchanged. A framework upgrade (model stamp change) **regenerates the rules** with a Studio warning — put durable palette edits in tokens, not rule literals. |
| A **layout mirror attribute** on the sheet (`SpaceM`, `TypeBody`, `RadiusControl`, `TargetMinimum`, `MotionFast`, …) | **No runtime effect — reference only**, on this legacy single-style path. Layout is solved headlessly from the Luau tokens (`src/tokens/…`); the generator overwrites these mirrors on every apply. Install a **theme package** (§5.8) and the mirrors are not emitted at all: typed metric attributes take their place and become the live authoring source. |
| Deleting/renaming the sheet or theme sheets | The next apply reseeds defaults (a schema-mismatched sheet is rebuilt). Keep the names. |

The seed-once rule: theme **tokens are always yours** — the generator never
overwrites them (upgrades only backfill new token names). Rules are yours while
the framework model is unchanged; when the model stamp changes the rules
regenerate (warned in the output). The mirrors and `NativeSheetStamp` refresh
on every apply.

### What never moved to the sheet

Layout and text geometry (the headless solver owns them — `textSize` is layout
authority, and the player's Roblox text-size preference is applied exactly once
by the engine), data bindings, the logical focus ring and ten-foot lift,
value-driven motion (the Toggle knob-track), pointer capture and cursor hints,
and `UIShadow` (still adapter-materialized behind its capability probe).
The split is between what a `StyleSheet` rule can express and what only the
adapter can write, and each side of it is measured.

## 5.8 Theme packages: a theme that owns metrics, not just colour

§5.7's Dark/Light themes are **palette** themes — they repaint, and that is all.
A theme can also own its typography, spacing, control heights,
radii, strokes, solver-visible content insets and asset-backed chrome, and a swap
re-solves the mounted screen instead of merely recolouring it.

The whole surface is public:

```lua
local themes = Facet.themes                     -- engine-free: define/resolve/neutral…
local theme_controller =                          -- client-only: install/swap/inspect
    require(ReplicatedStorage.Facet.client.theme_controller)

local package, report = themes.define({ base = themes.neutralPackage(), … })
local controller = theme_controller.install(adapter, package, { env = env, rootGui = gui })
controller.swap("Candlelight")
```

The four moving parts:

- **One versioned package** (`themes.define`, schema `facet-theme/1`) —
  declarative data, deeply frozen, content-stamped, validated for contrast,
  completeness, legal properties, insets, target floors and schema
  compatibility. No callbacks; a theme is inspectable, never code.
- **One frozen metric snapshot** (`themes.resolve`) riding the environment as the
  `themeMetrics` fact. Solver, renderer, tests and adapter all read the same
  values, so measurement can never disagree with paint. Controls ask for semantic
  roles (`textSize = "body"`, `gap = "m"`); a literal number is still legal and is
  thereby explicitly theme-independent.
- **Live authoring in the Style Editor.** Metric and font tokens are now typed
  attributes on the package's theme sheets — no longer reference-only mirrors —
  and a supported edit re-solves the running preview. One export action
  (`lune run tools/lune/theme_sync_cli`) writes them back into the committed
  package, and its `--check` mode fails a build when the two drift.
- **Bounded chrome.** A closed list of decoration slots, each either native paint
  (zero instances, gradients included) or adapter-created non-interactive
  `ImageLabel`s painted entirely by package rules, with declared content insets
  the solver honours and a tag-driven native fallback when the art fails. A slot
  may also carry a bounded STACK of layers and per-state art
  rather than a single picture — see §5.8a.

A swap is one transaction — `SetDerives` plus the snapshot commit in a single
invocation — so new paint and new geometry land in the same engine frame, and
mount identity, focus, selection, scroll and text entry all survive because
nothing is rebuilt.

**A LAYOUT that has to survive the swap, not just paint through it.** A theme can
change the type ladder AND the face, and a wide display family draws the same
string half again as wide at the same size. Anything you size with a device-pixel
literal is therefore a guess about ONE font: it over-wraps under a small ladder
and clips under a wide one. Two `UI.Grid` options exist for exactly this, and a
grid of labels usually wants both:

```lua
UI.Grid({
    id = "Packages",
    minColumnWidth = "intrinsic",  -- no column narrower than the widest child MEASURES
    itemSizing = "uniform",        -- and every cell takes that same measured size
    gap = 4,
    children = chips,
})
```

Both are re-measured on every solve under the ACTIVE snapshot, so a swap
re-columns and re-sizes the grid with nothing to update; `itemSizing` also turns
a ragged row of variable-width plates into one clean grid. Both are opt-in and
`natural` is the framework-wide default — a grid that does not ask keeps content
sizing exactly as it always had. The gallery's own theme picker
(`examples/gallery/client/theme_picker.luau`) uses both, and it is the surface
that proved why: with a literal `minColumnWidth` and a `fixed` row height its
chips clipped under Classic Desktop and overflowed their plates under Sci-Fi HUD.

**Chapter 9, [Custom themes](09-custom-themes.md), is the walkthrough**: deriving
from Studio Neutral, editing tokens, adding nine-slice panels and buttons,
insets and fallbacks, previewing across device profiles, validating and
exporting, installing, swapping, upgrading, and profiling ornate cost — with
Fantasy Parchment as the worked example. Contributors extending the theme system
itself use [`../extending/new-theme.md`](../extending/new-theme.md).

## 5.8a Rich skinning: when the art IS the interface

Rich skinning adds the authoring style where nothing on screen is a painted rectangle.
It is additive — a package written against §5.8 compiles and paints unchanged —
and it is entirely package data:

- **Layered slots.** A recipe may declare `kind = "layered"` with up to eight
  layers from a closed vocabulary (`fill`, `frame`, `corners`, `edges`, `plaque`,
  `tile`). Z-order is array order; a `corners` layer is four instances and an
  `edges` layer one per side, and the census counts what is really built.
- **Per-state ART, not just tints.** Anywhere an asset is legal, a
  `{ default, hover, pressed, selected, disabled, error }` map is legal, at the
  theme rung and at the per-view rung, through one normalizer. `default` is
  required, unstated states fall back to it, and a per-state inset change is a
  compile error — art may change on hover, geometry may not.
- **Value displays.** `barTrack` / `barFill` / `barCap` / `barCenter`,
  `toggleTrack` / `toggleKnob`, `stepperPlate`, `spinner` (one dot of an
  indeterminate ProgressView's ring). The bar's fill is drawn at full
  size and revealed through a clip window, so its art is byte-stable at every
  percent and a value change costs no adapter write at all.
- **Semantic icons.** `icons = { [name] = <asset> }` sized from `iconSizes` on the
  snapshot and tinted by the asset's `tintRole`; a theme with no icon draws an
  ASCII-safe fallback glyph in its own font, never tofu.
- **Pixel mode.** `identity.rendering = "pixel"` + `pixelUnit`: `Pixelated` on
  every image rule (censused), integer `SliceScale` enforced at compile, and
  snapshot lengths snapped up onto the grid.
- **`selectBy`.** One declaration on `theme_controller.install` maps the input
  paradigm to a package, so a phone skin becomes a desktop skin on dock, live,
  with the view tree unchanged.

**Chapter 10, [Rich skinning](10-rich-skinning.md), is the walkthrough**, and it
also documents the three-rung customization ladder end to end — theme package,
per-view override, and a custom control that ships its own art
([`../extending/skinned-control.md`](../extending/skinned-control.md)).

Three claims are still open: the human Style-Editor walkthrough, the
physical-phone pass over ornate chrome, and low-end-device cost. A Studio run
closes none of them. [Chapter 11](11-device-verification.md) explains
which instrument can close which class of claim.
