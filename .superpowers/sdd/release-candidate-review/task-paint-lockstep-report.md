# Paint-family lockstep — implementer report

**Status: COMPLETE.** Corner radii and hairline strokes now scale with the metric
ladder at ten-foot, derived from `metricScale`, and the number the framework
MEASURES is the number it PAINTS — on the sheet path (the default since today's
flip) and on the explicit-write fallback. Facet and its Rascal Rally consumer both
green; one real consumer defect found and fixed in the same round.

**Commits**

| repo | sha | what |
|---|---|---|
| Facet | `c4d05916c` | the round: classification, `paintForDisplay`, both sheet builders, the render target, the host, the theme controller, the guard specs, ADR-0039 Decision 3a, api.md, the cap ledger, the superseded close-out row |
| Facet | `c6c626046` | the fallback painter's own pin (`theme_controller.styleFor`, per distance, nine configurations) |
| Rascal Rally | `4e271c312` | `FacetSponsor` forwards the display class into the render target it builds itself, plus the contract rows that hold it |

All three via `tools/commit_isolated.py`. The Facet commit was hunk-scoped on
`src/client/screen_target.luau` (marker `displaySize`): a concurrent round is
mid-flight in that same file (the `paintPlan` refactor) and its two hunks were
dropped, verified in `git show`.

---

## What the change is

`snapshot.paintForDisplay(metricsLike, displaySize, pixelUnit?)` is ONE derivation
of the paint family, off the same `snapshot.metricScale` the measured ladder uses.
Both paint authorities call it:

* `tokens/sheet_model.build` / `buildPackage` take a `displaySize` and bake what it
  returns into the phantom `::UICorner`/`::UIStroke` rule literals;
* `client/screen_target` derives the `ctx.style` that `screen_paint`,
  `screen_chrome` and `tokens/styling`'s radius tokens write from;
* `client/host` is where the environment's `displaySize` fact crosses into the
  target — the one place that holds both;
* `client/theme_controller` builds a package's sheet, its `styleFor`, and its
  live-edit repaint push at the same class.

`densityClassOf` now answers `"scaleWhole"` for `radii.*` and `"scale"` for
`strokes.*`; `DENSITY_PAINT_SECTIONS` is gone. **The doctrine survives unchanged** —
*a metric may only scale where the framework owns the paint* — and what changed is
that the framework took the paint, through exactly the sheet-GENERATION seam R13's
own pointer named.

## The seven considerations, answered

**1 — Derivation, not literals.** Nothing multiplies by 1.5 anywhere. The rounding
rule is **the engine's own property type**: `UICorner.CornerRadius` is a `UDim`
whose Offset is an integer, so a radius scales to the NEAREST whole pixel (a pixel
package's grid wins where it has one — `snapToPixelUnit`, the resolver's own ceil);
`UIStroke.Thickness` is a float, so a hairline scales exactly, 1 → 1.5. Nearest
rather than ceil because a radius is not an accessibility floor and rounding a whole
family up fattens every corner on the screen for nothing. Pinned at NON-1.5 scales:
the spec drives `snapshot.metricScale` itself to 2, 1.25 and 3 and asserts measure
AND paint move together at each (114 leaf comparisons); a hardcoded 1.5 in
`paintForDisplay` fails it (mutation M4).

**2 — The capsule sentinel: it SCALES.** `radii.pill = 999 → 1499`. Exempting it
would mean a threshold constant nobody can derive, inside a design whose whole point
is that one number owns the family; and `pill` is not reliably a sentinel anyway
(`classic_desktop` authors `pill = 4`, `pixel_quest` 12), so a name-based exemption
would be wrong and a value-based one arbitrary. The paint identity is MEASURED
rather than claimed: `UICorner` clamps `CornerRadius` to half the box's shorter
side, so `min(999, s/2) == min(1499, s/2)` for every box up to 1998 px on that side
— swept over ten sizes from 1 px to 1998 px in the spec. The bound is stated in the
spec and in ADR-0039 rather than hidden: a box shorter-side taller than 1998 px
would differ, and nothing in this framework draws a pill that large. **The prior
evidence row re-verdicts**: `close-out.md` §13e recorded "capsule passes through
unscaled (999, not 1498)" — annotated in place as superseded, with what the same
GetStyled reading should now say (hairline 1.5, capsule 1499).

**3 — Authored wins.** The schema DOES have per-density authoring:
`metrics.tenFoot` is a map of dotted paths to absolute ten-foot pixels, and it can
legally name `radii.panel`. Until this round that was a live gap — the declaration
moved the MEASURE while the sheet kept painting the authored literal, the exact
disagreement the exemption existed to prevent. `paintForDisplay` applies the same
declaration, so 20 means 20 on both sides and is never double-scaled (spec: a
package declaring `radii.panel = 20`, `strokes.hairline = 3` measures and paints
20/3 while its undeclared `radii.control` still takes the derived 12; mutation M3).

**4 — Existing pins re-verdicted, one honest sentence each.**

| pin | verdict |
|---|---|
| `ten_foot_metrics.spec` "a radius and a stroke are painted by another authority, so they do not scale" | REWRITTEN as "a radius and a stroke are the PAINT family, and they scale in lockstep" — same 38 leaves over the same nine configurations, now asserting the derived value and the two new classes |
| `ten_foot_metrics.spec` sweep floor `checked > 550` | RAISED to `> 630` (true count 641). The old floor was vacuous after the change; 630 is above the 603 this sweep counted while the family was exempt, so the exemption coming back cannot pass |
| `snapshot.luau`'s "THE PAINT AUTHORITY BOUNDARY" comment | REPLACED by "THE PAINT FAMILY", which keeps the superseded reasoning and the doctrine verbatim and says what took the paint |
| ADR-0039 Decision 3 bullet | struck through, pointing at the new **Decision 3a**, which records the ruling, the two classes, the sentinel, authored-wins and the near-identity |
| `docs/reference/api.md` ten-foot section | "What does not scale: `radii` and `strokes`" rewritten; `themes.paintForDisplay` documented |
| `close-out.md` §13e row | annotated as superseded (see consideration 2) |
| `layout_defaults.spec` "AUTHORED WINS: a declared `maxMeasure`…" | UNTOUCHED — measure-side, unrelated, no churn |

**5 — Theme artifacts and the token dump: unchanged, proven.** The eight
`build/themes/*.rbxm` are pure DATA carriers (one ModuleScript whose `Source` is the
package's Luau text — `tools/build_themes.sh`); every StyleSheet is generated at
install time inside the consuming client, at that client's own distance. So the
scaling happens at BUILD-THE-SHEET time on the client, and no artifact needed
rebuilding. `tools/check_theme_artifacts.py`: PASS, 8 artifacts, 137 checks.
Near-density byte-identity is measured, not asserted: a dump of
`token_sync.records` (canonical form), the `buildPackage` stamp, rule count and
every Style-Editor mirror, for all nine configurations, is **sha256-identical**
between the pinned HEAD copy and the pinned change copy —
`f8207d99062b20456650bc3262005d6488771a8e790430bdce7f5a33e76b6cff`, 1070 lines.
`fantasy_parchment` is 99 tokens in both, which is the close-out's number.

**6 — Guards.** `check_theme_artifacts` PASS · `tools/lune/check_theme_drift` PASS
(exit 0) · `check_types` PASS · `check_doc_style` PASS · `check_source_size` PASS
(see Concerns) · `stylua` clean on every touched file. `check_tier_costs` reports 4
stale rows (`theme_drift`, `virtual_list_row_actions`, `row_actions_scenario`,
`overflow_sweep`) — PRE-EXISTING: `artifacts/spec-timings.json` is dated 2026-08-13,
none of the four is a file this round touched, radii do not feed tier costs, and the
guard cannot run at HEAD for comparison because the timings artifact is untracked.
Both paint paths are covered: the sheet path behaviourally (rule literals from both
builders, all nine configurations, `metricRuleProps`-driven), the explicit-write path
behaviourally through `theme_controller.styleFor` per distance plus a source-scan of
the target/host/controller wiring (the two engine files no headless world can mount).

**7 — Rascal Rally lockstep — a real defect found.** Three of RR's four Facet
surfaces (`GaragePilotGui`, `FacetRacerListGui`, `FacetSettingsGui`) take
`client.host` and were carried for free. **`FacetSponsor` builds its own core,
environment and render target** (`src/client/FacetSponsor/init.luau:444`) and would
have MEASURED at three metres while PAINTING at arm's length — 1.5x chrome around a
12 px corner on the game's biggest, production-default surface. Fixed red-first: the
fact is forwarded by hand, with the contract rows that hold it (the framework half —
18/12/1.5, equal to what the solver measures, near is the identity table — and the
consumer half — every surface hands its target the class). No other RR expectation
pins radii, strokes or the ten-foot paint, so nothing else moved. One incidental
find: my first comment contained the literal `Facet.client.host`, which a sibling
source-scanning spec reads to decide which surfaces are host-built — it turned that
spec red by describing code rather than being it. Reworded, and the reason is
recorded in the comment.

## Suite tails — content-pinned private copies

Measured in `git archive HEAD` exports, with only this round's hunks overlaid (the
working tree carries two other rounds' in-flight edits, including in
`screen_target.luau`, so the working-tree number is not this round's number).

| copy | pin (sha256 over `src`+`tests` `.luau`) | tail |
|---|---|---|
| HEAD `454e27f` alone | `382465046cc5ff78…` | **6915 passed**, 0 failed |
| HEAD + this round | `cdae9784b039ddfe…` | **6926 passed**, 0 failed (+11 = the new arms exactly) |
| Rascal Rally (working tree, full suite) | — | **3465 passed**, 0 failed (baseline 3463 + 2 new contract cases) |
| the tree left behind: clean export of HEAD `a9af1a1` (this round's four commits plus every other round that has landed) | — | **6939 passed**, 0 failed |

The dispatch baseline of 6905 was an earlier HEAD; two other rounds have landed
since (`23081c3`, `813f779`, `27af00f`, `50a7940`, `6f9e307`, `454e27f`).

## Mutations — nine, every one bites

| # | mutation | red |
|---|---|---|
| M1 | `strokes` leaves the scaled family | lockstep, future-scale, one-derivation, classification-completeness (4 rows) |
| M2 | whole-pixel rounds DOWN instead of to nearest | sweep, lockstep, future-scale, whole-pixel, capsule (5 rows) |
| M3 | the paint side ignores a package's `tenFoot` declaration | authored-wins |
| M4 | `paintForDisplay` hardcodes 1.5 instead of reading `metricScale` | future-scale (the derivation row) |
| M5 | `paintForDisplay` drops the pre-snap to the pixel grid | one-derivation (the off-grid pixel package) |
| M6 | `buildPackage` bakes the authored radius at every distance | every-metric-derived-rule |
| M7 | the built-in sheet bakes the authored radius at every distance | built-in-sheet |
| M8a | `ctx.style` is the authored style at every distance | the wire |
| M8b | the host never tells the target its class | the wire |
| M9 | `styleFor` hands the fallback path the authored family | compiled-style |

Run in isolated copies, never in the shared working tree.

## Concerns

1. **`screen_target.luau` is 8 characters under its ledger trigger.** The file was
   193,314 bytes with a documented trigger at 194,000 ("take the vocabulary module
   immediately if this file passes 194,000"). This round's three lines plus their
   comments crossed it; I cut the comments twice to land at **193,992**, and
   re-recorded the row in `docs/handoff/SOURCE_CAP_LEDGER.md` as **owed by the next
   round that opens this file**. That is a real, dated obligation, not a note.
2. **A live display-class change after construction does not move an existing
   target's paint.** A target takes its class at construction, exactly as it takes
   its palette (`setThemeStyle` is a declared growth seam `ScreenTarget` does not
   implement). On a real client this is unobservable — `GuiService.Viewport
   DisplaySize` is a device fact. It IS observable in the Studio EDIT preview and
   the theme-authoring profile switcher (`preview/device_profiles.apply`,
   `client/edit_preview`), where a mid-session switch to the console profile will
   scale the measure and leave the paint at the class the surface was built with.
   The honest fix is a small growth seam (`adapter.setPaintDensity` → re-push the
   metric rule props onto the live sheet, which is exactly what the director's own
   A/B did by hand); it is NOT in this round because the cheapest place to put it is
   the file in concern 1. Booked, not hidden.
3. **No device evidence yet.** Every claim here is headless or source-level. The
   ten-foot paint wants one console capture: GetStyled on a Large surface should now
   read hairline `1.5` and, on a themed package, the panel corner at 1.5x — the
   exact reading `close-out.md` §13e took the other way round.
4. **Concurrency.** Two other rounds are editing `src/client/screen_target.luau`,
   `src/client/native_style.luau`, `tests/lib/world.luau` and
   `tests/native_style_default.spec.luau`. Nothing of mine overlaps theirs
   semantically; the one interaction (their `paintPlan` refactor and my `style`
   derivation sit in the same function) is textually separate and committed
   separately. Whoever lands second should re-run the suite in a clean export.

## ADR-0040 row text (for the controller to append)

| B-16 | **The paint family scales at ten-foot, derived from `metricScale`** | Director, 2026-08-21, on the live console A/B (`captures/tv_corners_zoom_compare.png`): corner radii AND hairline strokes scale with the metric ladder at the ten-foot class, and stay DERIVED from `metricScale` so a future scale tweak moves them in lockstep. This supersedes **R13 in its result** and preserves its doctrine — *a metric may only scale where the framework owns the paint* — by doing the sheet-GENERATION work R13's own pointer named: `snapshot.paintForDisplay` is one derivation, and both authorities spend it (`sheet_model.build`/`buildPackage` bake the literal into the phantom `::UICorner`/`::UIStroke` rules; `screen_target` derives `ctx.style`; `client.host` carries the environment's `displaySize` to the target; `theme_controller` builds a package's sheet, its `styleFor` and its live-edit repaint at the same class). A radius rounds to a WHOLE pixel (a `UDim` Offset is an integer; a pixel package's grid wins where it has one), a stroke keeps its fraction (`Thickness` is a float): 12→18, 8→12, 1→1.5 at 1.5. The capsule sentinel scales (999→1499) and paints identically under `UICorner`'s clamp for every box up to 1998 px on its shorter side. A package's `metrics.tenFoot` may name a paint path and wins on both sides — closing a live gap where such a declaration moved the measure and not the paint. Near density is byte-identical: same table, same sheet stamp, same 99-token dump, and the eight built theme artifacts are unchanged (they carry Luau source, and every sheet is generated in the consuming client at that client's own distance). Guard: `tests/ten_foot_metrics.spec.luau` (11 new rows, 9 mutations). Consumer: Rascal Rally `4e271c312` — `FacetSponsor` builds its own target and now forwards the class, or the console HUD would have measured at three metres and painted at arm's length. |

---

# Fix round — the constructor class (2026-08-21, after the live console verify)

**Trigger.** A live console row (stamp `e0d6afd5`, DisplaySize Large) read the
framework's OWN showcase painting an unscaled capsule — GetStyled `0, 999` where
the derivation says 1499 — because `examples/gallery/client/init.client.luau:38`
builds its render target by hand and never handed it the display class. Sheet
token attributes read base (panel 12), which is correct by the near-density design:
the attributes are the authored ladder, and the scaling is in the rule literals.
**The defect was the constructor, not the derivation** — and it is the same class
Rascal Rally's `FacetSponsor` had already shown once. Two instances is a class, so
this round closed the class.

**Status: FIXED and CLASS-CLOSED.** Commit `5a43992d6` (Facet).

## The constructor census — every `screen_target.new(` in the repository

| call site | before | verdict |
|---|---|---|
| `src/client/host.luau:139` | passes | **PASSES** — the blessed bootstrap, wired in the first round |
| `examples/gallery/client/init.client.luau:38` | BARE | **FIXED** — passes `env:get("displaySize"):get()`, read after `roblox_env.bind` above it. This is the surface the live verify caught |
| `examples/performance/client/init.client.luau:102` | BARE | **FIXED** — same wiring. It is on the explicit-write path (`nativeStyle = false`), so its painter reads `ctx.style` and needed the fact just as much; near is the identity, so every `bench/perf_budgets.json` number was measured at the value this now states |
| `src/client/billboard_target.luau:43` | BARE | **FIXED — forwarded verbatim from its own `Opts`**, like `style`. Not an exemption: a billboard is a world surface, but its solver reads the same environment-wide `themeMetrics` as every other surface on that client, so painting near while measuring far would re-open the disagreement. A consumer passes the fact; absent is near |
| `src/client/edit_preview.luau:89` | BARE | **FIXED — and it is NOT a legitimate near-only case.** `preview/device_profiles` ships a `console` profile whose facts carry `displaySize = "Large"`, and `start()` applies a profile to `env` BEFORE it builds the target, so the class being previewed is the class it must paint. A live `setProfile` across the near/ten-foot boundary still moves measure and not paint — the construction-time rule, booked in ADR-0039 Decision 3a — and that is documented at the call site rather than waived |
| Rascal Rally `FacetSponsor/init.luau:444` | BARE | **FIXED last round** (`4e271c312`); re-swept this round, and it is still the only constructor in that repository |

`EXEMPT` is a written table in the spec and **it is empty** — nothing is waived.
Prose mentions of `screen_target.new({})` in `renderer`, `native_style` and
`theme_controller` comments are excluded by a positive rule (the call must be the
value of an assignment or a return), which is why the census reports five call
sites and not eight.

## The class-closing guard

`tests/ten_foot_metrics.spec.luau` — "every render-target constructor in this
repository states the distance it paints at": walks `src`, `examples` and `tools`,
anchors on each call with `%b{}` (the technique `native_style_default.spec`
established after a reviewer deleted an argument and left a comment claiming it),
and requires `displaySize` inside the call's own argument list or a written
exemption. It also asserts the five known paths are IN the census, so a walker that
silently stopped finding files cannot pass with an empty sweep.

## Fix-round mutations — five, all bite

| # | mutation | red |
|---|---|---|
| M10 | the gallery bootstrap goes bare again (the live defect, restored) | the census |
| M11 | the billboard stops forwarding the class | the census |
| M12 | the edit preview paints near while previewing a console profile | the census |
| M13 | the performance lab goes bare | the census |
| M14 | **a brand-new file with a bare constructor appears** | the census |

M14 is the one that proves the CLASS is closed rather than the four instances.

## Suite tails — content-pinned

| copy | pin (sha256 over `src`+`tests`+`examples` `.luau`) | tail |
|---|---|---|
| HEAD `b52d220` alone | — | **6949 passed**, 0 failed |
| HEAD + this fix round | `598f9b5ca6b1d7c1…` | **6950 passed**, 0 failed (+1 = the census arm) |

The working tree also shows one red — "the plate opens at ten-foot and its Close is
a 66px focus target" — which is the plate-B round's in-flight `blueprint`/
`region_expand` work: it is green in both pinned copies above, so it is not this
round's.

## Correction: which FRAMEWORK surfaces were exercised at Large

The first report's "carried free" sentence was about **Rascal Rally's** three
host-built surfaces, and it should not be read as a statement about the framework.
Stated properly:

* **Exercised at Large: none, live.** My evidence was headless (the derivation, the
  sheet literals, the compiled style, all nine configurations) plus source-scan (the
  target/host/controller wiring). No framework surface was mounted on a console by
  this round — which is exactly the gap the controller's live verify filled, and why
  it found what the headless suite could not see.
* **Wired and proven headlessly: `client.host`** — and only `client.host`. That is
  what "carried free" was true of: any surface built through the blessed bootstrap.
* **Not exercised and, as it turned out, not wired: the gallery showcase, the
  performance lab, the Studio edit preview, and the billboard target.** All four are
  fixed above; none has yet been read at Large on a device.
* **Still owed (device):** one console GetStyled row on the gallery after this
  commit — the capsule should read 1499 and a hairline 1.5 — plus the same reading
  on a themed package. The controller re-verifies live.

## ADR-0040 row: the number is **B-17**, not B-16

B-16 was taken by the DIR5 expand-affordance row. Corrected in both places the
wrong number reached: `src/client/screen_target.luau`'s `displaySize` comment and
the `SOURCE_CAP_LEDGER` row (whose text has since been re-recorded by the
native-default fix round — this round changed only the stale reference inside it,
and that row now reads **193,714**, 286 characters from the trigger, because that
round's extraction paid back my eight). **The row text in the section above is
row B-17.**

---

# Fix round 2 — the second door: a token resolved where it was written

**Trigger.** Second live console verify (stamp `b62ac109`, Large, gallery injected
*with* the round-1 wiring): the sheet rule `.facet-surface-raised::UICorner`
carried the derived `0, 18` — correct — while three live `UICorner` instances on
the same screen still read `0, 999`. **Status: FIXED, class closed.** Commit
`41e68298e`.

## The actual reader, found

The three instances are the segmented picker's sliding indicator —
`/S/View/Indicator/Layer/Bar`, `src/controls/selection_indicator.luau:434-436`,
`UI.corners(bar, "pill")`. They are painted from the node's own `corners` PROP,
not from a sheet rule and not from a surface role, and that prop was already a
NUMBER before any target existed:

`styling.normalizeCorners(spec, style?)` resolves a radius token **at authoring
time**, and its fallback is `style or default_style` (`src/tokens/styling.luau:20`).
Every call in `src/controls`, in `present/`, and in any consumer's code passes no
style — there is none to pass inside a control factory — so `default_style.radii
.pill = 999` was frozen into the blueprint. `screen_paint.applyCorners` then wrote
exactly what it was handed. **The target's `ctx.style` was derived correctly; this
number never asked it.** The coordinator's first hypothesis (the studio-neutral
boot handing `default_style` raw to the adapter) was ruled out by the sheet rule
reading 18 from that same style — one door was already right; this was the other.

## The fix: a name reaches paint as a name

The framework already does this everywhere else — `gap = "m"` reaches the solver
as a name and is resolved against the live `themeMetrics`; `Divider.thickness`
takes a metric name the renderer resolves. So:

* `styling.normalizeCorners` / `normalizeStroke` now carry the authored NAME beside
  the number, under `tokens` (`{ form = "uniform", radius = 999, tokens = { radius
  = "pill" } }`). A literal carries no token and never moves.
* **An absent stroke thickness is a token too** — its documented default *is*
  `strokes.hairline`, so `UI.stroke(bp, {})`, the commonest stroke in the
  framework, froze a themed number nobody had named. It names it now.
* `styling.paintCorners(data, style)` / `paintStroke(data, style)` re-resolve
  against the style the render target was built with — the derived one since round
  one. **Pure**, for the reason `native_style.paintPlan` was extracted this week:
  the painter is an engine file no headless world can mount, so the decision it
  spends must live where a test can call it. Total and identity-preserving: no
  token, no style, a style with no `radii`, or a token the theme lacks all return
  the authored number and the SAME table.
* `screen_paint.applyCorners` / `applyStroke` spend them.

No locked file was touched: the fix is at the door, so `presenter.luau:1495` and
`present/anchored.luau:436/490` — both of which author `"control"`/`"panel"`
corners — are carried without an edit, as are `chip`, `picker` and
`selection_indicator`.

## The door census (the class)

| door | where a paint token becomes a number | verdict |
|---|---|---|
| 1. the render target's `ctx.style` (and the sheet literals built from it) | `screen_target`, `sheet_model`, `theme_controller` | **derives** (round 1); every constructor states its class (fix round 1) |
| 2. authored token data | `styling.normalizeCorners` / `normalizeStroke` → `screen_paint` | **derives** (this round): the token survives, the painter re-resolves |

The census arm enumerates every module in `src` that reads the authored token
module (`tokens/default_style`) at all — **four**, each with a written reason
(`styling` the authoring fallback, `snapshot` the neutral base and the deriver,
`screen_target` the Light-theme identity check, `theme_controller` the `extra`
merge) — and asserts both appliers go through the shared resolver. A fifth reader
is red (M19).

**Out of scope, stated:** `shadows` are also resolved through `styling` against
`default_style`, and they correctly do NOT scale — ADR-0039's art-geometry rule
("a shadow's blur is a declared px figure the engine renders unchanged") — and
they are not part of the paint family the director ruled on. Gradients carry
colours, not lengths.

## Which framework surfaces are exercised at Large **by a test**

Round 1's evidence was derivation-level; fix round 1's was wiring-level. This
round adds the first **mounted framework surface at ten-foot**:

* **`Controls.Picker`, `presentation = "segmented"`, `indicator = "pill"`, mounted
  in a 1920×1080 `displaySize = "Large"` world through the real presenter and
  renderer onto a fake target** — the exact control whose three `UICorner`s the
  live row read. The arm follows `/S/View/Indicator/Layer/Bar`'s `corners` prop and
  asserts: the authored number is 999 at BOTH distances (the defect's own
  fingerprint, and why the token must survive), the token is carried, and the
  painted value is **1499 at Large / 999 at Medium**.
* Still NOT exercised at Large by a test: any surface that paints through the real
  `screen_target` (it needs a DataModel — the wiring is source-pinned instead), and
  the gallery/perf-lab/edit-preview bootstraps as programs. The controller's live
  re-verify remains the instrument for those.

## Fix-round-2 mutations — five, all bite

| # | mutation | red |
|---|---|---|
| M15 | normalized data stops carrying the token | the token arm, the resolver arm, the mounted-picker arm |
| M16 | the corner painter stops re-deriving | the door census |
| M17 | the stroke painter stops re-deriving | the door census |
| M18 | an ABSENT stroke thickness stops naming the theme number it took | the token arm, the resolver arm |
| M19 | a NEW module starts reading the authored token module | the door census |

## Suite tails — content-pinned

| copy | pin (sha256 over `src`+`tests`+`examples` `.luau`) | tail |
|---|---|---|
| HEAD `6addc5e` alone | — | **6982 passed**, 0 failed |
| HEAD + fix round 2 | `7a93a771af9bf33e…` | **6986 passed**, 0 failed (+4 = the four new arms) |
| working tree (all rounds in flight) | — | **6995 passed**, 0 failed |

`check_types` PASS · `check_doc_style` PASS · `stylua` clean. `api.md` documents
the surviving token beside `strokeData`/`cornersData`.

## Rascal Rally — it walks through this door twice

Not churn: the game authors corner tokens in two shipped surfaces —
`FacetSponsor/Ticker.luau:132` (the entry plate rounds `"control"`) and
`StartCountdown.luau:166/179` (the numeral plate rounds and takes the theme
hairline) — so its console HUD would have painted a phone's corner even with the
display class wired. Both now re-derive at paint, for free. Contract row added and
committed (`cae4c7a2b`): the two authored shapes at both distances, plus the
LITERAL corner `Marks.luau` computes from its own box side, which must not move.
**RR suite: 3465 passed, 0 failed.**

## What the third live verify should read

On a console row at Large: the three `Indicator/Layer/Bar` `UICorner`s should
GetStyled **`0, 1499`**, the sheet's `.facet-surface-raised::UICorner` stays
`0, 18`, and any authored hairline reads **1.5**. If a capsule still reads 999,
the node's `corners` prop will now say which door it came through — it carries the
token, so `tokens.radius = "pill"` with a 999 paint means the painter's style is
underived (door 1), and a missing `tokens` means an authoring path that bypassed
`styling.normalize*` entirely, which would be a third door and nothing in this
repository has one today.

---

# Gate round — the seven deltas were one delta, and the font block was never a finding

**Status: the four rows that shared one cause are GREEN, plus two adjacent ones.**
Commit `97bd808ba`.

## The 7-delta characterization

The check reports **one problem per node plus one for the dump**, and it prints
the WHOLE prop string on either side of a mismatch. So the seven decompose as
**six node deltas** (`/Vocabulary/Tag` — the `control-vocabulary` Chip — at three
viewports × two states) **plus one reproducibility line**, and each node delta
carries four prop changes of which **only one was uncharacterized**:

| # | delta | commit | ruling | paint at flat/neutral |
|---|---|---|---|---|
| 1 | the stored dump is not reproducible from the tree | — | the citable-artifact rule (category 1 in the checker's own header): `CURRENT` exists to be current | regenerated through its documented generator; `BASELINE_3_5` untouched |
| 2–7 | `/Vocabulary/Tag` props changed, ×6 (desktop/phone-portrait/tablet × nodes/opened) | — | one node, six report lines | — |
| ↳ `textSize=18` | the director fix round, **2026-07-25** | the class's intrinsic typography role reaches PAINT | **deliberately changed** 16→18; already characterized (`ALLOWED_ADDED_PROPS.textSize`) |
| ↳ `textFont={…BuilderSans#Regular#Normal…}` | **`a2361f5`**, 2026-08-02 (parity F2) | the role's FACE reaches paint beside its size | **identical** — every pre-existing role resolves to the face the adapter hardcoded; already characterized |
| ↳ `textWrapped=false` | **`fb76787`**, 2026-08-14 (ruling 5) | the wrap verdict reaches paint | **identical** — `false` IS the engine default; the value is pinned so a `true` fails; already characterized |
| ↳ `corners={…,tokens={...}}` | **`41e68298e`**, 2026-08-21 (this family, door 2) | ADR-0039 Decision 3a / ADR-0040 **B-17** | **identical** — proven below. **THE ONLY UNCHARACTERIZED ONE** |

**Attribution was probed, not inferred**: the dump was regenerated at each
candidate commit and its parent. At `41e68298e~1` the node reads
`corners={form=uniform,radius=999}` and at `41e68298e` it reads
`…,tokens={...}` — with the font block present on **both** sides. At `a2361f5~1`
there is no `textFont` and at `a2361f5` there is. So the font block is 2026-08-02's
and the sub-key is mine; the sweep's reading of "`corners.tokens` **plus** a
text-font block" was the report's formatting, not two open findings.

## The paint proof (claim is bytes, not record shapes)

```
regenerated dump                       e4bf27df405a8e88eea8d41c243050ceea669bbf462f7f50f74b0cd7e5e7e13a
regenerated dump, `,tokens={...}` cut  ccbaa828e8c52e9c319bbf2f35ff04b9b26ca2a0277e992498445080214190c1
the dump RS-A1 last cited              ccbaa828e8c52e9c319bbf2f35ff04b9b26ca2a0277e992498445080214190c1
```

Across 24 renders, 8 fixtures and 1461 flat nodes the round added **exactly six**
sub-keys and moved **no other byte**. At the flat/neutral class `paintCorners`
re-resolves `"pill"` to the 999 already there and returns the same table — the
re-derivation is the identity. Nothing was proven un-provable, so nothing was
stopped on.

## What was changed, and what was deliberately not

* **`ALLOWED_ADDED_SUBKEYS`** (new, in `check_flat_baseline`): a RULE, because
  this is a seam-level correction landing on every node of a kind — the form the
  file's own header prescribes. It removes exactly `,<subkey>={...}` from the prop
  that declares it and compares the remainder byte for byte. `stroke.tokens` is
  listed beside `corners.tokens` because they are one decision.
* **Mutation-proven**: with `radii.pill` moved 999 → 1000, the check still FAILS
  and names both numbers. A characterization, not a waiver.
* **`BASELINE_3_5` was NOT re-pinned** — declined a third time, on the file's own
  recorded reasoning. What was regenerated is `CURRENT`
  (`artifacts/rich-skinning-v2/rows/neutral-render-dump.json`, gitignored,
  regenerable) through `tools/lune/_theme_baseline`, and the citable record
  `rs-a1-image-is-element.json` now carries the new sha, the regenerate date and
  the paint-identity proof.
* **`font-aware-measurement` re-pinned honestly**: `fontKey` left
  `src/layout/solver.luau` in **`f0fc77e`** (the measure-facts extraction) — the
  string moved, the capability did not. The row now pins the fact where it lives
  (`src/layout/measure_facts.luau`) **and** the solver's binding
  (`require("./measure_facts")`), so the re-pin cannot be spent to make a real
  removal quiet. Not this family's regression; repaired rather than passed on.

## Per-gate outcomes (real checkout, not a copy)

| gate | row | verdict |
|---|---|---|
| `swiftui-parity-round2` | `checker-battery` | **PASS** |
| `swiftui-parity-round3` | `checker-battery` | **PASS** |
| `swiftui-parity-round4` | `checker-battery` | **PASS** |
| `rich-skinning-v2` | `layered-slots-and-posture` | **PASS** |
| `rich-skinning-v2` | `circle-button` (same cause, not in the brief) | **PASS** |
| `theme-packages-and-skinning` | `metric-snapshot-single-source` | **PASS** |
| `theme-packages-and-skinning` | `font-aware-measurement` | **PASS** (after the re-pin) |

`check_flat_baseline` itself: **PASS — 1461 flat nodes byte-compared; 13
characterized prop deltas, 5 new nodes, 4 added prop keys, 2 added sub-keys, 17
rect-drift scopes, 2 class substitutions.**

**Every one of the five gates now has exactly one recoverable row left:
`prior-gates-unregressed`** — and its recorded detail names the cause: *"another
sweep holds /tmp/facet_prior_gates.lock — refusing to start a second"*. That lock
was **orphaned by my own parallel gate runs** (the standing lesson: a backgrounded
sweep orphans the lock, and it refuses silently). Cleared, and the gate re-run
serially with the lock free — result appended below. The remaining
`FAIL_ENVIRONMENT` rows (`physical-and-human-rows`, `studio-device-canary`,
`studio-and-device-evidence`) are declared device rows, non-blocking by design.

**The lock, followed to the end.** With the lock cleared, `prior-gates-unregressed`
stops refusing and starts doing its real work: `tools/prior_gates.sh <artifact>
rich-skinning-v2`, which re-runs every gate BEFORE that one — a one-to-two-hour
sweep. I let it start (it got past `game-suite-untouched`, which PASSED in the real
checkout), then **stopped it deliberately and released the lock**, because that is
the same lock the controller's re-verify sweep needs and holding it for two hours
to reproduce a sweep the controller is about to run would block the thing it
proves. `/tmp/facet_prior_gates.lock` is confirmed free at hand-off and no gate
process of mine is alive. What is established: the row's only recorded cause was
the orphaned lock (its own detail string says so), and every other row of all five
gates is PASS or a declared device row. The stale
`artifacts/rich-skinning-v2/prior-gates-rerun.txt` on disk corroborates the
diagnosis from the other side — it records `FAIL theme-packages-and-skinning` with
`FAIL_RECOVERABLE font-aware-measurement`, which is exactly the row this round
re-pinned.

**A measurement caution worth recording**: gates run in a `/private/tmp` copy
produce FALSE reds on `rascalrally-consumer` and `game-suite-untouched`, because
both `cd ../../../games/RascalRally/code`. Both PASS in the real checkout. A gate
row that leaves the repository can only be judged where the repository is.

## Not mine — diagnosed, not touched

* **`native-stylesheets` / `docs-and-adr`** — fails on
  `grep -q "Native stylesheets (opt-in)" docs/guide/05-styling.md`. **`c1120fc`**
  (the native-paint default flip, ADR-0040 **B-15**) renamed that heading to
  *"5.7 Native stylesheets (the default): the Style Editor is the paint
  authority"*. The row's pin is stale by that round's own decision. **Owner: the
  native-default flip family.** The other five clauses of the row pass.
* **`api-architecture-consistency` / `studio-evidence`** — its whole run string is
  `python3 tools/check_perf_gate_evidence.py studio`, which **passes at this
  HEAD**: *"studio: preflight clean, fault proven live, capture admissible, images
  on disk"*. Whatever it wanted has since been supplied; it needs a re-run, not a
  fix.

## Suite tail

Content-pinned clean export of HEAD `97bd808ba`
(`403228067146048c1ef3f9f667768daef7de6d90a4893d285c8fdf52f61ea272`):
**7062 passed, 0 failed.** `stylua --check src tests tools examples` clean;
`check_manifest_integrity` 1518 suite greps all anchored; `check_gate_pins` PASS
(260 file pins, 487 run strings parse); `check_doc_style` PASS.
