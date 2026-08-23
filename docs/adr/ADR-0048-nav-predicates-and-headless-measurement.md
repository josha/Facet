# ADR-0048 — The four nav homes as predicates, the `isRegular` trap named around, and a headless measurement entry point

**Date:** 2026-08-23
**Status:** Accepted
**Number:** 0048. 0040 is the unreleased-breaking-changes register; **this
decision adds no row there** — every surface below is purely additive (new
fields, a new pure function, a new top-level module, a new optional
parameter on two RascalRally-internal functions). No documented default
changed value, no prop flipped to required, nothing was removed.
**Companions:** [ADR-0023](ADR-0023-declared-content-composition.md) (the
height half `adaptive.conditions` already carries, extended here),
[ADR-0027](ADR-0027-platform-chrome-band.md) (`navPlacement`'s own sibling
policy, `platformChrome`), [ADR-0038](ADR-0038-theme-tag-vocabulary.md) /
`src/render/tag_sync.luau` (the "pure module a headless spec can require
alone" precedent `src/measure.luau` follows).
**Home:** `src/layout/adaptive.luau` (`conditions`, `sizeClassAtLeast`),
`src/layout/text_metrics.luau` (`AVG_GLYPH_FRACTION`, now exported),
`src/measure.luau` (new), `src/init.luau` (`text.AVG_GLYPH_FRACTION`).
**Guards:** `tests/adaptive.spec.luau`, `tests/measure_entry_point.spec.luau`,
and — in RascalRally — `tests/hud_zone_model.spec.luau`.

## Context

`framework-gaps-phase2` audit §7 and §11: two small, disjoint gaps in the same
wave-2 round.

**§7 — `adaptive.conditions` stops one field short, twice.** `navPlacement`
is the app-level tab/sidebar policy (`"bottomBar" | "bottomBarCompact" |
"topBar" | "sidebar"`), but `conditions` shipped no boolean predicates over
it — only the raw string. `src/controls/tab_view.luau` already computed
these privately, as `isPlacement(name)`, for its own internal use; two
reference apps hand-rolled the identical `use(navPlacement) == "sidebar"`
memo at the APP level, because the framework had nowhere to promote it to.
`p1_glade` built a whole four-memo placement ladder before the TabView
migration retired most of it, leaving one; `p3_sipworks/views/shell.luau`
built `app.navSidebar` the same way, independently.

Separately: `isRegular` names the MIDDLE size class only — `isCompact`,
`isRegular`, `isWide` partition `sizeClass` three ways — but it READS as "at
least regular" and three of five reference apps wrote `not
use(conditions.isCompact)` for exactly that question, because the word the
API offers behaves wrong on the widest screen there is (`isRegular` is FALSE
on `wide`, i.e. a desktop). One of the three, `p3_sipworks`, spent six lines
of comment explaining the trap before working around it by hand.

**§11 — the measurement engine is unreachable from a headless-pure model.**
`api.md`'s own `text` section names the anti-pattern verbatim: *"the
alternative is what consumers were writing instead — a character count times
a guessed average glyph width, which is the measurer's own conservative
fallback."* `src/layout/text_metrics.luau` IS that measurer and has ZERO
requires and ZERO `GetService` — but the only PUBLISHED route to it is
`Facet.text` via `src/init.luau`, which makes 65 `@self` requires and
transitively pulls `src/client/*`. RascalRally's `HudZoneModel.fitSize`
carried exactly the anti-pattern api.md describes, as `GLYPH_EM = 0.62`, a
hand-copy of `text_metrics.luau`'s private `AVG_GLYPH_FRACTION`, under a
comment that misidentified it as *"Gotham Bold cap advance"* while the font
two lines down is `BuilderSans` — a number about no font at all, since the
fallback is uniform across every uncalibrated font.

## Decision

### 1. `conditions.navSidebar` / `navTopBar` / `navBottomBar` / `navBottomBarCompact`

Four `Readable<boolean>`s, each `navPlacement == <that value>` — the exact
equality-check idiom `tab_view.luau`'s `isPlacement(name)` already used,
PROMOTED rather than reinvented. `p1_glade` and `p3_sipworks/views/shell.luau`
now bind these instead of building the memo themselves.

### 2. `adaptive.sizeClassAtLeast(value, target)` and `conditions.atLeast` / `isCompactOnly` / `isRegularOrWider`

`sizeClassAtLeast` is the pure, ranked form (`compact < regular < wide`),
matching this module's PURE/REACTIVE-pair architecture (`sizeClass` /
`heightClass` / `navPlacement` all have a pure half `conditions` delegates
to). `conditions.atLeast(target)` is its reactive binding, general over any
target class. `isRegularOrWider` is the named spelling of `atLeast("regular")`
— the question every hand-rolled `not isCompact` site actually meant.
`isCompactOnly` is `isCompact` ITSELF, under the name that pairs with
`isRegularOrWider` so their opposite relationship reads from the names alone
— reuses the existing memo, not a second fact.

`p2_cartwheel`, `p3_sipworks/init.luau` and `p5_wardrobe` each had exactly
one `not use(conditions.isCompact)` site; all three now bind
`isRegularOrWider` (or, for `p3_sipworks`, `app.cond.isRegularOrWider`
directly replacing the hand-built `app.notCompact` memo) instead.

`adaptive.conditions(...)` now builds **eighteen** memos on a call with no
`opts.scope` passed (was twelve): the four nav predicates plus
`isRegularOrWider`. `isCompactOnly` aliases the existing `isCompact` memo, so
it adds no nineteenth. `api.md` and the function's own comment are updated to
the new count.

### 3. `src/measure.luau` — the headless entry point

A one-line republish (`return require("./layout/text_metrics")`), in the
idiom `src/render/tag_sync.luau` set this campaign: a pure module, ZERO
requires of its own beyond the one dependency-free target, so a spec (or any
headless consumer) can `require` it alone and never touch `src/init.luau`'s
65 `@self` graph. It sits OUTSIDE the `Facet` table by design — reaching it
never runs `init.luau`'s module function — so `check_surface_ledger`'s
coverage rule (which walks that table, not the filesystem) does not apply to
it, exactly as it does not apply to `tag_sync.luau`. `docs/MAINTAINERS.md`'s
"layout" row and `docs/reference/api.md`'s `measure` section are its
documentation of record.

`text_metrics.AVG_GLYPH_FRACTION` is exported for the first time (it was a
private local before this round), so `src/measure.luau` and `Facet.text`
(next) both republish the SAME value rather than each defining their own.

### 4. `Facet.text.AVG_GLYPH_FRACTION` — the same constant, for a caller that already holds `Facet`

A second route to the identical number, for the (more common) case where the
consumer already pays for the full `Facet` table — a live client script, for
instance — and just wants the fallback fraction as data rather than a
hand-typed literal. Both routes read the same module-level number in
`text_metrics.luau`, so there is exactly one source of truth regardless of
which a consumer reaches.

### 5. RascalRally: `HudZoneModel.itemCaption` / `itemNameFlash` take an optional `fallbackFraction`

**NOT a `require` of `src/measure.luau` — tried, and measured live to be the
wrong shape for this specific consumer.** `HudZoneModel.luau` is a Rojo
SIBLING of `Facet` (both `default.project.json` and `debug.project.json`
mount `code/src/shared` and `../../../GameStudio/ui/Facet/src` as direct
children of `ReplicatedStorage`), and a relative-string `require` from there
into Facet's tree resolves by FILE-SYSTEM depth under Lune (five `..`
segments reach `GameStudio/ui/Facet/src` on disk) and by INSTANCE-TREE depth
on the live, Rojo-synced place (two `..` segments reach the same sibling
folder — `Shared` and `Facet` are each one hop under `ReplicatedStorage`).
Measured live in Roblox Studio, on the connected RascalRally place:

```
error requiring "../../../../../GameStudio/ui/Facet/src/measure": could not
get parent of component ".."
```

No single literal string satisfies both runtimes for this pair of mounts.
Rather than fight that (an environment-sniffing branch, or a `.luaurc` alias
scheme unverified against this Lune install), `HudZoneModel` keeps its
own-header promise — "no Roblox types, runs under Lune with zero mocking,
requires nothing Facet-shaped" — and takes the number as DATA instead:
`itemCaption(slotW, slotH, longestLabelChars, longestLabel, fit,
fallbackFraction?)` and `itemNameFlash(cue, longestLabelChars, longestLabel,
fit, fallbackFraction?)`, exactly the same dependency-injection idiom the
file already used for `fit` (`Facet.text.size`, injected by the one live
caller that has it). `ItemFx.luau` — the sole caller of both — now passes
`Facet.text.AVG_GLYPH_FRACTION` alongside the fitter it already passed.

The module's own default (`GLYPH_EM`, unchanged in value at `0.62`, exported
as `HudZoneModel.FALLBACK_GLYPH_FRACTION`) stays as the last-resort constant
for a caller with nothing to inject — headless tests among them — but is now
PINNED equal to Facet's `text_metrics.AVG_GLYPH_FRACTION` by
`tests/hud_zone_model.spec.luau`, so a silent drift between the two numbers
fails the suite instead of shipping quietly wrong. This is the practical
reading of gap 11's own "and/or export the fallback constant" clause: both
halves of that "and/or" are built (the entry point, AND the exported
constant), and RascalRally's actual migration uses the constant via
injection, verified live to be the one of the two shapes this specific
cross-repo, cross-runtime consumer can safely take.

## What is breaking, and what is not

**Nothing is breaking.** Every new field, function and parameter above is
additive: `adaptive.conditions()`'s return grows six new keys, none renamed
or removed; `adaptive.sizeClassAtLeast` and `src/measure.luau` are new
exports with no prior name to collide with; `text.AVG_GLYPH_FRACTION` is a
new field on an existing table; `HudZoneModel.itemCaption`/`itemNameFlash`
gain a sixth, OPTIONAL, trailing parameter — every existing call site
(including the four that pass no `fallbackFraction`) behaves byte-identically
because `fallbackFraction == nil` resolves to the same module default the
function always used. `ADR-0040` gets no row.

## Consumers

`examples/reference/p1_glade/init.luau`, `p2_cartwheel/init.luau`,
`p3_sipworks/init.luau`, `p3_sipworks/views/shell.luau`,
`p5_wardrobe/init.luau` — all five bind the new predicates in place of the
hand-rolled memo they built before. `games/RascalRally/code/src/shared/
HudZoneModel.luau` and `src/client/ItemFx.luau` — the fallback fraction is
now sourced, not copied, and the drift between them is now a test failure
rather than a silent possibility.

**Registry evidence, recorded per the round's own instruction:**

- **Teaches-wrong #7** (raw `conditions.viewportWidth`, cited against
  `examples/gallery/scenarios/composition.luau:67`) does **NOT** dissolve
  into gap 7. That site clamps a FIXED PX OFFER against the raw viewport
  extent (`math.min(px, have)`) — genuine pixel arithmetic no boolean class
  predicate (this round's `navSidebar`/`isRegularOrWider`/`atLeast`, or any
  prior `isCompact`/`isRegular`/`isWide`) answers. It stays open.
- **Item 31** ("a pure viewport-fact simulator for benchmarks") does **NOT**
  dissolve into gap 11's entry point — that item is about VIEWPORT facts
  (breakpoints, size/height class), not TEXT measurement, a genuinely
  different capability. Demonstrated, not built: `src/layout/adaptive.luau`'s
  PURE half (`sizeClass`, `heightClass`, `navPlacement`, `orientationFor`,
  `columnsFor`) is ALREADY independently requireable on the same grounds this
  round proved for measurement — it requires only `spec_guard` ->
  `text_distance`, neither of which calls `GetService` or touches `game` —
  proven live under Lune in `tests/measure_entry_point.spec.luau`. What is
  missing, and what keeps the item open, is a NAMED entry point and an actual
  benchmark harness built against it; nobody has published or used the
  capability as one yet.
- **Item 32** ("a headless platform-band model") stays open, untouched by
  this round. The band-fact geometry lives in `src/env/environment.luau`
  beside its `GuiService` reads; no module owns just the pure geometry the
  way `text_metrics.luau` owns pure measurement. Extraction is unscheduled —
  the item's own "Coupled with" note already points it at gap 9
  (`platformChrome`), not gap 11.

## Alternatives, and why not

**A `.luaurc` alias for a cross-repo Facet require**, resolved identically by
Lune and by Rojo's live require-by-string. Plausible in principle — Rojo does
read `.luaurc` aliases — but UNVERIFIED against this repo's actual Lune
install, and a wrong guess here fails exactly the way the plain relative
string did: silently, for one runtime and not the other, discoverable only by
running both. Not worth the risk for two call sites when injection is a
strictly safer, already-measured-working alternative with an equally small
footprint.

**A live `require(game:GetService("ReplicatedStorage").Facet...)` guarded by
`if game then`.** Works live, harmless under Lune (the branch never
executes since `game` is undefined) — but reintroduces exactly the
`GetService`-shaped code `HudZoneModel`'s own header exists to keep out, for
a value the file's ONE caller already has for free. Fighting the file's own
stated architecture for a marginal win the caller-injection shape gets
without it.

**Threading the setter as module-level mutable state**
(`HudZoneModel.configureFallbackGlyphFraction(value)`, called once at boot)
instead of a per-call parameter. Considered and rejected: it adds a
boot-ordering hazard ("has anyone called configure yet?") a pure module
should not have, for no benefit over the two-call-site parameter thread
`fit` already established the idiom for.
