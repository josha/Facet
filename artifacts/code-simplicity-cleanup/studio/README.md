# Studio evidence — Step 5.5 cleanup

**Status: CLOSED 2026-07-28. All five matrix rows green, plus a sixth row for the
changed scroll path.** `studio-evidence` is no longer `FAIL_ENVIRONMENT`.

**Session:** 2026-07-28, Studio 0.731.210.7312203, place `Place1`, solo Play.
**Source stamp:** `efbe185e-2570354` — read back from `workspace.LuauUI_SourceStamp`
on every call below.

## Why a Studio session was required at all

The cleanup touched the solver (grid column derivation), the renderer
(`scrollToVisible`'s host lookup, the compact-label paint branch, the mounted-node
lookup), the mount layer (structural-region dispatch), five composite controls
(`enabled` semantics), and the scope diagnostic channel. Every one of those is in
the "visible / input / layout / adapter / lifecycle behaviour CAN change" class, so
the execution contract's real-adapter requirement is triggered, and because layout
can change the five-view matrix is triggered too.

## The place was re-injected first

The earlier session ran at stamp `2fb81a11-2569207`. The fresh-context review
response then changed `src/core/scope_impl.luau` and `src/motion/clock.luau`
(comments), `tests/`, and the gate manifest — moving the stamp to
`efbe185e-2570354`. Rather than carry the two old rows forward, the place was
**re-injected** (150 nodes, 2 patched) and **all five rows were re-run** at the new
stamp. No row below is inherited.

## Preflight — PASS

`mode = "preflight"` on the reusable driver (`tools/studio/device_matrix.luau`,
served verbatim from the sync server so the installed copy cannot drift):

- `ok: true`, `problems: []`
- source stamp matches the injected manifest
- run mode `running`, scenario surface ready, scenario state `ready`
- viewport not `1×1`
- `StudioDeviceSimulatorService`: all ten members present
- `VirtualInput`: available, all six documented methods present
- device catalog: **42 entries** (16 Phone, 15 Tablet, 5 Console, 4 Desktop, 2 VR)

## Rows driven — 5 of 5

| Row | Device | Viewport | Result |
|---|---|---|---|
| `desktop-standard` | HD 720 | 1280×720 | **PASS** — `sizeClass: wide`, full stored report |
| `compact-phone-portrait` | Samsung Galaxy S22 Ultra, dpi 501 | 360×691 | **PASS** — `sizeClass: compact`, Quality picker collapses **segmented → inline** |
| `compact-phone-landscape` | same S22 Ultra, LandscapeLeft | 678×339 | **PASS** — *never run before this session* |
| `tablet-landscape` | iPad 9th Generation, dpi 264 | 1080×810 | **PASS** — *never run before this session* |
| `console-ten-foot` | PS4 | 1920×1080 | **PASS** — *never run before this session*; ten-foot profile live end to end: `isTenFoot true`, `distanceProfile ten-foot`, `typographyScale 1.5`, `preferredInput Gamepad` |

Every row: `diagnostics: []`, `solverDiagnostics: 0`, `offscreenNodes: []`,
`nodesCapped: false`, 125 nodes, five **distinct** viewports.

Full matrix: `five-view-matrix.json`. Full desktop scenario report, verbatim:
`adaptive-controls-desktop-efbe185e.json`.

`compact-phone-landscape` needs the portrait row's device pinned
(`requires.sameDeviceAs`), so it is driven with
`pinnedDeviceId = "samsung_galaxy_s22_ultra"`. Without the pin it correctly
reports *"no candidate satisfied the row's requirements"* rather than silently
picking a different phone.

## The row that actually exercises the changed code — `scroll_host`

`scroll-host-keepvisible.json`. The cleanup replaced the renderer's full-tree
`scrollAncestorOf` walk with a `scrollHostOf[path]` map lookup, so this drives the
framework's only scroll write against **real Roblox `ScrollingFrame`s** and reads
`CanvasPosition` back off the instance:

| Step | Target | Returned | Real instance |
|---|---|---|---|
| `keepVisibleAlreadyVisible` | `FocusList/Focus1` | `moved: false` | nothing moved |
| `keepVisibleFar` | `FocusList/Focus13` | `moved: true`, y 456 | `FocusList.CanvasPosition.Y` 0 → **456** |
| `keepVisibleHorizontal` | `Strip/Cell11` | `moved: true`, x 570 | `Strip.CanvasPosition.X` 0 → **570** |

The **correct** host moved each time and the siblings did not — which is exactly
what the map lookup has to get right for it to be equivalent to the walk it
replaced.

> `AbsoluteCanvasPosition` is **not** a member of `ScrollingFrame` and throws when
> read. The readable offset is `CanvasPosition`; `AbsoluteCanvasSize` and
> `AbsoluteWindowSize` are real.

## Recorded honestly, not claimed away

- **`preferredInput` reads `KeyboardAndMouse` on both phone rows and the tablet
  row.** The earlier session's README recorded `Touch` for
  `compact-phone-portrait`; this session does not reproduce that and the
  difference is not explained away. `StudioDeviceSimulatorService` changes
  resolution, density and orientation — it does not by itself make the engine
  report a Touch preferred input. This is a limitation of the E3 instrument, not a
  library result. What the library *did* adapt on those rows is real and recorded:
  `sizeClass` → `compact` and the picker → `inline`. **Real touch preferred-input
  stays E4 and unproven.**
- **`unfitText` is non-empty on every row** (3, and 4 on phone-landscape): the
  Actions labels "Save changes", "Reset to defaults", "Delete profile" report as
  not fitting, and the Save label reports `degradedToTitle: true`. The driver does
  not raise these as diagnostics and every row is `ok: true`. No pre-cleanup
  capture exists, so this is recorded as an observation of current state and is
  **not** claimed to be either new or pre-existing.
- `clippedNodes` is 112 of 125 on every row — the scenario body lives inside a
  scroll host, so most nodes are clipped by construction.

## Still E4, still unproven

Physical touch targeting and feel, physical rotation behaviour and the real
orientation-change animation, and real gamepad delivery on console hardware. None
of these is inferable from an emulated row and none is claimed.

## What carries the geometry before/after

Not these rows — they prove the real adapter produces a *correct* tree, not the
*same* tree, because no pre-cleanup Studio capture exists to diff against.

The before/after is carried by **`lune run tools/lune/check_flat_baseline`**, which
regenerates the unthemed render from live source through the real
mount → renderer → target stack and byte-compares **1 140 flat nodes** — every
solved rect, every hit rect, every class, every adapter prop write — against the
frozen Step 3.5 baseline. That is E1 evidence, and it is why the rows above are a
spot check rather than the whole proof.

## Reproducing this

1. `lune run tools/lune/studio_sync` (serves on `:8642`). Do not pipe it through
   `head` — that SIGPIPEs the server.
2. Studio **Edit**: run `tools/studio/inject.luau`, then
   `workspace:SetAttribute("LuauUI_Scenario", "adaptive_controls")`.
3. Install the driver as a `ModuleScript` named `LuauUIMatrixDriver` under
   `workspace` from `http://127.0.0.1:8642/driver`. Do it in **Edit** so it
   survives into Play.
4. Play. From the **Client** datamodel:
   `local run = require(workspace.LuauUIMatrixDriver)`.
   **`run()` returns a JSON string, not a table** — decode it.
5. `run({ mode = "preflight" })`, then per row
   `run({ mode = "select", row = <row> })` and `run({ mode = "observe", row = <row> })`.
   Pass `pinnedDeviceId = "samsung_galaxy_s22_ultra"` for
   `compact-phone-landscape`.
6. For the scroll row: stop Play, set `LuauUI_Scenario = "scroll_host"`, Play again,
   and drive through the **BindableFunctions** at `workspace.LuauUIScenarioAPI`
   (`step`, `steps`, `report`, `reset`, …). `_G.LuauUIScenario` is **not** visible
   across `execute_luau` calls; the BindableFunction bridge is.
