# ADR-0019 — Theme packages, one metric snapshot, and bounded skinning

**Date:** 2026-07-24 · **Status:** Accepted (stage `theme-packages-and-skinning`, roadmap Step 3.5) ·
**Plan:** `docs/plans/theme-packages-and-skinning.md` · **Evidence:**
`artifacts/theme-packages-and-skinning/` (ledger + feasibility TP-M1–M6) ·
**Builds on:** ADR-0018 (native StyleSheets — complete, not reopened here).

## Decision summary

1. **One public, versioned `ThemePackage` contract** — declarative data, compiled and
   validated by a pure public compiler. It is a thin packaging and solver bridge around
   native StyleSheets, never a second styling language.
2. **One frozen plain-Luau `ThemeSnapshot`** is the only metric authority. It rides the
   environment as the `themeMetrics` fact, so solver, renderer, tests, and adapter all
   read the same values through the existing per-key reactive machinery.
3. **Controls speak semantic roles** (typography roles, space steps, control sizes);
   role names resolve to pixels at render/measure time from the snapshot, so a theme
   swap is a re-solve, never a blueprint rebuild or remount. Numeric literals stay
   legal and are thereby **explicitly theme-independent**.
4. **Style Editor sync = the plan's preferred workflow**: after seeding, the DataModel
   package sheet is the single authoring surface for supported paint *and* metric/font
   tokens; a public exporter writes the deterministic committed plain-Luau package; a
   freshness gate fails on drift. Reference-only layout mirrors are retired.
5. **Font-aware measurement keys on the effective Font descriptor**
   (`family#weight#style`), preflights declared fonts at install, reserves
   conservatively until calibrated, then relayouts once.
6. **Bounded chrome**: closed-vocabulary recipes per semantic decoration slot — native
   sheet paint first; where real children are required, exactly one non-interactive
   nine-slice `ImageLabel` decoration child per slotted node, painted entirely by
   package rules, with solver-visible content insets and tag-driven native fallback.
7. **The controller is target-scoped.** Per-package sheets + one `StyleLink` per root
   give true per-target theming (TP-M1); a target that cannot isolate fails
   installation with a capability error.

## Engine truths this ADR rests on (feasibility TP-M1–M6, Play Solo 0.731)

- **Per-target isolation works**: two roots with their own sheets/links paint
  independently; swapping one leaves the other byte-stable. An *unlinked* tree's
  `GetStyled` falls back to the plain property value (m1).
- **Nine-slice is fully rule-ownable**: `Image`, `ScaleType=Slice` (enum),
  `SliceCenter` (Rect), `SliceScale`, `ImageColor3`, `ImageTransparency` all apply via
  tag rules and resolve through `GetStyled`; plain reads stay blind. A bad content ID
  still "styles" — failure detection rides `IsLoaded`/the resource provider, not the
  style system. `GetStyled` on a class-inapplicable property **errors**; instruments
  pcall-guard (m2).
- **Typography is a token swap**: `Font`-typed attributes on theme sheets referenced as
  `$Token` from `FontFace` rules resolve and follow `SetDerives` (m3).
- **Metric tokens are engine-observable**: number/UDim/Font attributes are settable;
  number `$Token` refs resolve inside rules; `GetAttributeChangedSignal` fires on
  edits — the live re-solve loop's signal. **The base sheet does not see derived
  attributes**: runtime metric reads target the *active theme sheet* (m4).
- **A derive swap is atomic at the next frame**: after `SetDerives`, `GetStyled`
  reports the old theme for the rest of the invocation, then all nodes flip together
  (0/600 → 600/600); `SetDerives` itself costs 0.039 ms Studio-derated. Committing the
  derive swap and the snapshot swap in the same invocation, then re-solving
  immediately, lands new paint and new geometry in the same engine frame (m5).
- **Typed export round-trips exactly**: color/number/bool/string/UDim/Font serialize
  deterministically and re-import value-exact — the sync workflow's mechanics (m6).

## 1. The `ThemePackage` contract

`src/themes/package.luau` (pure, engine-free) exports `define(def) -> (package?, report)`.
Sections (schema `luauui-theme/1`):

- **identity**: `id` (stable slug), `displayName`, `schemaVersion`, `version` (semver).
- **style**: the color token schema (superset of `tokens.compile` — the same contrast
  and completeness gates run here) plus per-theme variants (e.g. Dark/Light) exactly as
  Step 2 models themes.
- **metrics**: typography roles `caption|label|body|heading|title` each
  `{font = {family, weight?, style?}, size, lineHeight}`; space steps `xs..xl`;
  `controlSizes.compact|regular|large = {height, paddingX, iconSize}`; `radii`;
  `strokes`; `targetSizes.minimum`; `insets` per decoration slot; `motion`.
- **chrome**: recipes keyed by semantic slot (§5): native treatment or nine-slice
  asset + insets + failure fallback.
- **assets**: semantic name → `{contentId, sliceCenter?, sliceScale?, preload,
  fallback, tintRole?}` with provenance notes required for repository packages.
- **compatibility**: required LuauUI schema range, required capabilities, declared
  degradations.

Validation rejects, each with the offending field and the fix: missing core roles,
unknown recipe/section fields, unsupported native properties (§4 linter), contrast
failures, invalid insets, target sizes below the accessibility floor, missing
fallbacks, incompatible schema versions. **No callbacks, no component trees** — a
package is inspectable data; `table.freeze` on success.

Derivation: a package may name a `base` package and override sections;
missing values inherit (the authoring path for "start from Studio Neutral"). Custom
controls register namespaced roles (`ns:role`) through the public contribution
contract with declared types, fallbacks, authority, and capabilities; validation
reports uncovered controls before play.

## 2. The `ThemeSnapshot` and role resolution

`src/themes/snapshot.luau` (pure): `resolve(package, themeName, facts, overrides?) ->
frozen snapshot`. Composition happens **exactly once**, in this order:

1. package base metrics for the active theme;
2. display/density policy (ten-foot floors — the existing `displaySize` composition);
3. preferred-text reservation seams (multiplier fact + additive offset, unchanged);
4. accessibility and minimum-hit-target floors (floors clamp **up**, never down);
5. explicit local overrides a screen deliberately requests.

The result rides `environment` as the new fact **`themeMetrics`** (default = the
Studio Neutral snapshot, so every existing screen keeps today's values with zero
opt-in). `env:set("themeMetrics", snap)` is the single atomic metric commit — one key,
one signal, one downstream invalidation.

Blueprint props gain **semantic forms**: `textSize` accepts a typography role name;
`gap`/`padding` accept space step names; composite controls resolve their own
dimensions through `controlSizes` internally. Resolution happens in the renderer's
layout-node construction and the solver's measure path, both reading the snapshot —
the blueprint stores the *role*, so mounted screens re-solve under a new snapshot
without rebuild. `typographyScale`/`typographyPaintScale` keep their existing
measure/paint split; the snapshot supplies the *authored* values those scales multiply.

A **drift lint** (suite-level) fails any reusable framework control that hardcodes a
theme-owned metric literal instead of a role.

## 3. Style Editor sync (the honest workflow)

The plan's **preferred** option, proven mechanically by m4/m6:

- The committed plain-Luau package **seeds** the DataModel package sheet once
  (Step 2's seed-once + stamp-migration semantics, per package).
- After seeding, the sheet is the **only manually editable source**: paint tokens and
  rules (as in Step 2) *and* metric/font tokens, which are now typed attributes on the
  package's theme sheets — **no longer reference-only mirrors**. The old mirror
  attributes are retired.
- The running preview subscribes `GetAttributeChangedSignal` on the active theme sheet
  and re-resolves the snapshot live — supported metric/font edits re-solve without a
  Luau edit.
- **One export action** (`theme_sync`: a scenario action plus a `tools/lune` CLI over
  the serialized dump) writes the deterministic committed package back. A **freshness
  gate** compares sheet values against the committed package and fails with "run the
  sync action" when they drift. Committed Luau is generator-written, so there is never
  a second hand-edited metric source.

## 4. Legal-property boundary (theme linter)

A theme rule may write only: the Step 2 `nativeSheetOwned` paint set, the decoration
slots' image-chrome set (m2), and phantom-modifier chrome. The linter rejects any rule
naming a property whose authority (per `render/authority.luau`) is layout, binding,
presentation, or host — `Size`, `Position`, `Visible`, `Text`, `CanvasSize`,
`AnchorPoint`, and kin can never be themed. This is validated at package compile, not
discovered at runtime.

## 5. Decoration slots and chrome recipes

Slot vocabulary (v1, versioned with the schema): `panel`, `control`, `field`,
`selection`, `divider`, `scrollbar`. A recipe per slot chooses:

- **native**: fills/strokes/corners/shadows/gradients through sheet rules (the Step 2
  vocabulary, extended). Flat themes therefore create **zero** decoration instances.
- **nineSlice**: the adapter creates exactly one non-interactive `ImageLabel`
  decoration child (`Active=false`, full-bleed, z below content), tags it
  `luau-chrome-<slot>`; the package's rules own every image property (m2). The recipe
  declares `contentInsets`, which feed the snapshot and the solver. On asset failure
  the adapter flips a `luau-chrome-fallback` tag (plus `luau-chrome-mute` on the art
  that must not draw over the fill — RS-A16-D5) and the package's declared native
  fallback rules repaint — deterministic, tag-driven, hit geometry untouched.

Recipes cannot insert interactive instances, rearrange content, or carry code.
Gradient support is native **confirmed** (TP-M7): `::UIGradient` rules render as
phantom modifiers, so gradients need no decoration child. `::UIShadow` rules are
**silently accepted and paint nothing** on 0.731 — theme shadows stay on the bespoke
`UIShadow` materialization behind its capability probe (ADR-0018 unchanged), and the
package compiler allowlists pseudo selectors to the proven set
(`::UICorner`, `::UIStroke`, `::UIGradient`), rejecting the rest — a silently inert
pseudo selector is a real hazard class.

## 6. Font-aware measurement

`text_metrics` keys migrate from short font names to canonical descriptor keys
(`family#weight#style`); existing short names remain as aliases for the three known
fonts. Typography roles carry the descriptor; `lineHeight` comes per role from the
snapshot (the global 1.2 factor becomes the default). At install, the controller
preflights every declared font: the adapter measures the reference corpus per
descriptor (`GetTextBoundsAsync`), seeds calibration and the per-word store. Until a
font calibrates, measurement uses the full-em conservative path (never clips), then
the existing premeasure round triggers **one** re-solve. The boot-window defect
([[roblox-text-bounds-boot-window]]) is already handled by session warm-up. Preferred
text stays applied exactly once (unchanged seams, re-proven in the matrix).

## 7. The controller and per-target scope

`src/client/theme_controller.luau`: `install(adapter, package, opts) -> controller`
with `swap(packageOrThemeName)`, `current()`, `inspect()` (active package, schema
version, effective snapshot, fallback state), and `onChange`. Installation
materializes the package's sheet (per-package name `LuauUITheme <id>`, Step 2 host
policy: designer-seeded ReplicatedStorage preferred, runtime creation client-local)
and links it at the target root — per-target isolation per m1. The default shared
`LuauUIStyle` path is unchanged for targets that never install a package. A target
that cannot own its root/link (or runs fallback mode without the capability the
package requires) fails installation with a capability error naming the missing
capability. In explicit-write fallback mode the package still works: its style section
compiles to the bespoke token set and the decoration child is explicit-written — same
data, Step 2's fallback discipline.

**Swap transaction** (m5): one invocation commits `SetDerives`(new theme sheet) +
`env:set("themeMetrics", newSnapshot)` + immediate re-solve → paint and geometry land
in the same engine frame; mount identity, focus, selection, scroll, text entry, and
resource ownership are untouched because nothing is rebuilt. Paint may ride Step 2
transitions (opt-in); geometry never animates independently of the solver.

## Integration rulings (2026-07-25, post-implementation)

- **Fallback targets are metrics-live, paint-at-construction.** `ScreenTarget`
  takes its bespoke style at construction and exposes no runtime style setter, so
  on a non-native target a package install commits the full metric half (all
  layout-affecting values swap live) while the palette applies from construction;
  `controller.inspect().fallback` reports the degradation and the controller calls
  `adapter.setThemeStyle(style)` on every commit for any target that grows the
  seam. Native targets — every shipping path — get the full transaction. Revisit
  only if a real consumer needs live palette swaps on a StyleSheet-less engine.
- **Gradients are palette, not chrome-recipe fields.** A gradient is colour, so it
  must swap with the theme: it rides `style.themes[].extra.chromeGradient.<slot>`
  and compiles to per-theme sequence tokens + `::UIGradient` phantom rules. The
  chrome recipe vocabulary stays `{kind, asset, contentInsets, fallback}`.
- **Metric-derived paint follows live edits via the repaint map.** Corner radii
  and stroke thickness are baked into rules as literals (a number attribute
  cannot be a UDim `$Token`), so `buildPackage` records `metricRuleProps` and the
  controller's commit pushes fresh values onto those live rules — paint follows
  the same sheet edit the geometry does, in the same invocation.
- **`themes.checkCoverage(pkg, declarations)` is the contribution gate.** `define`
  deliberately passes namespaced entries through; a contributed control declares
  its needs (name/kind/section/fields/authority/capability/fallback) and gets a
  complete treatment or a useful pre-play error, never silence.
- **Require-cycle hazard:** `sheet_model` requires the package compiler; nothing
  the compiler needs may live in `sheet_model` (shared values go DOWN into
  `tokens` — see `docs/lessons/lune-circular-require-hangs.md`).

## Review-round rulings and known limits (2026-07-25, four fresh-context reviews)

- **The core typography vocabulary is six roles**: `caption|label|body|heading|title`
  **plus `control`** (button/field text — added so migrating the 18px literals could
  not change effective values). §1's original five-role list is amended here.
  *Amended again 2026-08-02 (F2, the weight channel): **eight** roles, adding
  `strong` and `numeral`. They are OPTIONAL in a package and DERIVED in
  `themes.resolve` when absent — base role's family/style/size/lineHeight, weight
  changed to SemiBold / Bold — so no package's authored metrics or content stamp
  moved and every package published against the six-role list still compiles. The
  reason weight is a role and not a prop is §6's own rule read forwards: a role's
  descriptor reaches measurement AND paint, and `UI.Text.font` was deprecated
  precisely because an authored face reached only one of them.*
- **Floors clamp hit targets, not visuals.** `targetSizes.minimum` governs the
  effective HIT geometry (the renderer's expander), per Step 3's escalated ruling
  ("hit-area expansion, not visual growth"). A theme may draw controls smaller;
  it can never shrink the touchable area below the floor.
- **One live theme controller per environment.** `themeMetrics` is one env fact, so
  a second install on the same env is a capability error, not a silent clobber.
  Two *targets* want two envs (they already own separate adapters).
- **Same package on two separately-enved targets shares its sheet** (name =
  `LuauUITheme <id>`), so its *paint* theme state is shared across them — the same
  class of documented limit as Step 2's shared `LuauUIStyle`. Different packages on
  different targets are fully isolated (TP-M1).
- **Gradient `alpha` is engine `UIGradient.Transparency`** — it fades the parent's
  ENTIRE rendering including its text. The compiler rejects stops above 0.9, and
  reference gradients stay subtle (≤ 0.35). Found live: 0.72–0.96 washes ghosted two
  reference packages end to end.
- **Contributed-control metrics resolve at build time in v1.** A namespaced metric
  reaches the control through its own `resolve()` against the active snapshot; it
  does not yet re-resolve on a swap without a rebuild (the public prop grammar
  validates against the core namespace only). Recorded as a v1 limit.
- **Semantic theme ICON ASSETS are deferred.** v1 themes size icons
  (`controlSizes.*.iconSize`) and theme glyph paint; a semantic icon-asset contract
  (named icons swapped per theme) is future work. TP-A9's "icons" claim reads as
  icon *metrics*, and Parchment's stroke geometry deliberately matches Neutral
  (its borders are painted art, not strokes).
- **Bench pin:** `table-mutation` was re-pinned (+74% p95) with its justification in
  `bench/baseline.json` — theme-aware measurement (descriptor-keyed fonts, per-role
  line height, snapshot-resolved metrics) is real per-measure cost; it was optimized
  from 2.02× first (nested word store, canonical-font memo, per-snapshot metric
  memo). The 1.5× tripwire guards the new pin; device budgets are Step 7's.

## What stays out (non-goals, restated as decisions)

- No theme callbacks or theme-provided component trees.
- No StyleSheet writes to solver-, binding-, presentation-, or host-owned properties.
- No per-view nested theme overrides this stage (per-target only).
- No Sponsor migration; no low-end-device performance claims (Step 7).
- Step 2's authority model, seed-once semantics, tags/state vocabulary, defeat
  detection, and byte-equal fallback are consumed as-is.

## Consequences

- `LuauUI.themes` becomes public surface (`define`, `snapshot`, plus the client
  controller via the client entry); `VERSION` bumps to 0.6.0 at stage end.
- The renderer/presenter stop reading `default_style` directly for metric decisions
  (the presenter's hit-floor/forgiveness constants move to the snapshot).
- The five reference packages (Studio Neutral as base, classic desktop, glossy
  mobile, fantasy parchment, sci-fi HUD) become the compatibility corpus every future
  stage restyles against (roadmap Step 8).
