# Framework capability gaps — the full MOVE list (phase 2)

Extracted verbatim from the declarative-purity audit
(.superpowers/sdd/release-candidate-review/task-purity-audit.md, commit 2c5451e)
so the pick list lives in the artifacts folder. 97 consumer sites reduce to the
34 distinct gaps below (11 detailed + 23 in brief). The director's chat-ranked
six map to: chat #1 = audit §1 (app-namespace metrics), chat #2 = audit §10
(Facet.text as a prop), chat #3 = audit §2 (ViewThatFits), chat #4 = audit §4
(viewport self-measure), chat #5 = audit §9 + §8 (rootPolicy band-riding),
chat #6 = the gap-6 spacing step (audit §"what surprised" — the pending lint
finding). The seventh (focus-ring metric) is booked in t16-triage.md.
Status column: OPEN until a phase-2 round lands it.

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
