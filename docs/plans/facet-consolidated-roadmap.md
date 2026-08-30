# Facet consolidated roadmap — Roblox-native, declarative, device-profiled, Sponsor-proven

**Date:** 2026-08-13
**Updated:** 2026-08-16

This is the entry point for Facet work. Running the prompts in order is intended to
produce these outcomes:

Steps before Step 13 were written under the framework's pre-rename name and root
directory. Step 13 renames the complete framework and every current consumer to
**Facet**, including this roadmap and its root directory. All later steps use Facet.

1. Facet stops rebuilding Roblox capabilities that belong at the engine adapter.
2. designers can restyle Facet screens through Roblox's Style Editor, while the
   headless solver remains deterministic;
3. invalid or stale UI code fails clearly, and common controls/layouts adapt without
   device-specific screen copies;
4. versioned theme packages can change paint, typography, metrics, and bounded rich
   chrome while the solver reflows correctly and screen code remains unchanged;
5. performance claims are backed by the existing headless regression system plus
   real Roblox device evidence, with world-fixed `SurfaceGui` support kept distinct
   from an honest extension seam for future spatial input and VR;
6. a fresh-context simplification pass removes proven framework waste where found,
   without changing public behavior or smuggling in a redesign;
7. Rascal Rally ships the proved Facet Sponsor presenter as production default while
   retaining the untouched legacy presenter as an explicit rollback;
8. one API and architecture constitution makes new features predictable to authors
   and agents, with current exceptions documented rather than accidental;
9. desktop keyboard users get an automatic focus chain, activation, and value-control
   behavior without screen-local key wiring or gameplay input theft;
10. Roblox preferred text size becomes a live layout input; public UI and Rascal
   Rally Sponsor View reflow without overlap or inaccessible essential text, including
   compact mobile portrait and landscape;
11. self-contained performance places make Facet cost reproducible and optimizable in
   Studio and on the supported low-end Android floor;
12. every tutorial example is visibly instructive, playable, consistently styled, and
   verified through the real Roblox adapter.
13. three clean-room, production-scale reference experiences show what Facet can build
   inside Roblox and distinguish framework gaps from host-platform differences;
14. a measured architecture decision determines whether declarative 3D should become
   a sibling system without forcing world objects into the 2D UI solver;
15. the framework and every current consumer become Facet; a fresh Fable release review
   remediates whole-framework defects, makes the guide/API catalogs complete and plain,
   consolidates repeated mechanisms, makes the Input Action System authoritative,
   refactors for predictable human/agent maintenance, proves an ELI5 new-control path,
   resolves public names, re-profiles and optimizes the current performance lab,
   rewrites source comments in plain human language, and removes vendor-framework
   language outside the two explicit comparison areas;
16. the tutorial games, Sipworks, and Glade become complete play loops; Wardrobe
   retires; Facet gains a proved world-surface target and shared-source standalones;
   and the Facet/Rascal Rally verification loop becomes practical without weaker proof;
17. the existing repository is renamed `josha/Facet` and becomes an MIT-licensed,
    public-ready source distribution with a clean branch tip, audited history, tested
    human/agent onboarding, one stable Roblox Package asset, and a requirement-complete
    test/gate graph that avoids repeating hours of identical work; and
18. every Facet change keeps Rascal Rally's directly mounted consumer code, contract
   tests, build mappings, and affected Studio behavior synchronized in the same stage.

Steps 1–2, 3.5, 5, 6, 7, 8.5, 11–13, and 14 are Fable-led because architecture,
ownership, product interpretation, live diagnosis, or whole-framework judgment
remains coupled to execution. Fable dispatches only decided work packages to Opus 5.
Steps 3, 4, 5.5, 8, 9, 10, and 13.5 are bounded Opus 5 execution goals, using
[`claude-opus-5`](https://platform.claude.com/docs/en/about-claude/models/whats-new-opus-5)
with thinking enabled and `xhigh` effort as the starting point for agentic coding.
The prompts follow the
[Fable 5 guidance](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5)
for the architecture- and integration-sensitive goals and the
[Opus 5 guidance](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5)
for the execution goals: give the complete specification up front, constrain scope,
keep narration sparse, bound delegation, and avoid redundant verification scaffolding.
The plan documents carry the detailed decisions.

Every prompt also inherits the hard proof and autonomy rules in
[`agent-execution-contract.md`](agent-execution-contract.md). That contract exists
because a passing headless suite has not reliably predicted correct Studio behavior.
It requires a checked acceptance ledger, visible Studio slices throughout the work,
one reusable self-verifying Studio scenario surface, fresh-context verification,
honest evidence labels, and one batched physical/human review packet instead of
repeated requests for the user to test unfinished work.

## Read order and authority

Before any prompt, read the repository `CLAUDE.md`, every closer `CLAUDE.md`, and
the relevant `.claude` guidance. The repository boundary is important:

- `GameStudio/ui/Facet` owns reusable framework capability;
- `games/RascalRally` consumes the framework and owns game behavior and authored
  Sponsor presentation;
- game-specific logic must not move into GameStudio.

Because both Rascal Rally Rojo projects mount Facet source directly, every framework
source/contract/default/behavior/asset/distribution change must also audit and update
the affected Rascal Rally integration and a game-side contract test in the same
stage. If no production caller should change, update the compatibility test/evidence
instead of manufacturing code churn. The execution contract defines the required
consumer ledger, commands, Studio canary, and behavior-preservation rule.

These documents govern the work:

1. [`agent-execution-contract.md`](agent-execution-contract.md) — model handoff,
   evidence,
   Studio-loop, autonomy, and completion rules for all eighteen prompts.
2. [`roblox-native-audit-corrections.md`](roblox-native-audit-corrections.md) —
   current platform corrections; it wins over older claims.
3. [`roblox-native-primitives.md`](roblox-native-primitives.md) — detailed
   scrolling, virtualization, text, focus, safe-area, resource, and adapter audit.
4. [`roblox-native-stylesheets.md`](roblox-native-stylesheets.md) — native styling
   architecture and phased migration.
5. [`parity-next.md`](parity-next.md) and
   [`../reference/the comparison document`](../reference/the comparison document) — common
   controls/layout priorities, agent-safe authoring, performance proof, future
   platform seam, and the selected parity ledger.
6. [`theme-packages-and-skinning.md`](theme-packages-and-skinning.md) — versioned
   custom themes, solver-synchronized metrics, font measurement, rich chrome, and
   Style Editor workflow.
7. [`../guide/README.md`](../guide/README.md) and
   [`../extending/new-control.md`](../extending/new-control.md) — the consumer and
   extension workflows that must stay aligned with the runtime.
8. [`../reference/sponsor-view-parity.md`](../reference/sponsor-view-parity.md) —
   framework capability ledger for Sponsor Mode.
9. [`code-simplicity-cleanup.md`](code-simplicity-cleanup.md) — fresh-context,
   behavior-preserving simplification gate before game integration.
10. [`games/RascalRally/docs/FACET_SPONSOR_PARALLEL.md`](../../../../../games/RascalRally/docs/FACET_SPONSOR_PARALLEL.md)
   — full game-specific parallel-build and proof plan.
11. [`api-architecture-consistency.md`](api-architecture-consistency.md) — the
    predictable public API, lifecycle, extension, and enforcement rules.
12. [`desktop-keyboard-navigation.md`](desktop-keyboard-navigation.md) — Tab focus
    traversal, Space activation, value adjustment, responder ownership, and proof.
13. [`large-text-accessibility.md`](large-text-accessibility.md) — exact native
    preferred-text handling, reflow and overflow policy, and mobile Sponsor proof.
14. [`performance-stress-places.md`](performance-stress-places.md) — publish-ready
   device profiling lab, workloads, MicroProfiler protocol, and optimization loop.
15. [`example-quality-pass.md`](example-quality-pass.md) — tutorial gameplay,
    teaching, styling, input, and Studio-evidence requirements.
16. [`reference-app-validation.md`](reference-app-validation.md) —
    official-sample feature ledgers and three clean-room Roblox proof experiences.
17. [`declarative-3d-architecture.md`](declarative-3d-architecture.md) — decision and
    isolated spike for a possible sibling declarative world system.
18. [`release-candidate-review.md`](release-candidate-review.md) — fresh-context
    whole-framework review and remediation.
19. [`example-games-and-standalones.md`](example-games-and-standalones.md) — complete
    word, crossword-tile, and match-3 play, a real `SurfaceGui` walk-up terminal, and
    curated standalone example places.
20. [`distribution-readiness.md`](distribution-readiness.md) — existing-repository
    structure, MIT/provenance, complete-history privacy audit, agent onboarding,
    reproducible Roblox Package updates, single-execution test/gate simplification,
    and public-release verification.
21. [`studio-device-verification.md`](studio-device-verification.md) — the
    scriptable five-view Studio matrix, VirtualInput rules, multiplayer-test use,
    and evidence that still requires physical hardware.
22. [`parity-round2-brief.md`](parity-round2-brief.md) and
    [`parity-round2.md`](parity-round2.md) — the Milestone 1 work
    below: the brief is the binding scope, the design is the per-phase build plan.
23. [`device-bug-round-2026-08-12.md`](device-bug-round-2026-08-12.md) — Milestone
    1's device phase, and the ledger of what it left owed.
24. [`unfulfilled-placement-intents.md`](unfulfilled-placement-intents.md) — the
    director's decision queue for placement intents an author expressed and never
    got; a migration there moves pixels and is never taken unilaterally.

When a plan claim disagrees with current official Roblox documentation or a Studio
experiment, update the plan before implementation and record the evidence. Do not
silently code around the disagreement.

## What stays custom and what moves native

The useful boundary is not “engine-agnostic versus Roblox-specific.” Facet is a
Roblox framework. The boundary is decision versus mechanism:

- Keep deterministic decisions in pure Luau: layout geometry, logical focus,
  responder ownership, virtualization/windowing, semantic actions, drag/drop policy,
  animation choreography models, and injected environment facts.
- Use Roblox at the adapter edge for mechanisms it already owns: scroll physics and
  clipping, safe-area measurement, drag acquisition, touch gesture recognition,
  native path drawing, page layout where appropriate, image fetching/decoding,
  native styles, and engine-owned interaction states.
- Preserve headless test drivers and fallbacks. Native adoption must not turn an
  existing pure decision into an engine-only black box.

Key corrections to the earlier roadmap:

- `UIDragDetector`, not a larger raw-Grip system, is the first live drag mechanism.
- `GuiObject` already exposes long-press, pan, pinch, rotate, swipe, and tap events.
- `Path2D` is the first candidate for rings, arcs, curves, and stroked icons.
- `UIPageLayout` is worth testing for paged `TabView`, not general transitions.
- `GuiState` is read-only; Roblox owns native button state and Facet tags app state.
- `StyleQuery` has a closed built-in condition set; tags carry Facet's filtered
  paradigm decisions.
- Roblox preferred text size must be applied exactly once.
- passive gameplay HUDs keep `GuiService.SelectedObject` nil; only engaged
  modal/menu surfaces may test an engine-selection bridge.
- `PreloadAsync` has no physical cancellation; Facet can reject stale completion
  and avoid starting queued work.
- `billboard_target.luau` is implemented already.

## Execution order

| Step | Outcome | Main gate |
|---|---|---|
| 1 | Corrected Roblox-native substrate and evidence | Native spikes pass; headless decisions remain tested |
| 2 | Style Editor owns runtime paint and state styling | A designer edit changes a running Facet screen without a Luau edit |
| 3 | Trustworthy authoring plus everyday adaptive controls/layouts | Invalid UI fails clearly; common screens pass all input/layout profiles |
| 3.5 | Metric-aware theme packages and rich skinning | Public custom packages swap paint/fonts/metrics/chrome; solver reflows without remount or drift |
| 4 | Cross-platform performance and future-platform proof | Existing headless gates plus real phone/console evidence; no unearned VR claim |
| 5 | Sponsor-required framework capability | Every framework row in the Sponsor ledger is closed or intentionally game-owned |
| 5.5 | Fresh-context simplicity cleanup | Proven waste is removed; public behavior, prior gates, and Studio baselines remain intact |
| 6 | Parallel RascalRally Sponsor Mode | Full parity packet passes with legacy intact and still default during this gate |
| 7 | API constitution and consistency audit | Every public item follows a documented pattern or a justified exception; drift is checked |
| 8 | Desktop keyboard interaction | Tab/Shift+Tab, Space/Return, and value arrows work through the existing focus/responder system |
| 8.5 | Large-text accessibility | Native text preference is exact and live; public UI and Sponsor View reflow without inaccessible content on compact mobile |
| 9 | Publish-ready Facet performance lab | Deterministic Studio/device profiles and matched native baseline; low-end Android row honest |
| 10 | Tutorial gallery quality pass | All seven examples are played, styled, understandable, and governed by a canonical gate |
| 11 | Production-scale reference validation | Three clean-room proof experiences run; all official-sample features are honestly classified |
| 12 | Declarative 3D architecture decision | A sibling-versus-extension decision is proved by an isolated topology/lifecycle spike |
| 13 | Facet rename, release-candidate, and maintainability review | Facet is canonical everywhere; findings resolve; control authoring/naming, sensory haptics, profiling, reuse, IAS, comments, and agent maintenance pass |
| 13.5 | Facet game, world-surface, standalone, and test polish | Games, named examples, sensory feedback, terminal, and test-time budget pass; Wardrobe retires; proof remains complete |
| 14 | Facet public repo, Package, tests, and agent onboarding | Existing repo is renamed and release-ready; each unique check runs once; Package, fresh clone/agents, history, and release surfaces pass |

### Milestone 1 — parity round 2 (in flight; NOT a numbered step)

The work that followed Step 11 is a mission of its own rather than a new step, and
it is registered here because this file is the execution entry point and an
unregistered plan is a plan nobody reads.

| Plan | What it governs | State |
|---|---|---|
| [`parity-round2-brief.md`](parity-round2-brief.md) | The binding scope | — |
| [`parity-round2.md`](parity-round2.md) | The design: Phases 0–6, grouped **M1** = 1–2, **M2** = 3–4, **M3** = 5–6 | Phases 0–6 built; gate stage `swiftui-parity-round2` registered 2026-08-13 |
| [`device-bug-round-2026-08-12.md`](device-bug-round-2026-08-12.md) | The device phase: nine director findings in three causes | Groups B and C closed; the TD-13/TD-14 re-record **owed** |
| [`unfulfilled-placement-intents.md`](unfulfilled-placement-intents.md) | The director's queue from the §2.1 placement audit | Awaiting per-row rulings |

**The mission ran UNGATED, and that is on the record rather than tidied away.**
Phase-gate verification of `13fd3c6` found no round-2 entry in `phases.json` and
no block in `tools/lune/gate_manifest.luau`, so `tools/gate.sh` had no stage to
run for any of M1, M2 or M3: every milestone closed on hand-run suites, a
hand-run checker battery and reviewer judgement. The stage was registered after
the fact on 2026-08-13 as `swiftui-parity-round2` (26th and last in
`phases.json`), with twelve checks — suite floor 4589, `withAnimation`, the
layout vocabulary, indicators + `sensoryFeedback`, the four-input proofs, gallery
coverage, the overflow sweep, the eight-checker battery, the parity doc's
falsifiability, the Rascal Rally consumer contracts, the carried traversal red,
and the prior-gates sweep. Two consequences of the gap were fixed with it:

- **the floor.** The highest `tools/test.sh` floor in the manifest was 4136
  against an actual 4589, so nothing pinned this mission's finishing count. 4589
  is measured from a pristine `git archive 13fd3c6` export, twice.
- **the four-input proofs.** `check_registration` keys `inputProofs` on
  *controls*; round 2 added interactive **props** (`Table.onPrimaryAction`, the
  playlist table's hosted `rowActions`), which that checker structurally cannot
  see. The proofs are now enforced in the gate as `✓`-anchored suite greps —
  stronger than the checker's source-string rule, which proves a case is
  registered and never that it passes. **Named gap, not closed:** a *future*
  modifier or prop shipping interactive behaviour with no proofs is still
  uncaught, because a modifier has no mechanical interactivity signal to derive
  and a heuristic prop-schema scan is the noisy checker the simplicity ladder
  says gets disabled. `UI.sensoryFeedback` is deliberately outside the rule: it
  declares no input of its own.

Two more standing facts from the mission outlive it, because both reverse an
earlier decision and a future agent will otherwise "restore" the old one:

- **the 8px scroll-bar reserve is published under the overlay policy too**
  (director, 2026-08-12), which reverses the 2026-08-09 ruling that an overlay
  indicator claims no layout space;
- **`rowHeight` / `viewportHeight` on `newVirtualList` are deprecated aliases** of
  the axis-neutral `itemExtent` / `viewportExtent`, registered in
  `Facet.DEPRECATIONS`; both still work on a vertical list.

Steps 2 and 3 may overlap after property authority and native state are settled.
Step 3.5 starts only after Step 3's control vocabulary is stable; it does not reopen
completed Step 2. Step 4 then extends quality systems across theme swapping, fonts,
assets, and the earlier work rather than postponing measurement until the end. Step 6
must not start as a live interactive build until Step 5's foundations are proven and
Step 5.5 has completed without baseline drift.
Recorded/static Sponsor fixtures may be created earlier.

Step 5.5 is deliberately before game integration. Step 7 then freezes the API rules
before Step 8 adds keyboard behavior. Step 8.5 makes large text a live layout and
product requirement before Steps 9 and 10 exercise the resulting surface through
performance and tutorial product passes. Step 11 tests broader application
composition without treating host-only platform surfaces as framework gaps. Step 12's
declarative Part/Model decision stays separate from the two-dimensional `SurfaceGui`
target required in Step 13.5. The fresh review in Step 13 precedes that bounded
game/standalone pass. Step 13.5 must rerun affected release-review rows when it adds
the target or otherwise changes framework code, then Step 14 prepares the public
repository.

Physical-device and human-feel checks are real release gates, not tasks an agent
should simulate. If the required hardware or human review is unavailable, the agent
finishes the harness and automated evidence, records the exact remaining procedure,
and leaves the gate explicitly pending. Emulator or headless evidence must not be
relabeled as physical evidence.

Run Fable-led Steps 1–2, 3.5, 5, 6, 7, 8.5, 11–13, and 14 at Fable's highest
practical effort; dispatch only decided packages to Opus 5. Run Steps 3, 4, 5.5, 8,
9, 10, and 13.5 in Opus 5 with thinking enabled, `xhigh` effort, and enough output
headroom for the full tool-use run. Verify one vertical slice at a time rather than
deferring Studio to stage end.

“Without user intervention” therefore means no repeated implementation/debugging
rounds delegated to the user. It cannot honestly mean that either lead model
self-approves
physical console/touch behavior or Sponsor feel. Those irreducible checks happen once,
at the end, through the prepared review build and checklist.

Fable directly leads the architecture- and integration-sensitive stages and owns
live diagnosis and unresolved choices. Opus should make routine decisions and finish
the bounded execution stages. If live evidence introduces a material choice the
plans do not answer, Opus produces an evidence-backed decision packet rather than
silently redesigning the stage.

## Step 1 — Correct and adopt the Roblox-native substrate

Done July 23, 2026

Read the corrections addendum and the native-primitives plan. The first phase is an
evidence pass, not production code. It covers native scroll/clip, `UIDragDetector`,
native touch events, `Path2D`, `UIPageLayout`, safe areas, preferred text,
modal-only selection bridging, and resource status/stale completion.

### Fable goal prompt

```text
/goal Make Facet use Roblox-native UI mechanisms wherever the corrected audit says
to adopt or use a hybrid, while keeping deterministic framework decisions headlessly
testable. Read and follow:

- GameStudio/ui/Facet/docs/plans/agent-execution-contract.md
- GameStudio/ui/Facet/docs/plans/roblox-native-audit-corrections.md
- GameStudio/ui/Facet/docs/plans/roblox-native-primitives.md

Outcome: native engine mechanisms do the work Roblox already owns, while Facet keeps
the reusable decisions, fallbacks, and deterministic tests it genuinely needs.

Why: Facet is Roblox-only. Roblox should own scroll physics, clipping, drag
acquisition, native touch recognition, safe-area measurement, path rendering,
appropriate page layout, and resource transport. Facet should own layout geometry,
logical focus, virtualization, semantic input, payload/drop policy, and testable
fallback models.

Boundaries:
- The corrections addendum wins over older plan text.
- Do the documented Studio feasibility matrix first. Ground every platform claim in
  current official documentation and a tool result from this run.
- Keep the existing adapter-capability seam and a headless driver/fallback. No
  assertion that is headlessly tested today may become engine-only.
- Keep passive/gameplay targets at GuiService.SelectedObject=nil. An engine selection
  bridge is opt-in for an engaged modal/menu only and requires physical-gamepad proof.
- Treat PreloadAsync cancellation honestly: ignore stale completion and skip queued
  work; do not claim an in-flight fetch was stopped.
- Keep RascalRally game behavior unchanged, but synchronize affected Facet consumer
  code/tests under the execution contract.

The execution contract is a hard acceptance contract, not background reading. Before
coding, create the stage acceptance ledger and establish or extend the contract's
reusable Studio verification surface. Verify each vertical slice in a visible running
gallery as it lands. Native instance construction or a green headless model alone
does not pass an adoption row: record the running Instance tree, the relevant engine
state/event trace, integrated geometry or behavior, and a matching capture. For
input, distinguish real/injected native events from scriptable action firing.
Exercise fallback and native paths separately. Leave true gamepad, physical touch/OS
keyboard, and device-performance rows pending when the available instrument cannot
observe them.

Complete the adoption in reversible phases, updating the audit, ADRs, API reference,
tests, examples, and evidence as each capability lands. Verify the full Facet suite,
the relevant RascalRally suite, Studio device profiles, and fresh-context architecture
and Roblox-platform review. Fix verifier findings and rerun the affected live slice.
Report exact evidence and any fallback retained. Stop only for a destructive action,
a real scope change, or input only the user can provide. If irreducible evidence is
unavailable, finish the review harness and report automation complete with that row
pending—not the stage fully complete.
```

## Step 2 — Make native StyleSheets the runtime styling system

Done July 24, 2026

The desired promise is specific: a designer can open the Style Editor, find
human-readable Facet roles, edit paint or a supported state, and see the running UI
change without editing Luau. This promise does not extend to solver geometry unless a
tested export/synchronization step exists and is clearly documented.

Styling Transitions are optional polish while they remain beta. The publishable path
must work with instant state changes.

### Fable goal prompt

```text
/goal Implement the corrected native-stylesheet plan for Facet. Read and follow:

- GameStudio/ui/Facet/docs/plans/agent-execution-contract.md
- GameStudio/ui/Facet/docs/plans/roblox-native-audit-corrections.md
- GameStudio/ui/Facet/docs/plans/roblox-native-stylesheets.md

Outcome: Roblox StyleSheets and the Style Editor become the runtime source of truth
for every proven styleable paint property, semantic role, native interaction state,
app-state tag, theme, and transition. A designer can edit a named rule or paint token
in Studio and see it on a running Facet screen without changing Luau.

Why: visual authors should use Roblox's supported visual workflow, and future Roblox
styling improvements should benefit Facet without a competing custom paint system.

Boundaries:
- GuiState is read-only and engine-owned. Use native state selectors for native
  hover/press/non-interactable state and tags for Facet-owned state.
- Use only documented built-in StyleQuery conditions. Tags carry Facet's filtered
  input-paradigm and pointer-live decisions.
- One authority owns each engine property. Once a property is native-styled, remove
  Facet's direct write for that property; preserve an explicit-write fallback only
  as a separate target mode.
- Keep solver inputs available in pure Luau. Do not promise editor round-trip for
  spacing or type metrics without a tested export/freshness workflow.
- Run the preferred-text matrix and ensure Roblox preference is painted exactly once
  while headless measurement reserves matching bounds.
- Styling Transitions are progressive enhancement until publishable. Prefer the
  ReducedMotionEnabled query and keep instant-change behavior.

The execution contract is a hard acceptance contract. Create the acceptance ledger
and Studio preflight first, reusing the shared verification surface. A stylesheet row
passes only when a visible running Facet screen changes through an actual native
style rule or token change without a Luau source edit, and the artifact pairs the
capture with mount identity, focus, state, and property-authority telemetry. Prove
that an explicit write is no longer silently defeating each stylesheet-owned
property. Exercise hover/press/disabled, Facet app-state tags, theme changes, reduced
motion, and preferred text through the real adapter. A generated stylesheet, unit
test, or screenshot without runtime state evidence is insufficient. If the MCP cannot
operate the visual Style Editor, automate the runtime rule edit and leave one clearly
scoped designer-discoverability workflow check for the final batched human review.

Start with the plan's Studio evidence matrix, then implement behind an opt-in target
capability. Prove editor round-trip, authority handoff, theme swap, native/app state,
reduced motion, preferred text, fallback parity, and no remount/focus loss. Verify the
full suites and fresh-context platform/architecture review. Fix findings and rerun
the affected live slice. Update the styling guide so a human can tell which Style
Editor edits are immediate and which require export. Report the distinction between
automated runtime proof and any still-pending visual-editor workflow check.
```

## Step 3 — Make authoring trustworthy, then add everyday adaptive UI

In progress July 24, 2026

Start with the public-authoring contract because expanding a surface that silently
accepts invalid properties makes agent-written and human-written UI harder to trust.
Then build the native ScrollView, adaptive layouts, Button, Slider/Stepper, and common
layout/control vocabulary. ScrollView consumes Step 1's native host. Visual states
consume Step 2's native styling model.

### Opus 5 goal prompt

```text
/goal Make Facet safe to author, then deliver the adaptive-layout and common-control
milestones in the referenced plan.

Run with Claude Opus 5 (`claude-opus-5`), thinking enabled, `xhigh`. Follow the plans
as acceptance requirements; avoid adjacent features and unrelated refactors. Escalate
only materially unresolved architecture/product choices with an evidence-backed
decision packet for Fable 5 or the user.

Read:
- GameStudio/ui/Facet/docs/plans/parity-next.md
- GameStudio/ui/Facet/the comparison document
- GameStudio/ui/Facet/docs/plans/agent-execution-contract.md
- GameStudio/ui/Facet/docs/plans/studio-device-verification.md
- GameStudio/ui/Facet/docs/plans/roblox-native-audit-corrections.md
- GameStudio/ui/Facet/docs/guide/
- GameStudio/ui/Facet/docs/extending/new-control.md

Outcome: invalid UI receives immediate useful feedback, and common screens can be
written once while adapting correctly to supported input, display, and accessibility
profiles.

Complete Milestone 0 first: unknown-prop errors, useful public types, one reconciled
property schema/authority/update model, adapter/docs/test parity, dead-prop decisions,
honest extension seams, and complete conformance registration. Preserve compatibility
through the documented deprecation policy.

Then implement the plan in dependency order: native ScrollView; complete Button;
Slider/Stepper; adaptive stack/ViewThatFits; Grid fill and Spacer defaults; listed
layout modifiers and Divider; then ProgressView, Label, Picker variants,
PopupButton, and DisclosureGroup.

Non-negotiables:
- Use the Step 1 native hosts: UIDragDetector for Slider where proven, semantic Adjust
  for keyboard/gamepad, and one shared scroll/keep-visible substrate.
- Use the Step 2 native StyleSheet/state architecture; create no parallel paint-state
  system.
- Finish each control for mouse/keyboard, touch, gamepad/ten-foot, and live hybrid
  changes. Adapt from capabilities, space, viewing distance, and accessibility—not
  platform-name branches.
- Keep public APIs idiomatic, but never preserve silent failure or false examples for
  compatibility.

Treat agent-execution-contract.md as binding. Create the acceptance ledger and
instrumented gallery fixtures first; deliver and verify one vertical slice at a time
in visible Studio. Native-input proof must traverse the mounted control and include
raw event, semantic action, focus, effect/value, actual geometry, and capture; direct
callbacks do not prove input.

Run the canonical five-view API matrix from studio-device-verification.md, resolving
presets at runtime. Use VirtualInput only for paths it supports and live geometry for
coordinates. Include a live portrait/landscape change with state/focus preservation.
Keep physical touch, real gamepad, mobile OS keyboard, and hardware-performance rows
explicitly pending when Studio cannot prove them.

Verify focused and full tests, authoring errors/types, hit floors, disabled/bounds
behavior, lifecycle neutrality, adaptive/accessibility variants, screenshots plus
geometry/state traces, API/registration drift, and required fresh-context review.
Fix findings and rerun affected slices. Document intentional differences from the reference framework.
Headless/conformance green alone is not completion.
```

## Step 3.5 — Make themes metric-aware, reusable, and richly skinnable

Done - July 26, 2026

Run this only after Step 3 passes. Step 2 already proved native paint and palette
swaps; do not redo it. This stage closes the gap between recoloring Studio Neutral
and installing a genuinely different visual language whose fonts, density, control
metrics, and bounded decorative chrome still agree with the solver.

### Fable-led goal prompt

```text
/goal Deliver Facet's public theme packages, metric-aware swapping, and rich
skinning as specified by the plan.

Lead with Claude Fable 5 at its highest practical effort after Step 3 is green; Step
2 is complete and must not be reopened. Fable decides source-of-truth, metric
authority, font measurement, and chrome slots. Dispatch unambiguous implementation
packages to Claude Opus 5 (`claude-opus-5`), thinking enabled, `xhigh`. Avoid
adjacent features.

Read:
- GameStudio/ENGINEERING.md
- GameStudio/MODELS.md
- GameStudio/ui/Facet/docs/plans/theme-packages-and-skinning.md
- GameStudio/ui/Facet/docs/plans/agent-execution-contract.md
- GameStudio/ui/Facet/docs/plans/studio-device-verification.md
- GameStudio/ui/Facet/docs/adr/ADR-0018-native-stylesheets.md
- GameStudio/ui/Facet/docs/guide/05-styling.md

Outcome: authors can create, validate, install, reuse, and swap versioned themes
changing paint, fonts, metrics, and bounded native/asset chrome while screens stay
mounted and the solver reflows.

Preserve Step 2's native authority, seed-once edits, tags/states, and fallback.

Build one thin ThemePackage contract around native StyleSheets—not a second styling
language—and a reactive controller. Controls use semantic typography, spacing,
control-size, asset, and surface roles; numeric overrides explicitly opt out. Reject
missing, inaccessible, conflicting, stale, or incompatible data with useful errors.

Resolve every measurement input to one frozen plain-Luau snapshot shared by solver,
renderer, tests, and adapter. Compose theme, environment, accessibility/hit floors,
and local overrides once. Atomically switch derive and metrics; re-solve without
remount or state/focus/selection/scroll/text/resource loss. Paint may transition;
geometry may not animate independently of the solver.

Measure the effective Font descriptor, size, and line height. Adapter-calibrate
declared fonts, reserve conservatively while pending, then relayout once. Apply
preferred text exactly once.

Replace reference-only metric mirrors with a proven Style Editor sync: supported
font/metric edits re-solve live; one export/sync action persists them; a freshness
gate prevents drift. Keep one metric authority and reject rules conflicting with
solver, binding, presentation, or game ownership.

Use native styling first. When real children are required, allow only bounded
declarative chrome recipes and semantic decoration slots: native fill/gradient/
stroke/shadow or nine-slice assets with solver-visible insets and failure fallback.
No callbacks or interactive theme trees; flat themes pay no ornate-layer cost.

Make an original Fantasy Parchment package the primary proof. Build it only through
public APIs; use nine-slice panels/control chrome with correct insets, states,
fallbacks, and preserved platform paradigms. Also ship the other reference families
in the plan without copying protected assets or trade dress.

Treat the execution/device contracts as binding. Register
`theme-packages-and-skinning` and its ledger first. Use all Step-3 controls and the
five-view Studio matrix. Prove palette, font/metric, and ornate swaps in the mounted
adapter; actual font/paint and solved bounds agree under localization, preferred
text, reduced motion, ten-foot, missing assets/fonts, and incompatible packages.
Pair captures with geometry, mount, focus, resource, authority, and cost traces.

Keep Opus packages few and disjoint; Fable integrates. Preserve compatibility,
determinism, accessibility, authority, and game/framework separation. Do not migrate
Sponsor Mode.

Complete only with gate exit zero, public package/controller and authoring sync,
Fantasy/reference packages and fixture, custom-theme guide and green
`check_docs_cli`, upgrade/freshness checks, prior gates, visible Studio proof,
resolved reviews, and honest pending hardware.
```

## Step 4 — Prove cross-platform quality and preserve the future platform seam

Done - July 27

Facet already has headless performance and preview infrastructure. Extend it so
performance claims can be tied to real Roblox devices, and make the environment,
event, and render-target contracts extensible to future spatial UI without claiming
VR support prematurely.

### Opus 5 goal prompt

```text
/goal Turn Facet's existing preview, conformance, and performance systems into an
honest cross-platform proof system while preserving a future spatial-UI seam.

Run with Claude Opus 5 (`claude-opus-5`), thinking enabled, `xhigh`. Treat the plans
as acceptance requirements; avoid adjacent features/refactors. Send materially
unresolved architecture/product choices to Fable 5 or the user as evidence-backed
decision packets.

Read:
- GameStudio/ui/Facet/docs/plans/agent-execution-contract.md
- GameStudio/ui/Facet/docs/plans/studio-device-verification.md
- GameStudio/ui/Facet/docs/plans/parity-next.md
- GameStudio/ui/Facet/docs/plans/theme-packages-and-skinning.md
- GameStudio/ui/Facet/the comparison document
- GameStudio/ui/Facet/bench/
- GameStudio/ui/Facet/tools/lune/perf.luau
- GameStudio/ui/Facet/src/preview/device_profiles.luau
- GameStudio/ui/Facet/docs/plans/roblox-native-audit-corrections.md
- GameStudio/ui/Facet/docs/extending/new-platform-mode.md
- GameStudio/ui/Facet/docs/extending/new-render-target.md

Outcome: fast deterministic headless regressions remain separate from Studio/device
evidence capable of supporting real platform/performance claims. Facet gains only
the contracts needed to add spatial input/world surfaces later; do not claim VR.

Extend the current perf runner, artifacts, and shared Studio surface—do not create
competing systems. Add console/ten-foot coverage and production-shaped virtual-list,
native scroll/drag, dense HUD, StyleSheet churn, async-image, and lifecycle scenes.
Capture real frame work, Facet update cost, Instances, connections, memory, and
input-to-visible latency where exposed. Establish budgets from measured baselines and
frame targets, never desktop Lune results presented as low-end-device proof.
Include flat, metric-changing, and asset-backed theme swaps as distinct invalidation
and cost scenes.

Define the future spatial seam only: flat/world presentation facts; optional
ray/3D-hit/pose/handedness/phase data on normalized events; a future SurfaceGui
target; and focus, hover, occlusion, comfort, cancellation, and performance gates.
Do not add headset branches to normal screens.

Treat agent-execution-contract.md as binding. Start with a metric/evidence ledger.
Store each visible production-shaped capture with preflight, fixture state,
profiler/telemetry, engine/game/source identity, and evidence level. Prove an
intentional regression fails before trusting the performance gate. Keep Lune,
Studio-emulated, desktop-retail, phone, and console results in separate rows; never
fill physical rows with emulator data.

Finish the reusable driver in studio-device-verification.md: enumerate live presets,
run its canonical five views, use VirtualInput only for supported paths, export
bounded geometry/state/input/capture evidence, and prove an intentional layout/input
failure. Use StudioTestService only where Play/Run or multiple clients are required;
do not overstate client control.

Verify full headless and existing regression gates, the Studio device matrix, weakest
supported physical touch device, and supported physical gamepad/ten-foot path. Record
which evidence is automated, emulated, or physical. Update the guide and run required
fresh-context reviews against methods and claims; fix and rerun findings. Do not alter
RascalRally Sponsor behavior. If hardware is unavailable, finish the instrumented
review build/procedure, leave physical rows pending, and report automation complete—
not cross-platform proof complete.
```

## Step 5 — Close the framework gaps Sponsor Mode actually needs

> **Status: Done — CLOSED BY THE DIRECTOR 2026-07-28** (gate `sponsor-framework-gaps`; suite 2075→2567 after six director review rounds; ADR-0022;
> evidence + review packet in `artifacts/sponsor-framework-gaps/`). Physical/human rows
> remain the stage's honest pendings. Note: this section's "required areas" list was
> written against the 2026-07-22 audit — aspect ratio and `Path2D` rings were already
> closed before this stage ran (the 2026-07-27 re-audit in `sponsor-view-parity.md`).

This is framework work, not the game port. Close the Sponsor ledger with native-first
substrates and reusable APIs. The acceptance fixture is Sponsor-shaped, but no race
rules, copy, sound assets, camera policy, or authored celebration content belongs in
Facet.

Required areas include native scrolling and virtualized reorder/select/drop lists;
native-backed drag sessions and edge autoscroll; interruptible choreography models;
rotation and `Path2D` rings; view transitions and toast/banner presentation; z-index,
adaptive layout, async images, image tint, aspect ratio, and preferred-text
correctness; the existing billboard target; marker overlay composition; and semantic
sound/haptic hooks.

### Fable-led goal prompt

```text
/goal Close every reusable Facet framework gap required by the RascalRally Sponsor
parity matrix, without porting the game UI or embedding game policy.

Lead with Claude Fable 5 at its highest practical effort. Fable owns architecture,
live diagnosis, integration, and iteration; dispatch only decided, sizeable packages
to Claude Opus 5 at `xhigh`. Use the named `ui-designer` before implementation and on
the integrated result; resolve its in-scope findings. Avoid adjacent work.

Read:
- GameStudio/specialists/UI_DESIGNER.md
- GameStudio/specialists/APPLE_UI_MOTION_SKILL.md
- GameStudio/ui/Facet/docs/plans/agent-execution-contract.md
- GameStudio/ui/Facet/docs/plans/studio-device-verification.md
- GameStudio/ui/Facet/docs/reference/sponsor-view-parity.md
- GameStudio/ui/Facet/docs/plans/theme-packages-and-skinning.md
- GameStudio/ui/Facet/docs/plans/roblox-native-audit-corrections.md
- games/RascalRally/docs/FACET_SPONSOR_PARALLEL.md

Outcome: Facet can express every Sponsor ledger row at production quality; each row
is closed or honestly reclassified. Sponsor fixtures prove the reusable mechanisms
can match the legacy quality baseline; Step 6 proves the complete game UI.

Boundaries:
- Start with ScrollingFrame, UIDragDetector, GuiObject touch events, Path2D, native
  StyleSheets, and the existing BillboardTarget.
- Facet owns reusable virtualization, payload/drop legality seams, normalized and
  composed gestures, interruptible/reduced-motion-aware choreography, lifecycle,
  toast presentation, marker composition, and semantic feedback events.
- RascalRally retains state, authority/fairness, copy/localization, camera/world and
  minimap policy, particles, sound assets, and haptic choices.
- Style transitions cover style changes only; value/structural choreography needs
  its own motion model.
- Do not port Sponsor Mode or change its default presenter.

Create a responsibility ledger before coding. Sponsor fixtures consume public Facet
only: no fixture-local input/focus/layout/control workaround may stand in for a
framework requirement. Fix reusable mechanisms and public-contract bugs in Facet
with tests/docs/real-adapter proof. Keep only game policy/content outside it and
escalate a material unresolved architecture choice rather than hiding the gap.

Apply relevant motion principles—immediate response, direct tracking, interruption,
velocity handoff/projection, spatial consistency, reduced-motion equivalents, and
cheap frame updates—as generalized Facet contracts, never fixture/game bypass code.

Treat agent-execution-contract.md as binding. Convert every framework-owned ledger
row into an acceptance row before coding. Extend the shared Studio surface with one
instrumented replayable Sponsor gallery using deterministic fixtures and no live game
commands. Each Studio-visible row must use the real adapter and pair captures with
geometry, focus, action/gesture, lifecycle, and resource traces as applicable. Prove
failure and interruption paths; pure tests or blueprint dumps cannot close visual or
interactive rows.

Run relevant five-view rows through StudioDeviceSimulatorService and honest
VirtualInput paths; never relabel pointer as physical touch or synthetic navigation
as physical gamepad.

Create failing tests and runnable fixtures covering live racer-list reorder;
legal/illegal card drop plus edge autoscroll; ring/path UI; interrupted celebration;
toast/banner priority; failed/stale async avatars; world billboard; preferred text;
reduced motion; teardown/churn. Verify relevant phone, desktop, gamepad/ten-foot, and
hybrid paths, weakest-device performance, full suites, and required fresh-context
reviews. Fix findings and rerun affected fixtures. Update APIs, parity ledgers, ADRs,
and examples with evidence. Leave hardware-only rows explicitly pending rather than
substituting headless or emulated results.
```

## Step 5.5 — Fresh-agent simplicity and maintainability gate

> **Status: Done — 2026-07-28.** Gate `code-simplicity-cleanup` is PASS; the
> recorded suite result is 2571 and the evidence is under
> `artifacts/code-simplicity-cleanup/`. Baseline entering the pass was v0.7.0 plus
> the Step 5 surface and gates through `sponsor-framework-gaps`.
> Step 5 handed this stage a concrete carried ledger (see the prompt's Read list):
> the round-2 verifier residuals in
> `artifacts/sponsor-framework-gaps/verifier-responses.md` (cleanup-shaped: RR-7-R1
> cross-core conformance extension, RR-5-R1 false-double-dispose nuance, RR-3-R1
> dispose-during-iteration read, RR-1-R2 stats-invariant doc drift) and the
> escalation register in
> `artifacts/sponsor-framework-gaps/responsibility-ledger.md` (design-shaped:
> ESC-1 interactive-state theme vocabulary, ESC-2 pointer-zone `screenRectOf`
> consumers, plus verifier RR-1-R1 clock-quarantine granularity). Cleanup-shaped
> items are candidates to fix or retire with evidence; design-shaped items produce
> decision packets, never implementations smuggled into this pass.

Run this in a new task after Step 5 and before Step 6. The lead must inspect the
finished framework without inheriting its implementers' assumptions. It may make
small, proved simplifications; larger redesigns become decision packets rather than
being smuggled into a cleanup pass.

### Opus 5 goal prompt

```text
/goal As a fresh-context lead, simplify Facet without changing public behavior,
supported paradigms, or completed roadmap outcomes.

Run in a new task with Claude Opus 5 (`claude-opus-5`), thinking enabled, `xhigh`;
the lead must not have implemented Steps 1–5. Treat referenced plans as binding. Do
not invent work. Send material redesigns to Fable 5 or the user as evidence-backed
decision packets.

Read `CLAUDE.md` and `GameStudio/ENGINEERING.md`. Under
`GameStudio/ui/Facet`, read:
- docs/guide/02-architecture.md
- docs/adr/ADR-0011-semver-and-deprecation.md
- docs/plans/code-simplicity-cleanup.md
- docs/plans/theme-packages-and-skinning.md
- docs/plans/agent-execution-contract.md
- docs/plans/studio-device-verification.md
- tools/lune/gate_manifest.luau
- artifacts/sponsor-framework-gaps/verifier-responses.md
- artifacts/sponsor-framework-gaps/responsibility-ledger.md

Outcome: less owned code, duplication, indirection, and ambiguity with unchanged API,
behavior, evidence, and ownership. Retaining simple code is valid when proved.

Disposition every Step 5 carry-over; do not rediscover it. Verify and fix or retire
with evidence RR-7-R1, RR-5-R1, RR-3-R1, RR-1-R2, and remaining scope-less
`adaptive.conditions` callers. Treat RR-1-R1, ESC-1, and ESC-2 as design decisions
only: produce evidence-backed recommendations, never implement them here. The two
Sponsor artifacts define the exact findings, consumers, and riders.

Follow `code-simplicity-cleanup.md`. Freeze tests, gates/registration, API and
deprecations, Studio behavior, lifecycle/resources, and headless performance. Before editing, register
`code-simplicity-cleanup` with honest pending checks and create its candidate ledger.
Trace authoring, mount, render/style, input/focus, resource, control, and teardown,
including callers and dynamic/public/generated/Studio consumption; searches and line
counts prove nothing. For each candidate record evidence, preserved behavior,
proposal, risk, check, benefit, and disposition.

Use the plan ladder after understanding each flow: delete proved waste; reuse its
owner/helper; prefer Luau or a verified Roblox feature; consolidate decisions at the
shared root; remove indirection; keep the minimum clear code. Establish a
characterization check before every non-trivial change; land and check one coherent
change at a time.

Do not edit vendor, generated output, or historical artifacts. Make only the
execution contract's required RascalRally consumer/test updates; do not change game
behavior. Preserve exports/deprecation timing, authority, scopes, error
containment, headless/adapter seams, accessibility/input, completed theme and Sponsor
mechanisms, and intentional differences from the reference framework. Add no dependency, flag,
compatibility layer, speculative abstraction, broad rename/reformat, or feature.
Never weaken tests, gates, workloads, or physical requirements. Do not target line
counts. Update touched docs, comments, and registrations.

Treat the execution contract as binding. Run focused checks, then the full suite,
registration/API drift, affected prior gates, and performance regression checks. Use
real-adapter Studio scenarios only when visible/input/layout/adapter/lifecycle
behavior can change, and the five-view matrix when layout can change. Store
before/after behavior, geometry/traces, resources, and relevant performance.

Give fresh phase-gate and architecture reviewers the raw baseline, ledger, changes,
and evidence without your conclusions; add runtime/platform review only if triggered.
Fix requirement-affecting findings and rerun.

Complete only when the gate exits zero and writes
`artifacts/code-simplicity-cleanup/gate.json`; each change has a check and proof; full
suite/affected gates are green; API, ownership, and docs remain correct; triggered
Studio proof exists; and every candidate is dispositioned. Report
deletions/consolidations, retentions, evidence, pending hardware, and decision packets.
```

## Step 6 — Build and prove a parallel Facet Sponsor Mode

Done August 2, 2026

This step is the end-to-end proof. It is intentionally not called “migration.” Follow
the game plan exactly: legacy remains the default, one development-only selector
chooses one presenter, and no old-code removal occurs.

This is the historical pre-cutover prompt. The director separately authorized the
Facet default on 2026-08-03; current work preserves that default and the untouched
legacy rollback.

### Fable-led goal prompt

```text
/goal Build and verify the parallel Facet Sponsor Mode while preserving the working
legacy implementation as the shipped default.

Fable owns live diagnosis, integration, feel iteration, and ownership decisions; dispatch only decided,
disjoint implementation packages to Claude Opus 5 (`claude-opus-5`) at `xhigh`.
Avoid adjacent work.

Read:
- GameStudio/specialists/UI_DESIGNER.md
- GameStudio/specialists/APPLE_UI_MOTION_SKILL.md
- GameStudio/ui/Facet/docs/plans/agent-execution-contract.md
- GameStudio/ui/Facet/docs/plans/studio-device-verification.md
- games/RascalRally/docs/FACET_SPONSOR_PARALLEL.md
- GameStudio/ui/Facet/docs/reference/sponsor-view-parity.md
- GameStudio/ui/Facet/docs/plans/theme-packages-and-skinning.md
- GameStudio/ui/Facet/docs/plans/roblox-native-audit-corrections.md

Outcome: a developer can select and test a complete Facet Sponsor presenter with
behavioral, visual, and feel-parity evidence; legacy remains intact and default.

Safety boundary:
- Use one development-only selector, default legacy, and one mounted presenter.
- Prove no duplicate commands, bindings, effects, analytics, or resources.
- Share authoritative state/commands; never fork authority, fairness, or progression
  logic or infer legality from visuals.
- Never alter/delete/default-flip legacy; compare recorded fixtures, not two live
  presenters.
- Cutover/removal requires separate later user approval.

Dispatch `ui-designer` before coding to refresh a build-ready Facet spec from the
working baseline and ratified docs, then after integrated layers to review paired
device evidence. Sponsor view user experience must be as good or better than status quo on all platforms. Apply the motion skill where relevant. Fable fixes and repeats until
every automatable or specialist-identifiable gap is closed. The new UI must meet or
exceed named legacy criteria for clarity, response, directness, interruption,
readability, platform idioms, reduced motion, and cost. Material redesign needs the
human UI-SPEC gate; final physical/FEEL approval remains separate.

Apply the plan's declarative-responsibility test. RascalRally owns semantic game
state/commands, content, style/control choices, intended layout, and authored Sponsor
beats. Facet owns reusable mechanisms and environment-driven layout, paradigm,
input, focus, hit, scroll, lifecycle, accessibility, and motion adaptation. Ledger
custom helpers/direct engine access. Fix framework needs in Facet with public API,
tests, docs, and live proof before consuming them. Finish with no temporary UI
workaround, platform-name branch, or parallel input/focus/layout/control system.

Treat agent-execution-contract.md as binding. Freeze the baseline in the real place,
then check in the full parity ledger and deterministic replay fixtures. Use one shared
scenario protocol for both presenters, with only one mounted. Pair captures with
fixture/presenter identity, geometry/focus, input/action trace, and command/side-effect
counts. Automatically prove selector teardown-before-remount and one authoritative
command per intent. Neither screenshots alone nor traces alone prove parity.

Build in the plan's layers and verify every row: entry/lifecycle; table/list; cards
and input paradigms; HUD/story/feedback; world omens; both roles' results in both
orientations; localization/inclusion; failures, reconnect, teardown, and performance.
Use automated traces, screenshots/video, Studio, physical touch and gamepad,
weakest-device runs, required fresh-context reviews, and the human FEEL gate. Record
approved intentional differences.

Before user review, finish automation and produce one deterministic build with reset,
labels, trace export, expected outcomes, and a short physical/feel checklist. Leave
review/hardware pending honestly; do not switch defaults or remove old code.
```

## Step 7 — Establish one predictable API and architecture language

Done August 2, 2026

This stage runs after the parallel Sponsor implementation. It writes the rules every
later public feature must follow, audits the existing API against them, fixes small
compatible defects, and records larger migrations without smuggling in a redesign.

### Fable-led goal prompt

```text
/goal Establish and enforce a coherent Facet API and architecture constitution so
learning one part makes the rest predictable, without breaking working consumers.

Lead with Claude Fable 5 at its highest practical effort. Fable owns architecture,
exceptions, migration judgment, and integration. After decisions are explicit,
dispatch only sizeable disjoint implementation packages to Claude Opus 5
(`claude-opus-5`) at `xhigh`. Do not invent inconsistencies to justify churn.

Read:
- GameStudio/MODELS.md
- GameStudio/ENGINEERING.md
- GameStudio/ui/Facet/docs/guide/02-architecture.md
- GameStudio/ui/Facet/docs/reference/api.md
- GameStudio/ui/Facet/docs/adr/ADR-0011-semver-and-deprecation.md
- GameStudio/ui/Facet/docs/plans/api-architecture-consistency.md
- GameStudio/ui/Facet/docs/plans/agent-execution-contract.md
- GameStudio/ui/Facet/docs/extending/
- GameStudio/ui/Facet/src/init.luau
- GameStudio/ui/Facet/tools/lune/gate_manifest.luau

Outcome: one concise, example-backed constitution governs constructors, specs,
reactive values, results, callbacks, ownership/lifecycle, errors, input/focus,
adaptation, styling/property authority, engine adapters, extensions, versioning,
documentation, and evidence. Every current public item follows a named pattern or a
justified exception.

Audit the actual shipped surface first. Build a complete ledger of exports,
blueprints, composites, services, modifiers, callbacks, result objects, and extension
seams. Trace callers and lifecycle; current code and tests outrank historical prose.
For each inconsistency record user cost and one disposition: intentional exception,
compatible repair, deprecation, or future breaking-change proposal.

Fix only small compatible defects and public-contract lies in this stage. Preserve
behavior and use ADR-0011 for every migration. No broad rename, signature unification,
new feature family, speculative abstraction, or source-format pass. A consistent
exception is better than a harmful uniform rule.

Turn stable rules into helpful enforcement: public-surface/docs drift, schemas and
types, scaffold/extension templates, diagnostics, and focused checks. Do not encode
subjective design judgment as brittle lint. Run a fresh-author exercise: an agent
with only public docs adds one small composite through the canonical extension path,
without internal imports, and receives actionable failures for omitted obligations.

Register `api-architecture-consistency` with honest pending checks before edits.
Treat the execution contract as binding. Freeze API, tests/gates, lifecycle, docs,
performance, and representative Studio behavior. Use Studio only for changes that
can affect visible/input/layout/adapter/lifecycle behavior. Update the guide, API,
architecture map, extension docs, ADRs, and inventory without redundant prose.

Give fresh architecture and phase-gate reviewers the raw surface ledger, baseline,
diff, decisions, exercise, and evidence; add runtime/platform review only when
triggered. Resolve requirement findings and rerun.

Complete only when the gate exits zero and writes its artifact; every public item is
classified; compatible fixes and deprecations are proven; decision packets preserve
larger choices; checks and the fresh-author exercise pass; full/affected gates are
green; and docs identify one authoritative rule set. Report outcome and artifacts.
```

## Step 8 — Add desktop keyboard focus-chain behavior

Done August 3, 2026. 

Two platform limits are recorded rather than papered over:
Tab is the CoreGui players-list shortcut (the binding ships and works wherever the
list is disabled; `gamepad_contention.traversalKeyContended()` detects the
contended case), and keyboard Input Action bindings do not fire while a `TextBox`
holds focus, so `handleTraverse` is unreachable on today's engine. Evidence and
decisions in `artifacts/desktop-keyboard-navigation/`.

Facet's directional focus remains the base. This stage adds the desktop conventions
authors should get automatically when a keyboard is available, while engaged UI owns
input and passive gameplay remains untouched.

### Opus 5 goal prompt

```text
/goal Add automatic desktop keyboard traversal, activation, and value adjustment to
Facet through its existing focus, responder, and Input Action System architecture.

Run with Claude Opus 5 (`claude-opus-5`), thinking enabled, `xhigh`. Treat the plans
as the complete brief; make routine implementation decisions and avoid adjacent UI,
shortcut, or focus features. Send material unresolved choices to Fable 5/user with
evidence.

Read:
- GameStudio/ui/Facet/docs/plans/api-architecture-consistency.md
- GameStudio/ui/Facet/docs/plans/desktop-keyboard-navigation.md
- GameStudio/ui/Facet/docs/plans/agent-execution-contract.md
- GameStudio/ui/Facet/docs/plans/studio-device-verification.md
- GameStudio/ui/Facet/docs/reference/api.md
- GameStudio/ui/Facet/the comparison document
- GameStudio/ui/Facet/src/focus/
- GameStudio/ui/Facet/src/input/
- GameStudio/ui/Facet/src/present/presenter.luau
- GameStudio/ui/Facet/src/client/roblox_input.luau

Outcome: when keyboard capability is live and an interactive Facet responder owns
input, Tab/Shift+Tab traverse the active focus chain, Return and Space activate once,
and a focused value control consumes its declared arrows as Adjust. Screens add no
key listeners. Passive HUD/gameplay input remains untouched.

Extend the existing graph and semantic actions, never create a parallel focus chain.
Traversal follows mounted/group order, skips hidden/disabled/nonfocusable/losing
adaptive nodes, honors scope wrap policy, traps/restores modals, survives structural
churn, and calls the shared keep-visible service. Add public options only for author
intent the current graph cannot express, following the API constitution.

Bind through IAS at the adapter edge and only while the responder is engaged. Prove
hot-plug and teardown have no leaked sink. Exactly one Activate may result when IAS
and GuiButton.Activated observe the same press. While TextInput edits, Space and
arrows stay native; Tab uses its commit/validation path and advances only after edit
ends. A value control consumes only its axis; declined arrows still Navigate.

Register `desktop-keyboard-navigation` first. Write failing pure/action tests for
forward/reverse traversal, wrap/group crossing, disabled/hidden/churn, modal restore,
keep-visible, adjustment routing, editing, responder ownership, hot switching,
teardown, and duplicate activation. Update conformance, hints where useful, API/input
guides, examples, parity audit, and registrations.

Treat the execution/device contracts as binding. In visible Studio, drive raw Tab,
Shift+Tab, Space, Return, and arrows with VirtualInput through a form, scrollable
list, modal, TextInput, Slider, and Stepper. Include desktop and keyboard-capable
phone/tablet profiles. Pair captures with raw input, semantic action, focus, scroll,
state, responder, and lifecycle traces; label physical-only rows honestly.

Run focused/full suites and affected gates. Give fresh phase-gate and platform
reviewers raw artifacts; add architecture review if public contracts change. Resolve
findings and rerun. Complete only with gate exit zero/artifact, automatic public
control behavior, no game-input theft or duplicate activation, green docs/gates, and
required Studio proof and synchronized RascalRally consumer evidence. Do not change
RascalRally gameplay or publish/deploy.
```

## Step 8.5 — Make large text a first-class layout input

> **Status: Done — GATE PASS exit 0, 2026-08-03.** Suite 3133→3291 (+ game
> 3029→3067); measured offsets {0,4,10,14} replace the guessed table, applied
> exactly once with a live change subscription (epoch-guarded confirm);
> `disclose` full-value plates on Text/Toggle/Table columns; six-check
> `text_audit`; the live "Sponsor a…" Largest regression measured dead in the
> production place at the real setting; three fresh-context reviews' every
> BLOCKER/MAJOR fixed and pinned (LTN-7). LT-P1 physical phone + LT-P2 human
> readability stay honestly pending with the prepared review packet.

This stage closes the exact Roblox preferred-text seam, establishes one framework
overflow policy, and proves the result on the production Facet Sponsor presenter.
It is Fable-led because engine measurement, public API, accessibility judgment,
responsive composition, and game integration must be decided together.

### Fable-led goal prompt

```text
/goal Make Facet and the production Rascal Rally Sponsor View resilient at Roblox
PreferredTextSize Medium, Large, Larger, and Largest, especially compact mobile
portrait and landscape.

Lead with Claude Fable 5 at highest practical effort. Fable owns engine diagnosis,
accessibility/layout policy, framework/game boundaries, live integration, and product
iteration. Dispatch at most three decided, disjoint packages to Claude Opus 5
(`claude-opus-5`) at `xhigh`.

Read:
- GameStudio/ui/Facet/docs/plans/large-text-accessibility.md
- GameStudio/ui/Facet/docs/plans/agent-execution-contract.md
- GameStudio/ui/Facet/docs/plans/studio-device-verification.md
- GameStudio/ui/Facet/docs/reference/api.md and the current environment, text,
  layout, focus, scroll, and motion implementations
- games/RascalRally/docs/FACET_SPONSOR_PARALLEL.md
- games/RascalRally/docs/ui/UI_SPEC_sponsor_facet.md
- GameStudio/specialists/{UI_DESIGNER,APPLE_UI_MOTION_SKILL,ROBLOX}.md

Treat `large-text-accessibility.md` as the full specification. Outcome: preference is
applied exactly once, changes live without remount/state loss, and reliably drives
measurement/reflow. Public UI and Sponsor View stay readable, nonoverlapping,
reachable, and usable; essential content never becomes an inaccessible ellipsis.

Live-probe all four values before API/code; compare engine paint/bounds, TextService,
solver reservation, theme metrics, and ten-foot scale. Replace guessed offsets with
the smallest exact cached/failure-safe seam and subscribe to PreferredTextSize.
Never block first mount, double-apply, under-reserve, or loop reflow.

Apply the plan's order: reflow, then container scroll/keep-visible, then truncation
only for bounded secondary/identity text with cross-input full-value access. Never
hide an action, instruction, status, error, result, or required fact. Audit current
text, adaptive, scroll, compact-label, focus, and motion mechanisms before adding API.

If engaged reveal is necessary, keep it reusable, delayed, direction/grapheme-correct,
pausable, statically discoverable, reduced-motion-safe, one-per-active-presentation,
and free of per-label frame loops. Character/word replacement remains separate
opt-in research.

Diagnose bounds/lines, policy/full-value access, overlap/clipping, hit floors, hidden
focus, repeated reflow, and moving-label count; declare intentional overlays.

Keep responsibility declarative: Facet owns measurement, overflow, adaptation,
input/focus/scroll, diagnostics, and motion policy. RascalRally owns localized
content, importance, style/control choices, relationships, and layout candidates.
No game-local marquee, measurement, geometry, input, focus, scroll, or device branch.
Synchronize every affected RascalRally caller/test and Studio canary.

Exercise production Sponsor fixtures across every major surface/state. Include long
names/locales, large rosters, both themes, reduced motion, all four values, hot
Medium↔Largest, compact portrait/landscape, and 667x375 landscape. Correct truncation
rules that hide essentials; iterate on UI Designer evidence until no automatable or
specialist usability gap remains.

Register `large-text-accessibility` first; the execution/device contracts bind. Pair
Studio captures with text/geometry, composition, focus/scroll, preference source,
style, motion, and lifecycle traces. Add the plan's workloads/counters to Step 9.
Injected coverage is not the real read-only setting; physical Largest phone portrait/
landscape and subjective readability remain honest external gates.

Complete only with gate exit 0/artifact; exact live behavior; green public/Sponsor
matrices, Facet/RascalRally suites and prior gates; no inaccessible essential text,
overlap, state loss, unbounded motion, or game workaround; reviews resolved; and
API/guide/parity/Sponsor docs updated. Do not publish/deploy/push, remove legacy
Sponsor, or claim assistive-technology parity Roblox cannot expose.
```

## Step 9 — Ship a publish-ready Facet performance lab

**DONE**

This step turns Step 4's measurement infrastructure into a reproducible Roblox place
that can be opened, manually published as a private test place, and profiled on the
supported low-end Android floor. It starts with one scenario-driven place and adds a
second only when measured isolation requires it.

### Opus 5 goal prompt

```text
/goal Build the publish-ready Facet performance stress place and repeatable
Studio/low-end-Android profiling loop defined by the plan.

Run with Claude Opus 5 (`claude-opus-5`), thinking enabled, `xhigh`. Treat the plans
as acceptance requirements; avoid adjacent work. Escalate materially unresolved
architecture/product choices with evidence for Fable 5 or the user.

Read:
- GameStudio/ui/Facet/docs/plans/agent-execution-contract.md
- GameStudio/ui/Facet/docs/plans/studio-device-verification.md
- GameStudio/ui/Facet/docs/plans/performance-stress-places.md
- GameStudio/ui/Facet/docs/plans/large-text-accessibility.md
- GameStudio/ui/Facet/docs/plans/desktop-keyboard-navigation.md
- GameStudio/ui/Facet/docs/plans/theme-packages-and-skinning.md
- GameStudio/ui/Facet/bench/
- GameStudio/ui/Facet/tools/lune/perf.luau
- GameStudio/ui/Facet/tools/build_places.sh
- GameStudio/specialists/ROBLOX.md

Outcome: emit a self-contained examples/places/Facet-PerformanceLab.rbxl that opens
without Rojo and is ready for manual publishing and repeatable Studio/Android
profiling.

Verify current first-party MicroProfiler, profiling-skill, and LibMP guidance; use the
Roblox profiling skill when callable. Add balanced low-cardinality phase scopes, not
per-node labels or huge raw-frame JSON.

Boundaries:
- Extend existing perf scenes/runner, Studio surface, artifact/gate systems, and place
  conventions. Start with one scenario-driven place; add another only for a measured
  isolation/publishing constraint and record why.
- Check in source/project and built .rbxl files, but never publish, upload, deploy,
  attach a universe ID, push, or initialize Git.
- Mount one stress implementation per capture. Never weaken a workload, behavior,
  capture, or versioned budget to pass; version changed workloads.
- Label Lune, Studio, emulator, desktop-retail, and physical Android separately.
  Device emulation proves usability/layout only, never low-end performance.

Register `performance-stress-places` in the existing manifest with honest pending
checks first. Build the plan's deterministic scenarios, centered on a large
virtualized vertical list whose rows combine HStack, image, VStack text, and controls.
Exercise scrolling, Tab/arrow focus, selection/value changes, insert/remove/reorder,
cold/warm images, and bounded mounts. Include a matched raw-Roblox baseline
with only one path mounted, plus safe ramp/emergency stop, reset, clean-capture mode,
version labels, telemetry, and teardown.
Profile the same workload with the flat and most expensive reference themes,
including swap/reflow cost; do not compare changed content or behavior.

Treat agent-execution-contract.md as binding. Drive real adapter scenarios in visible
Studio and pair captures with scenario/workload version, counters, MicroProfiler
metadata, and source/build identity. Prove an intentional regression fails the gate.
From a clean source state, rebuild and open the emitted place; verify registry,
selector, reset, native reference, labels, export, and idle teardown.

Use the canonical device API matrix to prove the lab remains operable. Then run the
profiling loop: repeated baselines; falsifiable Facet cause; smallest fix; focused,
full, and perf gates; rebuild; identical repeated after-captures; cross-scenario
regression check. Record negative/inconclusive attempts.

Produce exact manual publish, mobile-MicroProfiler, capture/export, and comparison
instructions. If low-end Android is available, repeat under recorded device, thermal,
and graphics conditions; apply/establish the versioned floor budget and fix
framework-caused bottlenecks. Otherwise leave `PENDING_PHYSICAL` and say automation
complete, not low-end performance proven.

Complete only with the canonical gate artifact, source/.rbxl, deterministic/native
baseline evidence, Studio profiles, green perf/library gates, resolved required
reviews, and updated guide. Report results, artifact paths, and pending physical rows.
```

## Step 10 — Make every tutorial example teach and play correctly

**DONE**

This final pass treats the gallery as a product and a learning surface. It audits all
seven examples in play, makes styling consistent with the native StyleSheet
architecture, repairs the unclear settings-sync lesson, turns the word example into a
complete Wordle-like game, and actually validates the tile and match-3 loops.

### Opus 5 goal prompt

```text
/goal Run the Facet tutorial-gallery quality pass so every example teaches, plays,
styles, adapts, rebuilds, and verifies as specified by the plan.

Run with Claude Opus 5 (`claude-opus-5`), thinking enabled, `xhigh`. Treat the plans
as binding; avoid unrelated work. Escalate material unresolved choices with evidence.

Read:
- GameStudio/ui/Facet/docs/plans/agent-execution-contract.md
- GameStudio/ui/Facet/docs/plans/studio-device-verification.md
- GameStudio/ui/Facet/docs/plans/example-quality-pass.md
- GameStudio/ui/Facet/docs/plans/theme-packages-and-skinning.md
- GameStudio/ui/Facet/docs/plans/large-text-accessibility.md
- GameStudio/ui/Facet/ui_todo.md (§0, §2)
- GameStudio/ui/Facet/docs/plans/roblox-native-stylesheets.md
- GameStudio/ui/Facet/examples/gallery/
- GameStudio/ui/Facet/tools/lune/gate_manifest.luau

Outcome: all seven examples are understandable/playable without source, share one
native-StyleSheet product design, adapt across supported layouts/inputs, build as
standalone places, and pass the canonical `example-quality-pass` gate.

Examples own domain rules/content/state and declare style/control/layout intent.
Facet owns reusable behavior and environment-driven adaptation. Ledger helpers; fix
framework needs there with public API/tests/docs/live proof. Finish with no workaround,
platform branch, raw GUI/input bypass, or parallel control machinery; do not
generalize game rules.

Verify existing phases 0–4; do not repeat stale PASS claims. Extend current tooling
and register honest pending gate checks first. PLAY all seven in visible Studio and
fill the plan's matrix. Fix all blocking defects, including real play-throughs of
examples 06/07 and tests for observed failure, reset, rapid-input, and lifecycle bugs.

Automate all seven across the canonical five-view API matrix. Resolve presets at
runtime and use VirtualInput for supported Tab/Shift+Tab, Space/Return, arrows, text,
mouse, and pointer paths with live geometry. Never relabel pointer as physical touch
or synthetic navigation as physical gamepad.

Native StyleSheets/property authority must govern every example; do not revive custom
paint. Add the plan's authority-aware drift check and prove a contrasting runtime
theme-package swap—palette, metrics, and bounded chrome—restyles and reflows all
examples without edits/remount. Capture both across the matrix with
geometry/style/focus/mount evidence; include `Medium`/`Largest` under the Step 8.5
overflow policy.

Example 03 must visibly teach deterministic optimistic apply, pending, accept/
reconcile, deliberate reject with reason/rollback, and reset—without test-only calls.
Update its header and guide.

Example 05 must implement every Wordle-like mechanic in example-quality-pass.md,
including correct duplicate-letter budgeting, validation, keyboard-state accumulation,
end states, restart, and non-color semantics. Write failing pure tests first. PLAY the
mounted adapter through every input/hybrid row in the plan; direct model/callback
calls cannot prove native input.

Treat agent-execution-contract.md as binding. Verify each vertical fix live and pair
captures with native events, semantic actions, geometry, focus, state, style
authority, and lifecycle evidence. Source review or screenshots alone cannot pass a
gameplay row.

Do not pre-spawn a team. If useful, delegate at most two disjoint Opus 5 `xhigh`
packages (examples 03/05). The lead owns the full audit/play, shared work, integration,
and evidence. Run the required fresh-context phase gate once; add architecture or
platform review only when triggered. Resolve findings and rerun.

Do not publish, deploy, push, or initialize Git. Physical-only rows may remain
explicitly pending. Complete only with the gate exit 0/artifact, passing matrix/drift
check, correct 03/05, played/fixed 06/07, standalone rebuilds, green existing gates,
resolved reviews, and accurate docs. Report results, artifacts, and pending rows.
```

## Step 11 — Validate three production-scale apps with clean-room Roblox proofs

**DONE**

This stage answers a narrower, more useful question than “does Facet have every
declarative type?” It builds representative in-experience loops and distinguishes real
framework gaps from Roblox service work and host-only operating-system surfaces.

### Fable-led goal prompt

```text
/goal Determine and prove how well Facet can build the in-experience behavior of
three published sample applications as adaptive Roblox experiences.

Lead with Claude Fable 5 at its highest practical effort. Fable owns sample
interpretation, product/UI architecture, framework-versus-platform classification,
live integration, and diagnosis. Use the `ui-designer` for three clean-room,
build-ready proof specs. After shared decisions are fixed, dispatch at most three
disjoint sample packages to Claude Opus 5 (`claude-opus-5`) at `xhigh`.

Read:
- GameStudio/ui/Facet/docs/plans/reference-app-validation.md
- GameStudio/ui/Facet/docs/plans/api-architecture-consistency.md
- GameStudio/ui/Facet/docs/plans/agent-execution-contract.md
- GameStudio/ui/Facet/docs/plans/studio-device-verification.md
- GameStudio/ui/Facet/docs/plans/large-text-accessibility.md
- GameStudio/ui/Facet/the comparison document
- GameStudio/ui/Facet/docs/reference/api.md
- GameStudio/specialists/UI_DESIGNER.md
- GameStudio/specialists/ROBLOX.md

Outcome: three self-contained clean-room Roblox proofs run complete representative
loops across supported layouts/inputs, and a complete feature ledger says what is
available, composable, a Facet gap, a Roblox-service adaptation, or unavailable as a
Roblox host surface.

At stage start, inspect the current official vendor pages and downloadable source;
record source dates and actual behavior. Use them only as references. Create original
names, copy, data, and visual assets; copy no third-party code, art, trade dress, or product
identity.

Build the three plan-defined loops: garden resources/detail/purchase-shaped flow;
operations dashboard with adaptive split navigation, orders, timer, custom thumbnail
layout and charts; catalog/search/favorites/rewards/recipes/order/localization plus a
compact entry flow sharing the full components. Use deterministic fake services—no
real purchase, player-data write, private service, or required network. Map the real
Roblox service a production game would own.

Separate Facet UI behavior, game/service behavior, and host-operating-system behavior.
Widgets, App Clips, Live Activities, Dynamic Island, WeatherKit, and similar surfaces
with no experience API are platform differences, not framework failures. Do not fake
them and claim parity.

Create capability and responsibility ledgers first. Proofs use public Facet only
and own domain state/content/commands. Facet owns reusable layout, focus, input,
accessibility, presentation, motion, and adaptation. Fix bounded compatible framework
defects in Facet with API/tests/docs/live proof; never use raw GuiObjects, local key
listeners, parallel focus/layout, or device-name branches. Turn a large missing
subsystem into an evidence-backed follow-on proposal rather than hiding it locally.

Register `reference-app-validation`. Treat execution/device contracts as
binding. Build self-contained places/scenarios and play each loop across the five
views, public theme swaps, preferred text, reduced motion, localization, and relevant
keyboard/pointer/touch-shaped/gamepad-shaped rows. Pair captures with geometry,
input/action, focus, state, lifecycle, and performance evidence.

Run full/affected gates and fresh phase-gate, architecture, and platform reviews;
fix requirement findings and rerun. Complete only with gate exit zero/artifact,
working clean-room builds, complete honest ledgers, no consumer workaround, updated
parity/authoring docs, and explicit physical/human pendings. Do not publish/deploy.
```

## Step 12 — Decide the architecture for declarative 3D

**DONE**

The likely answer is a sibling declarative scene system that may share Facet's
reactive/lifecycle foundation, not world nodes added to the 2D solver. This stage
tests that answer with an isolated spike; it does not create a production feature.

### Fable-led goal prompt

```text
/goal Decide, with a runnable spike, whether and how this studio should build a
declarative fine-grained-reactive system for Roblox Parts and Models.

Lead with Claude Fable 5 at its highest practical effort. This is an architecture
decision whose server/client, replication, physics, streaming, identity, and package
tradeoffs cannot be delegated before they are understood. Dispatch only bounded
research or an explicitly designed spike to Claude Opus 5 at `xhigh`.

Read:
- GameStudio/ENGINEERING.md
- GameStudio/specialists/ROBLOX.md
- GameStudio/ui/Facet/docs/guide/02-architecture.md
- GameStudio/ui/Facet/docs/plans/api-architecture-consistency.md
- GameStudio/ui/Facet/docs/plans/declarative-3d-architecture.md
- GameStudio/ui/Facet/src/core/contract.luau
- GameStudio/ui/Facet/src/render/target_contract.luau
- GameStudio/ui/Facet/src/input/spatial.luau

Outcome: a plain-language reviewed ADR recommends Facet extension, sibling package,
separate system, or no build; an isolated spike supplies topology/lifecycle/cost
evidence. PASS means the decision is proved, not that Facet supports 3D.

Start from current official Roblox guidance and live probes. Inventory concrete
static layout, keyed collection, reactive visual property, attachment/assembly,
server-owned shared object, client-local decoration, streaming, and teardown use
cases. Keep physics controllers, terrain generation, networking replacement, and a
general game engine out of scope.

Compare adding world nodes to Facet, a sibling using a shared core, and an independent
system with compatible conventions. Test the plan's initial recommendation: share
fine-grained reactivity, identity, scopes, transactions, errors, and API principles,
but keep pixel/text/focus layout separate from CFrame/pivot/constraint/physics/
streaming/authority rules. Do not assume presentation is always server-side or equal
on clients; define explicit server-owned and client-local roots. Never replicate a
reactive graph or closure.

Register `declarative-3d-architecture` first. Build only the isolated disproof spike:
Part/Model hierarchy and local transforms; keyed add/remove/reorder preserving
survivors; bounded reactive property writes; nonduplicated server and client roots;
cleanup/reparent/destroy and streaming-like loss/reentry; invalid authoring and
callback failure; instance/connection/update cost. Use native mechanisms instead of
per-frame writes where Roblox owns the work.

Do not modify Facet public exports, extract its core, edit game code, or create a
production package. Because the spike changes no Facet contract, consumer lockstep
does not require a RascalRally edit. The ADR must decide whether extraction is worth migration risk,
name the boundary and first bounded milestone if recommended, and state non-goals,
authority, compatibility, risks, and required future device/performance proof.

Give fresh architecture, reactive-runtime, Roblox-platform, and phase-gate reviewers
the alternatives, raw spike, topology traces, and costs. Resolve factual findings.
Complete only with gate exit zero/artifact and a decisive recommendation; do not
publish/deploy or silently begin the follow-on build.
```

## Step 13 — Rename the framework to Facet and run a fresh release-candidate review

**DONE**

This stage first renames the framework and all current consumers from the pre-rename
name to Facet, then runs the whole-framework adversarial pass requested before
distribution. It reviews from a frozen baseline, remediates confirmed defects, makes
every human document clear, and describes Facet in Roblox terms. It gives humans and agents one
obvious control-extension path, resolves the public call vocabulary, consolidates
repeated implementation, makes Input Action System authoritative, and refreshes and
profiles the performance lab. It also gives enabled controls distinct, configurable
press, release, and selection haptics with a restrained default feel. Missing wishlist
features do not become bugs.

### Fable-led goal prompt

```text
/goal Rename the framework to Facet and run its release review. Fix defects, make IAS
authoritative, improve maintenance/API/performance, and ship polished sensory haptics.

Use fresh Fable 5 at highest effort for decisions/integration; delegate decided fixes
to Opus 5 `xhigh`. Read repo instructions and the binding release-review, API,
performance, and execution plans.

Freeze source/API, gate, lifecycle/performance, and Studio baselines; register the
ledger. Record proof. Missing is a defect only if promised.

Rename first with the plan's inventory and history-preserving moves. Source, paths,
outputs, tools, Studio/profile labels, docs, agents, and both RascalRally projects
become Facet. Preserve Sponsor default/legacy rollback.
Isolate persistent-name migration; otherwise permit the old name only in the rename
ADR/immutable evidence. Prove negative controls and a clean `GameStudio/ui/Facet` run.
Prepare Step 14's remote packet; do not mutate the remote.

Review architecture, ownership, errors, teardown, dead code, tests, comments, and hot
paths. Reproduce defects. Consolidate repeated code under one narrow owner; separation
needs a concrete reason. Give changes one owner/extension/proof path. Fix proved mixed
responsibilities, parallel registries, implicit lifecycle, incomplete seams, brittle
fixtures, and stale scaffolds. Keep RascalRally synchronized.

Inventory legacy/raw/parallel input paths. `InputContext`/`InputAction`/`InputBinding`
own routing/lifetime. Legacy calls need current impossibility proof, one allowlisted
adapter, tests/teardown, and removal trigger. Ban consumer use and double firing.

Audit sensory semantics against the reference framework's and Roblox's current docs. With Facet's
game-opt-in adapter enabled, ship original configurable `Custom` defaults for press,
release, and select with comparable subtle, distinct character—never copied or called
identical. Define cross-input timing once; cancellation cannot resemble success.
Prevent native/bus double pulses; prove override/silence, rate limit, preset fallback,
pooling, zero per-pulse allocation, and teardown. Update controls, demo, docs, lab, and
RascalRally. Add automated/Studio proof and paired phone plus Android/gamepad review;
mark perceived similarity `PENDING_DEVICE` until same-device human comparison.

Rebuild/drift-check guide/API catalogs and run the product-language negative control.
Use ELI5 concepts with exact API terms. Comments explain responsibility, invariants,
lifecycle, limits, or reasons—not agent shorthand/history.

Make the control guide an ELI5 path and one-record scaffold. A fresh agent and human
verifier build disposable `ColorWell` through public seams with full proof.
Audit call shapes; trial `Facet.Controls.Table` against one flat option without
repeating `Facet`. Record the ADR and migrate compatibly. Another fresh agent repairs a
seeded defect. Keep real improvements; rerun without private hints.

Refresh the performance place. Use Studio MCP and MicroProfiler/LibMP for
solve/layout, fine/bulk update, adapter/render, scroll, idle, and teardown baselines.
Optimize measured Facet hot spots with falsifiable causes and identical comparisons;
rerun tests/scenarios/RascalRally. Leave builds, captures, summaries, settings, and
Android instructions current.

Fix every blocker/high and safe maintenance issue; disposition the rest with owner,
risk, reason, and trigger. Run the test/gate/Studio/RascalRally matrix and fresh
reviews. Complete only with gate exit 0/artifact, rename/drift proof, findings disposed,
reuse/IAS/haptics met, current control/naming/maintainer paths, passing exercises, and
green docs/behavior/profiles. Report evidence and physical pendings. No unrelated
feature/package; do not publish/package or rename the remote.
```

## Step 13.5 — Polish Facet game tutorials and curated standalone examples

DONE

This bounded Opus pass first makes Facet and Rascal Rally verification practical. It
then completes the tutorial games, Sipworks, Glade, and sensory demo; retires Wardrobe;
ships a walk-up `SurfaceGui` terminal; and builds shared-source standalones.

### Opus 5 goal prompt

```text
/goal Finish Facet's games/examples, add 2D UI in the 3D world, ship shared-source
standalones, and make its verification loop practical.

Run Claude Opus 5 (`claude-opus-5`) at `xhigh`. Read repo instructions and the binding
example/standalone plan with its links. Follow its registration/baseline/ledger rules
and preserve Step 13. Examples own content; Facet owns reusable behavior. Use public
API; sync framework changes to RascalRally and Step 13 proof.

First optimize current Facet/RascalRally verification per plan. Preserve coverage,
mutations, and current caches; add no runner. Remove repeated work, safely batch or
parallelize pure producers, and pull forward Step 14 identity reuse when needed. Prove
timings, invalidation/verdict parity, one run/producer, and ≤20m headless; isolate
Studio/external time.

Word game: use a licensed local five-letter dictionary with broad guesses/familiar
solutions; record provenance/build, avoid proprietary/network data, and prove behavior/
cost. Keep all cells/cues visible across themes/text; preserve accessible play/reset.

Tile game: build the plan's finite crossword loop with center/connection rules,
dictionary Submit, score/refill, Undo, precise refusals, bounded goal, endings/reset,
visible decisions, and all inputs.

Match-3: use stable identities and public motion/structural transitions. Sequence swap,
invalid return, removal, gravity, refill, cascades, then unlock. Prove reset/teardown
and Full/Reduced parity; create no example animation system.

Sensory: start demo haptics on with toggle/status visible at the top. Through Step 13
public paths, demonstrate press/release/selection and one custom override. Visible
evidence and tests prove phase/cancel/no-op, identity, no duplicates, off/on, remount,
capability, cleanup, and all inputs without claiming motor output. Keep game opt-in.

Retire Wardrobe from player examples/builds; move only required proof outside
`examples`. Make shared-source Sipworks/Glade required standalones. PLAY their clear
goal, progress, recovery, success, reset, and all inputs; remove proof jargon.

World terminal: add the shared Outpost Power Terminal to showcase/standalone. It is 2D
Facet on `SurfaceGui`, not 3D/VR. Spike then add one public `surface_target`; prove
canvas, client `PlayerGui + Adornee + CanQuery`, style, input, occlusion, lifecycle,
cost, capabilities, and contracts/docs.

Use native `ProximityPrompt`, one Facet responder, direct pointer/touch, and IAS
keyboard/gamepad focus. Every exit/lifecycle path restores gameplay leak-free. No CAS/
UIS bindings. Keep UI client-side; server-validate shared-world commands.

Keep seven tutorials and the plan's curated standalone count. Each needs task, first
action, feedback/reset, and optional lesson. One manifest drives all outputs/docs;
share theme/motion controls, emit `.rbxl`, and never publish.

Delete only inventory-proved unused items; retire plain settings only after its
replacement. PLAY changed games, sensory default/off/on, every standalone, and terminal
walk-up/use/exit in Studio. Run the plan matrix, negatives, suites, prior gates/builds,
Step 13, and RascalRally checks. Give fresh reviewers evidence; resolve findings.

Complete only with gate exit 0/artifact; games/examples, test budget, sensory/world,
manifest, docs/inventory, and no-workaround/dead-item proof; plus exact physical
pendings. Report evidence/deletions. Do not publish/package.
```

## Step 14 — Prepare the existing repository for public distribution

The existing private repository — its pre-rename URL is recorded verbatim in
`artifacts/release-candidate-review/step14-remote-packet.md` — becomes `josha/Facet`
at one guarded owner checkpoint. This stage gives its public branch a clean
product/contributor structure, MIT licensing, provenance, and agent onboarding; it
also creates one private, stable-ID Facet Roblox Package with a guarded update
workflow. It simplifies the hours-long gate system without losing requirements or
negative controls. The Git repository remains canonical. The owner makes the repository and
free Creator Store listing public only after reviewing the release packet.

### Fable 5 goal prompt

```text
/goal Rename the private repo to `josha/Facet`, prepare its canonical MIT public-source
distribution, and create one verified private Roblox Package with a stable ID. Keep
the repo and listing private.

Use Fable 5 at highest effort for judgments; delegate decided work to Opus 5 `xhigh`.
Read repo instructions and the binding distribution plan/links. Register the gate;
inspect remote/history/status and preserve user work/guards.

Git is canonical; the Package is derived. Apply MIT with approved copyright. Preserve
third-party notices/rights; replace incompatible material safely or block.
Never infer ownership or silently relicense.

Use the plan's public allowlist. Archive private material with checksums outside Git;
audit Git/GitHub for secrets, private/game data, rights, and bulk. If purge is needed,
prepare only a tested clean candidate and owner migration/rollback packet.

Refresh README, guide/catalog, API, install/upgrade/Package, examples, extension,
contributor, test, release docs, and links; remove stale/internal claims and duplicates.
Create root `AGENTS.md` and thin Agent Skills-compatible `skills/use-facet/SKILL.md`;
route both to public API/theme/input/Studio/extension/release/RascalRally guidance.
Prove fresh agents can build and change Facet from public material alone.

Extend existing `tools/build_model.sh`; never create another model source. The Package
contains runtime plus license/source metadata. Add commit/hash/VERSION, semantic
manifest, non-secret config, and receipt. One interface provides offline build/status/
verify and guarded create/same-ID publish/rollback; changes rebuild/drift-check.

Default dry-run. Before remote/cloud mutation, batch one owner checkpoint for rename
authority and Package creator/metadata/listing/credential. Refuse duplicates. Mutation
requires confirmation, exact clean commit, matching version/hash/owner/asset, green
gates, and scoped secret. Never expose secrets, use cookies/forks, or replace the ID.

Use Open Cloud Model create/update only after official-doc research and a Studio spike
prove this `.rbxm` becomes a real Package; otherwise use the plan's Studio fallback.
Record the private ID. Prove in a clean place: `PackageLink`, tree/version/hash, runtime,
teardown, same-ID update, clean AutoUpdate, and protection of a modified copy.

Add a protected manual release command: build an immutable commit, rerun gates, update
the configured ID, poll/read back, Studio-verify, and retain its receipt.
Never publish every commit. Document no-Rojo install, Get Latest/version/AutoUpdate,
asset ID, and enabling the free listing only after Git is public.

Finish test/gate simplification per plan, reusing Step 13.5 work. Map requirements to
one producer; replace transcript greps/prior-gate replay with structured results and
one exact-identity run graph. Reject stale/partial evidence; keep affected/fast/full/
release tiers and isolate perf/Studio/external work. Preserve coverage/negatives; prove
mutation parity, invalidation, timings, and budget. Run RascalRally once per identity.

Mutation-test guards; verify reproducible manifests, fresh clone/consumers, examples,
suites/docs/adapters/prior requirements, and RascalRally sync. Complete only with gate
exit 0, no must-purge item, current public docs/link proof, root `AGENTS.md`, working
skill, private Package ID/update proof, fresh-agent success, and the owner packet. The
confirmed repository rename is in scope; do not push Git, change visibility, enable
listing, publish a GitHub release, or rewrite/delete other remote data.
```

## Completion checklist for the whole roadmap

The roadmap has achieved its goals only when all of these are true:

- every stage has a checked acceptance ledger and evidence manifest, and no row was
  passed by a lower evidence level than the behavior requires;
- Studio-visible behavior was verified incrementally in visible running slices, not
  inferred from the final headless suite;
- the corrected native capability matrix has evidence and adopted mechanisms sit at
  the adapter edge;
- no existing headless decision lost its tests;
- invalid public properties fail immediately with useful diagnostics, public types
  are useful, and guides/examples/registries match the runtime;
- a designer can edit native paint/state styling in the Style Editor and see it live;
- the styling guide states the layout-token synchronization boundary honestly;
- one semantic screen adapts across supported layout, distance, input, and
  accessibility profiles without device-specific copies;
- common controls/layouts pass all input and accessibility profiles;
- Roblox preferred text is measured and painted exactly once, updates while mounted,
  and all four values preserve public-control layout, state, focus, and full access
  to essential text;
- the production Facet Sponsor View remains readable, nonoverlapping, reachable,
  and usable at `Largest` on compact mobile portrait and landscape, with any permitted
  truncation exposing its full value and any moving-text fallback bounded and
  reduced-motion-safe;
- existing headless performance trends and real phone/console evidence are stored and
  labeled separately, with measured budgets for the supported device floor;
- the performance-lab source rebuilds self-contained `.rbxl` places that open without
  Rojo and are ready for the user to publish manually;
- its dense interactive scroll workload, matched native reference, MicroProfiler
  labels, deterministic reset, telemetry, and idle teardown are proven, and repeated
  physical low-end Android captures meet the versioned floor budget;
- the world-fixed `SurfaceGui` target passes its scoped canvas, topology, style,
  input, lifecycle, and Studio proof; spatial ray/hand/gaze input remains an extension
  contract, with no VR claim before its physical comfort/input/performance gate;
- the Sponsor framework ledger contains no unexplained missing row;
- Sponsor and tutorial consumers contain domain content plus declarative composition,
  not local substitutes for framework controls, layouts, paradigms, input, focus,
  accessibility, or motion;
- their ownership ledgers contain no unresolved workaround; reusable needs and public
  contract defects are fixed and proven in Facet before consumers use them;
- the parallel game implementation passes its full parity matrix and physical-device
  gate;
- the API constitution classifies every public item, explains intentional exceptions,
  governs future additions, and is enforced by useful drift/scaffold checks;
- engaged keyboard UI supports Tab/Shift+Tab focus traversal, Return/Space activation,
  and arrow adjustment through the existing focus/responder system, while passive
  gameplay and text editing retain their inputs;
- `example-quality-pass` is green; all seven tutorial examples were played in Studio,
  share the current native styling authority, visibly teach their lesson, rebuild as
  standalone places, and have working completion/reset paths;
- settings sync visibly demonstrates accept and reject/rollback, the word game meets
  its complete mechanics/input matrix, and the tile and match-3 loops were exercised
  rather than inferred from source;
- the word game uses a licensed/provenanced broad dictionary and keeps every empty,
  active, filled, and scored cell visible under all supported themes/text sizes;
- the crossword tile game has valid placement/connection/submit/undo/scoring/end-state
  rules, and match-3 visibly animates stable tile swaps, removal, gravity, refill, and
  cascades through Facet while Reduced motion preserves the result without travel;
- the sensory demo opens with its demo-owned haptics request on and the toggle/status
  visible at the top without scrolling across the size/Largest-text matrix; real
  built-in press, release, and selection defaults plus one public custom waveform are
  visibly demonstrable across inputs; off/on, remount, honest capability reporting,
  phase timing, no duplicates, and teardown are proven without changing Facet's
  library-level game-opt-in contract;
- Wardrobe is absent from the showcase, standalones, public example catalog, and
  publishable builds; any retained regression fixture has moved outside `examples/`
  with a proved owner and removal trigger;
- Sipworks completes paid order → final stamp → free pour → success → reset, and Glade
  completes dew + preferred nectar → wisp success → reset; both make goal, first/next
  action, progress, failure recovery, result, and Facet lesson clear in play;
- Step 13.5 records cold/warm before-and-after Facet and Rascal Rally verification
  timings; preserves the frozen pass/fail corpus and mutation bite; runs each unique
  deterministic producer at most once per exact identity; and completes its required
  headless work within 20 minutes on the documented machine, with Studio/external time
  reported separately;
- one checked-in manifest drives the showcase and six-to-eight curated standalone
  places, including the same walk-up world terminal in both; all share source and
  theme/motion chrome, rebuild self-contained, and have no obsolete or orphaned
  example output;
- the three clean-room reference experiences run representative complete loops, and
  their ledgers distinguish Facet gaps, game/Roblox-service work, and host-only
  platform surfaces without copying third-party code or assets;
- declarative 3D has a reviewed sibling-versus-extension decision and isolated spike;
  no spike or spatial-event contract is presented as production 3D/VR support;
- the fresh release-candidate review has no unresolved confirmed blocker/high defect,
  and every remaining finding has an explicit evidence-backed disposition;
- `GameStudio/ui/Facet`, its `Facet` ModuleScript/API, maintained filenames/content,
  generated artifacts, Studio/profile labels, agent tooling, and RascalRally consumers
  use Facet as the only current brand; old-name drift is limited to the approved rename
  ADR, external migration manifest, and immutable historical evidence;
- the maintainer guide, extension playbooks, scaffolds, ownership boundaries, tests,
  and gates agree on where each kind of change belongs; disposable fresh agents can
  add a representative extension and repair a seeded defect without private context;
- the ELI5 new-control guide and one-record scaffold let a fresh agent and separate
  human-guide verifier build the disposable palette-opening `ColorWell` through public
  seams,
  with input, focus, theme, accessibility, cleanup, tests, and Studio proof;
- one naming ADR governs every public category; canonical names and call shapes are
  predictable without repeating `Facet`, replaced control forms follow the deprecation
  policy, and types, docs, scaffolds, examples, tests, and RascalRally use the chosen
  surface;
- maintained source comments explain responsibilities, invariants, lifecycle, engine
  constraints, and difficult logic in plain human language, with no unexplained
  agent-only shorthand, prompt/gate codes, or implementation diaries;
- every pair or larger set of similar implementation chunks was consolidated into its
  existing owner or one narrow reusable mechanism, unless the ledger records a
  concrete semantic, lifecycle, dependency, clarity, or measured-cost reason;
- the Input Action System owns semantic commands and contexts; each remaining direct
  `ContextActionService` or `UserInputService` use has current impossibility evidence,
  one allowlisted adapter/diagnostic owner, tests, teardown, and a removal trigger;
- when the game enables Facet's haptics adapter, controls receive original,
  configurable press, release, and selection waveforms by default; cross-input phase
  timing, cancellation, fallback, one-pulse behavior, pooling, and cleanup are proven,
  while perceived similarity stays explicitly pending until paired physical review;
- the rebuilt performance lab matches current source and repeated Studio MCP plus
  MicroProfiler/LibMP captures separate solve/layout, fine and bulk update, adapter/
  render, scroll, idle, and teardown cost; measured framework hot spots are optimized
  or dispositioned without workload drift, and low-end Android proof stays honest;
- maintained Facet code, examples, and documentation contain no third-party vendor or framework
  references outside the dedicated parity document and optional, labeled guide
  comparisons; the exact-allowlist drift check proves the boundary;
- the guide index names and categorizes every current public layout, control,
  collection, service, target, and extension family; each item leads to useful guide
  or API detail, and automated drift checks bind the guide and exhaustive API
  reference to current exports, constructors, and registrations;
- human-readable documentation uses consistent terms, direct active sentences,
  defined technical words, short procedures, and no unexplained internal shorthand;
  fresh readers can complete the documented tasks without repository history;
- the existing repository is renamed `josha/Facet`, and its public-branch candidate is
  a clean, useful, reproducible source distribution; MIT and third-party notices are
  accurate, a fresh clone works,
  and the full-history/remote-surface audit has no unresolved must-purge item;
- one private official Roblox Package has a stable recorded asset ID and creator,
  matches the checked source VERSION/tree/hash, installs and updates as a real Package
  in Studio, and can be rebuilt/status-checked offline and published to that same ID
  through one guarded release action; its free listing waits for the repository-public
  owner checklist;
- its root `AGENTS.md` and thin `skills/use-facet/SKILL.md` route agents to current
  public guidance without duplication, and fresh-agent build/extension tasks pass;
- one living requirement graph drives structured results; the complete deterministic
  suite and every other expensive producer run once per exact release identity, stale
  or incomplete evidence fails, mutation parity preserves old defect detection, and
  the headless release run meets the documented budget or owns each irreducible cost;
- the remaining human and hardware work was presented as one instrumented review
  build and one ordered checklist rather than repeated ad hoc testing requests;
- every Facet source/contract/default/behavior/asset/distribution change has a
  RascalRally consumer-impact ledger, synchronized game integration or an explicit
  no-caller-change result, an updated game-side compatibility test, relevant game
  suite results, and an affected Studio canary where behavior is live;
- legacy Sponsor Mode is still present as the `UseFacetSponsor = false` rollback;
- the 2026-08-03 cutover decision is recorded, and no legacy deletion occurs without
  a later explicit decision.
