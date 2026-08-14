# Playbook: adding or extending a theme

Audience: an agent (or developer) with NO prior context on this repository, who
is either **shipping a theme package** or **changing the theme system itself**.
Follow the steps in order; every step has a command and a pass condition.

If you only want to *use* the feature — build a skin for your game — read
[`../guide/09-custom-themes.md`](../guide/09-custom-themes.md) instead. This
playbook is the contributor's side: the rules that keep a theme from breaking
the solver, the vocabulary you may and may not extend, and the evidence a theme
change owes before it is called done.

Read [`../reference/constitution.md`](../reference/constitution.md) first — the
rules your addition must follow.

> **What this document is, in plain words.** A theme in LuauUI is a settings
> table, not a program. It can change what the UI *looks like* — colours, type,
> sizes, and the pictures drawn behind buttons and panels — and it is
> structurally prevented from changing what the UI *does*: where things sit,
> what they say, whether they are visible, whether you can touch them. Almost
> every rule below exists to keep that line sharp, because the engine will not
> keep it for you: a theme that quietly wrote a size would break layout with no
> error message anywhere.
>
> The other half of this document is about **evidence**. A theme is a visual
> feature, and visual features fail in ways a green test suite cannot see, so
> each section ends with the specific command or the specific Studio capture
> that proves the section actually holds.
>
> Three sizes of change land here, and they are not the same job. Restyling your
> own game is [the guide](../guide/09-custom-themes.md), not this file. Adding a
> reference package to the repository is §5–§8. Changing the theme *system* — a
> new slot, a new recipe field, a new token kind — is §3 and §4, and it is a
> schema change with migration duties attached.

## 0. Ground rules

- Work from the library root: `GameStudio/ui/LuauUI` (all commands below assume
  it; use absolute paths in shell commands — relative paths against a wrong cwd
  are the #1 recorded time sink, `docs/lessons/absolute-paths-in-shell-commands.md`).
- Read [`../adr/ADR-0019-theme-packages.md`](../adr/ADR-0019-theme-packages.md)
  first. It is the decision record, including the post-implementation
  **Integration rulings** section, and it is not re-litigated by a package. Then
  read [`../adr/ADR-0020-rich-skinning-v2.md`](../adr/ADR-0020-rich-skinning-v2.md),
  which is additive to it: layers, per-state art, image value displays, semantic
  icons, pixel mode and `selectBy`. Every ruling in it cites the engine
  measurement it stands on.
- A theme package is **declarative data**. No callbacks, no component trees, no
  screen-specific branches. `themes.define` rejects a function found anywhere in
  the definition, and that rejection is the feature.
- Test-first is not optional. Never mark done while `./run-tests.sh` is red.
- Never edit `tools/lune/gate_manifest.luau`, `phases.json`, or
  `artifacts/theme-packages-and-skinning/acceptance-ledger.md` for a theme; the
  existing gate checks pick your work up through the suite and the checkers.

## 1. Property authority and the theme linter

**The rule:** a theme may repaint; it may never move, bind, hide, or retext.

The engine will not police this. An explicit write silently defeats a
`StyleRule` and fires no signal, so a themed `Size` would break layout with no
error anywhere. That is why the ruling runs at **compile** time, in
`themes.lintProperty(prop, scope?)` — exported publicly so a materializer or an
authoring tool rules on a property exactly as compilation does.

| Scope | Legal properties |
|---|---|
| `"rule"` (default) | the native paint set: `BackgroundColor3`, `BackgroundTransparency`, `TextColor3`, `TextTransparency`, `PlaceholderColor3`, `FontFace`, `ScrollBarImageColor3`, `CornerRadius`, `Stroke*` (see `render/authority.luau`'s `nativeSheetOwned`) |
| `"chrome"` | the above **plus** the decoration image set: `Image`, `ScaleType`, `SliceCenter`, `SliceScale`, `ImageColor3`, `ImageTransparency`, `ImageRectOffset`, `ImageRectSize`, `TileSize`, `ResampleMode` |

Everything else is rejected **naming the authority that owns it**: `Size`,
`Position`, `AnchorPoint`, `CanvasSize` (layout), `Text`, `PlaceholderText`
(binding), `Visible`, `Transparency`, `Rotation`, `TextSize`, `ZIndex`,
`ClipsDescendants` (presentation), `Active` (host). Image chrome named outside a
nine-slice recipe is rejected with its own message, because that is the
near-miss authors actually make.

If a theme *wants* to change a size, that is a **metric**, not a rule: put it in
`metrics` and let the solver read it from the snapshot.

Pass condition: `tests/theme_package.spec.luau` →
`"themes.lintProperty: the §4 legal-property boundary"`.

## 2. Core roles versus namespaced roles

The v1 core vocabulary is a **closed set**, versioned with the schema
(`src/themes/package.luau`):

| Constant | Members |
|---|---|
| `REQUIRED_TYPE_ROLES` | `caption`, `label`, `body`, `heading`, `title`, `control` |
| `OPTIONAL_TYPE_ROLES` | `strong`, `numeral` — the WEIGHT roles. Derived when a package omits them (see below), so they are legal to author and never required |
| `TYPE_ROLES` | all eight, in ladder order: the vocabulary a `textSize` refusal names |
| `REQUIRED_SPACE_STEPS` | `xs`, `s`, `m`, `l`, `xl` |
| `REQUIRED_CONTROL_SIZES` | `compact`, `regular`, `large` (each `height`, `paddingX`, `iconSize`) |
| `SLOTS` | `panel`, `control`, `field`, `selection`, `divider`, `scrollbar`, `sliderTrack`, `sliderThumb`, `badge`, `barTrack`, `barFill`, `barCap`, `barCenter`, `stepperPlate`, `toggleTrack`, `toggleKnob`, `spinner` |
| `REQUIRED_RADII` / `REQUIRED_STROKES` / `REQUIRED_MOTION` | `control`/`panel`/`pill`, `hairline`, `fast`/`normal` |
| `CONTROL_FAMILIES` | the per-family metrics with no better home (`slider.thumbSize`, `table.headerHeight`, …) |
| `MIN_TARGET_SIZE` | `44` — a theme may raise a target size, never lower one |

**The two WEIGHT roles are optional and derived.** `strong` (emphasis at reading
size) and `numeral` (a rank or score figure) are the answer to "I need bold
here" — a role rather than a `weight` prop, because a role's font descriptor
reaches the MEASURE seam and the PAINT seam together, and a face that reached
only one of them is exactly what got `UI.Text.font` deprecated.

Omit them and `themes.resolve` derives each from your own ramp: the base role's
family, style, size and line height, with only the weight changed —
`strong` = `body` at SemiBold, `numeral` = `control` (or `heading`) at Bold. A
display-face package therefore gets *its* face in both weights for free. Author
one and it wins outright:

```lua
metrics = {
    typography = {
        -- …the six required roles…
        numeral = { font = { family = "GothamSSm", weight = "Heavy" }, size = 22, lineHeight = 1.1 },
    },
}
```

Pick a weight the family actually ships. `Font.new` accepts any weight and
silently substitutes, and both seams substitute identically — so nothing breaks,
but you get a face you did not choose. The derivation deliberately stops at
SemiBold/Bold for that reason.

**Adding a core role is a framework change, not a package change.** It means:
extend the neutral package in `src/themes/snapshot.luau` (naming the literal it
replaces), make the consuming control resolve the role instead of its literal,
and let `tests/theme_drift.spec.luau` prove no reusable control kept the
hardcoded number.

**A contributed control uses a namespaced role instead.** `define` deliberately
passes `ns:role` entries through unvalidated — a package that *forgets* your
control is otherwise indistinguishable at compile time from one that covers it.
The gate is therefore explicit:

```lua
local result = LuauUI.themes.checkCoverage(package, myControl.needs)
-- result.ok, result.covered, result.missing = { { name, message, fix } }
```

Each declaration states `name` (`ns:role`), `kind` (`controlSize` | `color` |
`number`), `section`, `fields`, `authority`, `capability`, and a `fallback`. The
fallback is what makes an uncovered package **degrade** instead of erroring; the
pre-play check is what turns that degradation into a message somebody reads.

Each kind has exactly one legal home, and the two that do not work are worth
knowing before you lose an afternoon to them:

| `kind` | legal `section` | a package writes |
|---|---|---|
| `controlSize` | `metrics.controlSizes` | `["ns:role"] = { height, paddingX, iconSize }` |
| `color` | `style.themes[].extra` | `["ns:role"] = { r, g, b }` in EVERY theme |
| `number` | an open scalar metric section (`metrics.radii`, `metrics.space`) | `["ns:role"] = <number>` |

`metrics.controls` is a CLOSED family list and rejects a namespaced key by name;
a bare number in `metrics.controlSizes` compiles and then breaks
`themes.resolve`, because every entry there must be a `{ height, … }` table.

Two worked fixtures:
[`examples/themes/custom_control.luau`](../../examples/themes/custom_control.luau)
(`demo:gauge`, `demo:gaugeTint`), driven from both directions by the
`customControl` scenario step, and the fuller rung-3 example
[`examples/themes/ornate_gauge.luau`](../../examples/themes/ornate_gauge.luau),
which ships its own art and exercises all three kinds —
[`skinned-control.md`](skinned-control.md) is its playbook.

Pass condition: `tests/theme_package.spec.luau` →
`"theme package: namespaced contribution coverage (ADR-0019 §1)"`, and
`tests/theme_reference_packages.spec.luau` →
`"namespaced custom-control conformance (ns:role)"`.

## 3. Schema and version migration duties

Two schemas travel with the feature:

| Schema | Where | What it versions |
|---|---|---|
| `luauui-theme/1` (`themes.SCHEMA`) | `identity.schemaVersion`, `compatibility.requiresSchema` | the package contract |
| `luauui-theme-sync/1` (`token_sync.SCHEMA`) | the token dump | the export/freshness wire format |

Install and `swapPackage` compare the declared schema against the build's
**before any mutation**; a mismatch errors and leaves the target and the
environment untouched. Nothing half-installs.

If you change the metric vocabulary you owe all four of these:

1. extend the neutral package so every existing screen keeps its values;
2. keep `token_sync`'s path ↔ attribute mapping total (the reverse map is built
   from the known token set, never parsed, so an attribute can never mis-split);
3. re-run `theme_sync` over the committed reference packages and commit the
   regenerated metrics region;
4. bump the schema **only** with a migration note in the ADR — a silent schema
   change turns every published package into an install error.

Sheet-side, the rules are Step 2's and are consumed as-is: **seed once**, tokens
are the author's forever, upgrades **backfill** new token names only, and a
model-stamp change regenerates the *rules* with a warning. `inspect().sheet`
reports `seeded`, `migrated` and `stamp` so a migration is observable rather
than assumed.

## 4. Decoration-slot limits

The substrate is deliberately the smallest thing that works. Everything here is
closed vocabulary:

- **Slots**: the seventeen in `SLOTS` (§2). Adding one is a schema change (§3).
  Every slot past the original six — `sliderTrack`, `sliderThumb`, `badge`, the
  bar family, `stepperPlate`, `toggleTrack`, `toggleKnob`, `spinner` — reaches its node
  through the internal decoration HINT (`chrome_slots.attachHint`, the same
  `bp.meta` channel input contributions use) rather than through a public prop. A
  hint may also be `chrome_slots.NO_SLOT` — "this node is not a decoration
  surface, whatever you would have guessed" — which is what keeps an ornate
  package from painting a button plate over a Slider's accent fill. Their
  `metrics.insets` entries are OPTIONAL (default zero) so a package published
  against the earlier six-slot vocabulary still compiles. A new slot must never
  make an old theme WORSE: `stepperPlate` therefore falls back to the `control`
  recipe, so a package that predates it keeps painting steppers exactly as before.
- **One slot takes no art at all**: `spinner`. Its colour is not decoration, it is
  the information — the control rewrites each dot's tint every frame, and that
  tint paints the node's own plate, which any skin suppresses. A `nineSlice` or
  `layered` recipe on it is therefore a compile error rather than a silently
  frozen spinner; `kind = "native"` is legal, and what a package retunes instead
  is `controls.progress.spinnerDotSize`, `radii.control`, `strokes.hairline` and
  `colors.accent`. The general criterion, so a second slot can join it: the
  control writes that slot's colour continuously, and the colour is the only
  thing carrying a live fact.
- **Recipe fields**: exactly `{ kind, asset, contentInsets, fallback, sliced,
  shadow, layers, direction, size, startAsset, endAsset }`. Unknown fields are
  rejected with a "did you mean". `kind` is `native`, `nineSlice` or `layered`.
  `sliced = false` paints the asset whole (the default for the fixed-size-token
  slots: `sliderThumb`, `badge`, `barCap`, `barCenter`, `stepperPlate`,
  `toggleKnob`) and `sliced = true` forces slicing on one of them — a bordered
  stepper plate needs it and renders stretched without it. `shadow` is a preset
  name or a parameter table, validated at compile time against
  `styling.normalizeShadow`. `direction` (`ltr` | `rtl` | `ttb` | `btt`) is
  `barFill`'s only geometry; `size` / `startAsset` / `endAsset` belong to the bar
  ornaments.
- **Per-state assets**: any `asset` (recipe, layer, per-corner override, or a
  rung-2 view prop) may be a bare string or a
  `{ default, hover, pressed, selected, disabled, error }` map through ONE
  normalizer both rungs consume. `default` is required, unknown state keys are
  rejected naming the legal set, unstated states fall back to `default` with the
  tint rules still applying, and a per-state `contentInsets` difference on any
  axis is a compile error — art may change on hover, geometry may not.
- **Layers**: a `layered` recipe carries `layers`, a contiguous array of at most
  `chrome_slots.MAX_LAYERS` (8) entries from the closed kind set `fill`, `frame`,
  `corners`, `edges`, `plaque`, `tile`, each with its own fixed geometry
  vocabulary; a field borrowed from another kind is rejected. Z-order is array
  order. Two slots refuse a stack, each for a measured reason: `scrollbar`
  (canvas space) and `barFill` (its art is clipped whole art inside the adapter's
  percent window, so declared layers would paint NOTHING — put them on
  `barTrack`, as `glossy_touch.luau` does).
- **Instances**: a single-asset recipe materializes at most **one**
  non-interactive `ImageLabel` (`Active = false`, full-bleed, named
  `LuauUIChrome`, tagged `luau-chrome-<slot>`) per slotted node; a layered recipe
  materializes one per layer INSTANCE, which is not one per declaration — a
  `corners` layer is four and an `edges` layer is one per side. All of them are
  painted entirely by package rules. A recipe may never insert interactive
  instances, rearrange content, or carry code.
- **Pseudo selectors**: the allowlist is `::UICorner`, `::UIStroke`,
  `::UIGradient`. `::UIShadow` is **rejected at compile time** — on 0.731 it is
  accepted by `SetProperties`, reports no `SelectorError`, and paints *nothing*
  (`artifacts/theme-packages-and-skinning/feasibility/m7-gradient-shadow-phantoms.json`).
  A silently inert pseudo selector is a real hazard class; theme shadows stay on
  the bespoke `UIShadow` materialization behind its capability probe — that is
  what a recipe's `shadow` field materializes, so it is ADAPTER-owned paint on a
  node the sheet does not shadow, and there is no rule for it to defeat.
- **Gradients are palette, not chrome.** A gradient is colour, so it must swap
  with the theme: it rides `style.themes[].extra.chromeGradient.<slot>` and
  compiles to per-theme sequence tokens plus `::UIGradient` phantom rules — zero
  child instances. It may **never** target a value control's own chrome
  (`sliderTrack`, `sliderThumb`): a wash's alpha would make the node
  see-through and whatever the control draws behind it would read straight
  through the glass. `themes.define` rejects the declaration by name.
- **A value control's chrome paints itself, SOLID.** Slots reached only through
  the internal hint get `Slot — <slot>` / `— corner` / `— outline` rules keyed on
  `luau-slot-<slot>`, drawing from the same `SLOT_FILL_TOKEN` map the
  asset-failure fallback uses. Never give such a node a public `surface` to
  "borrow" a fill from — that is precisely how the panel treatment (and its
  gradient's alpha) reached a slider thumb and made it translucent. SOLID is the
  guarantee for a node with **no art**: the matching `Skinned — <slot>` rules are
  emitted by every package (a per-view override can skin a slot you declare
  nothing for) and lift the plate the moment a node actually carries art. Both
  families come from ONE emitter shared by the package builder and the built-in
  default's base seed, so an unskinned value control looks the same whether or not
  a package is installed.
- **Flat costs zero.** A `native` recipe materializes nothing. This is enforced
  in `src/tokens/chrome_slots.luau`, not merely intended.
- **Layer paint is rule-owned from birth.** The adapter never writes a layer's
  paint at create time. An explicit write made before a rule matches SURVIVES and
  defeats that rule permanently (measured, rs-m2), so a layer's plain `.Image`
  must read `""` while `GetStyled` resolves the package's value. That pair is the
  defeat-detection instrument; do not "fix" a repaint bug by writing the property.
- **Icons are a MEANING map.** `icons = { [name] = <asset name> }`, sized from
  `metrics.iconSizes` through the snapshot and tinted by the asset's `tintRole`.
  A name outside the framework set is a compile error with a "did you mean"
  unless it is namespaced `ns:name`. A theme with no icon for a requested name
  renders the framework's ASCII-safe fallback glyph in the theme font —
  `themes.isSafeGlyph` refuses anything outside plain ASCII, because a package
  may name any font and the characters a font is MISSING are what produce tofu.
  A live probe measured the old `U+25B8`/`U+25BE` carets at the tofu
  placeholder's advance in Michroma while the ASCII characters rendered
  normally (`artifacts/rich-skinning-v2/rs-a7-semantic-icons.json`).
- **Pixel mode** is `identity.rendering = "pixel"` + `identity.pixelUnit`
  (integer ≥ 1): `ResampleMode = Pixelated` on every image rule the package
  emits (censused, so `pixelatedRules == imageRules` is assertable), an integer
  `SliceScale` enforced at compile, and snapshot lengths snapped UP onto the
  grid. A non-pixel package is byte-unaffected.
- **`content` is the canonical asset field**, `contentId` is a permanent alias,
  and declaring both on one asset is an authoring error. Authored and exported
  data stay plain strings — the engine coerces them onto `ImageContent`, so there
  is no materialization shim; an object-sourced Content in a rule is rejected at
  compile because the engine accepts it and paints nothing.
- **The native plate is suppressed under a skin.** Every skinned slot emits
  `Skinned — <slot>` / `— corner` / `— outline` rules against the decorated node
  (tag `luau-skinned-<slot>`, added and removed with the decoration): the art IS
  the control, so the fill, the radius and the hairline it sits on stop drawing.
  A `native` slot keeps all three. Do not reintroduce a plate in a new surface
  branch — the adapter re-suppresses after `applySurface` for exactly that reason.
- **The text lift is mandatory where it applies** (TP-M8): under `Sibling`
  z-behavior a full-bleed child covers its parent's engine-drawn text at any
  ZIndex, so a text-bearing skinned node — `TextButton`, `TextBox` **and**
  `TextLabel`, which is what a badge is — gets one managed `LuauUIChromeText`
  label above the decoration, INSET by the recipe's `contentInsets`, and a
  `TextBox` yields its chrome while editing (`luau-chrome-editing`) because the
  caret is parent-drawn. Never "fix" this by
  switching a root to `Global` — that changes z-semantics for every surface.

Pass condition: `tests/theme_chrome.spec.luau` (rules, allowlist, cascade,
classification, census).

## 5. Asset provenance and import obligations

A repository theme package ships art that another project can reproduce. Before
adding an asset:

1. **Original, repository-owned art only.** No external imagery, no third-party
   asset, no game or OS trade dress. The reference skins are capability
   references, not replicas.
2. **Record provenance beside the art** —
   [`assets/themes/fantasy-parchment/provenance.md`](../../assets/themes/fantasy-parchment/provenance.md)
   is the template: generator, seed, exact regeneration command and library
   versions, per-file size and nine-slice border, what the interaction states do,
   the import/publishing procedure, and the licence.
3. **Record the content IDs in a manifest** —
   [`upload-manifest.json`](../../assets/themes/fantasy-parchment/upload-manifest.json):
   schema, package, upload date and method, and per-asset `file` → `contentId`
   with size and slice border. The IDs in the manifest and the IDs in the package
   must agree; `check_docs_cli` fails when they drift.
4. **Slice geometry is package data**, not an adapter guess:
   `SliceCenter = Rect(border, border, size − border, size − border)`. A
   nine-slice asset with no `sliceCenter` is an authoring error.
5. **Loading rides the resource provider.** `preload = "install" | "lazy"`; no
   raw content ID leaves package data by any other route; a failed asset flips
   `luau-chrome-fallback` exactly once and unflips on recovery. The paired
   `luau-chrome-mute` carries the HIDE and skips the condemned asset's own
   undecoded art, so a false failure can still recover
   (`docs/lessons/engine-never-decodes-invisible-images.md`).

## 6. Required tests

A theme change is covered by the spec that owns its seam. Add cases to the
existing file rather than a new one:

| Spec | Owns |
|---|---|
| `tests/theme_package.spec.luau` | `define`: compile/freeze/stamp, derivation, every rejection class, `lintProperty`, contrast parity, `checkCoverage` |
| `tests/theme_snapshot.spec.luau` | `resolve`: neutral parity with the pre-theme literals, composition order, floors, overrides, the `themeMetrics` fact |
| `tests/theme_roles.spec.luau` | role resolution in the renderer/solver, re-solve-without-rebuild, closed-set prop validation, canonical font-descriptor keys, byte-parity of migrated controls |
| `tests/theme_drift.spec.luau` | the lint: no reusable framework control hardcodes a theme-owned metric |
| `tests/theme_controller.spec.luau` | install (per-target, all-or-nothing), capability errors, the swap transaction, live token edits, `token_sync` round-trip, font preflight |
| `tests/theme_chrome.spec.luau` | `buildPackage` chrome rules, gradients as phantoms, the pseudo-selector allowlist, cascade order, slot classification |
| `tests/theme_reference_packages.spec.luau` | the reference corpus compiles through public APIs only, covers all four theme classes, the failure fixtures fail correctly, and the rung-3 control's coverage answers both directions |
| `tests/theme_layers.spec.luau` | layer schema and every layer rejection class, the per-layer rules, suppression over a stack, the per-kind census |
| `tests/theme_variants.spec.luau` | the per-state asset grammar shared by both rungs (defaults, fallbacks, inset parity) |
| `tests/theme_icons.spec.luau` / `theme_icons_applied.spec.luau` | icon resolution, fallback glyphs, and the applied-on-the-live-path pair |
| `tests/theme_pixel.spec.luau` / `theme_pixel_content.spec.luau` | the three pixel generation rules, and `content`/`contentId` equivalence |
| `tests/theme_authoring_scenario.spec.luau` | every scenario step, headless |
| `tests/theme_docs.spec.luau` | the documentation gate (§8) |

The suite total must be strictly larger than before your work — an unregistered
spec is a silent zero.

## 7. Studio evidence obligations

Headless conformance proves deterministic decisions. It does not prove that
Roblox painted, sliced, measured, or hit-tested anything.

1. Drive `examples/gallery/scenarios/theme_authoring.luau` — it mounts the whole
   control gallery and restyles it from the outside, so a theme is never proven
   against a theme-shaped fixture built to flatter it.
2. Run the canonical five view rows
   ([`../plans/studio-device-verification.md`](../plans/studio-device-verification.md)):
   `compact-phone-portrait`, `compact-phone-landscape`, `tablet-landscape`,
   `desktop-standard`, `console-ten-foot`. Locale, preferred text, reduced motion
   and failure fixtures are **axes**, run pairwise on the smallest covering
   subset.
3. **Pair every capture.** A nine-slice screenshot alone passes nothing: the row
   needs the actual slice properties read back through `GetStyled`, the
   decoration instance count, the solver-visible insets, hit geometry, focus and
   state identity, and the mount identity — the scenario's `report()` returns all
   of them in one object. Note that `GetStyled` **errors** on a property the
   class does not have, so every probe is pcall-guarded.
4. Follow [`../plans/agent-execution-contract.md`](../plans/agent-execution-contract.md)
   for the evidence ladder, and keep physical-touch, true-gamepad, human-judgment
   and low-end-performance rows explicitly **pending** — they are tracked in
   `artifacts/theme-packages-and-skinning/review-packet.md` (TP-P1–TP-P4), not
   closed by a Studio run.

## 8. Registration and gate obligations

Run, in order, from the library root:

```sh
./run-tests.sh                                   # suite green, count grew
lune run tools/lune/check_docs_cli               # docs match the shipped theme surface
lune run tools/lune/check_registration_cli       # every public export documented
lune run tools/lune/check_prop_parity_cli        # property views agree
lune run tools/lune/gate theme-packages-and-skinning   # must not REGRESS
```

`check_docs_cli` is the canonical documentation command for this stage. It is
**read-only by default** and enforces that the guide index links the custom-theme
and rich-skinning chapters, that every public `LuauUI.themes` export is
documented in `docs/reference/api.md`, that the guide and playbooks still name
the shipped tools (`theme_sync_cli`, `theme_controller`, `chromeCensus`,
`checkCoverage`), that the rich-skinning chapter still names the whole v2 surface
it teaches (layers, the variant states, the bar family, `stepperPlate`,
`selectBy`, `rendering = "pixel"`, the fallback glyphs), that the Fantasy
Parchment and OrnateGauge walkthroughs still point at files that still build
through the public API, that the example packages and their art/manifest/
provenance exist and agree — including the rung-3 control's own art folder —
that every local link in these four documents resolves, that the styling guide no
longer calls the package contract unshipped and no document calls the v2 surface
unshipped, and that every scenario step the guides teach still exists. On failure
it prints the exact document, the missing obligation, and the command or manual
action that fixes it. There are no generated blocks in this document set, so
`--write` has nothing to regenerate and says so.

The acceptance ledger
(`artifacts/theme-packages-and-skinning/acceptance-ledger.md`) and the gate
manifest (`tools/lune/gate_manifest.luau`) already carry this stage's rows —
TP-A1…TP-A14 and the matching gate checks. **Name them in your report; never
edit them.** The gate's pass rule counts human-signoff placeholders (`PENDING`
with no run command) as failures by design, so the gate command may exit nonzero
even when your work is perfect. Your bar: every check that was PASS before your
change is still PASS, and none moved to FAIL_RECOVERABLE. Never flip a PENDING
state yourself.

## Common traps

- **A require cycle through the compiler.** `src/tokens/sheet_model.luau`
  requires `src/themes/package.luau`. Nothing the compiler needs may live in
  `sheet_model`; shared values go *down* into `tokens`
  (`docs/lessons/lune-circular-require-hangs.md` — a Lune circular require
  hangs rather than erroring).
- **`GetStyled` on a class-inapplicable property errors.** Instruments must
  pcall-guard; a plain property read is *blind* to sheet paint and will happily
  report the engine default while the rule is working perfectly.
- **A bad content ID still "styles".** Failure detection rides `IsLoaded` and the
  resource provider, never the style system.
- **The base sheet does not see a derive's attributes.** A runtime metric read
  must target the *active theme sheet*, which is why the controller keeps exactly
  one watcher and moves it when the active theme changes.
- **Never rename the package sheet to `LuauUI`.** That is the library
  ModuleScript tree's name under `ReplicatedStorage`; a same-name lookup once
  destroyed the library itself. Package sheets are `LuauUITheme <id>`.
