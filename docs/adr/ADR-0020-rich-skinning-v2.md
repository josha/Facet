# ADR-0020 — Rich skinning v2: fully image-driven UI

**Date:** 2026-07-25 · **Status:** Accepted (lead rulings for the `rich-skinning-v2` gate) ·
**Charter:** `docs/plans/rich-skinning-v2.md` · **Builds on:** ADR-0019 (consumed, never reopened)
**Probes:** `artifacts/rich-skinning-v2/feasibility/rs-m1..m7.json` — every ruling below cites
the measurement it stands on. Ledger: `artifacts/rich-skinning-v2/acceptance-ledger.md`.

## Probe verdicts in one paragraph

TileSize is fully rule-settable (offset px / scale = fraction of label, per-state, composes
with Pixelated and ImageContent — rs-m1), so `tile` ships as a real layer kind. A five-layer
sibling ZIndex ladder orders exactly, the chrome text lift stays above any depth, compound tag
rules hit single layers, and one parent tag can yield a whole stack — but layer paint must be
rule-owned from birth because a pre-join explicit write survives and defeats later-matching
rules (rs-m2). AnchorPoint+scale-Position expresses corners/rails/plaques px-exactly with
input transparency through `Active=false` ornaments (rs-m3). Bar fills clip through a
ClipsDescendants window over a full-width sliced fill — ImageRect crop is rejected for sliced
art (rs-m4). Pixel mode needs Pixelated on every image rule, integer SliceScale, and
solver-side integer snapping aimed at scale-derived fractions (rs-m5). Per-state image swaps
paint next frame with zero reflow; PreloadAsync stays policy because Studio can't measure
retail-cold (rs-m6). Strings coerce on ImageContent rules and even `Content.fromUri` rules
round-trip as strings, while `Content.fromObject` in a rule is accepted-but-silently-inert
(rs-m7).

## R1 — Layered decoration slots (charter cap 2)

A chrome recipe may declare `layers = { ... }` — a bounded ARRAY (max 8, compile error above)
of layer tables, each `{ kind = "fill" | "frame" | "corners" | "edges" | "plaque" | "tile",
asset = <assetRef>, ... }` with a FIXED per-kind anchoring vocabulary:

| kind | geometry vocabulary | notes |
|---|---|---|
| `fill` | full-bleed (optional `inset = {x,y} px`, `mask = "pill"`); sliced by its asset's declared slice | the content-back |
| `frame` | full-bleed (optional `inset`, `mask`); sliced; sits above `fill` layers | border art |
| `corners` | `size = px` (+ optional per-corner asset overrides) | four ornaments, AnchorPoint idiom (rs-m3) |
| `edges` | `sides ⊆ {top,bottom,left,right}`, `thickness = px`, `margin = px` | sliced rail or tiled via `tile = px` |
| `plaque` | `size = {w,h} px`, `edge = "top"` (v1: top only), `overhang = px`, optional `text = true` sub-slot | overhang renders outside the rect (rs-m3) and is published in the slot's reservation metadata |
| `tile` | full-bleed (optional `inset`, `mask`); `tileSize = {w,h} px` (offset px is the canonical authoring form; rs-m1) | pinstripes, barber-pole, repeating rails |

**`mask = "pill"` (director round 5c, 2026-07-25; probe rs-m9).** The second field the three
FULL-BLEED kinds share, and a compile error on the other three. A closed set of ONE value,
for the reason `PLAQUE_EDGES` is one edge: rs-m9 measured a pill (UICorner at scale 0.5)
clipping a tiled child and measured nothing else. The adapter materializes one CanvasGroup
per masked layer, carries the layer's BOX on the wrapper and the art full-bleed inside it,
and leaves the wrapper **untagged** — so every existing rule path (resting art, per-state
variants, tint, fallback, suppression) still selects the same `ImageLabel`. rs-m9 Q2 is what
makes that safe: StyleSheet rules reach a tagged child inside a canvas exactly as outside,
and the `GetStyled`-versus-plain defeat instrument still works there. The wrapper's own
transparency is a class rule (`Canvas default`), never an adapter write. A canvas is a real
cost — rs-m9 Q5 measured ~7 KB and ~18 µs each, Studio-derated — so it is censused as
`canvasMasks` and RS-A17 reads it. `mask` and `inset` compose and answer different questions:
the mask decides the SILHOUETTE, the inset how far the content is held off the rim.

**`inset = { x = px, y = px }` (director round 5b, 2026-07-25).** The one field the three
FULL-BLEED kinds share, and a compile error on the other three (whose boxes are anchored by
their own geometry). Both axes optional and non-negative; the layer's box shrinks
SYMMETRICALLY per axis — `x` in from each end, `y` from each edge — which is the rectangle
an `edges` rail already gets from `margin`, on both axes. It exists because a full-bleed
rectangle is right for the layer that IS the plate and wrong for one riding ON it:
glossy-touch's stripe `tile` painted its square corners over the trough's rounded ends, so
the bar read blocky with no backing to blame (measured: the backing already resolved
transparency 1). Absent or `{ x = 0, y = 0 }` produces the identical box full bleed always
produced, so every package that declares none is byte-unchanged.

Z-order IS array order (adapter assigns ZIndex 1..N; the chrome text lift rides above N —
rs-m2). Layer instances are adapter-created, tagged per slot+index, `Active = false`
(input-transparent, rs-m3), and every paint property is RULE-owned from birth — the adapter
never writes paint at create time (the rs-m2 defeat refinement). The editing-yield
generalizes to one parent tag + a child-combinator rule.

Back-compat: today's single-asset `kind = "nineSlice"` recipe is unchanged and is exactly
equivalent to `layers = { { kind = "fill", asset = ... } }`. `kind = "native"` recipes and
flat themes create ZERO layer instances. The census grows per-layer-kind counts;
suppression (`luau-skinned-*`, R9) covers layered nodes identically.

## R2 — Per-state asset variants at both rungs (cap 3)

**One grammar, one normalizer.** Everywhere an asset reference is legal — a recipe's `asset`,
a layer's `asset`, per-corner overrides, bar/toggle/stepper slots, rung-2 view props — a bare
string stays legal (same art in every state) and a table
`{ default = ..., hover = ..., pressed = ..., selected = ..., disabled = ..., error = ... }`
becomes legal. `default` is required in map form; unknown state keys are compile errors naming
the slot and the legal set. Focus is NOT a variant state — it stays the selection slot +
`chrome.focus` (ADR-0019). The normalizer lives in the schema (`package` module) and BOTH
rungs consume it — the prop schema never forks from the recipe schema.

Semantics: unstated states fall back to `default`, with the existing per-state TINT rules
still applying on top of the defaulted art. If the map omits `disabled`, the standard
disabled treatment applies over `default` (accessibility floor preserved). State swaps are
emitted as the existing GuiState pseudo + tag-family rules carrying `Image` (rs-m1/m6:
next-frame, no reflow). A variant may declare `contentInsets` ONLY if identical across
states per axis — else compile error naming slot, state, and axis (charter: no reflow on
state change; the engine already guarantees paint-only swaps, rs-m6).

Preload policy: a variant map's assets join the package's existing install/lazy preload seam,
and `theme_controller.install` DRIVES that seam — every distinct install-policy content id is
requested through the resource provider when one is supplied via `opts.resources`, released on
swap and on uninstall (`controller.inspect().preload` reports `{ driven, requested }`). It is
an opts seam, not an unconditional fetch: this module is engine-free and the transport is the
caller's (`roblox_resources.bind`), so with no provider the step is lazily skipped and nothing
is claimed (~50 ms/asset Studio-derated, rs-m6; retail cold is unmeasurable in Studio —
recorded honestly, never claimed).

Rung 2 (`thumbImage`, `trackImage`, button image, …): same shapes; an explicit local value
opts that node out of theme changes visibly (`dump().skinRung`, ADR-0019 opt-out rule).

## R3 — Image value-displays (cap 4) + toggle slots (cap 10)

**Bar family** (closes the Step 3.5 progress-Bar cosmetic deferral): new slots `barTrack`
(nine-slice), `barFill` (sliced, clipped), `barCap` (whole image, start/end), `barCenter`
(whole image). The adapter builds: track ImageLabel → ClipsDescendants window Frame →
FULL-track-size fill ImageLabel inside (rs-m4 winner). Percent maps to ONE window `Size`
write — no re-solve, art byte-stable; fill `direction` is declared data
(`"ltr"` default; `"rtl"`/`"ttb"`/`"btt"` drive which axis+anchor the window uses).
Caps that must survive all percents are separate `barCap` layers, not fill art. Sliced fills
reject ImageRect cropping at compile (rs-m4). When flat/unskinned, the bar family owns SOLID
native paint via the `luau-slot-*` family and value-control gradients stay a compile error
(the ADR-0019 fix-round discipline extends to bars).

**Stepper**: slot `stepperPlate` (whole image, per-state) behind each glyph; glyphs
themselves become icon requests (R4).

**Toggle**: slots `toggleTrack` (nine-slice) + `toggleKnob` (whole image), per-state variants
on BOTH (the iOS-6 sliding switch). Knob TRAVEL stays solver-owned; art never moves geometry
(rs-m6 invariant + compile-time inset parity). The Step 3.5 `togglePalette` contract is
untouched and remains the flat/fallback truth — a package without toggle slots gets exactly
today's palette-true toggle.

## R4 — Semantic icon assets (cap 5)

Package-level `icons = { [semanticName] = <assetRef> }` (variant maps legal), sizes from
`iconSizes` metric roles riding the snapshot (metric packages resize icons), tints via the
existing `tintRole` asset field. The framework owns a FALLBACK GLYPH table per semantic name
(ASCII-safe strings by construction, because a package may name ANY font and the framework
cannot know which characters that font contains — the sci-fi tofu carets were U+25B8/U+25BE,
two GEOMETRIC-SHAPES characters Michroma simply does not have, measured at the tofu
placeholder's advance by a live glyph probe: `rs-a7-semantic-icons.json`); a theme with no
icon for a requested name renders the glyph through the theme font. Controls request icons by semantic name only (`icon = "chevron.trailing"`); raw asset
ids in control code stay forbidden. The follow-ups caret is the proof defect: under sci-fi it
must render that theme's icon asset, under a theme with no icon map the real glyph — never
tofu.

## R5 — Pixel-art mode (cap 6)

`identity.rendering = "pixel"` + `identity.pixelUnit = N` (integer ≥ 1). Three generation
rules (rs-m5): (1) every image-bearing rule the package emits carries
`ResampleMode = Pixelated`, censused so `pixelatedRules == imageRules` is an assertable
count; (2) `SliceScale` locks to integers at compile (fractional = error naming the slot —
sharp-but-uneven is the worst failure mode because it looks crisp in captures); (3) the
snapshot's metric values snap UP to integer multiples of `pixelUnit` (floors clamp up,
ADR-0019 precedent), and the solver's emitted px for pixel packages round to integers —
aimed at scale-derived fractions (authored offsets already self-floor at the engine, but
snapping makes adjacency deterministic instead of floor-accidental). Non-pixel packages are
byte-unaffected (cmp-enforced).

## R6 — Content adoption (cap 7)

`content` is the canonical asset field; `contentId` stays a legal alias — both normalize to
ONE string at `themes.define` (one resolution path, spec-pinned). Authored and exported data
stay plain strings; generated rules carry the strings verbatim on `Image` or `ImageContent`
alike (the engine coerces — rs-m7), so no materialization shim exists at all. Rule emission
REJECTS object-sourced Content at compile (accepted-but-silently-inert in the engine —
rs-m7, the fourth catalogued inert trap). EditableImage skins are the declared stretch: a
distinct layer source kind materialized by ADAPTER INSTANCE WRITE (deliberately
rule-defeating on that node, recorded in the authority manifest), not by rules.

## R7 — Profile-conditional selection: `selectBy` (cap 8)

`theme_controller.install(adapter, defaultPackage, opts)` grows
`opts.selectBy = { touch = pkg, pointer = pkg, gamepad = pkg }` — vocabulary is EXACTLY the
existing input-paradigm classes; nothing new is detected. Behavior: resolve the initial
package from the env's current paradigm facts (unmapped → the positional default package);
subscribe to the existing paradigm-change seam; on a SETTLED profile change (debounced so
hybrid flaps produce one swap per settlement, spec-pinned) call the existing atomic
`swapPackage` — mount/focus/scroll identity held by construction (ADR-0019 TP-A4). The
subscription lives and dies with the controller (dispose leak-checked). A manual
`swapPackage` while `selectBy` is active WINS until the next profile change and warns once
(predictability over cleverness). The view tree never observes any of it.

## R8 — The customization ladder (cap 11) + rung 3

Rung 1 = theme packages (this stage's recipes). Rung 2 = per-view modifier props sharing the
R2 grammar, with shadow/gradient modifiers composing predictably (the view modifier wins on
that node; theme recipes keep their slot shadows — ADR-0019). **"The view wins" is MEASURED,
not assumed** (`feasibility/rs-m8-gradient-composition.json`, fix round): on a node a theme
gradients through a phantom `.luau-surface-raised::UIGradient` rule AND that carries the
adapter's real `LuauUIGradient` child, `GetStyled` on that child returns the VIEW's sequence,
the theme's tokens appear nowhere on the node, and the visual A/B against a no-child sibling
shows the theme gloss on the sibling and only the view's wash on the card. `::UIGradient`
therefore groups with `::UICorner` (a real child SUPPRESSES the phantom) rather than with
`::UIStroke` (which coexists) — the engine honours exactly one UIGradient per GuiObject, so
there is no second slot for the phantom to occupy. No suppression rule and no compile-time
refusal is warranted. Rung 3 = a custom control:
the worked example is **OrnateGauge** — registers namespaced roles/metrics/slots through the
existing contribution contract, ships its own original art, passes `themes.checkCoverage`
both directions, and re-themes under two packages. Docs walk all three rungs end to end;
`check_docs_cli` gains the obligations and stays negative-proven.

## R9 — Image-is-the-element posture (cap 1)

The Step 3.5 `luau-skinned-*` suppression machinery extends to EVERY image-bearing slot and
to layered nodes: a skinned recipe may declare its decoration the ONLY paint; generated
suppression rules zero the native fill/corner/stroke, `GetStyled` is the proof instrument,
and the census counts suppressions. `OWN_PAINT_SLOTS` (slider rail/thumb, now + bar family)
keep their solid-paint guarantee. Flat themes remain byte-identical to the 0.6.0 baseline
(cmp-enforced at gate).

**Refinement (director round 5, 2026-07-25).** The posture applies UNIFORMLY: a value slot
that is SKINNED suppresses its own solid backing exactly like every other skinned slot —
the art is the element, and a slab behind it shows through every transparent pixel the art
has. The `OWN_PAINT_SLOTS` guarantee is therefore the FLAT guarantee: it holds, byte
unchanged, for a node with no art, because such a node never earns `luau-skinned-<slot>`.
The four suppression sets are PRE-ARMED on every package rather than emitted per declared
recipe, because a node earns that tag from three routes — a nine-slice recipe, a layer
stack, and the rung-2 per-view override — and only the first two are package-declared; the
third produced a tag with no rule (measured live: a rung-2 slider thumb on `glossy-touch`,
which declares no slider recipe, sat on a square opaque plate). The anti-translucency hazard
the Step 3.5 ruling was written for was a native GRADIENT riding value chrome; that is still
a compile error and is untouched here. Art quality behind a skinned slot is the art
contract's and RS-P1's, as it is for every other slot.

**Refinement (director round 7, 2026-07-25).** A recipe's `contentInsets` are
SOLVER-VISIBLE for every kind that materializes art, `layered` included. The
snapshot used to compose `chromeInsets` for `nineSlice` only, while the adapter
boxes a decorated node's lifted label by `contentInsets` for a layer stack too —
so a layered package's insets were applied at paint and reserved by nobody.
Measured live under fantasy-ornate: the toolbar's content-sized "Play" button
solved to 48x47 and its lift resolved to **-4.0 x 27.0**, a negative box, which is
why the label was absent rather than clipped. A recipe kind that puts art on a
node and an inset in its reservation is one decision, not two.

**Refinement (director round 6, 2026-07-25) — R9 at a real-child seam.** The
suppression posture reaches a node through PHANTOM `::UICorner` / `::UIStroke`
rules, and a REAL child of that class suppresses the phantom. The toggle is the
one slot whose chrome is real children (the palette-true switch's pill and edge),
so the adapter turns them off itself when the part is skinned and restores them
when it is not. The visible failure was severe and its obvious explanation was
wrong: a real `UICorner` on a `ScaleType = Slice` ImageLabel makes the engine
round each of the nine patches independently. **Roblox clamps overlapping slice
caps by itself** — measured at three sizes against the exactly-fitting scale — so
no `SliceScale` guard is warranted anywhere in this stage
(`docs/lessons/roblox-slice-and-uicorner.md`).

**Refinement (RS-DIR6-F1, close-out round 2026-07-25) — A BROKEN ASSET STAYS
HIDDEN IN EVERY STATE.** `Chrome — <slot> fallback` hides art that could not
load and repaints the slot's declared native fill under it; the disabled state
rule dims the same `ImageTransparency`. The cascade is Priority first, then
insertion order, with NO selector specificity, and this generator pins Priority
as `index * 10` — so GROUP ORDER decides, the `disabled` group is above
`chrome`, and the dim re-revealed exactly the art the fallback existed to hide.
The fix is by PRIORITY and not by scoping the disabled rule off fallback nodes,
because a StyleSheet selector has **no negation**: "everything except a fallback
node" is inexpressible. One extra rule per chrome tag —
`Chrome — <slot> fallback over states` (per layer:
`Chrome — <slot> L<n> <kind> fallback over states`), selector
`.<tag>.luau-chrome-mute` (`.<tag>.luau-chrome-fallback` until RS-A16-D5 split the
hide onto its own tag), carrying `ImageTransparency = 1` **and nothing else** — is
emitted into the `disabled` group immediately after that tag's disabled rule. The fill and the corner remain the chrome-group rule's; nothing
contests those. Per-entry emission means one slot's protection can never be
undercut by a later slot's disabled rule, because a different tag is a different
instance.

## Process rulings

- **Emission ≠ application** (the Step 3.5 live-only defect class): every new emit path
  ships with a paired applied-on-the-live-path spec (fake_target records create/tag-sync
  invocation order; falsifiability-checked).
- Layer/variant/icon/pixel validation errors follow the ADR-0019 error contract: name the
  field, state the rule, show the fix.
- Census extensions (per-layer-kind counts, suppressions, pixelated-rule count, variant
  asset counts, overhang metadata) are part of the SCHEMA work, not an afterthought — cost
  honesty (RS-A17) reads them.
- Build packages dispatch to Claude Opus 5 (thinking, xhigh) as disjoint briefs; the lead
  iterates each via SendMessage; every visual claim is proven in a live Studio session at an
  asserted stamp per `docs/plans/agent-execution-contract.md`.
- **The client adapter is now two files.** `ModuleScript.Source` refuses any string of
  200 000 bytes or more (live-probed 2026-07-25), and `tools/studio/inject.luau` syncs by
  assigning `Source` — so `screen_target.luau` at 199 613 bytes was 386 bytes from breaking
  Studio sync for the whole stage. The chrome/decoration materializer moved verbatim to the
  sibling `src/client/screen_chrome.luau` (199 613 → 116 936 + 90 042) behind a thirteen-function
  interface and an explicit `Context`. `screen_target` requires `screen_chrome` and never the
  reverse (`docs/lessons/lune-circular-require-hangs.md`). Anything added to the decoration
  subsystem belongs in `screen_chrome`; the source contracts that anchor on adapter function
  text resolve against BOTH files.

## Build-package plan (dispatch order)

| Pkg | Scope | Depends on |
|---|---|---|
| P1 | Schema + model: layer/variant/icon/pixel/content fields, validation classes, census model, sheet_model rule emission (incl. Pixelated stamping, variant state rules, suppression extension), headless specs | — |
| P2 | Adapter: layer instance ladder, ornament anchoring, window-clip plumbing, tag sync + application specs, editing-yield over stacks, scenario steps | P1 |
| P3 | Value displays end to end: bar family, stepper plates, toggle slots, flat fallbacks | P1, P2 |
| P4 | Icons + selectBy + pixel mode end to end (controller subscription, icon resolution + tofu fix, pixel package generation) | P1, P2 |
| P5 | Reference packages + original art: Fantasy Ornate, pixel-art package, platform pair (glossy touch + compact pointer), uploads + provenance | P1–P4 |
| P6 | Docs ladder + rung-3 OrnateGauge + check_docs obligations + review packet | P1–P5 |
