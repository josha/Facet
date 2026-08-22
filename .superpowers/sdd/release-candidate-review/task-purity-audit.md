# Declarative-purity audit — the consumer corpus

**Charge (game director, 2026-08-21):** *"The showcase code should not be doing layout
solving — the framework should be doing that. Our code should look conceptually akin to
SwiftUI where we're just specifying declarative info, theme/color info, behavior, and app
logic. Is there anything we need to cleanup to use the framework right (or that needs to
move to the framework)?"*

**Seat:** read-only audit. No file in either tree was modified; this report is the only
artifact. Audited against the working tree. The two in-flight fix rounds moved during the
audit and touched `src/blueprint.luau` and `src/blueprint_schema.luau` — two files this
report cites as answer key — so every cited line in them was re-verified by diff against
`HEAD` at commit time and is **byte-identical**. No corpus file was under churn.

**Corpus:** 165 example files (~70,000 lines) across `examples/gallery/**`,
`examples/reference/**`, `examples/performance/**`, `examples/themes/**`,
`examples/table_phaseb/**`; plus Rascal Rally's 43 Facet-consuming client files and a
sample of its 48 `facet_*` contract specs. `src/**` was out of scope except as the answer
key. Every scenario file was assigned; coverage was verified mechanically.

---

## The answer in one paragraph

**The showcase is not imperatively positioning anything.** Across ~70,000 lines there are
exactly five direct Instance geometry writes, all inside `foreign_instances.luau`, whose
subject *is* raw Instances. Structurally the corpus is declarative. The impurity is of two
other kinds, and they have different fixes:

1. **It spends un-named numbers.** 539 raw literals sit on the three props the theme system
   owns — 40% of all such props in the teaching corpus. This is one mechanical sweep plus a
   one-line lint scope change, because the lint already exists and already passes.
2. **It re-derives a thin layer of missing *nouns*.** The framework has excellent
   primitives and is missing about a dozen small constructs one altitude above them. Every
   wheel reinvented in this corpus — and several were reinvented four and five times
   independently — sits at exactly that altitude. That layer is the director's real ask.

Two results were genuinely surprising. First, **the shipping game is cleaner than the
showcase that teaches it** (22% raw vs 40%) — the teaching corpus is the offender. Second,
the audit was scoped as a style review and **found seven live defects**, including three that
are device-visible in shipping game screens and one class — hand-copied text arithmetic —
where three of four copies are measurably wrong and under-reserve by up to 1.5× on a
television. Those are in the DELETE list, but they should be treated as correctness work.

---

## Per-class counts

Consolidated across nine slices. "Sites" counts individual code locations; several DELETE
rows in the sponsor and adaptation slices cover multi-site patterns.

| Class | Findings | What it means |
|---|---:|---|
| **DELETE** | **161** | The framework default already answers. Cited seam required. |
| **MOVE** | **97 sites → 34 distinct candidates** | Real capability gaps. |
| **DECLARATIVE-OK** | **~76** | Derivations from declared tokens/props. SwiftUI-equivalent. |
| **PROBE-EXEMPT** | **~50** | Instrumentation that must read geometry. **13 flagged** as mistakable for example code. |

Counting note, stated plainly: a "finding" is a matrix row, and several rows cover a
repeated pattern across one file. Expanded to individual code locations the DELETE class is
roughly 600 sites, of which **539 are the single raw-literal class** measured below.
Excluding that class, DELETE is ~120 rows of genuine one-by-one API misuse. Nine slices
contributed: hud 16, adaptation 31, sponsor 13 (~43 sites), virtualization 6, performance 2,
reference 19, client+examples 7, misc 14, RR-Sponsor 43, RR-shared 6.

The MOVE dedup matters: **five separate slices independently filed the same
`viewportExtent` self-measurement gap**, and the app-metric-namespace gap was filed four
times. Those repetitions are the ranking signal, not noise.

### The raw-literal class, measured

Every one of these props accepts a theme-metric **name string**, and
`src/blueprint.luau:78-79` states the consequence outright: *"a literal number opts that
value OUT of theming, which is the documented escape hatch."*

| Prop | Named token | Raw number | % raw |
|---|---:|---:|---:|
| `gap` / `rowGap` | 332 | 204 | 38% |
| `textSize` | 337 | 226 | 40% |
| `padding` | 130 | 109 | 46% |
| **examples/ total** | **799** | **539** | **40%** |
| **Rascal Rally (production)** | **63** | **18** | **22%** |

### Clean negatives — prior rounds held

Reported because they are load-bearing evidence that this corpus is maintained:

- **`adaptive.conditions` scope: 25/25 call sites pass `opts.scope`** (23 examples, 2 RR).
  The twelve-memo leak class stayed fixed. Zero regressions.
- **Imperative positioning: essentially zero.** 5 sites, all in the fixture about raw
  Instances.
- **Hand-rolled breakpoints: one, corpus-wide.** The adaptation slice — where they would
  most likely hide — has zero. The single exception is
  `with_animation.luau:110,620-624`: `TWO_COLUMN_MIN_WIDTH = 520` plus
  `return if w >= TWO_COLUMN_MIN_WIDTH then "x" else "y"`, which re-implements
  `adaptive.axisFor` line-for-line — and `axisFor(width, { stackAbove = 520 })` exists for
  exactly that override (`src/layout/adaptive.luau:230-233`). Its own sibling fixtures
  (`canvas_group`, `nested_compositing`) already bind `conditions.axis` correctly, so this
  file is stale against its neighbours rather than representative.
- **All 13 theme packages are clean.** 4,099 lines read against
  `src/themes/snapshot.luau`: every package authors base metrics (which *is* the
  declarative act for a theme) and defers every derived section — `space.gutter`,
  `targetSizes.minimum` flooring, `controlSizes`, per-family `controls`, `metrics.tenFoot`,
  contrast math — to the framework. Zero hand-derivation of the ten-foot ladder anywhere.
  `classic_desktop.luau:130-136` argues its one override explicitly, which is the correct
  documented-exception shape.
- **The five `ref_*.luau` scenario wrappers are byte-identical delegation shims** (verified
  by diff, modulo module name and title). No wrapper-side viewport or host sizing.
- **The two named precedents are fully closed.** `row_actions.luau`'s "336 window" and
  `ROW_HEIGHT` are now `itemExtent = "measured"` + `estimatedItemExtent` +
  onGeometry-fed window + a `themeMetrics`-reading `vlistGap()`.
  `variable_extents.luau`'s `viewportHeight - 210` is gone, replaced by
  `Facet.text.lineBox`.
- **`itemExtent` usage is contract-correct.** `estimatedItemExtent` appears only ever
  beside `"measured"`; `"cards"` is used where the card paradigm applies; the
  pitch-as-extent anti-pattern api.md warns about appears **nowhere**.
- **Rascal Rally's results surface already migrated.** `ResultsLayoutModel.compute`'s
  collapse ladder and its `vpH < 520` threshold are dead on the Facet path — the
  declaration in `ResultsScreen` *is* the collapse policy, and the spec proves it by
  injecting a model whose `compute` throws. It reads `composition().unshown` rather than
  re-deriving elision. This is the model migration; the HUD half is what did not get it.
- **The game-side contract specs pin relationships, not device pixels.** Sampled six
  `facet_*` fixtures: they pin solve counts, call counts, collision counts, rect identity
  under a differential, and derivation *ratios* (44 × 1.5 = 66). None exhibits the
  "336 window" failure mode of baking a solved pixel into an assertion.

---

## The ranked MOVE list — the director's real ask

Thirty-one capability gaps were identified. These are the ten that matter, ranked by
breadth of independent rediscovery, then by blast radius.

### 1. There is no app-namespace channel in the metric ladder

**Rediscovered independently FOUR times**, twice in the showcase and twice in production —
the strongest signal in the audit.

- `examples/reference/p2_cartwheel/content/metrics.luau:4-10` — *"THE SPEC ASKS FOR
  `metrics.cartwheel.*` IN THE TOKEN SCHEMA, AND A PROOF CANNOT PUT THEM THERE."*
- `examples/reference/p3_sipworks/content/metrics.luau:4-11` — *"The spec states these as
  dotted theme-metric names (`metrics.sip.rowArt`). They cannot be."*
- RR `FacetSponsor/TableMetrics.luau` — 1,392 lines: ~60 dotted `metrics.sponsor.*` names
  (most marked PROPOSED), a `DEFAULTS` table of frozen legacy pixels, and a
  `resolve(snapshot)` that does a dotted lookup and falls back.
- RR `FacetSponsor/ResultsParts.luau` — `METRIC_NAMES` / `METRIC_DEFAULTS` / `metrics()`,
  the same shim shape a second time.

Verified why they are blocked: `snapshot.isMetricPath` validates a name against
`snapshot.neutral()` (`src/themes/snapshot.luau:1638-1658`), so a name no shipped package
declares is a **construction error**; `themes.resolve` rejects unknown override and
`metrics.tenFoot` names (`:1502`, `:1539`); and the ten-foot density ladder walks a closed
hardcoded set, `DENSITY_LENGTH_SECTIONS` (`:430`, checked at `:567`) — so even a smuggled-in
section would receive **no distance transform**.

Consequence: ~100 structural numbers across the corpus sit outside every theme, outside
the ten-foot ladder, and outside a package swap. Two apps then re-implemented the distance
transform by hand (`metricScale` multiply, `p2/gallery.luau:319-325`,
`p3/metrics.luau:96-104`), one concluding in a comment that *"a name would be better"* —
and p2 applied it to `tileMin` while leaving `chartH`, `heroH` and `previewMin` behind, so
the ladder is now half-applied inside a single flagship proof.

**Home:** `src/themes/snapshot.luau` + `src/tokens/`.
**Shape:** a reserved `app.*` namespace — `tokens.compile{ app = { tileMin = 96 } }` — that
`isMetricPath` accepts and the distance transform walks, so `px = "app.tileMin"` works
everywhere `px = "iconSizes.large"` does. **This one change deletes four shim files.**

### 2. `ViewThatFits` has no value-form, and its natural spelling silently breaks it

Two defects in one construct.

**(a) The `hug` trap.** A `hug` candidate caps at the offer, so it can never report "does
not fit" and the ladder pins its first rung forever. The solver only tests `w <= availW`
(`src/layout/solver.luau:659-660`) and **never refuses hug**. `hug` is the instinctive
spelling everywhere else in the framework. Four consumer files independently learned this
the hard way and defend against it in prose: `showcase_chrome.luau:467` (which names it
*"the p4_foyer trap"*), `p3_sipworks/views/shell.luau:119`, `p1_glade/init.luau:822`, plus
demo_picker/theme_picker. **A silent wrong result reached by writing the obvious thing.**

**(b) No readable output.** The consumer often needs the fit *decision* as a value — to
reserve space in a sibling, to place or skip a minimap. api.md frames the split itself
(*"`adaptive.conditions` is viewport-relative, while this measures the container"*) but
`conditions` returns Readables and `ViewThatFits` returns a subtree. **There is no
container-relative Readable.** RR's `HudZoneModel.sponsorTopStrip` papers over exactly this
with a hand-summed `GROUP_NATURAL_W = 100 + 10 + 200` mirrored from another file and a
`TOPBAR_SLACK = 24` fudge whose own comment admits it is guarding a guess.

**Home:** `src/layout/solver.luau` + `src/blueprint.luau`.
**Shape:** refuse `hug` on a `ViewThatFits` child at construction, loudly; and add a
container-relative `fits` Readable so the decision can be consumed as a value.

### 3. A box cannot declare its height in CONTENT terms

`UI.Composition` already has the vocabulary — Region floors are `{ lines = n }` /
`{ targets = n }` — and it is **locked inside Composition**. Outside it, a scroller or panel
viewport gets pinned in px next to content that scales with text preference and the ten-foot
ladder. Four sites in the adaptation slice alone (`flow_wrap.luau:57` with 14 apologetic
lines, `keyboard_navigation.luau:119`, `native_style.luau:125`, `preferred_text.luau:105` —
the last in the very fixture whose subject is text growth).

**Home:** `src/blueprint_schema.luau` DIM_TYPES.
**Shape:** `height = { type = "content", lines = 4 }` /
`{ type = "content", rows = 4, of = "controlSizes.compact.height" }`, resolving through the
same text facts `Facet.text.lineBox` already uses.

### 4. `newVirtualList` cannot measure the box it was given, on either axis

`viewportExtent` is asserted required (`src/controls/virtual_list.luau:672-679`) with no
self-measuring form, and the horizontal cross axis is documented as the consumer's job
(`:687-693`: *"wrap the list in a box of the height you want"*). `card_rail.luau` pays for
both with ~55 lines, four module constants, a raw-viewport read, and a reach into
`chromeInsets`/`chromeOutsets` — which appear **nowhere in api.md**. `sponsor_drop` and
`sponsor_list` independently hand-roll
`math.clamp(math.floor(h * fraction_or_minus_inset), min, max)` for the same reason.

**Home:** `src/controls/virtual_list.luau`.
**Shape:** `viewportExtent = "auto"` (measure the host, the way `ViewThatFits` measures per
container) and `crossExtent = "hug" | "measured"`.

### 5. `VirtualList`/`VirtualGrid` gaps refuse a theme token — and this *is* the vlistGap bug

Verified asymmetry:

- `Table.rowGap` is `(number | string)?` — *"a theme metric name ('xs'..'xl' or a dotted
  path)"* (`src/controls/table.luau:200-201`). `UI.Grid.rowGap` likewise.
- `VirtualList.rowGap` refuses strings (`src/controls/virtual_list.luau:659-666`).
- `VirtualGrid.rowGap` refuses strings (`:392-397`); **`VirtualGrid.gap` refuses even
  Readables** (`:405-409`).

So a consumer wanting a theme-tracking gap on a virtualized list has exactly one legal
path: hand-write a live-reading memo. That memo is `row_actions.luau:592`'s `vlistGap()` —
the *precedent fix itself*. The framework required the code the precedent was about.

**Home:** `src/controls/virtual_list.luau`, `src/controls/virtual_grid.luau`.
**Shape:** `rowGap: (number | string | Readable<number>)?`, matching Table. Deletes the
`vlistGap()` boilerplate and the `CELL_GAP`/`LINE_GAP` literals in one move.

### 6. `TabView` needs per-placement accessory slots

The framework shipped `Facet.Controls.TabView` *precisely* to kill the four-`When` nav
wheel — `p4_foyer/init.luau:817-820` says so. But its Spec (`tab_view.luau:150-171`) has no
leading/trailing/foot slot, so only the app whose chrome never moves could adopt it. p4 did.
p1 (wordmark at the rail's head) and p3 (a search field with *three* homes, plus a stamps
pocket pushed to the sidebar's foot) still carry ~300 hand-built lines each. **The examples
directory now ships two contradictory teachings of the same thing.**

**Home:** `src/controls/tab_view.luau`.
**Shape:** `Spec.accessories = { head?, foot?, trailing?, aboveBar? }`, each a
`(placement, scope) -> Blueprint?` factory, so the placement the control already resolved
decides which slots mount.

### 7. `adaptive.conditions` stops one field short, twice

**(a) No `navPlacement` predicates.** `conditions` ships `isCompact`/`isRegular`/`isWide`,
`isShort`/`isTall`, `isLandscape` — but `navPlacement` alone is a bare string. Both apps
that consume it hand-roll 4–5 identical `== "sidebar"` memos (`p1:750-761`,
`p3/shell.luau:482-498`). `tab_view.luau:381` already computes these privately.

**(b) `isRegular` means the middle class, and nobody wants the middle class.** Three of five
reference apps write `not use(conditions.isCompact)` (`p2:195`, `p3:170`, `p5:1009`); p3
spends six lines explaining that `isRegular` is false on a *desktop*, so the two-pane layout
would vanish on the widest screen there is. **The word the API offers reads correct and
behaves wrong on the largest device in the matrix.**

**Home:** `src/layout/adaptive.luau:411`.
**Shape:** add `navSidebar`/`navTopBar`/`navBottomBar`/`navBottomBarCompact`; add
`conditions.atLeast("regular")` plus the spellings `isRegularOrWider`/`isCompactOnly`.

### 8. Per-lane exclusion for app chrome — the HUD's 150 lines

A `Composition`'s lane band is one rectangle, so a host's own chrome row (covering some
columns and not others) cannot be reserved around declaratively. `hud.luau` spends ~150
lines plus a sampled monotone latch and a hand-built `reachEpoch` dependency token doing it —
and records that leaving the platform insets out of that token latched a wrong answer for a
whole epoch on a real device. `src/env/environment.luau:420` documents the punt in as many
words: *"which is what lets a consumer reserve around it per column."*

This is also the **reach-epoch precedent, still open and one bug-fix larger.** A consumer
maintaining a manual dependency set for a framework convergence loop is the smell.

**Home:** `src/layout/composition.luau` (lane pass).
**Shape:** `UI.Composition{ exclusions = Readable<{Rect}> }` — solved lanes intersect the
rects and start below any that overlap their own measured x-range. The framework already has
both inputs (`platformChrome.rects` and the lane rects it computes).

### 9. `rootPolicy` is a three-value enum guarding a four-case world

`platformChrome.bandInsets` exists and api.md says it is *"what a surface that means to ride
the band applies instead"* — but **no policy applies it**. So a band-riding surface must
present `edgeToEdge`, which drops all four insets, and re-spend them by hand. `hud.luau`
does, at `:564-600`, `:646-654`, `:956-986` — and its hand-rolled version is *strictly
better* than the shipped policy, because it also floors each edge against the theme gutter,
which `deviceSafeContent` does not. **When the consumer's hand-rolled version beats the
shipped policy, the policy is the bug.**

RR hit the same wall twice more: `HudZoneModel.sponsorTopStrip` and `GearDockModel` both
hand-derive topbar docking from `GuiService.TopbarInset` with manual change-listeners.

**Home:** the `rootPolicy` resolver in `src/present/*`.
**Shape:** add `rootPolicy = "bandSafeContent"`; inset `composition.ZONES.topbar` to
`platformChrome.band` in the solver; floor every policy at `themeMetrics.space.gutter`.

### 10. `Facet.text` is a function where consumers need a prop — and four copies are wrong

**This is the highest-severity MOVE in the audit**, because unlike the others it is shipping
wrong pixels today.

api.md's own `text` section confesses the scale of it: *"A survey run in 2026-08 found seven
near-duplicates of that formula in this repository and exactly one of them correct."* The RR
Sponsor package alone still holds **four** copies of the fit/line-box arithmetic —
`RolePickScreen:186`, `StartCountdown:89`, `ResultsParts:208`, `TableMetrics.mapTagReserve` —
each mirroring the framework's private `AVG_GLYPH_FRACTION = 0.62` and
`LINE_HEIGHT_FACTOR = 1.2` from `src/layout/text_metrics.luau` under comments that name the
source ("*The framework's own two text constants, mirrored with their source*").

**Three of the four are wrong.** `ResultsParts.lineBox` uses `1.25` while the same file
declares `LINE_HEIGHT = 1.2` sixteen lines later. None applies
`max(typographyScale, typographyPaintScale)`, so every band derived from them
**under-reserves by up to 1.5× on a ten-foot display**. api.md:4188 cites *"the production
role-pick CTA"* as the very bug the `offset` parameter was added for — and the production
role-pick CTA still does not call `text.fit`.

The imperative route won because it is *shorter*: a char count times a constant is one line,
while `text.fit` costs a memo, a `use`, an env read and a font name — **per site**. The
counter-example proves it: `ResultsParts` migrated only after being burned, and only because
someone threaded `Facet.text.size` in as an injected model (`ResultsModels.luau:37`).

**Home:** `src/blueprint.luau`.
**Shape:** `textSize = "fit"` (optionally `{ fit = { cap = "title", floor = 12 } }`),
resolved **inside the solver**, where the box, the font, the scale and the offset all
already are. That is the only place the four constants cannot be copied wrong.

### 11. The measurement engine is unreachable from a headless-pure model

api.md's `text` section names the anti-pattern verbatim: *"the alternative is what consumers
were writing instead — a character count times a guessed average glyph width, which is the
measurer's own conservative fallback."* RR's `HudZoneModel.fitSize` still carries exactly
that, with `GLYPH_EM = 0.62` — a copy of the framework's private
`AVG_GLYPH_FRACTION = 0.62` (`src/layout/text_metrics.luau:59`) — under a comment that
misidentifies it as *"Gotham Bold cap advance"* while the font two lines down is
`BuilderSans`.

Verified it is not laziness: `text_metrics.luau` has **zero requires and zero `GetService`**
(fully Lune-safe), and Facet *is* mounted at `ReplicatedStorage.Facet` beside `.Shared`. But
the only public route is `Facet.text` via `src/init.luau`, which makes 65 `@self` requires
and transitively pulls `src/client/*`, which do call `GetService`. A model that must run
headless therefore cannot take the dependency.

**Home:** `src/init.luau` packaging.
**Shape:** publish the measurement engine as an independently-requireable entry point (and/or
export the fallback constant), so a pure shared model can depend on measurement alone.

### The remaining 23, in brief

`composition.ARRANGEMENTS` has no lead-first two-lane preset (six re-authorings across three
apps, one shadowing the preset's own name) · no navigation-bar chrome seam (four hand-built
back+title bars) · no dim shorthand (`{type="fill",weight=1}` appears **326 times**; two apps
built private DSLs) · a node cannot hand back its own mounted path (p5 substring-scans
`adapter.paths()` because `UI.When` prefixes it) · `offset` takes numbers, not Readables,
while `scale`/`rotation` are reactive — which pushed a whole file to imperative
`setPresentationTransform` · `Table` has no content-hugging height and no header+body-union
column sizing (forcing a hand-measured 144px in a tutorial) · no `"intrinsic"` minimum
outside `UI.Grid` · `surface = "badge"` carries no intrinsic size · `newMenu.presentation`
is a static string · construct lifecycle facts are `dump()` snapshots, not Readables (two
files independently invented the same write-skip poller) · a control's native scroll must be
bound imperatively after `present` · `presenter.raise` (re-band a live surface without
dismiss+re-present) · no priority band for app-level global chrome · `VirtualGrid` has no
measured line-extent mode · `VirtualGrid.dump()` hides the per-lane cross extent ·
`composition.minimumOffer` · `resolution.simplified` beside `unshown` · `UI.Path.thickness`
has no metric channel · a derived `effectiveSafeInsets` fact · a pure viewport-fact
simulator for benchmarks · a headless platform-band model · a transformed-footprint
reservation (teaches-wrong 12) · a theme-owned decorative-chrome floor (two fixtures
independently hardened the same 40px against the overflow sweep) · a topbar band
*occupancy claim*, so one game surface can tell another it is already sitting there ·
`platformChrome` as a rect rather than only insets · a node-relative `screenRectOf` ·
`registry.ghostRect()` · `armStaging` as a declaration rather than a coordinate ·
`list.api.positionOf(key)` · `Facet.EXIT_CAP_SECONDS` and
`interactionTokens.contextPriority` (two framework constants currently known to consumers
only by comment).

---

## The ranked DELETE list

### 1. Raw literals on theme-owned props — 539 sites, 40% of the teaching corpus

The largest single class in the audit, and the cheapest to fix. `gap`, `rowGap`, `padding`,
`margin`, `offset` and every dim `px`/`min`/`max`/`preferred` accept a metric name;
`textSize` accepts a type role. Verified at `src/blueprint.luau:80,104,176`, resolved at
`src/render/layout_node.luau:340-345`.

The corpus convicts itself: `hud.luau` uses metric names in five `px` fields and
`gap = "s"` in its presenter opts, then writes raw integers in 27 stack gaps and paddings.
`callout.luau` writes `gap = "xs"` in a helper at line 102 and `gap = 8` in the page at line
250. **No reader can tell which is the house style.** See §"teaches wrong" #1 for the root
cause and the one-line fix.

### 2. Hit-target floors re-implemented by hand — ~15 sites

`height = { type = "minMax", min = 44 }` appears at eight sites in `adaptive_controls.luau`,
four in `composition.luau`, twice in RR's `FacetSettingsScreen.luau` (as `px = 56`), and once
in RR's `FacetSettingsGui.luau` (as `GearDockModel.tuning.minTouch`). The framework already
enforces the floor — `src/class_contract.luau:152 Button.minHitSize = 44` via
`src/render/layout_node.luau:187 effectiveHitFloor` — and for a *visual* floor the spelling
is `"targetSizes.minimum"`, **which ten-foot-scales to 80 and a raw 44 does not.**

### 3. `minColumnWidth` raw pixels — 17 sites, stale as of today

`"intrinsic"` became the **default on 2026-08-21** (`src/blueprint_schema.luau:1508-1520`),
and its own comment calls a px minimum *"a guess about a font."* The corpus still carries 17
raw-px sites against 14 `"intrinsic"` — six of them the identical `104` across unrelated
sponsor fixtures. `src/layout/grid.luau:103` names one of these exact numbers (132, in
`preferred_transparency.luau`) as the font-guess defect.

### 4. Deprecated `rowHeight`/`viewportHeight` aliases — 34 call sites across 8 files

Runtime-identical, but the showcase teaches the stale spelling in 34 places.
`Facet.DEPRECATIONS` is a frozen *registry* with **no runtime warning**, so the stale
spelling costs the author nothing to write. Includes `sponsor_drop`, `sponsor_list`,
`virtual_list_native`, `perf_capture`, `row_actions`, `table_phaseb`, `levers`, `perf_lab`.

### 5. Live defects found en route — 7 real bugs, not style

These are behavioral, not stylistic. Three are in flagship teaching code and three are in
shipping game screens:

- **`p5_wardrobe/init.luau:1148`** — `env:get("reducedMotion") == true` compares a
  **Readable table to a boolean** and is permanently false, so the wardrobe turntable spins
  regardless of the accessibility setting. Verified: `env.get` returns the readable
  (`src/env/environment.luau:617-620`); `p2_cartwheel:197-198` does it correctly via
  `use(env:get("motionPolicy")) == "reduced"`. `env.get` returning `any` is what let it
  through `--!strict`.
- **`p5_wardrobe/init.luau:957-959`** — Picker option labels resolved at build time with
  `Lnow`, so the section names are the only chrome in the app that ignores its own locale
  flip. `p4_foyer:838` documents that Readables are accepted there.
- **`examples/gallery/client/theme_picker.luau:520-524`** — the 14-char label clip gates on
  `isCollapsible`, while its sibling `demo_picker.luau:671-673` gates on `opts.composed`.
  Production mounts `mountThemePicker(true, true)` (`init.client.luau:687`), so **in the
  shipped showcase the theme chip is character-clipped inside the chrome's ViewThatFits
  ladder while the demo chip is not** — defeating the ladder's stated design intent.
- **RR `FacetRacerListScreen.luau:196-203`** (production) — `ROW_HEIGHT = 28` chosen so *"the
  full 8-racer grid"* fits *"the phone-landscape panel"*: the exact 336/ROW_HEIGHT
  precedent shape, in shipping code. **Its justification has expired** — it cites *"the flat
  renderer cannot clip ScrollView overflow (live-caught 2026-07-20)"*, but `ScrollView` now
  defaults `clipChildren = true` (api.md:318, :572).
- **RR `Ticker.luau:236` vs `FollowScreen.luau:159`** (production) — the ticker strip
  offsets above the watched card by the **static** `watchedCardHeight`, while the card
  actually renders at the **derived, growing** `watchedCardReserve(metrics, paintOffset)`.
  At Large/Larger/Largest text preference the card grows and the strip lands on top of it.
  This is precisely the repo's own named defect class: *a px height fixed against unfixed
  content.*
- **RR `init.luau:2157`, `:2333`, `StoryFlow.luau:1140`** — three reactive facts read with a
  one-shot `:get()` outside any memo (`conditions.sizeClass`), so a **rotation never
  updates them**. `init.luau:451-459` does the same with `displaySize` under a comment
  admitting the stake: *"without this line the console HUD would MEASURE at three metres and
  PAINT at arm's length."*
- **`p2_cartwheel/screens/dashboard.luau:82-92`** — an every-frame
  `setPresentationTransform(path, { scale = … })` where `scale` is a documented reactive prop
  on every rendered class (`src/blueprint_schema.luau:870`). The neighbouring
  `celebration.luau` had to go imperative for a *translation* (no declarative twin — MOVE),
  and that established idiom then propagated onto a case that didn't need it.

---

## § What the framework teaches wrong

Design findings — places where the imperative habit exists *because a framework API makes the
declarative route harder than the imperative one*. These are not cleanup.

### 1. The theme-drift lint is deliberately not pointed at the corpus whose job is to teach

This is the root cause of the audit's single largest finding class, and the fix is one line.

`tools/lune/check_theme_drift.luau:11-14`, verbatim:

> *Scope: the REUSABLE framework surface — `src/controls/*`, the renderer's layout-node
> builder, and the presenter's geometry decisions. **Examples, tests, and game code are
> deliberately out of scope: an app author's literal is a legitimate opt-out, and saying so
> is the point of the escape hatch.***

That reasoning is **correct for a game and wrong for the gallery.** A game author's literal
*is* a legitimate opt-out. But the gallery is not an app — it is the reference a reader
copies from, and 539 opt-outs with no visible house style teach the opt-out as the idiom.
The mechanism already exists, is allowlist-based, and **passes clean on `src/` today
(verified: exit 0)**. Pointing it at `examples/` with its own allowlist converts the entire
DELETE #1 class from a judgement call into a mechanical gate.

### 2. The escape hatch is the shorter spelling

Compounding #1: `gap = 8` is one character shorter than `gap = "s"`, legal everywhere, and
identical under Studio Neutral — so it survives review and every test. The framework's own
docs teach it: api.md's layout examples are `UI.HStack{ gap = 8 }`. A reader learns the
opt-out from the reference manual before they ever learn the token exists. **Make `Metric`
the first form in every doc example**, and have strict authoring emit an advisory when a
number lands exactly on a space step.

### 3. The spacing scale cannot spell its own most-wanted value

`SPACE_STEPS = {xs, s, m, l, xl, gutter}` = 4/8/16/24/40
(`src/themes/package.luau:146`, `src/tokens/default_style.luau:68`). The single most common
gap in the entire corpus is **6 — 61 occurrences across 25 files** — and there is no rung for
it. Nor for 2 (×16), 10 (×8), 12 (×8), or 1 (×2). Ninety-five off-scale sites cannot be
fixed by DELETE #1 at all.

**The framework concedes this in its own source.** `src/themes/snapshot.luau:158`:
`label = { gap = 6 }, -- label.luau icon->title gap (no space step is 6)` — and solves it by
inventing a private per-control metric, **a channel consumers do not have**. The scale is too
coarse in the small range for chip-dense UI, and the framework routes around its own scale
rather than extending it.

### 4. The framework built the answer and then made it un-adoptable

`TabView` exists specifically to kill the four-`When` nav wheel and says so in its header —
but models an app whose only moving part is the tab strip. Two of its three known consumers
could not take it whole, so both kept ~300 hand-rolled lines. **A construct that answers only
the simplest of its known consumers has not landed**, and the examples directory now ships
two contradictory teachings of the same thing. The same shape recurs: `ARRANGEMENTS.twoLane`
is HUD-shaped (`main` first) while every app shell puts nav on the *lead* side, so six
hand-authored arrangements exist across three apps — one of them shadowing the preset's own
name with different lanes, so a dump cannot tell them apart.

### 5. The framework instructs the imperative route in its own docstrings

`virtual_list.luau:690-693` tells a horizontal list's author to *"wrap the list in a box of
the height you want"*, and `:667-671` blesses the consumer-side viewport memo. `card_rail`
obeyed both, honestly and at length — and **the blessing is the defect**, because obeying it
requires knowing that `viewportRect` is raw, that `coreSafeInsets` and the Screen's padding
must come off, that a scrollbar gutter must be guessed on both axes, and that a plate's
height must include `chromeInsets.panel`/`chromeOutsets.panel`, which appear nowhere in
api.md. **The most careful consumer file in the slice is also the least declarative one, and
that is not a coincidence.**

### 6. `platformChrome` describes an obstacle and offers no way to avoid it

`src/env/environment.luau:420` states the punt explicitly. Every downstream defect in
`hud.luau` traces to that sentence — the band-riding margin split, the strip height, two edge
spacers, a three-times-refuted column-reserve heuristic, and the reach-epoch latch. `hud.luau`
records being caught by the near-miss: *"`collisions` is about two REGIONS overlapping each
other, and the app's chrome is not a region — so nothing was watching."* A fact that names an
obstacle without a way to avoid it guarantees every consumer re-derives avoidance, and this
corpus demonstrates three of the four obvious derivations are measurably wrong.

### 7. The adaptive vocabulary has traps that read correct

`isRegular` is false on a desktop. `conditions.viewportWidth` is **raw** — it subtracts no
insets — and `adaptive.luau:466-471` carries the verifier finding saying so, along with the
ruling that *"a decision that must respect insets belongs in ViewThatFits, which measures."*
That warning lives in the framework; `composition.luau:64-74` clamps a box with the raw
number anyway. **If measuring is the honest route, the raw Readable should not be the most
reachable member of the `conditions` table.**

### 8. An inert prop is accepted silently

`Facet.Controls.Picker` reads `sizeClass` only inside its automatic branch
(`picker.luau:461-465`). `menu.luau:375` passes both `presentation = "segmented"` and
`sizeClass` — a prop that can never be consulted — and the comment directly above it
*describes that exact defect while leaving it in place*. The framework refuses `cards`
without `itemExtent = "cards"`; it should refuse this the same way. The same class:
`estimatedItemExtent` is correctly refused outside `"measured"` — the pattern exists, it is
just not applied consistently.

### 9. `env.get` returns `any`, and that cost a flagship app its accessibility behavior

The env facts are the framework's most-read surface. Returning `Readable<T>` instead of `any`
would have made `p5_wardrobe:1148` a compile error in every consumer at once, under
`--!strict`, at the commit that introduced it.

### 10. Probe and example are woven together in the corpus that teaches

Thirteen PROBE-EXEMPT sites were flagged as mistakable for example code. The worst:
`hud.luau` runs ~1,050 of its 3,359 lines as paint-probe instrumentation *inside the
exemplar's `build`*, and the two share `glass()` — the file's headline "one plate, one
recipe" teaching helper — which the probe calls with `{ type = "fixed", px = 164 }` and a
`padding = { right = 104 }`. A reader following `glass` to its call sites meets raw-pixel
geometry with no marker that it is instrument, not example. Worse, that call site's comment
cites 168, 208 and "a third of the narrowest landscape window" against code that says 164 —
**a stale comment on a taught helper.** Similar: the perf lab's `rows.heightFor` carries 30
lines of hard-won extent arithmetic (correctly PROBE-EXEMPT, per api.md's own named
exception) with no cross-reference telling the reader that `itemExtent = "measured"` is the
idiom and this file is the deliberate exception.

### 11. A capability nobody can find does not exist

RR's `StoryTokens.countdownBox` is, character for character,
`{ type = "percent", fraction = 0.34, min = 90, max = 220 }` plus
`UI.aspectRatio(bp, 1.3)`. It was instead written as a pure function over two solved rects,
fed through `onGeometry`, then converted from an absolute centre to an anchor delta by
`countdownAnchorOffset` — **a conversion whose own comment documents the shipped portrait
bug it exists to fix** (the box's centre landed on the layer's right edge, so the countdown
appeared offscreen).

The `percent` dim is documented in **one table cell** at api.md:309 among six other dim
shapes, with no worked example. `containerRelativeFrame` gets a full paragraph but is sold
for "half the scroller" and "a third of the viewport per page" — neither of which reads as
"34% of the map canvas, clamped to 90..220". The cost of that discoverability gap was a
hand-written responsive solver *and* one shipped device bug.

The same shape recurs across the corpus: `{ type = "fill", weight = 1 }` is written **326
times** in the reference apps because there is no `UI.fill` shorthand, and two apps built
private dim DSLs rather than keep repeating it.

### 12. The framework documented a device bug and shipped the workaround as prose

api.md:325 records a real 2026-08-17 defect — a 100×70 box at scale 1.5 / rotation 30°
painted 182.4×165.9 into its 100×70 slot and spilled onto its neighbours — and then **hands
the consumer the trigonometry** as the fix rather than shipping it as an API.
`nested_compositing.luau:94-119` transcribes that formula verbatim, plus a
`FOOTPRINT_SLACK = 6` fudge constant.

This is the director's question inverted: **here the framework itself reached for the
imperative route and is teaching it forward.** Every future consumer combining `scale` and
`rotation` on a container with siblings is one copy-paste from correct and one omission from
reproducing the original bug. `Facet.layout.transformFootprint(w, h, scale, deg)` — or better,
a `UI.reservedFor(bp, { scale, rotation })` that reserves automatically — closes it.

### 13. An option whose only correct value is "don't pass it" should be refused

api.md:601-604 states that `newAutoscroll` picks its band per host — *"40 px when the host is
wider than it is tall, 44 px when it is taller. The framework picks between the two per host;
**there is no call to make**."* But the option is still accepted, and the docs print both
numbers. So RR copied them into `TableMetrics.DEFAULTS`, branched them on the **screen's**
size class rather than the **host's** shape, read that class with a non-reactive `:get()`,
and handed the result back — **three regressions from one option that had no correct
non-default value.**

The framework already knows this pattern: `virtual_grid` refuses `minColumnWidth` alongside
`columns`, and `estimatedItemExtent` is refused outside `itemExtent = "measured"`. The
refusal habit exists; it is simply not applied consistently (see also #8's inert
`sizeClass` on a segmented Picker).

---

## What I would do next, in order

**Correctness first — these ship wrong pixels today:**

1. **Fix the seven live defects** in DELETE 5. Three are in flagship teaching code; three are
   in shipping game screens. The `Ticker`/`FollowScreen` overlap and the three
   non-reactive `:get()` reads are device-visible.
2. **Ship `textSize = "fit"`** (MOVE 10) and delete the four hand-rolled copies. Three of the
   four are measurably wrong and under-reserve by up to 1.5× at ten-foot. api.md already
   records that six of seven copies repo-wide were wrong; a solver-resolved prop is the only
   fix that cannot be copied wrong again.

**Then the cheap structural wins:**

3. **Point `check_theme_drift` at `examples/`** with its own allowlist. Converts the bulk of
   the DELETE class into a mechanical gate and permanently fixes "no visible house style".
   One line of scope, then a sweep.
4. **Add the `app.*` metric namespace** (MOVE 1). Deletes four shim files across the showcase
   and production, and is the precondition for those numbers ever riding the ten-foot ladder.
5. **Refuse what has no correct value**: `hug` on a `ViewThatFits` child (MOVE 2a), the
   `autoscroll` band, the inert `sizeClass` on a non-automatic Picker. Three construction-time
   checks; one of them retires a trap four independent authors documented in prose.
6. **Extend the spacing scale** to cover 2/6/10/12, or open the per-control metric channel to
   consumers (teaches-wrong 3). Ninety-five sites are unreachable without it.

**Then the noun layer** — `viewportExtent = "auto"` (filed by five slices independently),
`TabView` accessories, `navPlacement` predicates + `atLeast`, content-terms height, rowGap
token parity, `UI.fill`/`UI.hug` shorthands, and a per-child anchor origin.

---

*Audit performed read-only across 165 example files (~70,000 lines), 43 Rascal Rally
Facet-consuming client files, and a sample of 48 game-side contract specs. Nine parallel
slices, every claim in this report's headline findings independently verified by the auditor
against `src/**` before inclusion.*
