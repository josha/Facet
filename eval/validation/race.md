# Individual kart race

Worktree: `C:\git\facet-wt\race`, branch `eval/race`.
The base is `eval/vibe` because `eval/slice-run` did not exist. The first commit merges `claude/agent-evals-5`.

## Race contract

`GetRoundState` and `RoundStateChanged` use the same state: `round`, `phase`, `endsAt`, `mode`, `racers`, and optional `rewards`. There are no team fields. `racers` is in server position order. Each racer has `name`, `position`, `lap`, `lapCount`, `completedLaps`, optional `bestLap`, `gap`, `finished`, and `eliminated`. Lap times and gaps use seconds. A finished racer stays ahead of an unfinished racer. At the time limit, checkpoint progress orders unfinished racers. Results retain that order. `rewards[name]` gives Coins: 50 for first, then 5 fewer per position, with a minimum of 20. The shared Ledger pays Coins, 5 Gems, 120 XP, and daily race progress once.

`Hub.State.positions` is the same ordered list of names, with the local name shown as `You`. It comes from the round state. The manual `positions` hook updates both views. The `laps` hook updates completed laps and finish state. A new race resets to a fixed grid: players first, then names in alphabetical order.

`mode` defaults to `race`. All racers can finish three laps. `lap-knockout` is optional. When the leader completes a new lap, the last active unfinished racer is out. No knockout occurs before lap 1, twice for the same lap, or for the only remaining racer. `RoundEvent` is only for these knockout notices: `{ kind = "elimination", victim, by, at }`. `by` is `lap N`. Manual scenarios can set the same OUT state with the existing hook. They cannot set a lap-zero knockout. Natural finishes do not advance manual scenario phases.

## Motion and world

The server calculates progress from `Workspace:GetServerTimeNow`. Rival models carry a start clock, grid progress, speed, and lane. Clients use the same clock and spline every render frame before the camera. The server does not stream kart CFrames. Native VehicleSeat physics stays with the player. Off-track recovery runs on the owning client. The smoothed chase camera runs at `Enum.RenderPriority.Camera` and restores the hub camera.

`Workspace.WorldTheme` accepts `bright` and `scifi`. A missing attribute uses `bright`. Eval projects set `scifi`. The strong playtest project sets `Lighting.Technology` to `Future`. The sci-fi world has a metal deck and plaza with twelve thin Neon panel seams. Ambient and OutdoorAmbient keep the floor and silhouettes visible. Eight seeded light towers replace the trees. Cyan is the primary accent. Two tower beacons use magenta. Barriers have dark metal bodies and thin cyan Neon rails. Each body spans two track sections, measured at its own lane endpoints to keep the bends closed. Curbs alternate muted blue accents. The metal start gantry has cyan trim and a pale green start light. The kart nose and spoiler keep their Neon accents.

The night Sky has 5,000 stars and a large native moon. Blue Atmosphere and purple decay color soften the horizon. Bloom and ColorCorrectionEffect control glow and contrast. Four shadowless lights illuminate the scene: two SurfaceLights under the hub stall roofs and two PointLights on track towers. There are no frame updates or unseeded random values in the world builder. Both themes keep 511 generated world parts and eight parts per kart. The sci-fi theme uses the sixteen parts saved by the tree replacement for twelve floor seams and four gantry details. Curbs stay 0.03 studs above their old position. Finish tiles keep a 0.03-stud gap above the road. The headless geometry case builds both themes and compares every visible decoration face with every asphalt section, including oriented horizontal overlap.

Native APIs checked: `RunService.BindToRenderStep`, `Workspace.GetServerTimeNow`, `VehicleSeat`, `Model.PivotTo`, native scrolling and layout, `Material.Neon`, `Atmosphere`, `BloomEffect`, and `Sky`. The pinned Compose runtime and consumer API were checked. Native engine APIs supply rendering, physics, and layout. Race rules and the deterministic spline are game policy. No Facet or Compose API changes are needed.

The world polish also uses native `Sky.StarCount`, `Sky.CelestialBodiesShown`, `Sky.MoonAngularSize`, `Lighting.Ambient`, `Lighting.OutdoorAmbient`, `Atmosphere.Decay`, `ColorCorrectionEffect`, `SurfaceLight`, and `PointLight`. The creator-docs engine reference and the pinned Compose API reference were checked. Native parts, materials, sky, and lighting supply this scene. Compose components and resource ownership do not need a new mechanism for static world construction.

## Check tiers

Universal race checks require a player position and lap, rival standings, a live position update, finishers in results, and the server currency reward. They retain selection release, the clear road center, actual thumbstick, jump and action-button rectangles, safe insets, readable text, contrast, and target size. They do not require a color palette or a named UI framework.

Spec checks retain exact phase and timer formats, `Position N`, `Lap N/TOTAL`, named roster entries, optional OUT notices, four feed lines, exact reward copy, scoreboard columns, and keyboard toggles. The scoreboard reads server positions, completed laps, gap, and finish state. Hub and turn prompts request a sci-fi neon identity. The blind judge assesses the look. There are no new hidden style checks.

The strong reference uses a cyan and violet palette, upper-edge standings and loadout scrollers, and a results scroller. Closing results returns to the hub. The weak reference puts the race readout in the center, which fails the universal road-clear check. Its earlier focus, phone-width, and purchase faults remain.

## Calibration

Headless calibration runs the shared reference checker for both variants of all 11 tasks: contract, strict types, lint, and Rojo builds. The geometry and race-rule cases use Verify. These establish static and deterministic behavior. They do not establish rendered contrast, replication quality, touch input, camera quality, or live strong-pass and weak-fail results. Studio was not opened.

When the eval releases Studio, run from this worktree:

```powershell
lute run tools/facet facetbench prepare
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/validation/games.json --parallel 1
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/validation/hub-first-time-tutorial.json --parallel 1
lute run eval/tasks/racing-hub/hidden/driving.luau --workspace eval/validation/racing-hub/strong --outputs artifacts/race/studio-driving/out --captures artifacts/race/studio-driving/captures --report artifacts/race/studio-driving/report.json --run individual-driving --devices desktop,phone-portrait,phone-landscape,tablet,console
```

The fixture suites run both references on all five devices. Keep universal and spec reports separate. Confirm that the strong reference passes the universal race cases and the weak reference fails the center-clear assertion. Check the optional knockout mode after lap 1, a natural three-lap finish, camera restoration, client recovery, and rival motion on a phone. Inspect the night-world captures for readability.

Build the playtest place:

```powershell
rojo build eval/validation/racing-hub/strong/default.project.json -o C:\Users\bacon\AppData\Local\Temp\claude\C--git-Facet\1761db0d-2ae5-46ec-82c2-3fb8baf68f14\scratchpad\racing-race.rbxlx
```

## Validation receipt

| Check | Result |
| --- | --- |
| Strict types, old solver | Passed: 1,191 targets, zero blocking diagnostics, 186 negative probes rejected. |
| Strict types, new solver | Passed on all 17 changed Luau targets, then on the final readout predicate. This is focused evidence. |
| Eval corpus | Passed. Case counts remain 17 universal and 138 spec cases per device for the base hub. |
| Headless reference calibration | Passed: all 22 strong and weak task assemblies pass contract, strict types, lint, and Rojo build checks. |
| Race and world cases | Passed: four Verify cases cover payouts and reset, optional knockouts, both world geometries, and the closed spline. |
| Fast gate | Passed: all 13 selected producers. This is the fast tier, with 25 producers and 14 cases excluded. |
| Full gate | Exited zero: 35 producers passed, benchmark and performance timing deferred on this host. Selected 37 of 38 producers; the release-only proof was excluded. This is not a release attestation. |
| Separate benchmark | Passed. |
| Package build and status | Both exited zero. Status reports unpublished source drift and pending Studio evidence. Nothing was published. |
| Sci-fi playtest build | Passed at the scratchpad path above. |
| Studio calibration | Not run. Studio was kept closed. The commands above remain required for live geometry, readability, motion, and input evidence. |

Logs are under `artifacts/race/`: `types.log`, `types-new-focused.log`, `types-new-readout.log`, `corpus.log`, `references-final.log`, `geometry.log`, `fast-final.log`, `full-final.log`, `bench.log`, `package-build.log`, and `package-status.log`.

An early sandboxed check could not update Lute's global typedef cache. The retry with cache access passed. An early gate found a formatting error in the generated scoreboard overlay. The source patch was corrected, and the regenerated eval sources pass StyLua. The first full run deferred host timing checks. These results are separate from deterministic regressions. No live strong-pass or weak-fail result is claimed by the headless checks.

## Sci-fi world polish receipt

The generated world stays at 511 parts in both themes. Each kart still uses eight parts. The sci-fi world adds four shadowless lights. The default builder theme stays `bright`. The strong eval stays `scifi` and uses Future lighting. The scratchpad playtest place was rebuilt after the final source change. Studio was not opened for this work. Rendered floor contrast, star visibility, haze, and glow still need live review.

The focused Verify run passed all five race and world cases. The new case checks the part budget, light limit, metal barriers, Neon trim, tree replacement, sky, post effects, and the default bright theme. The existing geometry case still checks every road section in both themes. Both strict solvers passed the two changed Luau targets with zero blocking diagnostics. This is focused type evidence. The eval corpus check passed. The fast gate passed all 13 selected producers, with 25 producers and 14 cases excluded by tier. This is fast-tier evidence. The local package build and package status both exited zero. Status reports unpublished source drift and a pending Studio check. Nothing was published.

The first strict run found an optional material type in the new code. Explicit enum branches fixed it. The first new test used an unavailable global Enum. It now uses the engine fixture's Enum. A benchmark attempt reported unstable host timing. These early results are not final validation results.

The full gate exited zero. It selected 37 of 38 producers: 36 passed, the performance timing check was deferred on this host, and the release-only proof was excluded. All selected cases ran. The complete old-solver check passed 1,191 targets with zero blocking diagnostics and rejected all 186 negative probes. Headless reference calibration passed with zero findings. The full gate's benchmark passed with stable timing. The performance timing deferral also appears in the earlier baseline receipt. It does not establish a world regression or a release attestation.

The standalone benchmark retry exited 2 with `FAIL_ENVIRONMENT`: the timing calibration drift was 16.1%, above the 15% limit. No performance regression is established by that run. The successful benchmark inside the full gate and the invalid standalone timing results are separate evidence.

Polish logs are under `artifacts/race/`: `polish-types-focused.log`, `polish-corpus.log`, `polish-fast.log`, `polish-full.log`, `polish-bench.log`, `polish-bench-final.log`, `polish-package-build.log`, and `polish-package-status.log`. The full gate report is `artifacts/verify/native/gate/gate-1792097578-971101-1/outcome.json`.
