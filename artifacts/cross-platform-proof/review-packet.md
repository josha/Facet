# cross-platform-proof — review packet

**Stage:** roadmap Step 4 · **Date:** 2026-07-26 · **Library:** 0.7.0 · suite 1949
**Status: automation complete, release evidence pending.**

Everything an instrument in this build could reach is done and stored. What is left
needs hardware this build has no access to, or a person's judgement. This packet turns
that remainder into one focused pass — you should not have to discover the test cases,
assemble state, read logs, or work out which result failed.

Four rows are open: **XP-P1** (weakest supported physical touch device), **XP-P2**
(supported physical gamepad / ten-foot path), **XP-P3** (desktop-retail baseline) and
**XP-P4** (human review). Each has an exact procedure below.

---

## 0. What you are checking, in one paragraph

This stage did not make LuauUI faster. It made LuauUI's numbers *honest*: every
performance record now names the instrument that produced it, and the gates refuse to
let a headless or emulator number stand in for a device result. The three physical rows
below are the numbers that do not exist yet — and the whole system is built so that
their absence is visible rather than papered over. Your job is to fill them, and to say
whether the honesty reads as honesty to someone who did not build it.

---

## 1. The review build

No special build. The stage ships in the ordinary tree.

```bash
cd GameStudio/ui/LuauUI
lune run tools/lune/studio_sync        # serves library + gallery + the matrix driver
```

Then in Studio, in the **Edit** datamodel, inject the manifest (the block used
throughout this stage is in `docs/guide/11-device-verification.md` §"Running it"), set
the workspace attribute `LuauUI_Scenario = "perf_capture"`, and press Play.

The fixture is one screen — a dense live HUD, a 200-row virtualized roster and a pinned
action bar — chosen because it is the shape a real race HUD or garage has. It fits a
360×691 phone and a 1920×1080 television from one semantic tree, with no device-name
branch anywhere in it.

**On-screen labels.** The build/fixture identity is readable at any time:

```lua
local run = require(workspace.LuauUIMatrixDriver)
run({ mode = "preflight" })   -- studioVersion, sourceStamp, libraryVersion, scenario, viewport
```

---

## 2. XP-P1 — the weakest supported physical touch device  `PENDING_PHYSICAL`

**What is owed:** frame work, LuauUI update cost, Instances, connections, memory and
input-to-visible latency for the production-shaped fixture, on the weakest Android
device you support.

**Why no emulator can close it.** The matrix's compact-phone row selects the narrowest
*canvas* (a 772×360 catalog preset, 360×691 as rendered). That is a layout extreme, not a hardware floor: the
emulator runs on your development machine's CPU and GPU. Nothing in this build has ever
executed LuauUI on a slow chip.

**Procedure**

1. Publish the gallery place to a private test place (this stage published nothing; the
   Step 7 performance lab owns the publish-ready place).
2. On the device, join and confirm the fixture mounted: the roster scrolls, the Lap bar
   is at 35%, the action bar is pinned at the bottom.
3. Record, per the same workload the Studio rows used (60 driven refreshes then 60
   sampled frames):
   - frame work p50/p95/p99 — the device MicroProfiler, or `RunService.Heartbeat` deltas
   - LuauUI update cost — wall time around `presenter.refresh()`
   - Instances and connections — the `measure` step reports both
   - memory — `Stats:GetTotalMemoryUsageMb()` and the Lua heap
   - input-to-visible — tap **Boost** and read the `readInput` step's number
4. Record the device model, OS version, thermal state (cold start vs after 10 minutes)
   and graphics quality level. A number without these is not reproducible.

**Where it goes:** a new `artifacts/cross-platform-proof/device/phone-physical.json`,
schema `luauui-device-perf/1`, `evidenceClass: "phone-physical"`, with at least one
row carrying a **measured** `M1_frameWorkMs`. Then set
`deviceBudgets["phone-physical"].measured = true` in `bench/perf_budgets.json` and run
`tools/perf.sh`.

**What the capture must carry.** Five refusals guard this, all deliberate and all tested,
and each of the last three was added because a fresh-context review defeated the ones
before it:

1. `tools/check_perf_budgets.py` rejects `measured: true` unless a capture of that class
   exists *with rows*;
2. `perf_runner.checkBudgets` rejects a row of that class that carries no measured frame
   work, and refuses the whole budget when the report holds no rows of the class;
3. ingestion keys on the ROW's own class and drops any row whose class disagrees with its
   file's — a relabelled container cannot relabel its contents (round-3 F1);
4. `perf_runner.provenanceProblems` requires the row to CARRY an attestation:
   `provenance.isStudio = false`, `clientKind = "retail"`, and a non-empty `instrument`,
   `deviceModel`, `capturedAt` and `attestedBy`, plus `evidenceLevel = "E4"`, a measured
   M1 with a finite non-negative `p95_ms`, and M2–M6 present. The earlier version of this
   was a blocklist of Studio field names and one extended `sed` renamed its way past it
   (round-5 F1); a positive requirement cannot be satisfied by renaming, only by writing.
   The attestation must also AGREE with the row it sits on — `provenance.deviceModel`
   against `device.name` — because the likeliest honest mistake this very procedure
   invites is copying the Studio capture as a schema template, writing a real attestation
   and real numbers, and forgetting the device block underneath (round-6 F1);
5. a device-class row that names the reference profile can no longer displace the headless
   run it would stand in for — the attempt is itself reported as a violation (round-5 F2).

**What none of this can do.** A determined author with commit access can write the
attestation by hand. That is forgery with a name attached rather than a one-line relabel,
and no gate living in the same repository as the evidence can do better. The honest
statement is: these refusals stop relabelling and accident, and they make fabrication an
explicit, multi-field, signed act.

**The budget it will be checked against:** 30 Hz frame target, a quarter of the frame
for LuauUI's own update ⇒ **8.33 ms**. If the measured number exceeds it, that is a
finding, not a reason to move the budget.

---

## 3. XP-P2 — the supported physical gamepad / ten-foot path  `PENDING_PHYSICAL`

**What is owed:** that the console row's layout is not merely *emulated* correctly, and
that gamepad input is actually delivered.

**What the automation already established** (see
`artifacts/cross-platform-proof/rows/matrix/console-ten-foot.json`): with the `ps4`
preset selected, the running session reports `displaySize = Large`,
`preferredInput = Gamepad`, `distanceProfile = ten-foot`, `typographyScale = 1.5` and
effective overscan insets of 60/60/90/90 — the ten-foot presentation genuinely engaged,
rather than the row measuring a large desktop.

**What it did not, and cannot:** gamepad *delivery*, platform arbitration, Button A
contention with the Roblox menu, real television overscan, and console frame work.
Studio cannot synthesize a true gamepad input class.

**Procedure**

1. On a real console (or a desktop with a physical pad and the retail client), join the
   place with the fixture mounted.
2. Confirm `PreferredInput == Gamepad` arrives from hardware, not from a preset.
3. D-pad through the roster: focus should move row to row, and an off-band row should
   scroll into view. Confirm the focus visual is legible **from your sofa**, not from
   30 cm away — that is the whole point of the ten-foot row.
4. Press A on the Boost button. Confirm the counter increments and that the Roblox menu
   does not also open (Button A contention).
5. On a real TV, confirm nothing important sits inside the overscan margins.
6. Record console frame work under the same workload.

**Where it goes:** `artifacts/cross-platform-proof/device/console-physical.json`, then
`deviceBudgets["console-physical"].measured = true`. Budget: 60 Hz ⇒ **4.17 ms**.

`tools/perf.sh` ingests physical-class rows from that directory automatically, so the
budget is genuinely checked once the file exists — proven end to end with a synthetic
capture (in-budget passes, over-budget fails, an unmeasured row fails).

---

## 4. XP-P3 — the desktop-retail baseline  `PENDING_PHYSICAL`

**What is owed:** the same measurements from the **retail** Roblox client rather than
Studio. Studio's frame work includes Studio's own work — the p99 outliers in the stored
rows (40–100 ms against a 16.7 ms median) are compilation, the Explorer and the driver's
own round-trips, not the screen.

**Procedure:** join the published place in the retail client, run the same workload,
record the same fields. `artifacts/cross-platform-proof/device/desktop-retail.json`,
`deviceBudgets["desktop-retail"].measured = true`. Budget: 60 Hz ⇒ **4.17 ms**.

This row is the cheapest of the three and the most useful first: it isolates "Studio
overhead" from "LuauUI cost" on hardware you already have.

---

## 5. XP-P4 — human review  `PENDING_HUMAN`

Two judgements, both of which the implementing agent may not make for itself.

### 5a. Ten-foot legibility

Open `artifacts/cross-platform-proof/captures/console-ten-foot.png` and, ideally, the
live console row. The type floor is applied (×1.5) and the content is inset by the
overscan margins. **Question:** is the roster readable at three metres, and does the
focused row read as focused at that distance?

Compare against `captures/compact-phone-portrait.png` and `captures/desktop-standard.png`
— the same semantic tree at 359×690 and 1280×719. **Question:** does one screen adapting
across all three read as *designed*, or as *stretched*?

### 5b. Does the honesty read as honest?

This is the stage's actual deliverable, and it needs someone who did not write it.

Read, in this order:
1. `artifacts/cross-platform-proof/acceptance-ledger.md` §0 — the metric ledger.
2. `docs/guide/11-device-verification.md` — the chapter a consumer reads.
3. Any single row in `artifacts/cross-platform-proof/device/studio-emulated.json`.

**Questions:**
- Could a reader in a hurry take any number here as a device result? If yes, which one,
  and what would fix it?
- Does the `blind` marker read as "we could not measure this" or as "this is zero"?
- Is the difference between M1 (whole-frame work on the host) and M2 (LuauUI's share)
  clear enough that nobody will add them together?
- The frame ceiling is one-directional: exceeding it proves a real problem, passing it
  proves nothing. Is that stated somewhere a reader will actually meet it?

---

## 6. What is already closed, so you do not re-check it

| Row | Closed by | Evidence |
|---|---|---|
| XP-A1..A7 | headless, this run | `artifacts/phase-4/perf.json`, `bench/perf_budgets.json`, `rows/xp-a*.json` |
| XP-A6 | the gate broken on purpose and restored | `rows/xp-a6-regression-proof.json` |
| XP-B1..B4 | five live Studio rows on one source build, captures hash-pinned, each with an input trace or a stated reason it has none | `matrix.json`, `captures/`, `rows/matrix/` |
| XP-B3 | what `VirtualInput` actually supports, measured — including the correction of two false claims this stage first published | `rows/xp-b3-virtualinput.json` |
| XP-B5/B6 | a broken layout and a suppressed input effect, both caught | `rows/xp-b5-intentional-failure.json` |
| XP-C1/C2 | Studio capture with preflight, identity and the metric ledger | `device/studio-emulated.json` |
| XP-D1..D5 | contracts + specs + the VR-claim guard | `rows/xp-d*.json`, `tests/spatial.spec.luau` |

---

## 7. Open follow-ups this stage did not close

Neither blocks the physical rows; both are honest loose ends rather than pending
hardware.

- **`VirtualInput` delivery.** Its documented methods are all present and callable
  (that correction is the subject of `rows/xp-b3-virtualinput.json`), but in this
  session its calls succeeded while delivering no observable input events, apart
  from one early press that did. Caching a single instance did not restore it and
  the cause is unresolved. Every native-input trace here therefore came from the
  Studio MCP injector and says so in `input.path`. The next stage that needs
  scriptable input should start here.
- **`Stats.FrameTime` versus the Heartbeat interval.** They disagreed by ~4× in one
  capture and agreed in another. Each row records the ratio it measured; nothing
  here adjudicates it, which is why the headline M1 number is the unambiguous
  `RenderCPUFrameTime` and every other series is published under its own name.

### Added 2026-07-27 by the compact-label stage  `CL-P1` / `CL-P2`  `PENDING_PHYSICAL`

Appended, not edited: the rows above are closed evidence at their own dates. These
two are new and neither has been on hardware.

- **`CL-P1` — the compact ladder on a physical phone.** `adaptive_controls` gained a
  `CompactRow`: one `fill` button that says "Edit item" on a desktop and takes its
  compact form on a phone, plus three narrow ones (a shorter string, an icon, and a
  control that declares nothing and therefore still ellipsizes). Everything about it
  is measured headlessly under all nine packages; **nothing has been seen on a
  device.** What to look for: the `fill` button must swap at the width where its
  label stops fitting and swap BACK on rotation without a remount, and the "declares
  nothing" control must be the only one showing a `…`.
- **`CL-P2` — the framework's own icon art, drawn.** Eleven PNGs uploaded through
  Open Cloud, all **Approved** and all **`Image`** (`AssetTypeId` 1) — verified by
  asset IDENTITY, because `IsLoaded` is not readable evidence in the Edit datamodel
  and a known-good shipped asset reads `false` too. Identity is not the same claim
  as *renders*. What to look for: a pencil on the table's Edit/Done toggle when the
  toolbar is narrow; the tint following each package's `content` role (dark mark on
  the five light theme variants, light mark on the six dark ones); and `/` rather
  than a pencil under the three packages that decline the set (`pixel_quest`,
  `glossy_touch`, `compact_pointer`).
- **Known gap, reported not fixed:** icon art has **no asset-failure fallback path**.
  Slot decorations get `luau-chrome-fallback` / `luau-chrome-mute`; icons get
  nothing, and because the glyph beneath is already at `TextTransparency = 1`, a
  content id that 404s draws *nothing at all* rather than falling back to its
  character. Not reachable today (every id is Approved and Active), but it is the
  failure mode a future re-upload or a moderation reversal would take.

## 8. Exit / rollback

Nothing to roll back: this stage added measurement and contracts, changed no control
behaviour, and touched no game code. To leave the review session:

```lua
local run = require(workspace.LuauUIMatrixDriver)
run({ mode = "reset", uninstall = true })   -- StopSimulationAsync, then removes the driver
```
