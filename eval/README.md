# FacetBench

The headline suite is [`extended.json`](extended.json). It uses short player prompts for the hub and ten chained follow-ups. [`extended-spec.json`](extended-spec.json) uses detailed diagnostic briefs. See [the slice report](reports/slice.md) for a saved paired measurement and the built place of each arm.

FacetBench measures how well AI coding agents build Roblox game interfaces. It compares two arms on the same game:

| Arm | Setup |
| --- | --- |
| `plain` | Plain Roblox Instances and native engine features. No third-party interface framework. See [`arms/plain/AGENTS.md`](arms/plain/AGENTS.md). |
| `facet` | The Facet interface library and its author kit. See [`arms/facet/AGENTS.md`](arms/facet/AGENTS.md). The arm has a third overlay, the generated kit. Before a run, write it with `lute run tools/facet kit --out artifacts/facetbench/arm-facet --force`: the library in `Packages/Facet`, the `info`, `docs`, `lint`, `preview` and `audit` commands, the documentation, the starter blocks and the use-facet skill. |

Both arms get the same briefs, the same [team notes](arms/shared/TEAM_NOTES.md), the same agent, the strict type check `tools/typecheck/check.luau` from `arms/shared`, and the generated `artifacts/facetbench/arm-shared` with the pinned Roblox definitions (write it with `lute run eval/tools/shared-kit.luau`). The briefs say what players and designers want. The hidden checks look only at what a player can see and do, at the calls to the game contract and at the interface geometry of the engine. No brief or check depends on the API of either arm.

The suites use the [Verify agent evaluation](../tools/vendor/verify/docs/agent-eval.md). Verify provisions each run, starts the agent, runs the hidden checks, audits the interface, judges the screenshots and computes the statistics.

## The racing hub

The racing hub combines the 16 UI tasks that we see most often in Roblox games into one game with one economy and one hub. [`sources.md`](sources.md) describes the interfaces behind it. See [`tasks/racing-hub/brief.md`](tasks/racing-hub/brief.md).

| Task | Player task |
| --- | --- |
| `racing-hub` | Build the whole game interface: the HUD and dock, the shop, garage, inventory, drivers, crates, daily rewards, codes, settings, the mechanic, the queue, the race HUD and the results. |
| `hub-shop-categories` | Follow-up turn: shop category tabs and a confirmation for large purchases. |
| `hub-garage-sort` | Follow-up turn: garage search and sort. |
| `hub-settings-reset` | Follow-up turn: reset settings to defaults with a saved indicator. |
| `hub-race-scoreboard` | Follow-up turn: a sorted race scoreboard. |
| `racing-hub/slice` | A configuration of the racing hub for the fast loop: the same starter, a [brief](tasks/racing-hub/slice/brief.md) that asks only for the HUD, its dock panels and the shop, and only the HUD, shop and coherence checks. |

Each task directory holds `task.json`, the short `vibe.md` prompt and the detailed `brief.md` spec. The racing hub also has `starter/` and `hidden/`. The starter is a Rojo project. `src/server` owns game state and validates requests. `src/shared` is the strict typed network contract. The interface goes in `src/client/Interface/init.luau`. A follow-up starts from the workspace named by `from` in the same arm and seed and keeps earlier checks.

## Hidden checks

Each task has these checks, in this order:

1. `contract` (command, required): `src/server` and `src/shared` are the same as in the starter.
2. `types` (command, not required): `tools/typecheck/check.luau` in strict mode over `src/client`. It records `types.passed` and `types.errors`.
3. `play` (Verify report, required): [`tools/play/host/play.luau`](../tools/play/host/play.luau) builds the workspace, mounts the probe and starts a disposable Studio. Each device runs universal cases. `--systems` keeps the slice's `hud-dock,shop` systems.
4. `spec` (Verify report, not required): the same host runs the original diagnostic cases in fresh game sessions. Its state, timeouts, captures and performance evidence stay separate.
5. `audit-<screen>` (interface audit, not required, one for each device): the Verify interface audit of the dump that the play check saved for that screen. `lute run eval/tools/check.luau` checks that each audited screen is named by a case of each audited session.

The play check drives the interface only as a player can:

- It finds elements by their visible text, their role (button, text field, selectable) and their position near other text. It never reads instance names.
- It taps and clicks with engine `VirtualInput` events at the screen point of the element, after it checks that no other control covers the point. A tap counts only when the button fires `Activated`. It scrolls a list to find a row that is not mounted yet.
- It types with `VirtualInput` text input into the focused text field, and scrolls with the wheel or with a touch drag.
- On the console device it moves the engine selection with direction keys and activates with Return, as a gamepad would.
- It reads the results from the game contract through the server `AdminCommands` hook of the starter.

For each device the play check also writes `{captures}/<device>/<screen>.png` (the Studio capture of each named screen), `{outputs}/dumps/<device>/<screen>.json` (the interface audit dump), `{scores}` (the cases that passed and the capture counts) and `{outputs}/perf.json` with `perf.<device>.<metric>` scores. Run output stays under `artifacts/`; the repository holds no dumps, captures or logs.

### Game coherence scores

Each device collects visible properties from the dumps of all named screens. The counts are a union across screens. Each count has a generous upper bound so a small design variation can pass.

| Score suffix under `coherence.<device>.` | What it covers | Upper bound |
| --- | --- | --- |
| `distinctFonts` | Text font families. Weights do not add a family. | 6 |
| `distinctTextSizes` | Text sizes, rounded to whole pixels. | 24 |
| `distinctTextColors` | Text colors, rounded to 0.01 per channel. | 48 |
| `distinctSpacing` | Layout gaps and padding, rounded to whole pixels. | 32 |
| `distinctButtonColors` | Button background colors. | 32 |
| `distinctButtonStyles` | Button background color and transparency, text color, size, and bold state. | 64 |
| `returnControlSpreadX`, `returnControlSpreadY` | The range of the right edge and top position of each panel's Close control, divided by the viewport size. | 0.40, 0.25 |

Navigation cases check one-level Close and Back, a visible return control on each panel, console focus return, and a route back to the hub. Cross-screen cases check the shared wallet, purchase ownership, equipped parts, the mechanic's free crate, the next race's kart and driver, positions, and race rewards. The slice runs no cross-screen case.

## Cost measurements

The probe measures the interface in play mode on each device. It counts only the game interface: the descendants of the layer collectors in the `PlayerGui`, without the touch controls, the chat and the probe overlays.

| Score | What it covers |
| --- | --- |
| `mountSeconds` | Seconds from play start to the start of the first complete, stable layout run. The probe confirms the run over one second of rendered frames, with a 20-second failure bound. It includes player join, probe readiness, host calls and fixed host waits. |
| `baseGuiObjects`, `baseComponents` | GuiObjects and UIComponent instances at rest after mount. |
| `peakGuiObjects`, `peakComponents` | The largest counts at the end of a case that names a screen. |
| `idleFrameP50Ms`, `idleFrameP95Ms` | The median and the 95th percentile of the client frame time (the `RenderStepped` delta) over two idle seconds after mount. |
| `activeFrameP50Ms`, `activeFrameP95Ms` | The same frame times while the cases that name a screen run. |
| `heapDeltaKb` | `gcinfo()` in the returned-hub snapshot minus after mount. Noisy. |
| `instanceDelta`, `guiObjectDelta` | `Stats.InstanceCount` and GuiObjects in that snapshot minus after mount. |
| `guiMbDelta` | `Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Gui)` in that snapshot minus after mount. |

The frame time is the whole client frame, including the probe. Both arms run the same game, place, device and cases, so the difference between the arms is the difference of the interfaces. `lute run eval/tools/overhead.luau <evidence directory>` prints each metric for each task, device and arm, the ratio of the treatment arm to the baseline arm, and the median ratio. `lute run eval/tools/coverage.luau <evidence directory>...` writes `usage.json` for each Facet run and prints which Facet controls the runs use and which no run uses. `lute run eval/tools/internals.luau <run directory>...` writes `internals.json` for each run and lists each tool call that opens Facet or author-tool source, with the reason that the agent wrote before the call. The Facet arm reads source only to diagnose a suspected bug, so each entry points at a documentation gap or a bug.

The play host is shared with the `preview` and `audit` author commands. It is in [`tools/play`](../tools/play).

Mount uses the same probe for both arms and both references. Each measured UI
object must exist and have a measured size. The probe compares object identity,
parent, absolute position and absolute size each frame. An addition, removal,
replacement, reparenting or other layout movement restarts the stable run.
An empty screen cannot settle. Zero sizes remain valid for hidden objects and
empty progress fills; later size changes are compared on each frame.

Live content does not restart the run when only its own content or fill changes.
The probe excludes a TextLabel or TextButton whose Text changed in that frame.
It also excludes an element whose size changes on one axis, whose position
stays fixed and whose parent size stays fixed. Any other resize or a neighbour
moving still restarts the run. The one-axis rule also covers text sizing when
the parent size and the element position stay fixed. These rules use no arm,
library or instance-name filter.

Each device's `perf.json` record keeps `mount.liveContent` with each excluded
element's identity, full path, reason, frame count and first and last observation
times, with before and after geometry and text samples.
`mount.timedOut` and the `mountTimedOut` score identify failure-bound captures;
their mount value uses the 20-second bound. The host also logs these captures.
The raw bound is retained in `perf.json`; a timed-out capture emits no valid
`mountSeconds` score, so the existing missing-evidence rule fails closed.
The 1.10 Facet/plain mount limit remains in `overhead.json`.

For a saved workspace, `lute run tools/facet facetbench mount WORKSPACE OUTPUT`
captures desktop and phone portrait in one owned Studio and closes it. It
observes the current definition and the whole-screen geometry checksum on the
same rendered frames. `legacyMountSeconds` and `mount.legacyTimedOut` preserve
the comparison. The command runs no agent and changes no saved source.

## Render preflight

Eval place projects use `Lighting.Technology = Future`. The corpus check
rejects missing technology and `Compatibility`.

Check a place before agent measurement:

```sh
lute run tools/facet facetbench render eval/validation/racing-hub/strong/default.project.json artifacts/facetbench/render
```

The command builds the place and starts an owned Studio. It checks a viewport
larger than 1 by 1 and advancing rendered frames, records the observation, and
closes that Studio. This check does not replace reference calibration.

## Devices

| Device | Real in Studio | Approximated |
| --- | --- | --- |
| `desktop` | Device Simulator preset `hd_1080`: a 1920 x 1080 viewport, mouse and keyboard input. | The Studio window scales the view, so a capture can be smaller than 1920 x 1080. |
| `phone-portrait` | Preset `iphone_14` in portrait: the screen size, the notch and home bar insets and `TouchEnabled`. The simulator turns `VirtualInput` mouse events into `Touch` input. | No multi-touch, IME or on-screen keyboard. |
| `phone-landscape` | Preset `iphone_14` in landscape. | As for `phone-portrait`. |
| `tablet` | Preset `ipad_10th_generation` in landscape. | As for `phone-portrait`. |
| `console` | Preset `xbox`: a 1920 x 1080 console viewport with `GuiService:IsTenFootInterface()` and `GamepadEnabled`. Engine selection navigation moves and activates the controls. | `VirtualInput` has no gamepad events. Arrow keys stand for the D-pad, Return for A and `Backspace` for B. |

## Metrics and thresholds

For the finished headline run, use `lute run eval/tools/report.luau <evidence directory>`.
It writes `headline.md` with rule intervals, task medians, overhead ratios and
seed costs. See [the report inventory, confirmed overhead limits and Studio
validation steps](REPORT.md).
Instances are reported, not gated. The headline passes only when all quality
and overhead rules pass and no required evidence is missing.

[`thresholds.json`](thresholds.json) declares the claim before a run. The treatment is `facet`; the baseline is `plain`. Intervals use paired percentile bootstraps over tasks, at 95% confidence, with 4000 resamples and seed 20261014. Each rule needs at least 5 paired tasks. The headline has 11 chained tasks.

| Rule | Metric | Passes when |
| --- | --- | --- |
| `pass-rate-gain` | `passRate` | The pass rate of `facet` is at least 25 points higher. |
| `pass-rate-gain-interval` | `passRate` | The lower bound of the difference is above 0. |
| `judge-win-rate` | `judgeWinRate` | The blind judge prefers `facet` in at least 70% of the comparisons. |
| `judge-win-rate-interval` | `judgeWinRate` | The lower bound of the win rate is above 0.60. |
| `fewer-audit-violations` | `auditViolations` | `facet` has at most 0.4 times the audit violations of `plain`. |
| `fewer-tokens` | `totalTokens` | `facet` uses at most 0.5 times the tokens. |
| `less-wall-time` | `wallSeconds` | `facet` takes at most 0.6 times the wall time. |
| `faster-turns` | `turnLatencyP50` | The upper bound of the median turn latency ratio is below 1. |

A headline run passes when the agent completed, the contract and every universal
play case passed, and no budget was exceeded. Spec cases remain diagnostic.
Use `eval/tools/report.luau` for that verdict. The separate non-required spec
producer retains diagnostics without changing universal state or measurements.

## Run

Install Roblox Studio, sign in, and turn on the Studio MCP server. Install the toolchain with `rokit install` (Lute, Rojo, StyLua and luau-lsp). The agent is the `codex` command line with the pinned tools first on `PATH`. Before an extended run or reference calibration, run `lute run tools/facet facetbench prepare`. Before a run, write the shared files with `lute run eval/tools/shared-kit.luau` and the Facet arm kit with `lute run tools/facet kit --out artifacts/facetbench/arm-facet --force`.

| Suite | Use | Tasks | Seeds and devices |
| --- | --- | --- | --- |
| [`games.json`](games.json) | Five tasks with independent follow-ups. | The racing hub and four independent follow-ups. | Seeds 1 to 3, five devices. |
| [`slice.json`](slice.json) | The fast loop while Facet changes. | `racing-hub/slice`. | Seed 1, desktop and phone portrait. |
| [`extended.json`](extended.json) | The headline with vibe prompts and universal gates. | Hub and ten chained follow-ups. | Seed 1, five devices. |
| [`extended-spec.json`](extended-spec.json) | Detailed-spec diagnostic with both check tiers. | The same 11 tasks. | Seed 1, five devices. |
| [`validation/games.json`](validation/games.json) | The strong and weak reference interfaces, with the Verify `fixture` adapter. No agent runs. | The racing hub. | Seed 1, five devices. |

Run from the repository root:

```sh
lute run tools/vendor/verify/tools/agent-eval.luau plan   --suite eval/extended.json
lute run tools/vendor/verify/tools/agent-eval.luau run    --suite eval/extended.json --seed 1
lute run tools/vendor/verify/tools/agent-eval.luau judge  --suite eval/extended.json --transport api
lute run eval/tools/report.luau artifacts/facetbench/extended
```

- `plan` lists the runs. It starts nothing.
- `run` runs the agents and the hidden checks. Each play check starts its own Studio, so keep `--parallel 1`.
- `judge` compares the screenshots of both arms for each task, device and seed. With `--transport api`, it reads `ANTHROPIC_API_KEY`. Calibrate the judge with human labels before you rely on its win rate.
- `report` writes `quality.json` and `headline.md` and exits 1 when the verdict is `FAIL`.

To run the play check on one workspace:

```sh
lute run eval/tasks/racing-hub/hidden/play.luau --workspace <workspace> --outputs <evidence>/out --captures <evidence>/captures --report <evidence>/report.json --run manual --scores <evidence>/scores.json --devices desktop,console
```

`--devices` keeps only the named devices, and `--systems` only the named systems. Such a run is not a complete check. For a follow-up workspace, use the turn's own `hidden/play.luau`.

## Validation

[`validation/racing-hub`](validation/racing-hub) holds the plain-Roblox `strong` and `weak` reference interfaces. The strong interface has one hub, one wallet, and shared navigation. The weak interface differs in three files: missing selection paths and panels that are too wide for phones in `Kit.luau`, stale purchase states in `shop/init.luau`, and a central race timer in `round-hud/init.luau`; the suite reads its other files from `strong`. Run it when Studio is available:

```sh
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/validation/games.json --parallel 1
```

The gate producer `facetbench` runs [`tools/check.luau`](tools/check.luau). It loads the suites and the thresholds and checks that the play scenarios cover each device and each audited screen. It starts no Studio and no agent.

## Limits

- A pass proves that the hidden checks accepted the final workspace in Studio on this host. It proves nothing about real phones, real consoles or real gamepads.
- The checks find elements by visible text. An interface that shows the right words in an unusual structure can still fail a check.
- The play check reads the contract state through a server hook of the starter. An agent that breaks the starter project can fail the check for that reason.
- The audit reads native and resolved styled properties. It does not see rendered pixels or animation. Its selection path is an approximation.
- Captures come from the Studio viewport through the MCP capture tool. Their size depends on the Studio window.
- `VirtualInput` refuses a key that Roblox binds to a core action, for example Tab while the Roblox player list is on. The scoreboard turn asks for the player list to be off, and the check reports a refused key as a failure with the reason.

The starter contains a shared playable kart world. Eval agents build only the interface. See [the reference guide](validation/racing-hub/README.md) for the race contract, controls, world, and driving checks.

## Check tiers and calibration

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
The references use native Instances. The existing audit is a property audit: rendered
occlusion, text legibility and physical controller behavior still need Studio
and human review. Do not call the references calibrated before that review.

## Scoped Studio MCP access

Verify provisions a new Studio for each agent run, exposes one
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

The team notes require a setup failure if scoped tools are absent. Keep `--parallel 1`. Native isolation evidence is required before parallel runs.

## Studio calibration commands

First assemble and check the references:

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
