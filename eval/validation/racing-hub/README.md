# Racing hub references

The strong reference has one interface module for each system and a shared reference kit. One hub owns panel navigation. The server owns one wallet, part ownership, selected loadout, free crates, XP, and race rewards. The weak reference keeps the same content but removes selection support, forces large panels, and leaves purchase state stale. Its directory holds the three files that differ: `Kit.luau`, `shop/init.luau`, and `round-hud/init.luau`; `validation/games.json` reads the other files from `strong`.

Build the starter and reference overlays with Rojo. Static checks do not prove live input, geometry, or a strong versus weak result. See [the evaluation guide](../../README.md#check-tiers-and-calibration) for current tier counts and calibration requirements.

The reference uses native `UIListLayout`, `UIGridLayout`, `UIPadding`, `ScrollingFrame`, `GuiService.SelectedObject`, `GuiObject.SelectionGroup`, and `ContextActionService.BindActionAtPriority`. The engine API and the existing reference kit cover layout, selection, and input. The Compose runtime and component APIs were checked. They are not used in the plain reference because the reference must work without a UI package. The score code uses the public Verify interface dump and context APIs. It adds game-specific observations and uses the existing play host for execution and reports.

When Studio is available, run from the repository root:

```sh
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/validation/games.json --parallel 1
```

For an existing interface workspace, run all devices:

```sh
lute run eval/tasks/racing-hub/hidden/play.luau --workspace <workspace> --outputs <evidence>/out --captures <evidence>/captures --report <evidence>/report.json --run racing-hub-manual --scores <evidence>/scores.json --devices desktop,phone-portrait,phone-landscape,tablet,console
```

Use each turn's `hidden/play.luau` for its completed workspace. Review the Verify report, each named screen, the dumps, and `coherence.json`. Check the weak failures as well as the strong results before recording a calibration result.


## Turn overlays

Each reference directory contains only changed interface files. The fixture suite for a turn uses strong references for all preceding turns. Its final turn uses either the strong or weak file. Thus a weak reference has one deliberate fault. Preparation derives `followups/strong` from the racing-hub reference and three patches. It also derives fixture task configurations from the canonical task files. Verify scopes task overlays to declared arm names: the agent suite has `plain` and `facet`, and the fixture suites have `strong` and `weak`. Verify has no suite-level mapping for these task arm names. The derived configurations keep all checks, resolve command paths to the canonical task directory, and map the overlay to the fixture arms. Generated files are ignored by Git.

| Turn | Checks on every device | Deliberate weak fault |
| --- | --- | --- |
| Livery editor | Body and accent swatches, shade, decal grid, dirty preview summary, unsaved state before Save, saved decal and shade, reopen, Revert question, Cancel, discard, dirty Close or B. | Revert skips the discard question and keeps the draft. |
| Track vote | Three cards, changing countdown, first vote, own-vote mark, changed vote with old count removed, remote count change, highest-count winner, locked actions. | Vote actions remain enabled after time ends. |
| Quick chat | Eight reachable wheel choices, one send, visible message, preserved cooldown, disabled send, send after cooldown, return navigation. Desktop opens with Q. | Send choices stay enabled during cooldown. The server still rejects a second send. |
| Upgrades | Both prices, disabled purchase with Coins but no Gems, Cancel, one charge in each currency, updated rating readout, separate kart levels. | The enabled state ignores Gems. The server still rejects the purchase. |
| Party invite | Three presence states, case-insensitive search, empty state, Clear, offline action disabled, Pending, Accepted, Declined, correct party strip. | Clear keeps the filter text. |
| First-time tutorial | Three ordered steps, Back, Skip, final Next, target activation while help is visible, return to the same step, recorded dismissal. | Back keeps the current step. |

| Device | Additional input and geometry evidence |
| --- | --- |
| Desktop | Mouse activation, Q entry, visible text fit, viewport bounds, screenshots and interface audits. |
| Phone portrait | Touch activation, scrolling to offscreen choices, 44-pixel target checks, text fit, safe-area audits. |
| Phone landscape | The same checks at the short landscape height. This is a separate session, not a rotation test. |
| Tablet | Touch activation and scrolling at the tablet size, target and text-fit checks. |
| Console | Engine selection routes to actions, Return activation, Backspace as B, and focus return. Real gamepad button events remain manual evidence. |


## Race contract

`GetRoundState` and `RoundStateChanged` use the same state: `round`, `phase`, `endsAt`, `mode`, `racers`, and optional `rewards`. There are no team fields. `racers` is in server position order. Each racer has `name`, `position`, `lap`, `lapCount`, `completedLaps`, optional `bestLap`, `gap`, `finished`, and `eliminated`. Lap times and gaps use seconds. A finished racer stays ahead of an unfinished racer. At the time limit, checkpoint progress orders unfinished racers. Results retain that order. `rewards[name]` gives Coins: 50 for first, then 5 fewer per position, with a minimum of 20. The shared Ledger pays Coins, 5 Gems, 120 XP, and daily race progress once.

`Hub.State.positions` is the same ordered list of names, with the local name shown as `You`. It comes from the round state. The manual `positions` hook updates both views. The `laps` hook updates completed laps and finish state. A new race resets to a fixed grid: players first, then names in alphabetical order.

`mode` defaults to `race`. All racers can finish three laps. `lap-knockout` is optional. When the leader completes a new lap, the last active unfinished racer is out. No knockout occurs before lap 1, twice for the same lap, or for the only remaining racer. `RoundEvent` is only for these knockout notices: `{ kind = "elimination", victim, by, at }`. `by` is `lap N`. Manual scenarios can set the same OUT state with the existing hook. They cannot set a lap-zero knockout. Natural finishes do not advance manual scenario phases.

## Motion and world

The server runs seeded opponent driving at fixed steps and samples the physical player kart. Opponents change lanes, keep a following gap, and brake when blocked. Server collision bodies interact with the player. Clients predict current progress and lane from replicated snapshots and correct non-colliding visual copies before the chase camera. Native VehicleSeat physics stays with the player. Off-track recovery runs on the owning client. The smoothed chase camera runs at `Enum.RenderPriority.Camera` and restores the hub camera. See [opponent spacing](#opponent-spacing) for the driving policy and evidence scope.

`Workspace.WorldTheme` accepts `bright` and `scifi`. A missing attribute uses `bright`. Eval projects set `scifi`. The strong playtest project sets `Lighting.Technology` to `Future`. The sci-fi world has a metal deck and plaza with twelve thin Neon panel seams. Ambient and OutdoorAmbient keep the floor and silhouettes visible. Eight seeded light towers replace the trees. Cyan is the primary accent. Two tower beacons use magenta. Barriers have dark metal bodies and thin cyan Neon rails. Each body spans two track sections, measured at its own lane endpoints to keep the bends closed. Curbs alternate muted blue accents. The metal start gantry has cyan trim and a pale green start light. The kart nose and spoiler keep their Neon accents.

The night Sky has 5,000 stars and a large native moon. Blue Atmosphere and purple decay color soften the horizon. Bloom and ColorCorrectionEffect control glow and contrast. Four shadowless lights illuminate the scene: two SurfaceLights under the hub stall roofs and two PointLights on track towers. There are no frame updates or unseeded random values in the world builder. Both themes keep 511 generated world parts and eight parts per kart. The sci-fi theme has twelve floor seams and four gantry details. Finish tiles keep a 0.03-stud gap above the road. The headless geometry case builds both themes and compares every visible decoration face with every asphalt section, including oriented horizontal overlap.

Native mechanisms include `RunService.BindToRenderStep`, `Workspace.GetServerTimeNow`, `VehicleSeat`, `Model.PivotTo`, native scrolling and layout, `Material.Neon`, `Atmosphere`, `BloomEffect`, and `Sky`. Native engine APIs supply rendering, physics, and layout. Race rules and the deterministic spline are game policy. No Facet or Compose API changes are needed.

The world also uses native `Sky.StarCount`, `Sky.CelestialBodiesShown`, `Sky.MoonAngularSize`, `Lighting.Ambient`, `Lighting.OutdoorAmbient`, `Atmosphere.Decay`, `ColorCorrectionEffect`, `SurfaceLight`, and `PointLight`. Native parts, materials, sky, and lighting supply this scene. Compose components and resource ownership do not need a new mechanism for static world construction.

## Check tiers

Universal race checks require a player position and lap, rival standings, a live position update, finishers in results, and the server currency reward. They retain selection release, the clear road center, actual thumbstick, jump and action-button rectangles, safe insets, readable text, contrast, and target size. They do not require a color palette or a named UI framework.

Spec checks retain exact phase and timer formats, `Position N`, `Lap N/TOTAL`, named roster entries, optional OUT notices, four feed lines, exact reward copy, scoreboard columns, and keyboard toggles. The scoreboard reads server positions, completed laps, gap, and finish state. Hub and turn prompts request a sci-fi neon identity. The blind judge assesses the look. There are no new hidden style checks.

The strong reference uses a cyan and violet palette, upper-edge standings and loadout scrollers, and a results scroller. Closing results returns to the hub. The weak reference puts the race readout in the center, which fails the universal road-clear check. It also has selection, phone-width, and stale-purchase faults.

## Calibration

Headless calibration runs the shared reference checker for both variants of all 11 tasks: contract, strict types, lint, and Rojo builds. The geometry and race-rule cases use Verify. These establish static and deterministic behavior. They do not establish rendered contrast, replication quality, touch input, camera quality, or live strong-pass and weak-fail results.

Run from the repository root:

```powershell
lute run tools/facet facetbench prepare
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/validation/games.json --parallel 1
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/validation/hub-first-time-tutorial.json --parallel 1
lute run eval/tasks/racing-hub/hidden/driving.luau --workspace eval/validation/racing-hub/strong --outputs artifacts/race/studio-driving/out --captures artifacts/race/studio-driving/captures --report artifacts/race/studio-driving/report.json --run individual-driving --devices desktop,phone-portrait,phone-landscape,tablet,console
```

The fixture suites run both references on all five devices. Keep universal and spec reports separate. Confirm that the strong reference passes the universal race cases and the weak reference fails the center-clear assertion. Check the optional knockout mode after lap 1, a natural three-lap finish, camera restoration, client recovery, and rival motion on a phone. Inspect the night-world captures for readability.

Build the playtest place:

```powershell
rojo build eval/validation/racing-hub/strong/default.project.json -o artifacts/facetbench/racing-race.rbxlx
```


## Opponent spacing

`Opponents` owns driving policy. It runs at a fixed 60 steps per second. Each
driver has a seeded pace and a small periodic pace change. Three lanes cover
the road. A driver checks the lane ahead and the gap behind before it reserves
a passing lane. Lane movement is limited to five studs per second. Drivers
reduce speed as they approach the following gap. They stop when every route is
blocked. Checks wrap at the start line and include lapped karts and the player. The player's projected width includes its steering angle.

The server samples the player's physical kart and moves opponent collision
bodies. It calculates laps, finish times, and standings from the resulting
progress. Finished opponents continue around the circuit. Their recorded finish
time and position remain fixed by the existing race rules.

Opponent chassis parts collide. `PhysicsService` collision groups keep wheels
from catching on kart bodies. Wheels still collide with the road. Chassis
friction is low and elasticity is zero. Native `Touched` events trigger the
bump response even when a player's replicated position is late. Contact reduces
opponent speed and
applies a horizontal `BasePart:ApplyImpulse` to the player. A cooldown limits
repeat impulses. The player's `LinearVelocity` force and target speed reduce
briefly so the impulse can move the kart aside. `AlignOrientation` continues to
keep the player upright. No vertical impulse is applied.

Clients leave collision bodies under server control. They hide those bodies
locally and render non-colliding copies from consecutive snapshots. A snapshot
holds progress, lane, and time since race start. The epoch is a separate number
attribute so a Vector3 does not round away subsecond clock precision. Rendering
runs before the chase camera with `RunService:BindToRenderStep`. The client
predicts the current position and corrects its render state continuously. This
keeps a moving kart's visible body close to its collision body. Extrapolation
is limited to 0.1 seconds.

Native mechanisms include `PhysicsService`,
`BasePart.CollisionGroup`, `BasePart.CanCollide`, `BasePart.AssemblyLinearVelocity`,
`BasePart:ApplyImpulse`, `BasePart.Touched`, `LinearVelocity`, `AlignOrientation`, `Model:PivotTo`,
`Workspace:GetServerTimeNow`, and `RunService:BindToRenderStep`. They supply
collision response, constraints, transforms, and render scheduling. Racing policy and network
snapshot interpolation belong to this game. They need no interface composition
mechanism or Facet change.

## Headless checks

`tests/racing_track.verify.luau` uses Verify's public harness. It simulates
120 seconds at 60 steps per second for three seeds, with a parked player on the
circuit. It checks every pair of oriented kart footprints at every step. It
also checks continuous lane movement, identical seed replays, passing, and
completion of three laps. A second case blocks all lanes and checks braking.
The existing race contract and world cases remain in the same spec.

These cases prove deterministic driving policy and sampled geometry. They do
not prove native contact response or replication quality. The live driving check
in this guide and rear and side contact checks supply that evidence.


## Driving and scenario controls

Both arms and reference assemblies use the starter's server, shared data, and
driving client. The scenery seed is 20261015. The plaza has a garage, shop,
mechanic, crate area, and queue gate. Sunfield Circuit has 80 asphalt sections
and 16 checkpoints.

WASD and arrows drive on a keyboard. The left thumbstick and triggers drive on
a gamepad. The default Roblox thumbstick drives on touch devices. Hold Left
Shift or gamepad X for at least 0.35 seconds while moving, then release to boost.
A sharp steering input also charges drift. Ease that input to release the boost
on touch. A boost lasts 1.2 seconds. The race camera restores the hub camera
when the race ends. Recovery returns an off-track kart to its last checkpoint.

Scenario preparation calls the `manual` hook. Manual rounds put the player kart
on the spline controller. Natural finishes do not advance manual phases. The
knockout hook sets OUT state and emits a lap event. The driving client does not
override selection.

`SunfieldRaceStep` is the server MicroProfiler label. Workspace attributes
`RaceStepMeanUs`, `RaceStepMaxUs`, and `RaceStepHz` report the last measurement
window. They exclude client rendering, replication, and engine physics. Measure
frame time and memory in Studio.

State-changing server requests use a per-player lock across yields. Success and
errors release the lock. Read requests do not take this lock. Return to Hub
takes the lock.

Build with `rojo build eval/validation/racing-hub/strong/default.project.json -o artifacts/facetbench/racing-race.rbxlx`.
Open the place in Studio. Press Play, open the interface Play control, and join
Solo or Duo. Drive three laps or wait for the time limit. Inspect results and
return to the hub. Check keyboard, gamepad triggers, touch drift, seat stability,
camera recovery, and respawn on each device.

The live driving check starts a normal race through the `driving` hook. It
requires an unanchored VehicleSeat with autopilot disabled. Its route controller
writes throttle and steering. It does not pivot the kart or advance race state.
The check requires more than 30 studs of movement, steering input, three ordered
server checkpoints, and an updated eight-racer standings list. It clears inputs
after success or failure.
