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
