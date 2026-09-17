# Example migration and toast continuity

This follows the [Signals and authoring summary](2026-09-17-signals-and-authoring-summary.md).
The [example index](../../examples/README.md) identifies current code to copy;
[component authoring](../guide/15-components.md) defines the authoring rules.

## Authoring

Maintained example trees use ordered numeric children. Tutorials, showcase chrome,
toast and progress pages, and shared reference views use mounted components and
getters. Ordinary controls no longer need explicit ownership or `.blueprint`.
The automatic-motion page is the first Motion tab. Match 3 declares motion on its
board; game commands write state without wrapping each operation in `withAnimation`.

Shared application models retain Core lifetimes across page changes. Diagnostic
examples retain handles when their report or interaction driver exercises an
imperative API. Custom board targets retain the primitive Button for selected
paint and glyph layout. These boundaries are distinct from ordinary composition.

AGENTS.md, contributor and maintainer guidance, the component guide, tutorials,
adaptive/control recipes, API reference and feature scaffold now teach the same
vocabulary. Historical proposals and before/after examples remain historical.

Migration also exercised framework integration: deferred components now work in
NavigationStack pages and Alert content; drag enablement tracks a getter while
payload functions remain callbacks. View.ProgressView inherits its owner and
clock. Getter indexes borrow their keys and values so a cyclic value cannot
retain a retired component; the live owner keeps shared bindings available. AsyncImage leases follow the mounted owner, with stale-response rejection.

## Toast behavior and Studio evidence

Toasts support top/bottom placement and ordinary width dimensions, including
content-fit `hug` with a maximum. The first toast selects the edge for that stack;
the showcase labels this choice "Edge for new stacks". Surviving rows animate to
their new positions when another toast leaves.

The default slide does not rasterize text through a CanvasGroup. Explicit fades
remain available. The fit-content showcase body uses hug dimensions through its
nested containers, so its measured width includes the text.

Fresh Studio source stamp `5dea676f-9303219` was checked in the full showcase.
Actual mouse input exercised the Automatic page: expansion, purchase and reversal
left selection on Scanner, balance at 60 and Beacon first. Settings, game layout,
and bottom content-fit toasts were inspected in screenshots. Toast text read back
as TextSize 16, TextScaled false, with zero CanvasGroups while two toasts were
visible. The second toast's title moved from y=178 through 146, 118, 105, 98, 96,
95 to 94 after the first disappeared; it remained mounted throughout.

The rebuilt benchmark place's 249 Facet modules were compared byte-for-byte with
the current source: zero differences. After the getter lifetime fix, all 249 modules were compared again, with zero
differences. After the callback-delivery optimization, the rebuilt modules were compared once
more with zero differences. The final source marker is `4c1997c41f61`, from
package source hash `4c1997c41f61f3b571c9c0c0af21ae453ddcdc470cb8c3c7b6c27ccb0fb64b8a`.
Raw local evidence is under `artifacts/example-migration/`.

## Verification

The full deterministic suite passed 10,097 tests across all 448 specs with zero
failures (567.0 seconds). The new getter collection witness failed against the old
cache and passed with the fix; the live-binding test checks that collection does
not break sharing or updates. Counts alone would not have caught that retention.

`tools/verify.sh full --explain` passed after the documentation follow-up
(`862a1704ce0f`, 62.5 seconds). It reused the successful suite for unchanged code
and checked the updated documentation and remaining gates. Its report separates
fresh deterministic results from archived Studio/device receipts; the current
Studio and performance evidence described below is retained separately in
`artifacts/example-migration/`. The tutorial preserves its lessons about visible
confirmation outcomes, actionable rejection feedback and explicitly delivering
resource fixtures alongside the new authoring examples.

The final Studio runtime was synced again at `62df2406-9304250`; the content-fit
Toasts page was rechecked visually after both runtime fixes, with no console errors.
A fresh motion sample reproduced y=178 → 146 → 118 → 105 → 98 → 96 → 95 → 94
while keeping the same second toast mounted, with native TextSize 16 and no text scaling.
All 14 example/reference places and the 249-module package were rebuilt.

The final runtime passed `tools/perf.sh`: **135 runs, 27 scenes**, using the
unchanged budgets. `tools/bench.sh` passed all **17 scenes**, with 1,500 samples
and 50 warmup iterations; the final yardstick drift was **0.5%**. The artifact's
19 rows include the two yardstick readings.

The typing benchmark initially exceeded its historical 1.50× gate at 1.54× and
1.55×. A cancellation-batching experiment did not help and was removed. The final
Signals adapter reuses its delivery queue and reattaches signal observers without
pulling a value it already holds. Two complete benchmark runs then passed at
**1.46× and 1.44×**. The last typing p50 was **0.168 ms**; the preceding authoring
rollout's ratio was 1.447×. Failed attempts and both optimized results are retained;
the budget and frozen baseline were not changed. The extra Studio window had
remained open after the first close request, so those repeats are not evidence
of a closed-versus-open Studio improvement.

Automatic and explicit motion are both exercised: final p95 was **3.060 ms** for
declarative motion and **2.985 ms** for explicit motion in the matching retained
tree benchmark. These are headless measurements, not device guarantees.

FacetBench also completed all five large headless workloads with 750 samples and
50 warmup iterations. Final yardstick drift ranged from 1.18% to 7.87%; nameplates
used one of the runner's bounded drift retries.

The Studio frame matrix completed all five large workloads twice, first with
300 samples/30 warmup frames and then with 600 samples/60 warmup frames. All rows
reported `ok`; moving-position workloads verified live GuiObjects moved. The
final frame p95 values were:

| Workload | Update p95 (ms) | Frame p95 (ms) |
|---|---:|---:|
| Battle HUD | 5.590 | 17.453 |
| Damage fountain | 4.662 | 17.388 |
| Killfeed/nameplates | 6.460 | 17.354 |
| Nameplates | 6.113 | 17.379 |
| War-room inventory | 16.117 | 25.040 |

Studio CPU-yardstick drift was high, so its normalized ratios are **not reliable
before/after comparisons**. The first matrix's frame p95 ranged from 17.35 to
18.31 ms; the longer inventory run exposes a heavier tail. These are desktop
Studio observations, not physical phone/console or retail-client certification.
The existing unmeasured hardware budgets remain pending.

The Studio relay did not reach the client in this tool session (the server
context reported zero players). Temporary local/bootstrap triggers also did not
advance. Both were removed, and each bounded matrix ran directly in the client
tool context with no concurrent matrix and a fresh Play session. The normal
renderer still created and updated live Roblox UI. The console scrape checked
the source marker and all five completion rows. The temporary benchmark window
was closed after capture; no driver was added to the shipped examples.

The flat compatibility check compares 1,137 nodes against the existing frozen
baseline. Characterized migration differences name the standard Button Label
children and the declarative Alert anchor; no additional geometry waiver was
introduced. Documentation links and the renamed consumer-test evidence were
updated, and the Match 3 source check now reads executable automatic-animation
code rather than accepting the obsolete name in a comment.
