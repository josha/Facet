# 11 — Verifying on devices, and reading performance numbers honestly

This chapter is about instruments. Facet publishes performance numbers and
cross-platform claims, and every one of them is only as good as the thing that
measured it. So the framework's rule is simple and it is enforced by the gates:

> **Every number says which instrument produced it, and every instrument says
> what it cannot see.**

If you take one thing from this chapter, take this: a fast headless number is
not a phone result, and no amount of it ever becomes one.

## The five evidence classes

| Class | Instrument | What it proves | What it cannot |
|---|---|---|---|
| `lune` (headless) | `tools/perf.sh`, headless on your development machine | deterministic regressions in Facet's own decision and commit cost | engine frame work, paint cost, any device claim |
| `studio-emulated` (Studio) | a Roblox Studio Play session with a simulated device | the integrated adapter's real Instances, connections and frame work **on your host** | low-end CPU/GPU, memory pressure, thermals, battery |
| `desktop-retail` (device) | the retail Roblox client on your desktop | non-Studio client behaviour and desktop frame work | mobile or console hardware |
| `phone-physical` (device) | the weakest supported physical Android device | the supported device floor | console behaviour, subjective feel |
| `console-physical` (device) | the supported console / ten-foot path | gamepad delivery, overscan, console frame work | mobile behaviour, subjective feel |

Every performance record carries exactly one of these. `bench/perf_runner.luau`
emits only `lune` — that is a constant, not a parameter, because there is no
argument you could pass that turns a Lune process into a phone. And
`checkBudgets` **refuses** to enforce a device budget against a report with no
rows of that class: the refusal is a violation, not a pass.

The physical classes appear in every artifact **with zero rows** rather than
being omitted. Absence is stated, never inferred.

## The two budgets, and why they are different in kind

`bench/perf_budgets.json` holds both:

- **Trend budget** — `max(observed_p95 × 4, floor)`, derived from a measured
  baseline. It catches regressions. It says nothing about any device.
- **Frame ceiling** — the share of the supported frame target (a quarter) that
  one Facet update may occupy. It is **one-directional**: your development host
  is faster than every supported device, so exceeding the ceiling proves the
  scene cannot hold the frame target *anywhere*. Passing it proves nothing.

Device budgets for the three physical classes are declared with their frame
targets and marked `measured: false`. `tools/perf.sh` prints them as skipped on
every run, so an unchecked budget can never read as a checked one.

Re-baseline with `tools/perf.sh baseline` **only** when a cost increase is
intended. To convince yourself the gate is real, break it on purpose:

```bash
FACET_PERF_INJECT_REGRESSION=dense-hud tools/perf.sh   # expect exit 1
tools/perf.sh                                            # expect exit 0
lune run tools/lune/prove_perf_gate                      # does both, and records it
```

## The five-view device matrix

Five view rows cover the useful layout extremes: compact phone portrait, the same
phone landscape, tablet landscape, desktop at the standard development viewport,
and console/ten-foot. The rows themselves are code, not prose —
`src/preview/matrix_rows.luau` is where they live, and it is the only definition.

Roles, not device names. `src/preview/matrix_rows.luau` holds the pure selection
policy: it takes the **live** device catalog and ranks it, so no catalog ID is
hard-coded anywhere and a Studio release that renames a preset does not silently
break the matrix. Two of its rules exist because the catalog is misleading:

- Roblox classifies its Android TV entry as a **Tablet** (1920×1080 at 44 dpi).
  Filtering the tablet row on form alone measures a television.
- It classifies handheld consoles as **Console** — `generic_handheld_720`
  (1280×720 at 274 dpi) and `generic_handheld_1080` (1920×1080 at 411 dpi).
  Filtering the ten-foot row on form alone measures a device held at arm's
  length.

Pixel density is what separates them, and both exclusions are recorded on the
row with their reason.

A row also declares what must be true of the *running session* once the preset
is selected — not just what the catalog claimed. The console row requires
`displaySize == "Large"` (with no touch capability on the preset, so the
derived `effectiveDisplaySize` reads the same `"Large"` — ADR-0058's
touch-vs-`"Large"` correction never fires on a console row), because
`effectiveDisplaySize` is the fact that actually drives the ×1.5 type floor,
the overscan margins and the strengthened focus visual. Without it the row
would measure a large desktop and call it a console.

### Running it

```bash
lune run tools/lune/studio_sync        # serves library + gallery + the driver
# inject the manifest into the open place (Edit datamodel), set the workspace
# attribute Facet_Scenario = "perf_capture", then Play
```

Then, in the **Server** datamodel (HttpService is server-only during Play),
install the driver from the sync server into `workspace.FacetMatrixDriver`, and
drive it from the **Client**:

```lua
local run = require(workspace.FacetMatrixDriver)
run({ mode = "preflight", expectStamp = workspace:GetAttribute("Facet_SourceStamp") })
run({ mode = "row", row = "compact-phone-portrait" })
run({ mode = "row", row = "compact-phone-landscape", pinnedDeviceId = "<the phone row's device>" })
```

Then `lune run tools/lune/matrix_report` joins the rows with their captures and
pins each capture's content hash, so a picture and its trace cannot drift apart.

### Two sessions, not one — and which facts are which

Three different behaviours get lumped together as "device facts". They are not
the same, and only one of them forces a second Play session.

| Fact | Behaviour on a mid-session `SetDeviceAsync` | Measured |
|---|---|---|
| Viewport, orientation, resolution, density | follow immediately | every row |
| `displaySize`, `PreferredInput` | follow, but **several frames later** | stable after 7 frames on all five rows |
| **Touch capability** (`TouchGui`, a touch interaction class) | does **not** follow — decided at Play start from the then-selected preset | a desktop-booted session shows a 360×691 phone viewport with `touch = false` |

So the second session exists for **touch**, not for the display class: the phone
and tablet rows run in a session booted on a phone preset, and the desktop and
console rows in one booted on a desktop preset. The console row's
`PreferredInput = Gamepad` *does* arrive mid-session — after seven frames.

That settling delay is the trap. The driver waits for `preferredInput` and
`displaySize` to hold steady for six consecutive frames and records how many
frames it took; reading immediately after a console selection returns
`KeyboardAndMouse`, and a row that recorded it would have said the ten-foot
session had no gamepad. The viewport needs the same treatment for a different
reason: it stops changing before an orientation change is finished, so it is
re-read after the facts settle.

## Input: what counts, and what does not

`VirtualInput` is the intended scriptable input path, and its documented methods
are all present and callable: `SendKey(isPressed, KeyCode)`,
`SendMouseButton(position, Enum.UserInputType, isPressed)`, `SendMouseDelta`,
`SendMousePosition(Vector2)`, `SendPointerAction`, `SendTextInput(string)`.
`SendMouseButton` tracks button state and rejects a duplicate, so a run that
leaves the button down makes the next press a silent no-op.

> **This paragraph used to say the opposite.** An earlier version of this stage
> probed four member names that exist under no security level, and — because
> indexing a missing member *throws* rather than returning `nil` — reported the
> throw as a security refusal. The probe is tri-state now (`present` / `absent` /
> `blocked` / `error`) and keeps the raw error text, which is what makes the
> difference checkable rather than assumed. The same mistake had produced a
> second false claim about the device simulator. Both are recorded in the run's own
> evidence row, which is what makes the correction checkable rather than a
> remembered story.

One open limitation, stated because it is unresolved rather than because it is
comfortable: in this session VirtualInput's calls **succeeded but delivered no
observable input events** to the running client, apart from one early press that
did. The obvious hypothesis — that creating a fresh instance per call breaks
delivery — was tested and eliminated: one cached instance behaves the same. The
cause is not established. So this stage's native-input traces came from the
Studio Model Context Protocol (MCP) injector, every row says so in
`input.path`, and no row claims
VirtualInput drove it.

Whichever injector you use, two rules keep it honest:

1. **Calibrate the injection offset per row.** Injected coordinates and the
   coordinates the engine reports are offset by an amount that depends on the
   emulated configuration — measured at 47px on a 360×691 phone and 0px on a
   1080×810 tablet in the same session. A remembered constant silently aims your
   click somewhere else and the screenshot still looks right. Inject once, read
   the reported position back, add the delta. (`gameProcessed == false` on the
   raw event is a free second opinion: a click that hits no GUI is not consumed
   by the GUI.)
2. **Pair the raw event with the effect.** A capture cannot tell "the control
   did nothing" from "the click missed". The `perf_capture` scenario records
   both ends inside engine callbacks — the native `InputBegan`/`InputEnded` and
   the property write that changes what a player sees — so the difference is
   visible and measurable.

Injected pointer input in a phone-shaped viewport is **not** physical touch.
Synthetic KeyCodes are **not** a gamepad. Those rows stay `PENDING_PHYSICAL`.

### The device simulator's real surface

`StudioDeviceSimulatorService` on Studio 0.731 exposes `SetDeviceAsync`,
`SetOrientationAsync`, `SetResolutionAsync`, `SetScalingModeAsync`,
**`StopSimulationAsync`**, and the getters `GetDeviceAsync`,
`GetResolutionAsync`, `GetPixelDensityAsync`, `GetOrientationAsync` and
`GetScalingModeAsync`. The driver reads the getters rather than echoing the
catalog back at you — otherwise a requirement check just re-asserts the filter
the selection policy already applied.

**Set the scaling mode explicitly.** `ActualResolution` renders at exact pixel
resolution; `FitToWindow` scales to fill the pane. Asking for 1280×720 without
setting it returned 1280×719, which is easy to misfile as an emulator quirk. With
the mode set, the desktop row reports exactly 1280×720, and the mode is recorded
on every row.

**Re-read the viewport after the facts settle.** The size stops changing before
the engine has finished an orientation change: the landscape phone row once
recorded a *portrait* 360×691 viewport beside a correctly-landscape environment
of 678×339.

## `StudioTestService`: only where it is actually needed

Use it for scripted Play/Run sessions and for rows that genuinely need more than
one client — join/leave cleanup, lifecycle across clients. It supports up to
eight simulated clients, but current Studio does **not** give reliable
fine-grained control of each one, and `GetTestArgs()` has a documented
client-LocalScript issue. So: keep scenario selection authoritative on the
server or through the replicated test surface, and do not claim per-client
device profiles.

Device-layout sweeps are solo focused-client sessions. They do not need it, and
this stage did not use it.

## The hands-on place: `Facet-Showcase.rbxl`

Every claim above is an instrument reading. None of them is somebody holding the
thing. For that, `tools/build_places.sh` builds one publishable place —
`examples/places/Facet-Showcase.rbxl` — that you open once and explore:

- a **demo chip** at the top-left switches between the all-controls fixture and
  all seven tutorial examples, in game;
- a **theme chip** beside it switches between the reference theme packages, in
  game.

Before this, choosing what to look at meant setting a workspace attribute
(`Facet_Example = 5`) and republishing — a fine developer affordance and a
useless one on a device you are holding.

**How the chrome stays out of the way.** The two chips are separate presented
surfaces, so no solver lays them out together and neither can measure the other.
Floating them over the demo was the first answer and it was wrong: every demo
puts content somewhere, so a fixed overlay always covers *something*. The
showcase instead RESERVES a strip, through the same mechanism the CoreGui topbar
uses — it writes `coreSafeInsets` = (the engine's `GetGuiInset().Y` + the bar
height) on every frame, so the solver lays every demo out below both chips.
Nothing overlaps because nothing floats. Two details are load-bearing and each
cost a round to find:

- compute the inset **from the engine**, not by adding to whatever
  `coreSafeInsets` currently holds — the script runs before the adapter has
  published the real topbar, so the additive form reserved 40px of a 58px topbar
  and put the chips *underneath* the Roblox buttons;
- clip the chip **label**, not the chip **box** — a Button label wraps inside a
  narrower box, so `maxWidth` grew the chip a second line and pushed it back out
  of the strip and over the demo's title.

**Driving it without a pointer.** The place publishes
`workspace.FacetShowcaseAPI` (`list`, `current`, `showNext`) as
BindableFunctions, the same shape the scenario runner uses and for the same
reason: the Studio MCP's `execute_luau` runs in a different Luau virtual
machine (VM) from the
client LocalScript, so `_G` does not cross but the DataModel does.

`current` and `showNext` both answer `{ current, mounted, ok }`: `current` is the
demo that was *asked* for, `mounted` is the one actually on screen (`false` when
the build threw — it runs under a `pcall`, so the failure never leaves the
client console), and `ok` is whether they agree. Read `mounted`, not `current` —
a sweep taken on the id alone measured a leftover surface 21 times on 2026-08-15
and called it clean.

The place is evidence of the `studio-emulated` and `desktop-retail` kind at
best; publishing it and holding it is what produces the `phone-physical` and
`console-physical` rows this stage leaves pending.

## The device-emulator visual sweep (gate)

The five-view matrix above proves ONE fixture, ONE theme, per session. The
director's own recurring finding is different in kind: overlap/cutoff/
stray-stroke/pop bugs that show up on a THEMED surface (Pixel Quest, Fantasy
Ornate) that no headless test constructs — because the escape is in how a
package's own chrome (a glow, a plate, a per-state art rung) interacts with a
real engine layout, not in the framework's declared geometry. `tools/
check_device_sweep.py` + `tools/studio/device_sweep_matrix.json` +
`tools/studio/device_matrix.luau`'s `row`/`observe`/`live` modes turn that
into a gate: a machine-readable verdict over device preset × theme package ×
scenario, captured once and diffed against a stored baseline forever after.

**This gate cannot run in CI.** It requires an open Studio session with the
place injected and an operator (human or agent) driving
`StudioDeviceSimulatorService` and the scenario/showcase surface through the
Studio MCP `execute_luau` tool. `check_device_sweep.py`'s default mode reads
persisted evidence off disk; only `--selftest` (validates the matrix config's
own shape against the real `matrix_rows` ids, no Studio needed) is
CI-shaped.

**Two ways to reach a cell**, because the framework has two mutually
exclusive boot modes (`examples/gallery/client/boot_mode.luau`):

- **Scenario mode** (`Facet_Showcase = false`, `Facet_Scenario = "theme_authoring"`
  before Play) drives the base matrix: `theme_authoring` wraps the
  `adaptive_controls` fixture with `installPackage:<name>` package-swapping
  and publishes `workspace.FacetScenarioAPI`. Use `device_matrix`'s `row`
  mode (select the device preset, then `step("installPackage", theme)`, then
  `observe`) — this is the only surface with in-place theme swapping, so it
  is also what any OTHER scenario-mode fixture (`ref_glade`, `ref_foyer`,
  `virtual_list_native`, …) is missing: those are driven at `neutral`
  (their own reference styling) via plain `Facet_Scenario = "<name>"` +
  `observe`.
- **Showcase mode** (`Facet_Showcase = true`, the default — leave
  `Facet_Scenario` unset) is the only way to reach a themed `hud`/`menu`/
  `tab_view`/`row-actions` demo, because `demo_picker.DEMOS` (not the
  scenario registry) is what the showcase's in-game theme chip drives, and
  it lists those by id. Select the demo via `workspace.FacetShowcaseAPI.
  showNext`/`current`, apply a package via `pickPackage`, then use
  `device_matrix`'s **`live` mode** (`observeLive`) — showcase mode never
  creates `FacetScenarioAPI`, so `live` walks `Players.LocalPlayer.PlayerGui`
  directly with the same containment/paint judgement (`judgeInstanceTrees`,
  shared by both `observe` and `live`) instead of depending on it. The
  desktop-scrollbar notable cell (below) also runs in showcase mode, at a
  windowed (non-`ActualResolution`-forced) viewport, because that is the
  director's own repro shape. **Naming trap**: the showcase's package ids use
  **hyphens** (`pickPackage("pixel-quest")`, `pickPackage("fantasy-ornate")`) — its own
  `identity.id` convention — while `theme_authoring`'s `installPackage` step
  matches the FacetThemes folder's **file basenames**, underscored
  (`"pixel_quest"`, `"fantasy_ornate"`); both name the same packages,
  reachable through the boot mode each is native to. `live` mode has two
  further disclosed limits versus `observe`: no solver-diagnostics visibility
  at all (only `FacetScenarioAPI.report()` exposes them), and `unfitText`
  carries no declared/undeclared distinction (no `textPolicies` channel
  outside scenario mode) — treat a `live`-mode `unfitText` entry as
  informational, not gating.

**The matrix**: `device_sweep_matrix.json`'s `deviceRows` × `themes` on
`baseScenario` is the floor (5 × 3 = 15 cells); `notableCells` names specific
director-reported surfaces beyond it (each with its own device row, theme,
scenario, and a `director` field citing the finding it re-proves) that the
gate REQUIRES evidence for; `plannedCells` holds cells identified but not yet
driven (each with a `status` explaining why) — moving a cell there is how you
defer it honestly instead of leaving the gate permanently red over future
work. Captures
follow `capture_viewport.sh`'s convention:
`<deviceRow>__<theme>__<scenario>.png`, or a notable cell's own `id` in place
of `deviceRow` when it overrides the viewport.

**Evidence**: one JSON file per cell in
`artifacts/device-emulator-sweep/rows/<cell>.json` (schema documented in
`check_device_sweep.py`'s header — `ok`, `evidenceClass`, the four finding
arrays, `solverDiagnostics`, `settledTwice`, a `capture` path with its
sha256, and a `triage` block on every red cell), one PNG per cell in
`artifacts/device-emulator-sweep/captures/`, and a `baseline.json` mapping
cell → last-known verdict so a future run's red cell can say WHAT regressed
rather than just that something is red. `check_device_sweep.py` (no
`--selftest`) reads all of this and exits non-zero on any MISSING cell or
untriaged REGRESSION.

**The "first-paint watch" substitute.** If a first-paint/transition
invariant with an on-glass arm exists for the surface under test, wire it in;
otherwise (the common case here) call `observe`/`live` twice, a beat apart,
and record `settledTwice = true` only when both calls agree — proving the
settled frame matches what a fresh re-solve produces, per a `hud`/`Shrink`-
class fixture whose Vocab chip layout genuinely shifts for several frames
after a package swap before it settles (measured live, task SWEEP).

**Trigger discipline** — run this sweep:
- before any director device-pass/review of the showcase or a reference app;
- after any change touching `screen_scroll_indicators.luau`,
  `screen_presentation.luau`, `screen_target.luau`'s paint/containment path,
  `render/transitions.luau` (backdrop/pop), or any `examples/themes/*.luau`
  package;
- before closing a campaign/phase that claims cross-platform or themed
  correctness;
- whenever a device-owed register item is claimed "covered by sweep" — the
  row proving it must exist and pass first.

**Traps specific to this gate** (measured, task SWEEP): kill any stale
`studio_sync` on `:8642` before injecting — a second server silently answers
alongside a leaked one and there is no error, only stale sources. A node's
own `Visible` property says nothing about a HIDDEN ANCESTOR — a
ViewThatFits-style construction's losing candidate is fully mounted, and its
own chrome decorations (`FacetChrome`/`FacetChromeText`) read `Visible =
true` on themselves while the collapsed parent is `Visible = false`; without
tracking hidden ancestry the same way clip ancestry is tracked, the
offscreen/containment/unfit checks report the loser's stale collapsed-width
geometry as a live defect (`device_matrix.luau`'s `effectivelyHidden`
annotation on the shared census, fixed in task SWEEP after it produced a
false six-node offscreen finding on a themed phone-portrait cell). A manual
`ScrollingFrame.CanvasPosition` write for investigation purposes can conflict
with the framework's own reactive control of that property — call
`FacetScenario.reset()` (or re-enter the demo) rather than trusting a session
that has been hand-scrolled.

**Known gate limitations** (found by live measurement this round, not fixed).
Two further CHECKER limitations, found by the closing re-review (parked with
rulings — see the campaign ledger and
`review-finalwave-verdicts.md` for the mutation evidence): (4) a row's waiver
is ROW-level, not finding-scoped — a row that already carries any waiver will
silently PASS a NEW escape class; when adding a waiver, re-read the whole
row's evidence, and treat any waivered row's PASS as covering only what the
waiver names. (5) the summary line double-books triaged `real-regression`
cells inside PENDING, so its bucket counts can exceed the required-cell
total; the REAL-REGRESSION count is authoritative, the PENDING count may
overlap it.
Limitations 1 and 2 are false-**NEGATIVE**-only: each is a class of real
defect the check structurally cannot see, so a red cell from that same check
is still trustworthy — it just cannot promise there is nothing else wrong.
Limitation 3 is the opposite direction and does not get the same reassurance:
it is a false-**POSITIVE** generator. A prior draft of this list called
limitation 3 false-negative-only too, which was backwards and was corrected
after an independent review of the sweep evidence — limitation 3 is the
single largest source of findings in the shipped sweep evidence (8 entries
on `ps5-showcase-hud` alone, 2 on every `live`-sourced matrix cell). **Do not
cite "false-negative direction only" to wave off a limitation-3 finding —
read it as a real, expected red that needs an explicit per-entry waiver,
never a reason to hand-set `ok: true` on the whole cell** (the same review
found exactly that had happened — an `ok: true` cell whose own recorded
finding arrays were never cross-checked against the claim):

- **Containment tests ancestor-escape, not sibling-adjacency** (false
  negative). A decoration that sits flush at zero inset against a SIBLING's
  edge under a shared ZStack (a badge overlapping its own tile's corner, say)
  can never be flagged: `judgeContainment` only walks name-PREFIX ancestry to
  find a tagged boundary, and two siblings composed under a shared,
  often-untagged, sometimes not even materialized group node have no
  ancestry relationship to test at all. Confirmed live: a HUD tile badge
  sitting flush at its own tile's top-right corner with zero inset reads
  `containment: []`.
- **Containment tests position/size, never shape** (false negative). A
  decoration positioned and sized exactly right but painted with the wrong
  corner radius (a hardcoded-radius focus ring on a squared-off package's
  button, which has no `UICorner` of its own to compare against) is invisible
  to every existing check — `dumpGuiInstance` already counts
  `modifierChildren.UICorner`, but nothing reads the radius VALUE or compares
  it to anything.
- **The offscreen check has no exemption for a deliberately negative-Y
  reserved chrome band, and that makes it a false POSITIVE generator, not a
  false negative.** The showcase's own topbar-strip reservation, and any HUD
  strip mounted inside it, both legitimately paint above `y = 0` by design
  (matching `coreSafeInsets.top`, `tests/lib/device_views.luau`'s
  `CORE_TOP = 58`); only `ScrollingFrame` clipping is exempted today, so this
  whole class reads as **spurious** `offscreenNodes` — a red the check raises
  over nothing wrong, which is the textbook definition of a false positive.
  An `offscreenNodes` entry at exactly `pos.y == -coreSafeInsets.top` is
  expected, machine-checkable, and must be waived per-entry by the gate's own
  derived-verdict pass (`tools/check_device_sweep.py`, which derives `ok`
  from the row's recorded evidence rather than trusting it verbatim) — never
  dismissed by hand-setting the whole cell's `ok` to `true`.

## What the automated matrix can never close

- physical touch targeting, gestures, or touch feel;
- real gamepad delivery, platform arbitration, or console behaviour;
- the mobile operating-system keyboard;
- operating-system display scaling outside the selected configuration;
- retail-client networking;
- low-end CPU, GPU, memory, thermal, battery or frame-time performance;
- subjective readability, hierarchy, motion, or production feel.

Those rows stay `PENDING_PHYSICAL` or `PENDING_HUMAN`. Studio-emulated
performance is useful regression evidence and is never the low-end Android
result.

## What "frame work" means here

Roblox exposes several frame quantities and they are not interchangeable:

- `Stats.RenderCPUFrameTime` — the client's CPU render frame time. This is the
  captures' **named headline**, because it is unambiguous and it is what a UI
  framework actually loads.
- `Stats.RenderGPUFrameTime`, `Stats.FrameTime` — published beside it, each under
  its own name.
- `RunService.Heartbeat` delta — the frame **interval**. Under a frame-rate cap it
  is floor-limited by the cap and cannot resolve any work below it. An earlier
  version of this capture published only this, and every row read ~16.6 ms
  regardless of what was on screen.

`Stats.FrameTime` and the Heartbeat interval did not always agree across these
captures. Nothing here adjudicates that, so each row records the ratio it
measured rather than a story about it. **Never add the two together**: one is
whole-frame
work on a fast host, the other is Facet's share of one client's work.

