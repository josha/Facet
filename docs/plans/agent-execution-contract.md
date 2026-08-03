# LuauUI execution contract — prove the running Roblox UI

**Date:** 2026-08-01
**Status:** Required by every build prompt in
[`luauui-consolidated-roadmap.md`](luauui-consolidated-roadmap.md).
Roadmap Steps 3–14, including Steps 3.5 and 8.5, plus Step 5.5 when cleanup can affect
visible behavior, follow the canonical scriptable Studio matrix in
[`studio-device-verification.md`](studio-device-verification.md).

This contract exists because a green headless suite is necessary but has not been
enough. Previous LuauUI work passed pure tests and still needed repeated correction
in Studio for paint, clipping, text, hit targets, input routing, focus, and game
integration. The goal is not more ceremony. The goal is for the agent to find those
problems before asking a person to test.

The lead agent should choose the local implementation sequence within the decisions
already made by the stage plan. This document defines what evidence is admissible,
what “complete” means, and how to keep working when Studio automation cannot exercise
a real platform behavior.

## 0. Model profile and planning handoff

The roadmap deliberately uses two lead models:

- Steps 1–2 remain Claude Fable 5 goals because they establish the platform and
  styling architecture.
- Step 3.5 is a Fable-led architecture goal whose decided, disjoint implementation
  packages run in Claude Opus 5 (`claude-opus-5`).
- Steps 5 and 6 are also Fable-led: architecture, framework/game ownership,
  cross-platform interaction, motion feel, and live integration decisions remain
  coupled to implementation. Fable uses the named UI Designer specialist and
  dispatches only decided packages to Opus 5.
- Steps 7, 8.5, 11, 12, and 13 are Fable-led for API architecture, large-text
  product/engine integration, reference-product interpretation, 3D topology, and
  whole-framework review/diagnosis respectively.
- Steps 3, 4, 5.5, 8, 9, 10, and 14 use Opus 5. Run Opus with thinking enabled,
  `xhigh` effort as the starting point for agentic coding, and enough output budget
  to finish the long tool-use run.

For Fable-led Steps 5 and 6, follow the orchestration and product-quality contract in
`games/RascalRally/docs/LUAUUI_SPONSOR_PARALLEL.md`. Fable owns live diagnosis,
integration, and reruns; it must continue while an in-scope automated, Studio, or
specialist finding remains. The UI Designer owns the build-ready interaction/
adaptation/motion specification and integrated quality reviews, not implementation.
Apply `GameStudio/specialists/APPLE_UI_MOTION_SKILL.md` through reusable LuauUI
mechanisms and the declared property-authority model, never as game-side bypass code.

For an Opus 5 stage, treat the listed plans and acceptance criteria as the complete
execution brief. Deliver the requested scope without adding adjacent features,
unrelated refactors, or extra abstractions. Make routine implementation decisions
without asking. If live evidence reveals a materially different architecture or
product choice that the plans do not resolve, write a short evidence-backed decision
packet for Fable 5 or the user rather than silently narrowing, widening, or redesigning
the goal.

Keep progress communication sparse: one sentence before the first tool call, then a
brief update only for an important finding or direction change. Lead the final report
with the verified outcome and keep written artifacts no longer than their substance
requires.

Opus 5 already self-corrects and verifies its own work. Do not add redundant “verify
again” loops or verifier subagents for work the lead can check directly. The
repository's independent phase-gate and specialist reviews remain required because
they are acceptance controls, not substitutes for the lead's own checks. Delegate
only sizeable, genuinely independent work with disjoint ownership; keep implementer
spawn counts low and never delegate a handful of tool calls.

## 1. Autonomy rule

Assume the user is not available during the run.

- Proceed with every reversible action that follows from the goal.
- Diagnose and fix failures instead of handing the first failure to the user.
- Do not ask the user to click through intermediate builds or reproduce an issue the
  available tools can inspect.
- Pause only for a destructive or irreversible action, a real scope change, or
  information only the user can provide.
- Batch physical-device and human-feel checks into one final review packet after all
  automated, headless, and Studio-checkable work is complete.
- If a physical device or human judgment is genuinely required, leave that row
  pending. Never replace it with emulator, screenshot, or headless evidence.

Before reporting progress or completion, audit every claim against a tool result from
the current run. A plan, an intention, a test name, or a file existing is not evidence
that the behavior works.

## Rascal Rally consumer lockstep

Rascal Rally's normal and debug Rojo projects mount `GameStudio/ui/LuauUI/src`
directly. A LuauUI source, public-contract, default, behavior, asset, or distribution
change is incomplete until its direct game consumer is synchronized in the same
stage.

For every such change:

1. identify the changed contract and search all Rascal Rally callers, adapters,
   types, fixtures, build mappings, and documentation that depend on it;
2. update affected game integration code rather than leaving compatibility shims or
   workarounds in the game;
3. add or update a Rascal Rally contract/integration test that exercises the change
   through a real game surface;
4. run the affected LuauUI checks, the relevant Rascal Rally suite, both game Rojo
   project mappings when applicable, and an affected Rascal Rally Studio canary for
   visible, input, layout, adapter, or lifecycle behavior; and
5. include a consumer-impact ledger and the game commands/results in the stage
   evidence.

Do not manufacture a production-game edit for a compatible internal change. In that
case, update or add the game-side compatibility test/evidence and record why no
caller change was correct. Documentation-only changes with no contract or behavior
effect update Rascal Rally documentation only when its claim changed. Preserve game
behavior, content ownership, feature flags, the production LuauUI Sponsor default,
and the `UseLuauUISponsor = false` legacy rollback unless a separate authorized goal
changes them. A LuauUI gate cannot pass while its Rascal
Rally consumer is stale, failing, or unaudited.

## 2. Create the acceptance ledger before coding

Turn the stage outcome into a checked-in acceptance ledger before implementation.
Extend the repository's existing evidence and gate conventions rather than building
a competing system. Keep it to observable acceptance behavior; it is not a second
implementation plan or a list of every file the agent expects to edit.

Every row needs:

| Field | Meaning |
|---|---|
| ID | Stable name that can be cited by tests and artifacts |
| User-visible behavior | What a player, designer, or framework author observes |
| Risk | What could be wrong while a lower-level test still passes |
| Required evidence | The minimum evidence level from section 3 |
| Driver | The command, fixture, Studio action, device procedure, or human check |
| Artifact | Trace, geometry dump, screenshot/video, profiler capture, or review result |
| Status | One of the honest states below |

Use these status meanings:

- `PASS_AUTOMATED` — the required headless or Studio behavior was observed by a tool
  in this run and the artifact is stored.
- `PASS_PHYSICAL` — the required behavior was observed on the named physical device,
  with the build and result stored.
- `PASS_HUMAN` — the named visual or feel criterion was reviewed against a concrete
  fixture and approved.
- `FAIL_PRODUCT` — the product behavior is wrong. Fix it before moving on.
- `FAIL_ENVIRONMENT` — the instrument is unavailable or blind. Record the exact
  failure, recover or retry where possible, and do not diagnose the product from it.
- `PENDING_PHYSICAL` / `PENDING_HUMAN` — the automated work and review harness are
  ready, but the irreducible physical or judgment check has not happened.

A row cannot pass through a different, easier row. For example, a headless focus test
does not pass a real gamepad row, and a screenshot does not pass an input-routing row.

## 3. Evidence ladder

Use the lowest level that can actually observe the behavior, but no lower.

| Level | What it proves | What it does not prove |
|---|---|---|
| E0 — source and documentation | API names, intended ownership, and current platform guidance | Runtime behavior |
| E1 — pure/headless | Deterministic decisions, validation, state transitions, lifecycle, geometry invariants, and regressions | Roblox Instances, engine layout/paint, input delivery, clipping, or timing |
| E2 — live engine probe | A Roblox class/property/event exists and behaves as measured | The integrated LuauUI screen uses it correctly |
| E3 — visible Studio slice | The real adapter, Instances, presentation, and game or gallery wiring work together in a visible play session | A physical OS/device path or subjective production feel |
| E4 — physical device | The retail client and real input/display/device behavior work on named hardware | Whether the result meets the intended visual and interaction feel |
| E5 — human review | Readability, hierarchy, polish, pacing, and platform feel meet the stated target | Uninstrumented correctness |

Apply these minimums:

- Layout, text, clipping, z-order, paint, and animation require E3 geometry/state
  evidence plus a capture. A capture alone is not enough.
- Engine property authority and native feature adoption require E2 plus an E3
  integrated slice.
- Mouse and keyboard behavior require an E3 raw-input or native-widget trace where
  Studio injection is available. Calling a Luau callback directly is not evidence.
- Scriptable `InputBinding:Fire()` proves the downstream action path only. It does not
  prove native arbitration, input classification, or hardware delivery.
- Touch-emulator geometry can be E3. A real operating-system keyboard, touch feel,
  and device performance require E4.
- Synthetic gamepad KeyCodes do not prove `PreferredInput == Gamepad`, physical
  forwarding, Button A contention, or console behavior. Those rows require E4.
- Performance claims about the supported device floor require E4. Lune and Studio
  numbers remain separately labeled regression or development evidence.
- The native StyleSheet runtime can be proved at E3. Whether a designer can easily
  find and edit the intended rule in Studio's Style Editor is an E5 workflow check if
  the automation cannot operate that editor.
- “Feels like the existing Sponsor Mode” is E5 and cannot be self-approved by the
  implementing agent.

## 4. Studio preflight: prove the instrument works

Run this before every Studio evidence session and store the result with that session:

1. Record the Studio version, place/build identity, play mode, device profile,
   orientation, viewport size, and relevant feature flags.
2. Confirm the running place contains the source state just built. Inspect a version
   marker or known changed object; do not assume Studio refreshed.
3. Confirm `workspace.CurrentCamera.ViewportSize` is larger than `1,1`, the game view
   is visible, command execution works, and a canary capture succeeds.
4. Clear or mark the log boundary so new warnings and errors belong to this run.
5. Confirm the expected LuauUI target and presenter mounted exactly once.
6. Drive one canary input and observe both the raw/native signal and the intended
   application effect before running the matrix.

If the viewport is `1,1`, capture hangs, input produces no raw event, or the source is
stale, mark `FAIL_ENVIRONMENT`, repair or restart the session, and rerun the preflight.
Do not infer a framework defect from a blind instrument.

Honor the recorded Studio limits in `docs/lessons/`:

- injected mouse coordinates use the target's `AbsolutePosition` space;
- prefer Roblox's `StudioDeviceSimulatorService` over manually clicking the Device
  Emulator, discover preset IDs at runtime, and record the selected configuration;
- prefer `VirtualInput` over external clicking for mouse, keyboard, text, and pointer
  paths; derive positions from live geometry under the active simulator profile;
- `VirtualInput` does not synthesize real touch or gamepad, and it errors when an
  event would interact with `CoreGui`;
- use `StudioTestService` for scripted Play/Run and join/leave rows, but do not assume
  fine-grained control of every simulated client or per-client device profiles;
- Studio cannot synthesize a true gamepad input class;
- a script-fired IAS binding bypasses some native arbitration;
- the device emulator does not summon the real mobile operating-system keyboard;
- screenshots can look aimed correctly even when routed input landed elsewhere.

For layout-affecting work in Steps 3–14, including Steps 3.5 and 8.5, or Step 5.5,
run the five view rows defined in `studio-device-verification.md`: compact phone portrait, the
same phone landscape, tablet landscape, desktop, and console/ten-foot. Do not run the
entire Studio catalog. Resolve the current presets through the API, record the exact
configurations, and keep preferred text, locale, reduced motion, and hybrid input as
targeted fixture axes rather than multiplying every combination.

## 5. Reusable Studio verification surface

Studio MCP should be the transport into a running Roblox session, not the only test
driver or the test oracle. External clicking is too fragile to carry the full
agentic loop.

Before substantial roadmap implementation, build or extend one development-only
verification surface using the existing gallery, preview profiles, artifacts, and
gate system. Do not create a second UI framework or ship test controls to players. It
should let an agent:

- select a named deterministic scenario and reset it without assembling game state;
- mount the real LuauUI adapter and identify the exact presenter/source version;
- change supported viewport, orientation, environment, accessibility, and fixture
  facts through declared test seams and, where supported, Roblox's scriptable Studio
  testing APIs;
- advance success, failure, interruption, stale-async, and lifecycle states
  deterministically;
- record actual Instances, geometry, visibility/clipping, focus, style authority,
  semantic actions, commands, resource ownership, warnings, and performance counters;
- expose a clear ready/running/pass/fail state the MCP can read;
- export a stable machine-readable artifact keyed to the acceptance row;
- request named captures at stable moments;
- run one scenario or a representative batch without user interaction.

Use this runner for state setup and observation, not to counterfeit hardware input.
If it calls a control API or scriptable action, label that evidence as downstream
state/action proof. Native input rows still require the Studio or physical input path
defined in section 3.

When a new stage needs a scenario, extend this surface and its registry. Do not paste
a one-off command-bar script into the evidence packet and call it a reusable gate.

## 6. The implementation loop

For each independently observable vertical slice:

1. Freeze a baseline fixture, trace, and capture where an existing behavior is being
   preserved or matched.
2. Add a failing E1 test for every pure decision and regression that can be modeled
   without Roblox.
3. Add or update the E2/E3 fixture and its instrumentation before making the behavior
   green. The fixture must expose enough state to diagnose failure without asking the
   user.
4. Implement the smallest complete slice.
5. Run focused tests, the relevant architecture/registration gates, and the live
   Studio slice. Do not defer all Studio testing until the end of the stage.
6. Compare the runtime result with the acceptance row, not merely with the
   implementation's own dump.
7. Audit the slice against its acceptance row and current tool artifacts. Fix every
   correctness or acceptance failure, add the smallest durable regression, and rerun
   the affected evidence.
8. Periodically rerun the full suite and a representative Studio canary so later
   changes cannot invalidate earlier slices unnoticed.

At the stage boundary, give the one required fresh-context phase-gate verifier the
goal, acceptance ledger, changed source (and a diff when available), and raw
artifacts—without the implementer's conclusions. Add an architecture, reactive
runtime, or Roblox-platform specialist review only when the stage changed that
authority. Fix every requirement-affecting finding and rerun the affected evidence.

When Studio uncovers a defect the headless suite missed, improve the system in two
places:

- add the smallest headless regression if the missed part is a deterministic
  framework decision; and
- keep a Studio scenario for the adapter, engine, or integration behavior that a
  headless model cannot observe.

Record a durable lesson under `docs/lessons/` only when the finding is not already
captured there. Update an existing lesson instead of creating a duplicate.

## 7. Evidence bundle

Every stage ends with a machine-readable manifest and a short human-readable summary
using the repository's existing artifact locations and gate schema. The bundle must
contain:

- the acceptance ledger with final status for every row;
- exact commands and their exit results;
- Studio preflight data;
- raw event/action traces for interactions;
- instance, geometry, focus, style-authority, and lifecycle telemetry relevant to
  the stage;
- captures named by fixture, device profile, orientation, input path, and state;
- baseline-versus-new comparison when preserving behavior;
- profiler captures and measurement conditions for performance claims;
- the LuauUI-to-RascalRally consumer-impact ledger, game-side code/test updates, and
  exact consumer verification results;
- the fresh-context verifier findings and the fixes or explicit disposition;
- all `FAIL_ENVIRONMENT`, `PENDING_PHYSICAL`, and `PENDING_HUMAN` rows with one exact
  procedure for closing each.

Pair pictures with facts. A screenshot should have a matching fixture ID and a trace
or geometry dump that identifies what state it shows. Avoid fragile global
pixel-equality across engine versions; use explicit geometry, visibility, contrast,
state, and clipping assertions, then use captures for visual review.

## 8. How to finish without repeatedly involving the user

Complete every automatable row first. For remaining physical or human rows, produce
one review build and one review packet containing:

- a development-only entry point or selector;
- a short ordered scenario list with reset controls and deterministic fixtures;
- an on-screen build/fixture/device label;
- automatic event, focus, command, and performance capture;
- expected results and the specific judgment being requested;
- an export action that saves the review results and traces;
- rollback or exit instructions.

The user should not have to discover the test cases, assemble game state, inspect
logs, or explain which result failed. The packet should turn the remaining work into
one focused pass.

If hardware or human review is unavailable, report **automation complete, release
evidence pending**. Do not report the stage or roadmap outcome fully complete.

## 9. Minimum live evidence by roadmap stage

| Stage | Live proof required before an automated-complete claim |
|---|---|
| 1 — native substrate | The intended native Instances exist in the running tree; scrolling changes native canvas state and clips descendants; drag/touch/path/page/safe-area/resource behaviors have engine traces and integrated captures; fallbacks are exercised separately |
| 2 — StyleSheets | A running screen changes through a native style-rule/token change without a Luau source edit; native and app states change the intended rules; explicit writes no longer defeat stylesheet-owned properties; focus and mount identity survive |
| 3 — authoring and common UI | Invalid public authoring fails at the boundary; the actual gallery drives each control through available real Studio input; portrait, landscape, desktop, and console-emulated layouts have geometry and captures; layout/input hot changes retain valid state |
| 3.5 — theme packages | A clean consumer builds Fantasy Parchment through public docs/APIs; its nine-slice panels/control chrome and every package install/swap run in the mounted all-controls fixture; palette, effective font/metrics, solved/actual/hit geometry, states, adaptive paradigms, fallbacks, focus/resource identity, Style Editor synchronization, documentation drift, and flat-versus-ornate cost have paired evidence across the device matrix |
| 4 — quality and future seam | Production-shaped scenes emit separate headless, Studio, and physical artifacts; telemetry measures the promised quantities; unavailable device measurements remain pending; spatial work is limited to contracts and test fixtures |
| 5 — Sponsor framework gaps | Every reusable gap runs in a Sponsor-shaped Studio gallery with deterministic fixtures for success, failure, interruption, reduced motion, preferred text, and teardown; the UI Designer reviews its interaction/adaptation/motion quality against named legacy criteria; relevant Apple-motion principles are generalized behind public LuauUI contracts; no RascalRally game policy appears in LuauUI |
| 5.5 — simplicity cleanup | Current Studio baselines remain unchanged for every touched visible/input/adapter path; public exports, deprecations, lifecycle/resource counts, and prior gates are compared before and after; cleanup claims are backed by a candidate ledger rather than line count alone |
| 6 — parallel Sponsor | The real place freezes named legacy quality baselines, runs the LuauUI presenter against the same fixtures, proves only one live presenter/command effect, and produces paired captures/traces for every matrix row; Fable repeats integrated UI Designer reviews until no automatable/specialist gap remains; an ownership ledger proves framework needs were fixed/tested in LuauUI and no local workaround/parallel adaptation machinery remains; physical and director FEEL approval remain separate gates |
| 7 — API consistency | The fresh-author exercise uses only public docs and APIs; any compatible change that can affect runtime has matching real-adapter proof; the surface ledger and checks classify every public item or justified exception |
| 8 — desktop keyboard | Raw Tab/Shift+Tab, Space/Return, and arrow input reaches semantic traversal/activation/adjustment through the real adapter; responder ownership, text editing, exactly-once activation, keep-visible, and teardown are traced |
| 8.5 — large text | All four native preference values and live changes have exact-once measurement/paint evidence; the public surface and production Sponsor fixtures reflow without overlap or inaccessible essential text; compact portrait/landscape, full-value access, focus/scroll survival, reduced motion, and bounded reveal work have paired traces/captures |
| 9 — performance lab | Self-contained places rebuild and run without Rojo; the scenario runner, dense scroll workload, matched native reference, bounded mount window, MicroProfiler labels, capture metadata, reset, and teardown work in Studio; low-end Android remains a named physical row |
| 10 — example quality | All seven examples are played through the real adapter; teaching, style authority, geometry, input, completion/reset, failure, and lifecycle rows have paired traces/captures; an ownership ledger proves examples contain domain/content plus declarative composition while reusable fixes live behind public LuauUI APIs; source claims alone close nothing |
| 11 — reference apps | Each clean-room reference proof runs a complete representative loop across the applicable five views and input paths; the feature ledger cites live evidence and never substitutes a fake for an unavailable Apple host surface |
| 12 — declarative 3D decision | The isolated Part/Model spike records explicit server/client roots, identity, writes, lifecycle, streaming-like loss/reentry, failures, and cost; no spike evidence is relabeled as production 3D or VR support |
| 13 — release review | Representative production scenarios preserve their baseline after fixes; every confirmed live-observable defect has reproduction and after-proof; the full finding ledger is independently audited; the guide index categorizes and names every public layout, control, service, target, and extension family, the API reference is exhaustive, and drift checks bind both to current exports/registrations |
| 14 — source sharing | The allowlisted source export mounts, themes, adapts, accepts input, and tears down with no monorepo-only import; two exports match; internal material is excluded; root `AGENTS.md` plus the thin skill guide two fresh agents through successful public-API build and extension tasks; no Roblox Package is required |

## 10. Completion language

Use precise completion language:

- “Implemented and headlessly verified” means E1 only.
- “Studio verified” means the E3 preflight passed and the integrated behavior has a
  stored artifact.
- “Physical-device verified” names the device and build.
- “Parity complete” requires every required automated, physical, and human row.

Never collapse these into “all tests pass.”
