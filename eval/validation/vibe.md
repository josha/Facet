# Vibe evaluation calibration

The owner selected short player prompts on 2026-10-15. `extended.json` is the
headline: 11 chained tasks, two arms, seed 1 and five devices.
`extended-spec.json` keeps the detailed briefs as a diagnostic. The `brief.md` files are diagnostic specs. `slice.json` uses its short prompt.

Each play case has a tier. The universal cases run with their own
navigation, server-state and geometry observations. The retained cases are
spec diagnostics because they include exact copy, formats, counts or sequences.
Universal cases do not depend on those diagnostic cases passing. Follow-up
universal cases retain earlier player outcomes. The diagnostic play report can
fail while the headline run passes. The report tool requires the universal
scores, the contract, agent completion, budgets, complete universal audits,
blind judgments and the existing quality and overhead rules. Use that tool for
the headline. Verify's raw `passed` field is not the headline pass rate.

| Turn | Universal play | Spec play | Universal audits | Spec audits |
| --- | ---: | ---: | ---: | ---: |
| racing-hub | 17 | 138 | 16 | 39 |
| hub-shop-categories | 18 | 140 | 16 | 41 |
| hub-garage-sort | 19 | 142 | 16 | 43 |
| hub-settings-reset | 20 | 144 | 16 | 44 |
| hub-race-scoreboard | 20 | 145 | 16 | 45 |
| hub-livery-editor | 22 | 147 | 17 | 47 |
| hub-track-vote | 24 | 149 | 18 | 49 |
| hub-quick-chat | 26 | 151 | 19 | 51 |
| hub-upgrades | 28 | 153 | 20 | 53 |
| hub-party-invite | 30 | 155 | 21 | 55 |
| hub-first-time-tutorial | 31 | 158 | 22 | 58 |
| racing-hub slice | 6 | 24 | 5 | 6 |

Counts are per device. The headline uses all five devices; the slice uses two.
The table excludes one build case in each producer and the contract and type commands.

The play build case and the unchanged-contract command are universal integrity
checks. Strict types are diagnostic. Each `audit-universal-*` is universal;
the other audits are spec diagnostics. The required `play` producer runs only
universal cases. The non-required `spec` producer runs the original cases in
fresh game sessions. Both write reports, scores and `tiers.json`.
The score names are `play.universal.<device>.fraction`, `.passed`, `.total`
and `spec.fraction.<device>`. Diagnostic captures
are kept in `checks/spec-captures`; only universal captures enter the blind
judge. The full original briefs remain available to the spec agent.

Within universal screen audits, clipping, truncation, contrast, offscreen
content, safe areas, touch targets, interactive overlap, gamepad reachability,
hidden focus and broken selection links are universal. Type scale, spacing
scale, instance budgets and press feedback are diagnostic. Their violations
remain in the raw audit reports but do not enter the headline audit metric.
Synthetic tests prove that even large failures in those four categories do
not gate the headline.

Each producer owns its process, Studio, game state and performance observations.
Universal purchases and race rewards cannot change the starter state expected
by the exact-spec cases. Diagnostic failures, timeouts and performance scores
do not enter the universal verdict. Their evidence remains under `checks/spec`.

Touch observations read `PlayerGui.TouchGui.TouchControlFrame` at runtime.
They use the visible ThumbstickFrame or DynamicThumbstickFrame, JumpButton and
each bound CAS button. The probe uses AbsolutePosition and AbsoluteSize in the
same viewport coordinates as the UI dump. The check runs in the hub, open
panels, the queue, the race and results. It checks both interactive controls
and text. It requires the TouchControlFrame to be observable on touch devices;
an absent probe is not a pass. Rectangle attachments preserve the measured
controls for review. The weak hub Kit puts a button on the actual jump button.
CAS buttons remain available to the player driver and the audit. A reserved
button and its own labels do not collide with themselves; other UI still fails.
The other weak turns retain their faults; several also disable their Close
action. Tutorial Back still fails to return to the earlier step.

The predicates use GuiObject.AbsolutePosition, AbsoluteSize,
ContextActionService:GetAllBoundActionInfo() and GetButton(). Compose's
geometry.overlaps and firstClear operate on supplied rectangles; they do not
observe Roblox's default controls. Its component ownership and state APIs do
not supply those observations either.
The references use native Instances. No Compose mechanism or vendor snapshot
was changed for these checks. The existing audit is a property audit: rendered
occlusion, text legibility and physical controller behavior still need Studio
and human review. Do not call the references calibrated before that review.

## Scoped Studio MCP handoff

Verify main has the change since `5c8e51d`. It provisions a new Studio for each agent run, exposes one
immutable id through an MCP proxy, refuses other ids and unknown tools, and
closes the Studio before hidden checks or after an adapter failure. It exposes
play/stop, captures, execute_luau, input and console output. Input runs native
VirtualInput code on Client. Images pass through as MCP images.

`arms/studio-access.json` is the identical setup for both arms. The Verify
snapshot selection includes the proxy executable. Direct MCP configuration does not need
plugins, so both arms keep plugins, computer use and browser use disabled.
The Facet arm keeps its product CLI. Both arms use recorded adapter token
usage for all shell and MCP calls, including cached tokens. No MCP text is
counted twice and no MCP call is free.

Do not start a headline agent run with the old pin. The team notes require a
setup failure if scoped tools are absent. Keep `--parallel 1` until the owner
has accepted native isolation evidence. Sequential mode is the configured
fallback; no agent evaluation was run for this change.

## Studio calibration commands

No Studio was launched for this work. First assemble and check the references:

```sh
lute run tools/facet facetbench prepare
lute run tools/facet check facetbench-references
```

Then run every turn and arm sequentially in PowerShell:

```powershell
$turns = @('racing-hub','hub-shop-categories','hub-garage-sort','hub-settings-reset','hub-race-scoreboard','hub-livery-editor','hub-track-vote','hub-quick-chat','hub-upgrades','hub-party-invite','hub-first-time-tutorial')
foreach ($turn in $turns) {
  $task = if ([Array]::IndexOf($turns, $turn) -in 1..4) { "eval/tasks/extended/$turn" } else { "eval/tasks/$turn" }
  foreach ($arm in @('strong','weak')) {
    $out = "artifacts/facetbench/calibration/$turn/$arm"
    lute run "$task/hidden/play.luau" --workspace "artifacts/facetbench/reference-headless/$turn/$arm" --outputs "$out/checks" --captures "$out/captures" --report "$out/report.json" --run "calibrate-$turn-$arm" --scores "$out/scores.json" --devices desktop,phone-portrait,phone-landscape,tablet,console
  }
}
```

Read the tier scores for every device. Each strong reference must pass every
universal case; each weak turn must fail a universal case. These commands run
only the universal tier. Add `--tier spec` with a separate output directory to
inspect the original diagnostic cases from a fresh game state.
Inspect the touch rectangle attachments, especially phone landscape, in both
the hub and race. Check actual driving, mouse, touch and gamepad interaction,
focus return, back routes, scrims and all visible text. Rotate and resize during
the tutorial. The fixed-device sessions do not prove live rotation behavior.

Run the extended evaluation:

```sh
lute run eval/tools/check.luau
lute run eval/tools/shared-kit.luau
lute run tools/facet kit --out artifacts/facetbench/arm-facet --force
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/extended.json --parallel 1 --fresh
lute run tools/vendor/verify/tools/agent-eval.luau judge --suite eval/extended.json --transport api
lute run eval/tools/report.luau artifacts/facetbench/extended
```

Before agent measurement, test two owned Studios and an unrelated open Studio
with the proxy. Each run must list only itself, refuse the other's id for every
tool, and refuse unknown tools. Test adapter failure and timeout cleanup. Run
Verify's native gate on that authenticated host. Do not enable parallelism on
headless evidence alone.

For the diagnostic suite use `eval/extended-spec.json`, then:

```sh
lute run eval/tools/report.luau artifacts/facetbench/extended-spec --suite eval/extended-spec.json
```
## Headless validation receipt

The corpus check passes, including both prompt variants, all tier declarations,
producer isolation, device coverage and capture mappings. The reference check
assembles all 22 workspaces and passes their contract, strict types, lint and
Rojo builds. It does not prove that the strong references pass the live
universal cases or that the weak references fail them.

Strict types pass over all 1184 repository targets with zero blocking
findings and all 186 negative public-type probes. The final focused run over
the five changed host, report, fixture, test and corpus files also passes,
with zero blocking and 897 dependency diagnostics. The headline synthetic
spec passes after testing spec-only failures, diagnostic audit budget failures,
missing universal evidence and a failed required universal producer.

The full Facet gate was run as `gate-1792087777-32964-1`. Its only failed
producer was format; the formatting was then corrected. Do not call that run
a full pass. The focused checks and final fast gate do not replace full gate
evidence. The benchmark run reports `FAIL_ENVIRONMENT`: yardstick drift is
38.5 percent, so its timing verdict is invalid. Package build and package
status exit successfully. No package was published. The status still records
publication drift and pending native evidence.

Verify's final headless gate is `gate-1792087879-509799-1`: 806 of 810 cases
pass, including the new isolation and cleanup cases. Four process watchdog
and process-observation failures reproduce on main `ff2a119` in baseline run
`gate-1792087523-881767-1` (33 of 37 cases in the affected files pass).
They are baseline failures, not new scoped-MCP regressions. Native input,
launch, isolation and cleanup still need the owner's Studio host.

No Studio, native gate, agent evaluation or blind judge was launched.
No commits were pushed. The Verify snapshot was not re-pinned pending review.

The final fast gate passes all 13 selected producers in
`gate-1792092538-819329-1`; 25 producers and 14 cases are not selected.
Earlier sandboxed attempts failed only because the type self-test could not
refresh `~/.lute/typedefs/1.0.1`. The final run used the required cache access.
The focused headline run `gate-1792092180-308341-1` passes all 10 reported
cases. Documentation style, links and `git diff --check` also pass.
