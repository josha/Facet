# Game UI quality work

The work branch is `iter/quality`. It starts at `6492055d`. The validation
baseline is the same commit in `C:/git/facet-wt/quality-baseline`.
No agent evaluation, publication or push was run.

## Audit evidence

The [inventory](quality-audit-inventory.md) lists all 206 findings in the supplied
universal and spec reports: 128 plain and 78 Facet. Each row names its source
reports, rule, element, value and detail. The CSV at
`artifacts/quality/audit-inventory.csv` has one row per finding.

The headline uses ten universal screens per arm. It excludes low-severity
findings. This accounts for the difference between the plain headline of four
findings and its 51 recorded findings at all severity levels.

| Rule | Severity | Plain recorded | Facet recorded | Plain with corrected check | Facet with corrected check | Rebuilt Facet |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `interactive-overlap` | medium | 4 | 16 | 4 | 0 | 0 |
| `outside-safe-area` | medium | 0 | 12 | 0 | 4 | 0 |
| `touch-target-small` | medium | 0 | 8 | 0 | 8 | 0 |
| `spacing-scale` | low | 23 | 0 | 23 | 0 | 0 |
| `type-scale` | low | 24 | 0 | 24 | 0 | 0 |
| `contrast-low` | high | 0 | 0 | 0 | 0 | 0 |
| All | | 51 | 36 | 51 | 12 | 0 |

The corrected-check columns re-audit the saved dumps. They cannot recover styled
colors that the old collector did not record. The rebuilt column uses fresh
native dumps of the hub, Shop, Boosts, Quests and Offer on desktop and phone.
The copied game keeps its client, server and shared code. Only its Facet
package is replaced for these captures.
All ten rebuilt reports score 100. Open and Close succeed for all four panels on
both devices. Each Close returns to the original instance census.

Of the 36 Facet headline findings, 24 are check errors and 12 are real defects:

- Eight safe-area findings name `Modal.DismissOutside`. This empty, non-selectable
  dismiss target must cover the full viewport. It is not safe-area content.
- Sixteen overlap findings compare a modal action or a collection purchase
  button with the dock behind the modal. The full-screen dismiss target blocks
  the dock. These are not two available actions at the same point.
- Four safe-area findings name sheet content or actions near the home indicator.
  Sheet did not reserve native safe insets when its ScreenGui used
  `ScreenInsets.None`.
- Eight target findings name `Header.Close` or the `All` filter. Their widths are
  about 37 and 40 points. The button floor had depended on an explicit
  `controlSize`, and it discarded the width floor when the height was sufficient.

The spec reports repeat these cases and include `Actions.boost`, plus purchase
buttons for `rainbow_trail`, `sport_motor` and `lucky_charm`. The inventory retains
each recorded row key. The saved reports and later raw dumps can name different
virtual rows. The overlap classification depends on the modal input barrier,
not on a row name. No finding is dismissed by a Facet tag or instance name.

The missing `driving-probe` is a separate fixture-loading error. It is not one
of the 36 UI findings. The author kit now includes the driving handler in
`tools/play/engine`; it loads RaceTrack only for an explicit driving request.
The standalone-kit test bundles the actual probe with no `eval` directory.

The corrected collector also exposed a disabled `Owned` label at 4.38:1 on the
consumer's accent color. The theme now limits disabled text transparency for
paired filled controls with the existing contrast calculation. It preserves
the requested transparency when the contrast is sufficient.

The shared check fix is Verify commit
`ce04d9f1b16e17fbd0ac71b28b9bedffc45085ae`, on local branch
`iter/quality-audit`. Its complete native gate passes all 21 producers. The
change uses `GetStyled`, accounts for full-viewport modal occlusion, and retains
negative cases for unsafe foreground content and overlapping foreground
buttons. The existing strong/weak calibration and thresholds remain unchanged.
The generated Facet snapshot was updated with `sync verify`; it was not edited
directly. The Verify commit has not been pushed.

## Library changes

- Default Button touch and gamepad targets keep both dimensions above the theme
  minimum. `Compose.show` mounts the extra native constraint only when needed.
- Sheet uses `GuiService:GetInsetArea` to reserve the part of the native safe
  area that its panel overlaps. The scrim still covers the full viewport.
- Overlay arrival uses a non-clipping `Frame.Visible` gate. A `CanvasGroup`
  clipped the expanded scrim at the core inset. The original commit fails the
  focused desktop Sheet case; the new code passes it. The existing deferred
  geometry and ownership tests still pass.
- The theme compiler combines native StyleRule comma selectors only where
  property order and motion state are preserved. Native styling still resolves
  selectors and applies transitions. The default theme falls from 547 rules to
  388, including the new contrast rules.
- Disabled filled controls keep readable paired text instead of applying an
  unsafe opacity to every palette pair.

The engine APIs checked were `StyleRule.Selector`, `StyleRule.Priority`,
`UISizeConstraint`, `GuiService:GetInsetArea`, `Frame.Visible` and `CanvasGroup`.
Compose `show`, fragments and presence already provide the required ownership
and lazy lifetime. No Compose change or second scene graph was needed.

## Instance and construction costs

| Native game measurement | Before | After | Change |
| --- | ---: | ---: | ---: |
| Desktop base instances | 617 | 456 | -26.1% |
| Phone base instances | 592 | 436 | -26.4% |
| Desktop peak instances | 835 | 674 | -19.3% |
| Phone peak instances | 754 | 606 | -19.6% |
| Desktop peak GuiObjects | 162 | 162 | unchanged |
| Phone peak GuiObjects | 126 | 126 | unchanged |
| Default theme StyleRules | 547 | 388 | -29.1% |

Plain has 80 base instances and 62 peak GuiObjects. Facet still has a substantial
fixed cost. This work does not establish parity with plain.

The saved game uses Screen, Composition, Region, VStack, HStack, Text,
ProgressView, Button, Badge, VirtualGrid, VirtualList and four Sheets. Sheet
content is already lazy: a closed Sheet costs one placeholder Frame and does
not call its content factory. No eager panel tree was found in the closed hub.

The native engine double gives these isolated costs. Construction times are
single diagnostic samples, not paired engine mount claims. The footprint
command subtracts its empty screen. Its resource ceilings are unchanged.

| Fixture | Instances | Construction ms |
| --- | ---: | ---: |
| Empty default theme, including StyleSheet | 389 | 11.661 |
| Closed Sheet | 1 | 0.182 |
| VStack with gap and padding | 3 | 0.228 |
| Wrapped HStack | 2 | 0.151 |
| Badge | 1 | 0.194 |
| ProgressView with label | 9 | 0.750 |
| Empty Screen | 3 | 0.365 |
| Composition with one Region and VStack | 12 | 0.710 |
| VirtualGrid with the game's part row pattern | 39 | 2.324 |
| Button | 1 | 0.239 |
| Bounded Button | 2 | 0.463 |
| Text | 3 | 0.587 |
| Fixed Text | 1 | 0.237 |
| Open Sheet with short text | 39 | 4.838 |
| VirtualList with one Button row | 31 | 2.901 |
| VirtualList with two Button rows | 34 | 3.386 |

The per-row structure remains three instances in this fixture. The resource
footprint check passes, including zero resources after teardown. Rendered
geometry is checked separately in Studio.

## Timing evidence

The supplied Facet mount measurements were 22.291 seconds on desktop and
6.213 seconds on phone. The final capture measures 22.293 and 9.172 seconds.
The later isolated plain pair measures 22.239 and 13.145 seconds, for observed
Facet/plain ratios of 1.002 and 0.698.

These ratios do not prove the 1.10 target. The unchanged probe waits for a full
second with no geometry change, with a 20-second limit. Native geometry traces
show continuing currency-label width and progress-fill changes from the live
game. Desktop measurements reach this limit in both arms. Shared Studio
background throttling also makes the live frame-time samples unsuitable for a
new idle-frame performance claim. No budget or measurement definition was
changed to make the result pass.

Five paired native-double rounds use the exact original commit and the final
worktree. Ratios below are quality/base medians. Their ranges cross one; none
receives the runner's consistent-regression flag.

| Scene | p50 ratio | Paired p50 range | p95 ratio |
| --- | ---: | --- | ---: |
| Dense HUD | 0.952 | 0.66-1.00 | 0.948 |
| Screen lifecycle churn | 1.026 | 0.96-1.05 | 1.027 |
| Stylesheet state churn | 1.127 | 0.88-1.39 | 1.007 |

## Validation status

| Check | Result | Scope |
| --- | --- | --- |
| Rebuilt game audit | Pass | Ten screens, zero findings, both devices |
| Open and Close | Pass | All four game panels, both devices; exact base census restored |
| `ports_overlays` | 45/45 pass | Complete suite, including desktop, iPhone and Xbox scrims |
| `layout_geometry` | 15/15 pass | Complete suite |
| `frame_stability` Button | 1/1 pass | Complete interaction case, phone-sized fixture, Medium text |
| `frame_stability` Sheet mount | Baseline failure | Five gallery tab movements; the original commit has the same five movements and first delta |
| Resource footprint | Pass | All 19 fixtures; unchanged ceilings; zero resources after teardown |
| Native census | Recorded | Theme and the game control patterns above |
| Paired native performance | Recorded | Five rounds; three scenes; results above |
| Verify native gate | 21/21 producers pass | Complete upstream gate |
| Facet behavioral cases | 2,028 pass | Complete committed plan; zero failures and timeouts |
| Facet maintainer-tool cases | 434 pass | Complete tool selection; zero failures and timeouts |
| Repository types | Pass | 1,195 targets, zero blocking diagnostics; 186/186 negative probes rejected |
| `gate full` | Narrowed pass | 35 producers passed, bench and perf deferred; release-only producer not selected |
| Package verification and canary | Pass | Built artifact mounts, updates, receives input and tears down |
| Final `gate fast` | Pass | All 13 selected producers; 14 cases deselected by standard fast policy |
| Final standalone `bench` | Pass | 4.2% yardstick drift; unchanged timing budgets |
| Final package build and status | Exit zero | Build complete; publication drift and pending Studio package check reported |
| Final arm kit | Pass | 522 files at `artifacts/facetbench/arm-facet` |

The Sheet frame case is `all-controls/actions/sheets/phone/Medium`, with
`FacetFrameStabilityMountOnly=true`. Its first failure is the gallery's
`actions.TabBand.Tabs.Strip.buttons` moving by `[-76, 0, 0, 0]` on frame two.
The baseline report is in
`C:/git/facet-wt/quality-baseline/artifacts/studio-live/frame_stability-quality-baseline-sheet.json`.
The candidate report is
`artifacts/studio-live/frame_stability-quality-sheet-mount.json`.
This is not a complete passing frame-stability suite. Earlier broad and short
interaction runs timed out; one short Sheet run also had a Studio start timeout.
The Button interaction case completed with the longer process deadline. No
performance ceiling was changed.

The final full command exited zero. It does not attest a complete green gate:
`bench` and `perf` were deferred because a host timing budget failed away from
the reference host. The release-only `prove-perf-gate` producer was not selected
by the full tier. No code producer failed. See
`artifacts/quality/full-final.log` and
`artifacts/verify/native/gate/gate-1792108499-862849-1`.

The full gate benchmark had 50.1% yardstick drift and reported
`FAIL_ENVIRONMENT`. An earlier standalone benchmark passed with 0.1% drift in
`artifacts/quality/bench-final.log`. These are separate observations. The earlier
pass does not turn the final timing deferrals into passes.

The final standalone benchmark passed with 4.2% yardstick drift. This is in
`artifacts/quality/bench-last.log`. The final fast command passed all 13 selected
producers in `artifacts/quality/fast-final.log`. Its standard policy deselects
14 cases. The full run above includes them.

The final package build and status commands exited zero. Package status reports
source drift from the last publication and a pending Studio package check.
The package was not published. The arm kit was rebuilt with 522 files. See
`artifacts/quality/package-build-last.log`,
`artifacts/quality/package-status-last.log` and
`artifacts/quality/kit-last.log`.

The gates ran at `f78c5034`. The following report commit records these results
without a source or test change. Package source content is unchanged by it.

## Evidence files

All paths below are relative to this worktree, except the baseline path above.

| Evidence | Path |
| --- | --- |
| Original audit snapshots | `artifacts/quality/evidence/{plain,facet}` |
| One row per recorded finding | `artifacts/quality/audit-inventory.csv` |
| Saved-dump re-audits | `artifacts/quality/re-audit/{plain,facet}` |
| Final Facet captures, audits and census | `artifacts/quality/facet-all` |
| Isolated plain captures | `artifacts/quality/plain-pair` |
| Footprint | `artifacts/quality/footprint-final.json` |
| Native control census | `artifacts/quality/native-census-final.jsonl` |
| Paired performance | `artifacts/quality/paired-final/report.md` |
| Overlay live report | `artifacts/studio-live/ports_overlays-quality-arrival-final.json` |
| Layout live report | `artifacts/studio-live/layout_geometry-quality-final.json` |
| Button interaction live report | `artifacts/studio-live/frame_stability-quality-button-interactions.json` |
| Rebuilt author kit | `artifacts/facetbench/arm-facet` |

## Commits

| Commit | Change |
| --- | --- |
| `9c034d79` | Keep optional driving probe inside author kit |
| `db70064b` | Keep default touch targets and Sheet content inside native safe areas |
| `75ff28e3` | Compact native theme rules and preserve disabled text contrast |
| `e4c774d4` | Re-pin Verify for styled property and modal audit accuracy |
| `36b2af91` | Record updated Verify provenance |
| `d02cc0c5` | Measure saved game UI without running an agent |
| `4c8e0887` | Present overlays through a native non-clipping arrival frame |
| `3a0204de` | Match centered Sheet safe insets to the native keyboard shift |
| `3b19794d` | Complete the native game census and strict tooling types |
| `8688e1ab` | Preserve authored fade stroke motion states during rule compaction |
| `77ea5574` | Record every slice audit finding by rule and element |
| `a2f412e5` | Keep quality evidence internal and type authored rule fixtures |
| `f78c5034` | Rebuild example places with compact themes and safe overlays |
