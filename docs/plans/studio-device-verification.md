# LuauUI Studio device verification

**Date:** 2026-07-24
**Status:** Required verification substrate for roadmap Steps 3–14, including Step
3.5, and for Step 5.5 cleanup changes that can affect visible or interactive
behavior.

## Decision

Use Roblox's scriptable Studio testing APIs to automate a small, stable
cross-device matrix. This replaces manual Device Emulator clicking and fragile
external pointer injection for the behavior these APIs can observe. It does not
replace physical-device or human-feel gates.

Current first-party sources:

- [New Studio Testing APIs and Assistant Improvements](https://devforum.roblox.com/t/new-studio-testing-apis-and-assistant-improvements/4657854)
- [`StudioDeviceSimulatorService`](https://create.roblox.com/docs/reference/engine/classes/StudioDeviceSimulatorService)
- [`VirtualInput`](https://create.roblox.com/docs/reference/engine/classes/VirtualInput)
- [`StudioTestService`](https://create.roblox.com/docs/reference/engine/classes/StudioTestService)

Re-check these sources when implementing because Studio is a rolling platform.

## What each API owns

### Device and orientation

`StudioDeviceSimulatorService` is the device-matrix driver. From a Studio-only
plugin or supported Assistant/MCP workflow, it can enumerate the current device
catalog, select a preset, change orientation, override resolution and DPI, choose
viewport scaling, and create persistent custom profiles.

Do not hard-code catalog IDs. Discover them with `GetDeviceListAsync()`, inspect
each candidate with `GetDeviceInfoAsync()`, choose the device that satisfies the
named matrix role, and record the exact ID and returned configuration in the
artifact. Device switching and overrides are plugin-security APIs and some calls
error in PlayServer mode, so this driver belongs in development tooling, not in
LuauUI runtime code or a shipped example.

### Player-like scriptable input

Create `VirtualInput` through `UserInputService:CreateVirtualInput()`. Use it for
mouse buttons and movement, keyboard keys and text, and pointer wheel/pan/pinch.
These events run through Roblox's input path rather than calling a LuauUI callback
directly.

Coordinates must be derived from the mounted control's live
`AbsolutePosition`/`AbsoluteSize` and the active simulator configuration. A test
must fail as an environment error if the event lands on `CoreGui`, the viewport is
stale, or the raw event does not arrive. Never retry by calling the control's
callback directly.

`VirtualInput` does not synthesize a real touch contact or gamepad. It also does
not summon a mobile operating-system keyboard. Pointer pan on a phone-shaped
viewport is useful automation, but it is not physical-touch evidence.

### Play and multiplayer lifecycle

Use `StudioTestService` for repeatable Play/Run sessions, test arguments, staged
joins, disconnects, and server-returned results. It supports up to eight simulated
clients. Current Studio does not provide reliable fine-grained control of every
individual client through this API, and `GetTestArgs()` has a documented
client-LocalScript issue. Keep scenario selection authoritative on the server or
through the existing replicated test surface.

Device-layout sweeps are normally solo focused-client sessions. Use multiplayer
sessions only for requirements that actually need multiple clients, such as
join/leave cleanup or Sponsor lifecycle. If combining a device preset with a
multiplayer launch, select and verify the preset before the test and record what
each client actually reports; do not assume every client inherited the requested
profile.

## Canonical matrix

Five view rows cover the useful layout extremes without multiplying every fixture
across the full Studio catalog:

| ID | Simulator role | Orientation | Main risk covered |
|---|---|---|---|
| `compact-phone-portrait` | Narrowest supported built-in phone preset with stable output | Portrait | Minimum width, vertical compression, safe insets, touch-sized geometry |
| `compact-phone-landscape` | Same phone preset | LandscapeLeft | Short height, orientation adaptation, state survival |
| `tablet-landscape` | Representative built-in tablet preset | LandscapeLeft | Mid-size reflow and density assumptions |
| `desktop-standard` | Desktop profile at the project's standard development viewport | Landscape | Pointer/keyboard layout and uncapped-width mistakes |
| `console-ten-foot` | Console form at 1920×1080 or the closest built-in preset | Landscape | Ten-foot sizing, focus visibility, and large-view composition |

The console row proves only layout, geometry, and focus behavior visible in Studio.
It does not prove gamepad delivery, `PreferredInput == Gamepad`, television
overscan, or console performance.

For text-entry work, add one optional `phone-keyboard-occluded` row using a custom
device configuration with a recorded virtual keyboard height. This proves that the
layout responds to the declared occluded area; it does not prove a real mobile
keyboard.

Preferred text size, reduced motion, locale expansion, and hybrid input are fixture
axes, not new device profiles. Run them on the smallest relevant subset that covers
their failure mode instead of taking a Cartesian product of every axis.

## Required automation loop

For each applicable row:

1. Run the execution contract's Studio preflight.
2. Resolve the current catalog entry and record its configuration.
3. Select the device and orientation through `StudioDeviceSimulatorService`.
4. Wait for `ConfigurationChanged`, then require a stable non-`1×1`
   `CurrentCamera.ViewportSize`.
5. Record device ID/name, form, resolution, DPI, scaling mode, orientation,
   viewport, safe/inset geometry, Studio version, and build/fixture identity.
6. Mount or reset one deterministic scenario through the shared verification
   surface.
7. Assert solved and actual geometry, clipping, visibility, focus, style authority,
   state, and mount identity before taking a picture.
8. Drive supported mouse, keyboard, text, or pointer actions with `VirtualInput`
   using live control geometry. Pair the raw/native event with the semantic action
   and visible state change.
9. Capture the stable state and export one machine-readable row result.
10. Tear down the scenario and stop or reset device simulation before the next row.

The driver should run one fixture or a representative batch and emit a bounded
summary. It must reuse the existing gallery scenario surface, gate manifest, and
artifact schema rather than becoming a second UI test framework.

## Measured on Studio 0.731 (2026-07-26, roadmap Step 4)

The plan above was written from documentation. These are what the APIs actually did
when the driver was built against them. Where they contradict the text above, these
win — and the driver re-probes every one of them per run rather than remembering them,
so the day a limit lifts, the automation starts using the capability.

| Claim above | What was measured | Consequence |
|---|---|---|
| "prefer `VirtualInput` over external clicking" | Its documented methods — `SendKey(isPressed, KeyCode)`, `SendMouseButton(pos, Enum.UserInputType, isPressed)`, `SendMouseDelta`, `SendMousePosition(Vector2)`, `SendPointerAction`, `SendTextInput(string)` — are **all present and callable**. `SendMouseButton` rejects a duplicate button state. **However**, in the Step-4 session its calls succeeded while delivering no observable input events (one early press excepted); the cause is unresolved. | Native input evidence for Step 4 came from injected input, labelled as such on every row. VirtualInput remains the preferred path and is re-probed each run. |
| device switching is scriptable | `SetDeviceAsync`, `SetOrientationAsync`, `SetResolutionAsync`, `SetPixelDensityAsync`, `SetScalingModeAsync`, **`StopSimulationAsync`** and the getters `GetDeviceAsync` / `GetResolutionAsync` / `GetPixelDensityAsync` / `GetOrientationAsync` / `GetScalingModeAsync` are all present, in Edit **and** Client. | A driven session CAN be returned to "no simulated device" from a script. Read the getters rather than echoing the catalog, or a requirement check merely re-asserts the selection filter. |
| "require a stable non-`1×1` viewport" | Necessary but **not sufficient**. `preferredInput` and `displaySize` settle *after* the viewport does: reading immediately after a console selection returned `KeyboardAndMouse`, and the same preset read seven frames later returned `Gamepad`. | The driver settles the **facts** (stable for six consecutive frames) as well as the pixels, and records how many frames it took. |
| record the resolution | The **scaling mode** decides this, not the emulator: with `SetScalingModeAsync(ActualResolution)` set, `SetResolutionAsync(1280, 720)` reports back exactly `1280×720`. Without setting it, `1280×719`. | Set and RECORD the scaling mode on every row. The 2px tolerance in the row requirements is slack for a mode the driver did not set, not a claim about the emulator. |
| step 4's "stable non-`1×1` viewport" | Necessary but not sufficient in a second way: after an orientation change the size stops changing *before* the engine has finished, so a row recorded a portrait `360×691` viewport beside a correctly-landscape environment of `678×339`. | Re-read the viewport after the fact-settle loop, and record the pre-settle value separately. |
| "derive positions from live geometry" | Necessary but not sufficient. Injected pointer coordinates are offset from the coordinates the engine reports by an amount that depends on the **emulated configuration** — 47px on a 360×691 phone, 0px on a 1080×810 tablet, in one session. | Calibrate per row: inject once, read the reported position, add the delta. `gameProcessed == false` is a free second opinion that the aim was wrong. See `docs/lessons/injected-input-offset-is-per-configuration.md`. |
| device sweeps are solo sessions | **Touch** is a boot-time fact: a desktop-booted session shows a phone viewport with `touch = false`. `displaySize` and `PreferredInput` are NOT boot-time — they follow a mid-session `SetDeviceAsync` about seven frames later (the console preset really does publish `Gamepad`). | The five rows need **two** Play sessions, for TOUCH; and every row must settle the display facts, not just the viewport. |
| — | `HttpService` requests are **server-only** during Play. | The driver is fetched and installed from the Server datamodel, then required from the Client. |
| — | The override setters require an ACTIVE device. Measured: `SetScalingModeAsync` errors with *"no device is active"* straight after `StopSimulationAsync`; Roblox documents the same precondition for the resolution and pixel-density setters. | Select the device FIRST, then scaling mode / resolution / density. The driver's per-candidate setter order is deliberate. |

The device catalog is also misleading in two directions, which is why the selection
policy filters on pixel density rather than `DeviceForm` alone: Roblox classifies its
Android TV entry as a **Tablet** (1920×1080 at 44 dpi), and its handheld consoles as
**Console** — `generic_handheld_720` at 1280×720/274 dpi and `generic_handheld_1080`
at 1920×1080/411 dpi.

**A note on how two of these rows were first written wrong.** The `VirtualInput` and
"no stop member" rows above originally said the opposite, because a *boolean*
capability probe cannot tell "that member name does not exist" from "you are not
allowed to call it", and the probe used invented names. Both were caught by a
fresh-context platform review checking the names against first-party documentation.
The probe is tri-state now; the general rule is in
`docs/lessons/capability-probes-must-be-tri-state.md`.

## Honest evidence boundary

The automated matrix can close Studio-visible layout, clipping, focus, StyleSheet,
mouse, keyboard, and pointer rows when the trace and capture agree. It cannot close:

- physical touch targeting, gestures, or touch feel;
- real gamepad delivery, platform arbitration, or console behavior;
- the mobile operating-system keyboard;
- operating-system display scaling not represented by the selected simulator
  configuration;
- retail-client networking;
- low-end CPU, GPU, memory, thermal, battery, or frame-time performance;
- subjective readability, hierarchy, motion, or production feel.

Keep those rows `PENDING_PHYSICAL` or `PENDING_HUMAN` under the execution contract.
Studio-emulated performance remains useful regression evidence but is never the
low-end Android result.

## Use by roadmap stage

| Step | Required use |
|---|---|
| 3 | Sweep each new adaptive layout/control fixture through the five view rows; use `VirtualInput` for observable pointer/keyboard paths and a live phone orientation change |
| 3.5 | Build Fantasy Parchment through public APIs, then swap it and the flat package in the all-controls fixture; verify nine-slice panels/control states, effective fonts/metrics, solved/actual/hit geometry, adaptive input paradigms, mount/focus identity, asset fallback, and cost |
| 4 | Build the reusable driver, artifact schema, and intentional-failure proof if Step 3 did not already finish them; keep emulated and physical performance rows separate |
| 5 | Run Sponsor-shaped framework fixtures on the relevant matrix rows, including drag/scroll, interruption, preferred text, and teardown |
| 6 | Run identical legacy and LuauUI Sponsor fixtures at the same device rows; use `StudioTestService` only for lifecycle rows that need multiple clients |
| 7 | Run the fresh-author control and any runtime-affecting compatible repair on applicable rows; documentation-only rules need no fake Studio evidence |
| 8 | Drive Tab/Shift+Tab, Space/Return, and arrows with `VirtualInput` on desktop and keyboard-capable phone/tablet configurations; pair raw input with responder, focus, action, scroll, and state traces |
| 9 | Use the matrix to prove performance-lab layout, scenario controls, and repeatability; never treat it as the low-end Android performance gate |
| 10 | Batch all seven examples under both materially different theme packages across the five view rows, then drive the canonical keyboard/pointer gameplay paths with `VirtualInput`; keep touch/gamepad rows separate |
| 11 | Run each clean-room reference loop on the applicable five views and prove reflow, theme, state/focus survival, and supported input paths; Apple host-OS features are ledger rows, not simulator fixtures |
| 12 | Use Studio for server/client topology, Instance/lifecycle, streaming-like, failure, and cost evidence; the five-view UI matrix applies only if the spike includes a player-facing LuauUI surface |
| 13 | Rerun representative matrix scenarios for every runtime-affecting finding/fix and compare them with the frozen baseline |
| 14 | Run the standalone consumer from the clean source export and prove mount, theme, adaptation, input, geometry, and teardown without monorepo imports; Package publishing is irrelevant to this row |
