# Racing world handoff

The starter contains the shared world. Both arms and all reference assemblies use the same server, shared data, and driving script. No external assets or binary places are committed. The scenery seed is 20261015.

The plaza has a garage, shop stall, mechanic stand, crate area, queue gate, and a spawn that faces the track. Sunfield Circuit has a closed Catmull-Rom spline, 80 asphalt sections, alternating curbs, barriers, a finish gantry, trees, and 16 checkpoints. A race has three laps and seven rivals with distinct colors. Each leader lap marks the last active racer OUT. The racers that finish stay ahead of unfinished racers. Finish order selects the winning team. The existing Ledger pays the team reward, Gems, XP, and daily race progress once. The 90-second limit ends a race with unfinished racers ranked by checkpoint progress.

The player uses a native VehicleSeat with HingeConstraint wheels, planar LinearVelocity, AngularVelocity steering, and AlignOrientation for upright recovery. WASD and arrows drive on a keyboard. The left thumbstick and triggers drive on a gamepad. The default Roblox touch thumbstick drives on touch devices. Hold Left Shift or gamepad X for at least 0.35 seconds while moving, then release to boost. Holding a sharp steering input also charges drift; easing that input releases the boost. This gives touch players the same mechanic without another button or GUI. A boost lasts 1.2 seconds. The race camera follows the kart; the previous camera type, subject, and field of view return when the race ends. The server reseats a player who jumps or respawns during a race. A kart that leaves the circuit returns to its last checkpoint.

The scenario preparation calls the existing `manual` hook before each system. Manual rounds put the local kart on the same spline controller as the rivals. Natural finishes and lap eliminations do not change scenario state in this mode. Existing phase, timer, elimination, position, queue, and reward hooks remain available. The scenarios drive their existing events in the same order. The driving client does not override selection, so it cannot hide a UI failure.

The round HUD has three new behavior cases. They sample selection with no panel open, reject interactive UI in the lower-left thumbstick region, and reject visible UI paint in the central road corridor. The checks use Verify dumps and the existing play host. They do not read interface names or framework APIs. The strong reference clears selection on race entry and uses edge readouts. The weak reference puts its timer in the center. This deliberately fails the road corridor check. Existing weak faults remain. The headless geometry tests check the exclusion rules. The actual strong-pass and weak-fail calibration still requires Studio.

## Cost

The world builder creates 511 static parts. The project adds the spawn and mechanic: 513 parts in the hub. Each kart adds eight parts. A race with one player and seven rivals has 577 world and kart parts, excluding the player's avatar. Kinematic rivals have no active physics constraints or collisions. The player has four wheel hinges and three active drive constraints. Hub frames only test whether a race is active. There are no geometry or driving updates in the hub.

During a race the server runs at no more than 30 updates per second. Each update does at most eight racer updates, seven model pivots in normal play (eight in scenario mode), and an eight-entry in-place standings sort. The client updates one kart's velocity, steering, and camera per rendered frame. The hot loops create no Instances, connections, closures, or Luau tables. Native Vector3 and CFrame values still have engine costs. Lap elimination and recovery are occasional work outside the normal update budget. The existing hub state publisher still runs at four updates per second.

Actual engine frame time and memory require Studio. `SunfieldRaceStep` is the server MicroProfiler label. Workspace attributes `RaceStepMeanUs`, `RaceStepMaxUs`, and `RaceStepHz` report the last measurement window. They exclude client rendering, replication, and engine physics. Inspect them with the existing frame and memory evidence during calibration. No Studio frame-time result is claimed by a headless build.

## Build and play

From `C:\git\facet-wt\scenery`, run:

```powershell
rojo build eval/validation/racing-hub/strong/default.project.json -o artifacts/facetbench/scenery/strong.rbxlx
```

Open `C:\git\facet-wt\scenery\artifacts\facetbench\scenery\strong.rbxlx` in Studio. Press Play, use the interface Play control, and join Solo or Duo. The queue fills with rivals. Drive three laps or wait for the time limit. Inspect results and return to the hub. The starter place has the empty interface entry point for eval agents; use the strong place for the full manual game loop.

Use the fixture command in [the reference handoff](racing-hub/README.md) for calibration. Studio was not launched during this work. Confirm keyboard, gamepad triggers, touch drift, seat stability, camera recovery, respawn, and the three HUD checks on all five devices.

## Native API review

The creator-docs references for VehicleSeat, HingeConstraint, LinearVelocity, AngularVelocity, AlignOrientation, ContextActionService, and Camera were checked. The native seat owns movement input and sitting. Constraints own physics. ContextActionService owns the optional drift action. Camera owns the chase view. Kart-specific speed, drift charge, spline progress, and race rules are game policy. Compose runtime constructors and ownership were checked in the pinned package and consumer references. Compose owns UI composition; it does not replace native physics or the world server. No Facet or vendor contract changed.

## Live playtest repairs

State-changing starter requests use one `guarded` helper when each `OnServerInvoke` callback is assigned. The helper holds a per-player lock across yields and releases the lock after success or an error. Read requests do not take this lock. Return to Hub also takes the lock. No code reads an engine callback to wrap it. The starter, extended starter, and reference handlers were checked. The `admin.OnInvoke` reads in the starter refer to plain Luau tables, not BindableFunctions. No other forbidden callback read or protected property access was found in these game sources.

The strong HUD puts the player stats after the Red roster in one native `UIListLayout`. The team panels use `ScrollingFrame`, `AutomaticCanvasSize`, and `UISizeConstraint` to limit their height to the device viewport. The command dock follows the measured bottom of the Blue roster. Text wrapping and viewport changes update these layouts. The hidden HUD case checks visible text rectangles across ScreenGuis, including full containment. It applies screen and scrolling clips and allows one pixel of edge rounding. It does not inspect arm names, control names, or framework APIs. Geometry fixtures accept separated readouts and reject the old overlapping positions. Actual strong-pass and weak-fail calibration still requires the five-device Studio run.

The Roblox references for `RemoteFunction.OnServerInvoke`, `RemoteEvent.OnServerEvent`, `BindableFunction.OnInvoke`, `UIListLayout`, `ScrollingFrame`, and `UISizeConstraint` were checked. Native callback assignment and layout cover the fixes. The pinned Compose runtime and consumer API were checked. Compose UI ownership does not supply game request serialization. The plain reference must work without a UI package.

### Verify gaps for upstream

- `reflection-snapshot.luau` stores properties and events, but no callback members or member security metadata. The environment cannot enforce callback read restrictions from that snapshot.
- `tests/lib/native_engine.luau` enables `functionDoubles`. In Verify's `environment.luau`, assignment of an undeclared function stores a simulated method. `readMember` then returns that method. A focused probe confirmed that assignment followed by a read succeeds for both `RemoteFunction.OnServerInvoke` and `BindableFunction.OnInvoke`. The same mechanism can accept `OnClientInvoke` reads.
- `readMember` does not check property scriptability or caller security. The configured `undeclaredReads = "nil"` also suppresses errors for absent members. A focused probe confirmed that reading `Script.Source` does not raise an error in this double. Roblox forbids that read from a Script or LocalScript. The game does not use `Script.Source`. See [Roblox Script.Source](https://create.roblox.com/docs/reference/engine/classes/Script/Source).
- Property writes do check `ReadOnly` and `Scriptability` metadata in `reflection.luau`. This is not evidence that protected reads, protected writes, or execution-context restrictions are enforced.
- `facetbench-references` checks contracts, types, style, and Rojo builds. It does not execute server startup. The existing racing specs exercise track math, race rules, scenarios, and geometry policy. They do not boot the server script. A passing build therefore did not establish that the intermission loop could start.
- Verify's built-in `interactive-overlap` rule checks interactive controls within one root. It does not check noninteractive text against other text across roots. The game-specific HUD case now uses the public UI dump to check that missing observation. Engine geometry still needs Studio.
