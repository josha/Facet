# cross-platform-proof acceptance ledger

**Gate:** `cross-platform-proof` · **Created:** 2026-07-26 ·
**Contract:** `docs/plans/agent-execution-contract.md` §2 · **Matrix:** `docs/plans/studio-device-verification.md`
**Governing docs:** `docs/plans/swiftui-parity-next.md` investment 10, roadmap Step 4.

Stage-start facts (measured 2026-07-26, before any edit in this stage):
suite **1868** green (stage total: **1949**); `LuauUI.VERSION = 0.7.0`; `tools/perf.sh` PASS with 8 scenes × 4
profiles; `tools/gate.sh rich-skinning-v2` PASS.

Status values are the contract's honest states: `PASS_AUTOMATED`, `PASS_PHYSICAL`,
`PASS_HUMAN`, `FAIL_PRODUCT`, `FAIL_ENVIRONMENT`, `PENDING` (automated work not yet
performed), `PENDING_PHYSICAL`, `PENDING_HUMAN`. A row cannot pass through a different,
easier row. Every `PASS_*` cites an artifact produced by a tool run in the session that
set it. **All rows start PENDING.**

The stage centerpiece is *honesty*, not speed: after this stage, every number LuauUI
publishes says which instrument produced it, what that instrument can and cannot see,
and which claim it is therefore allowed to support. A fast headless run is not a device
result, and this stage's job is to make that structurally impossible to confuse.

---

## 0. Metric / evidence ledger

This is section 0 because the contract requires the ledger before the code. Each row is
a quantity the stage promises to measure. `Lune` = headless `tools/perf.sh`;
`Studio` = the emulated Studio session driven through the shared scenario surface;
`Physical` = a named retail device. A cell reading **blind** means the instrument
structurally cannot observe the quantity and must never report a number for it.

| # | Metric | Lune (E1) | Studio-emulated (E3) | Physical (E4) | What a number here never proves |
|---|---|---|---|---|---|
| M1 | Real frame work (whole-frame cost) | **blind** — no engine frame exists | measured: `Stats.FrameTime` / `RenderCPUFrameTime` / `RenderGPUFrameTime` over a fixed window, published beside the `RunService.Heartbeat` **interval** — which is floor-limited by any frame-rate cap and is explicitly *not* frame work | same, on retail hardware | Studio frame work is the *host's* frame work with an emulated viewport; it is not the device's. The Heartbeat interval is not frame work at all. |
| M2 | LuauUI update cost | measured: per-phase p50/p95/p99 around `run()` | measured: wall time around the presenter's driven refresh, inside the client VM | same | a fast update on a fast host says nothing about a slow GPU or a thermally-throttled CPU |
| M3 | Live Instances | measured: adapter node census (`FakeTarget`) | measured: real `GuiObject` descendants of the mounted `ScreenGui` | same | instance count is a cost *driver*, not a cost |
| M4 | Connections | measured: reactive registry observers+effects (declared stand-in) + adapter-held engine-connection count | measured: same two counters from the live client VM | same | the stand-in counts what LuauUI owns, not what the engine allocates internally |
| M5 | Memory | measured: `gcinfo()` heap floor, growth rate, per-iteration slope | measured: Luau heap plus `Stats:GetTotalMemoryUsageMb` where the API answers | same | heap slope is a leak signal, not a memory budget |
| M6 | Input → committed property write (a **lower bound** on input-to-visible) | measured *deterministically*: semantic action dispatch → the committed visible property write, in one call chain, **no frames involved** | measured: the raw native event that completed the gesture → the property WRITE, both timestamped inside engine callbacks. `GetPropertyChangedSignal` fires on the write, which strictly *precedes* the frame that renders it — so this is a **lower** bound, and it is not frame-quantized | same | neither number is display latency: no instrument here sees scan-out, and neither one includes the frame that draws the change |
| M7 | Theme-swap cost | measured: three separate scenes (flat / metric-changing / asset-backed) with their own invalidation shapes | measured: swap wall time + chrome census + live instance delta (**no preload counts** — the swap step does not request preloads) | same | a Studio swap cost is derated by the host; it bounds nothing on a phone |

**Evidence classes.** Every performance record carries exactly one
`evidenceClass ∈ { lune, studio-emulated, desktop-retail, phone-physical, console-physical }`
and its `evidenceLevel ∈ { E1, E3, E4 }`. Rows never merge. The physical classes exist in
the schema from day one **with no rows**, so a reader can see what is missing rather than
inferring it from silence.

**Budget model.** Two budgets, both versioned, deliberately different in kind:

- **Trend budget** (`class = lune`) — `max(observed_p95 × 4, floor)`. Catches regressions.
  Says nothing about any device. This is the existing model and it is preserved.
- **Frame ceiling** (`class = lune`, one-directional) — the share of the supported frame
  target one LuauUI update may occupy. Because the Lune host is *faster* than every
  supported device, `headless > ceiling ⇒ the scene cannot fit the frame target anywhere`.
  The converse is not inferable and the artifact says so on every record.
- **Device budgets** for the phone/console classes are declared in the budgets file with
  their frame targets and are marked `measured: false` until a physical capture fills them.
  They are not enforced against emulator data — the gate refuses to check a device budget
  from a non-device class.

---

## A. Headless performance system (E1)

| ID | User-visible behavior | Risk | Evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| XP-A1 | The headless matrix covers the ten-foot/console presentation, so a console-only layout cost cannot regress unnoticed | Console is the only profile whose type scale, overscan and focus treatment differ; a 4-profile matrix silently excludes it | E1 | `tools/perf.sh` | `artifacts/cross-platform-proof/rows/xp-a1-console-profile.json` | **PASS_AUTOMATED** |
| XP-A2 | Production-shaped scenes exist for a large virtual list, native scroll/drag, a dense HUD, StyleSheet state churn, async images, and mount/unmount lifecycle churn | Toy scenes make the framework look cheap; the shapes real games use are the ones that regress | E1 | `tools/perf.sh` | `artifacts/cross-platform-proof/rows/xp-a2-production-scenes.json` | **PASS_AUTOMATED** |
| XP-A3 | Flat, metric-changing and asset-backed theme swaps are three *distinct* scenes with distinct invalidation and cost | One "theme swap" number hides that a palette swap repaints while a metric swap re-solves and an asset swap also fetches | E1 + E3 | `tools/perf.sh`; live `themeSwap` step | `rows/xp-a3-theme-swap-scenes.json` (E1 invalidation shapes) + `rows/xp-a3-theme-swap-studio.json` (E3 instance census: flat 65 nodes / 0 layers, Fantasy Ornate 125 nodes / 45 layer instances, clean teardown back to 65) | **PASS_AUTOMATED** |
| XP-A4 | Every record carries the M1–M7 metric set, with `blind` where the instrument cannot see | A missing field reads as zero; zero reads as free | E1 | `tools/perf.sh` | `artifacts/phase-4/perf.json` | **PASS_AUTOMATED** |
| XP-A5 | Budgets are derived from a measured baseline **and** a frame target, and the artifact states which claim each supports | "It passed the budget" is meaningless without knowing what the budget was derived from | E1 | `tools/perf.sh baseline` then `tools/perf.sh` | `bench/perf_budgets.json` | **PASS_AUTOMATED** |
| XP-A6 | An intentional regression **fails** the gate, naming the scene and the budget it broke | An unfalsified gate is decoration | E1 | `tools/lune/prove_perf_gate` | `artifacts/cross-platform-proof/rows/xp-a6-regression-proof.json` | **PASS_AUTOMATED** |
| XP-A7 | Lune, Studio-emulated, desktop-retail, phone and console results are separate rows. A device budget is met only by a MEASUREMENT of that class: the gate refuses a report with no such rows, refuses a row of that class carrying no usable frame work, and — once stored captures can be ingested so a device budget is checkable at all — refuses any row whose own class disagrees with its file's, refuses a row that carries no affirmative `provenance` attestation, and refuses a device row that tries to stand in for the headless reference run | The single failure mode this whole stage exists to prevent. It was reopened by the ingestion path and closed three times: keying on the file's class (round 3), a blocklist of Studio field names that one extended `sed` renamed past (round 5), and a device row displacing the reference run in the trend index (round 5). What it CANNOT stop is a hand-written attestation — forgery with a name on it — and the review packet says so | E1 | `tools/perf.sh` + spec + the whole-path proof | `rows/xp-a7-evidence-classes.json` | **PASS_AUTOMATED** |

## B. Reusable Studio device-matrix driver (E3)

| ID | User-visible behavior | Risk | Evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| XP-B1 | The driver resolves the five matrix roles from the **live** device catalog; no catalog ID is hard-coded, and the chosen configuration is recorded | Studio is a rolling platform; a pinned ID silently selects the wrong device or errors | E1 (policy) + E3 (resolution) | `src/preview/matrix_rows.luau` spec; live `GetDeviceListAsync` | `artifacts/cross-platform-proof/matrix.json` | **PASS_AUTOMATED** |
| XP-B2 | One checked-in reusable driver takes each canonical view through a fixed mode sequence and emits one bounded machine-readable row each. It is deliberately **not** one call: `SetDeviceAsync` yields, and touch/gamepad are boot-time facts, so the five views span two Play sessions | A one-off command-bar script is not a reusable gate (contract §5) | E3 | `tools/studio/device_matrix.luau` via MCP | `artifacts/cross-platform-proof/matrix.json` | **PASS_AUTOMATED** |
| XP-B3 | `VirtualInput` is used only for the paths it supports, and what it supports was MEASURED with the documented member names; where a trace came from the MCP injector instead, the row says so | Pointer input in a phone viewport is not touch; synthetic KeyCodes are not a gamepad — and a probe that guesses member names publishes false platform facts | E3 | driver input stage | `rows/xp-b3-virtualinput.json` | **PASS_AUTOMATED** (with one OPEN limitation recorded: VirtualInput's calls delivered no observable events in this session) |
| XP-B4 | Each row exports bounded geometry, state and a hash-pinned capture, plus an input trace on the rows where native input was injected; a row with neither an input trace nor an explicit reason fails the check | A screenshot can look right while routed input landed elsewhere | E3 | driver | `artifacts/cross-platform-proof/captures/` | **PASS_AUTOMATED** |
| XP-B5 | An intentional **layout** fault makes the driver fail the affected row | A driver that cannot fail proves nothing | E3 | driver fault-injection mode | `artifacts/cross-platform-proof/rows/xp-b5-intentional-failure.json` | **PASS_AUTOMATED** |
| XP-B6 | An intentional **input** fault (the effect is suppressed) makes the driver fail the affected row | Same, for the input pairing | E3 | driver fault-injection mode | `artifacts/cross-platform-proof/rows/xp-b5-intentional-failure.json` | **PASS_AUTOMATED** |
| XP-B7 | `StudioTestService` is used only where Play/Run or multiple clients are actually required, and the documented client-control limits are stated | Overstating client control produces evidence nobody can reproduce | E0/E3 | doc + driver policy | `docs/guide/11-device-verification.md` | **PASS_AUTOMATED** |

## C. Studio / device performance capture (E3, physical PENDING)

| ID | User-visible behavior | Risk | Evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| XP-C1 | A Studio capture records M1–M7 plus engine build, place/source identity and fixture state, in a schema separate from the headless trend file | Mixing them is how a desktop number becomes a phone claim | E3 | `perf_capture` scenario + driver | `artifacts/cross-platform-proof/device/` | **PASS_AUTOMATED** |
| XP-C2 | Each production-shaped capture stores its preflight result beside its numbers | A number from a blind instrument is worse than no number | E3 | driver preflight stage | `artifacts/cross-platform-proof/device/` | **PASS_AUTOMATED** |
| XP-C3 | The weakest supported physical touch device is measured | Only E4 supports a device-floor claim | E4 | review packet procedure | — | PENDING_PHYSICAL |
| XP-C4 | The supported physical gamepad / ten-foot path is measured | Studio cannot synthesize a gamepad input class | E4 | review packet procedure | — | PENDING_PHYSICAL |

## D. Future spatial seam — contracts only (E1)

No row in this section may be read as VR support. Section D exists so that adding spatial
input and world surfaces later does not require rewriting every screen.

| ID | User-visible behavior | Risk | Evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| XP-D1 | The environment can describe flat versus world presentation and spatial pointing as *facts*, and normal screens contain no headset branch | A `vr` boolean at screen level is the mistake the playbook forbids | E1 | spec | `artifacts/cross-platform-proof/rows/xp-d1-presentation-facts.json` | **PASS_AUTOMATED** |
| XP-D2 | A normalized event may optionally carry a selection ray, 3D hit, device/hand pose, handedness, phase and target; existing 2D callbacks stay valid when those are absent | An extended event that breaks 2D consumers is a rewrite, not a seam | E1 | spec | `artifacts/cross-platform-proof/rows/xp-d2-spatial-events.json` | **PASS_AUTOMATED** |
| XP-D3 | A future `SurfaceGui` world target is declared in the render-target contract and playbook with its unanswered questions, and is explicitly **not implemented** | A stub that "loads" becomes a support claim | E0/E1 | spec + docs | `artifacts/cross-platform-proof/rows/xp-d3-future-target.json` | **PASS_AUTOMATED** |
| XP-D4 | Focus, hover, occlusion, comfort, cancellation and performance are recorded as the gates a VR claim must pass, each explicitly unmet | Without a named gate list, "we support VR" has no falsifier | E0 | doc | `docs/extending/new-platform-mode.md` | **PASS_AUTOMATED** |
| XP-D5 | No shipped document, artifact or export claims VR support | The one irreversible mistake in this section | E1 | `tools/lune/check_docs_cli` VR-claim rule | `artifacts/cross-platform-proof/rows/xp-d5-no-vr-claim.json` | **PASS_AUTOMATED** |

## S. The hands-on showcase place (E3 by instrument; it is what PRODUCES the E4 rows)

Added after section D, at the director's request: one publishable place with the demo and the
theme both switchable **in game**, so the physical rows in section P can be driven by somebody
holding a device instead of by republishing a place per example. The place is not evidence of a
device claim — it is the instrument that lets a person produce one.

| ID | User-visible behavior | Risk | Evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| XP-S1 | One built place (`examples/places/LuauUI-Showcase.rbxl`) presents the all-controls fixture plus all seven tutorial examples, switchable from a chip, with no attribute edit and no republish | A showcase that needs a rebuild to change what it shows cannot be explored on a device | E3 | live Studio drive of all 8 demos | `rows/xp-s-showcase.json` + `tests/gallery_demo_picker.spec.luau` | **PASS_AUTOMATED** — all 8 mounted in sequence; the recorded cycle shows 3 ScreenGuis after every swap and after a full loop |
| XP-S2 | The theme picker rides the same strip and swaps the reference packages in game | Themes were previously chosen by a workspace attribute | E3 | live Studio drive | `rows/xp-s-showcase.json` | **PASS_AUTOMATED** — the collapsed chip renders and carries the live theme name; theme APPLICATION itself is the Step 3.5 stage's evidence, not re-proved here |
| XP-S3 | The chrome never covers the demo: the place RESERVES a strip through `coreSafeInsets` and the solver lays every demo out below it | A floating overlay always covers *something*; this is how it stopped | E3 | live Studio drive at 360×691 and 1233×1067 | `rows/xp-s-showcase.json` (geometry) | **PASS_AUTOMATED** — chips at y 8..54, demo root below, no overlap on either viewport |
| XP-S4 | The reservation writes only the TOP edge and carries the adapter's other three through | `coreSafeInsets` is a four-edge fact; writing three zeroes deletes the notch and home-indicator insets on a landscape or notched phone | E1 | code + fresh-context review | `examples/gallery/client/init.client.luau` `reserveBar` | **PASS_AUTOMATED** — found as round-4 F4 and fixed. **This row claims the code shape, not the pixels**: the landscape and notched rows are not re-driven here |
| XP-S5 | The place can be advanced without a pointer (`workspace.LuauUIShowcaseAPI`: `list`, `current`, `showNext`) | The injected-input limitation (XP-B3) leaves no scriptable pointer path | E3 | live Studio drive | `rows/xp-s-showcase.json` | **PASS_AUTOMATED** — all 8 demos cycled through the BindableFunction bridge |
| XP-S6 | Each demo's reactive state is reclaimed on a swap, not just its Instances | Ownership here is explicit, and the tutorial examples allocate on the core they are handed and return no `dispose` | E1 + E3 | host-installed per-demo scope; live re-drive | `rows/xp-s-showcase.json` `perDemoScope` | **PASS_AUTOMATED** — the host hands each demo a proxy core that owns into a per-demo scope; a full 9-step cycle re-driven after the change mounts every demo, leaves 3 ScreenGuis at every step and logs nothing. The post-change LAYOUT was **not** re-measured: the Studio render surface collapsed to a 1×1 viewport mid-session and did not recover (`rows/xp-s-showcase.json` `perDemoScope.notVerified`) |
| XP-S7 | What the place CANNOT prove is stated where the place is documented | A hands-on place reads like device proof | E0 | doc | `docs/guide/11-device-verification.md` | **PASS_AUTOMATED** |

**What this section does not claim.** No row here is a performance measurement, and the place
running well on the development host says nothing about a phone — that is what section P is for.
XP-S4 is a code-shape row, not a pixel row: the four-edge reservation was fixed after review but
the landscape and notched-phone views were not re-driven against it. The XP-S3 geometry was measured
on the build BEFORE the per-demo scope change (XP-S6); the Studio render surface collapsed to 1×1
before it could be re-measured, so no pixel claim here is post-change. And no row here cites a
stored picture: the geometry in `rows/xp-s-showcase.json` was read from the live tree, and the
five PNGs under `captures/` belong to the perf_capture fixture, not to this place.

## I. Integration

| ID | Behavior | Driver | Status |
|---|---|---|---|
| XP-I1 | Library suite green and grown from the 1868 stage-start floor | `tools/test.sh` | **PASS_AUTOMATED** — 1949 green (1868 → 1949: +81 across `perf_evidence`, `spatial`, `matrix_rows` and the showcase demo picker); the gate floor is the FINAL number, so losing this stage's own tests fails it |
| XP-I2 | RascalRally suite green; no Sponsor behavior altered by this stage | game `run-tests.sh` + diff | **PASS_AUTOMATED** — 2429 green. This stage edited no file under `games/`: the game tree carries 20 uncommitted files from earlier work, all with modification times before this session's first edit (newest 13:52; this session started later), and nothing in this stage's change list is under `games/`. |
| XP-I3 | Every previously passing gate still passes | `tools/gate.sh <each>` | **PASS_AUTOMATED** — `prior-gates.txt`: 13 exit-zero + `authoring-adaptive-ui` unregressed at its own close state (19/19 automated PASS, its standing physical row still PENDING) |
| XP-I4 | Guide, API reference and playbooks describe the shipped surface; doc gate green | `check_docs_cli`, `check_registration_cli` | **PASS_AUTOMATED** — both PASS; guide chapter 11 added and indexed |
| XP-I5 | Required fresh-context reviews run against methods and claims; findings fixed and rerun | verifier subagents | **PASS_AUTOMATED** — two fresh-context reviewers; the platform reviewer ran three rounds and the phase-gate reviewer five. Round 1: 15 platform findings (2 BLOCKER — six false platform facts) + 20 phase-gate findings (2 MAJOR holes in the device-budget refusal). Round 2: the VirtualInput correction had landed in the preflight but not the per-row probe; the GUI-memory fix in the producer but not the consumer. Round 3: a non-deterministic perf budget, a self-contradicting `prior-gates.txt` I had written, a device-budget path that could refuse but never check, `ConfigurationChanged` connected after the setters, and an unqualified `guiMb`. Round 4 broke the ingestion fix itself: one consistent `sed` relabelled the whole Studio capture so file and rows agreed and five host rows satisfied a measured phone budget; the same round found `reserveBar` writing three zeroes into the four-edge `coreSafeInsets` fact, `fresh-context-reviews` grepping the whole verifier file for an accept token instead of reading its verdict, a stale suite floor, and the showcase shipped with no ledger row at all. Round 5 defeated the round-4 fix in turn — the provenance rule was a blocklist of Studio field names and one longer `sed` renamed past it — and separately showed a device row displacing the headless reference run, turning an injected 8× regression from exit 1 into exit 0; it also rejected my decision to record the demo-swap leak rather than fix it, correctly, since the fix is in the showcase host and touches no tutorial example. Round 6 confirmed all three fixed by attacking each one. All fixed and re-driven; verdicts in `verifier-platform.json` / `verifier-phase-gate.json` |

## P. Physical and human rows (never closed by emulator or headless evidence)

| ID | What is owed | Why it cannot be automated here | Status |
|---|---|---|---|
| XP-P1 | Weakest supported physical touch device: frame work, LuauUI update cost, memory, input-to-visible latency on the production-shaped scenes | No device attached to this build | PENDING_PHYSICAL |
| XP-P2 | Supported physical gamepad / ten-foot path: real `PreferredInput == Gamepad`, focus visibility at distance, overscan, console frame work | Studio cannot synthesize a gamepad input class | PENDING_PHYSICAL |
| XP-P3 | Desktop-retail baseline (non-Studio client) for the same scenes | Requires the retail client, not Studio | PENDING_PHYSICAL |
| XP-P4 | Human review of the ten-foot legibility captures and of whether the published metric vocabulary reads honestly to a non-author | E5 by definition; the implementing agent may not self-approve | PENDING_HUMAN |

Closing procedures for every `PENDING_PHYSICAL` / `PENDING_HUMAN` row live in
`artifacts/cross-platform-proof/review-packet.md`.
