# LuauUI fresh-context simplicity cleanup

**Date:** 2026-07-24  
**Status:** Proposed gate between roadmap Steps 5 and 6.

## Purpose and placement

Run this after the Sponsor-required framework capability in Step 5 is complete and
before either production Sponsor integration or the performance lab. At that point
the intended framework surface exists, but game integration has not yet made
unnecessary internals harder to remove.

This is a behavior-preserving cleanup, not a license to redesign LuauUI. Its outcome
is less owned code, fewer parallel paths, clearer ownership, and a codebase a fresh
agent can navigate more reliably. A small audit that correctly retains already-simple
code is better than a large refactor performed to justify the pass.

The pass adapts the efficiency principles in
[Ponytail's `AGENTS.md`](https://github.com/DietrichGebert/ponytail/blob/main/AGENTS.md):
understand the real flow first; ask whether code needs to exist; reuse what is already
present; prefer standard-library, platform-native, and installed capabilities; then
write the minimum clear code. `GameStudio/ENGINEERING.md` remains the repository
authority and adds LuauUI's platform, testing, documentation, and agent-maintainability
requirements.

## Scope

Review LuauUI-owned source, tests, tools, registrations, examples, and maintainer
documentation. Do not edit:

- `vendor/`, generated `build/` output, historical artifacts, or third-party code;
- RascalRally or any other game's code;
- behavior merely because the reviewer would have designed it differently.

Generated outputs may be rebuilt only to verify that their sources still produce
them.

## Audit before editing

Use a fresh-context lead that has not implemented Steps 1–5. It must read the
repository instructions, architecture guide, public API/deprecation policy, current
roadmap decisions, and relevant lessons, then trace representative flows end to end:
authoring to mount, layout to adapter, style authority, input to semantic action,
focus, resources, controls, and teardown.

Freeze the current baseline before proposing changes:

- full library suite and registration checker;
- current completed roadmap gates;
- public exports and deprecation ledger;
- representative Studio scenarios and lifecycle/resource counters;
- current headless performance results, labeled as regression evidence only.

Create `artifacts/code-simplicity-cleanup/candidate-ledger.md`. Each candidate names
the location, concrete evidence, behavior that must remain, proposed simplification,
risk, required check, expected maintenance benefit, and disposition.

Look specifically for:

1. unreachable, obsolete, or superseded owned code;
2. duplicate decisions or parallel helpers that should have one owner;
3. wrappers, indirection, configuration, or generic seams with no current consumer;
4. custom mechanisms now covered by an existing helper, Luau facility, installed
   dependency, or current Roblox-native feature;
5. mixed-responsibility modules that a fresh agent cannot understand in one pass;
6. repeated test/gate scaffolding and stale comments, diagrams, or registrations;
7. per-frame work or retained resources that measurements show can be removed.

Do not use raw line count, file size, or static-search output as proof by itself.
Trace callers, dynamic registration, public exports, generated consumption, Studio
wiring, and teardown. Verify current Roblox documentation or an engine probe before
replacing a mechanism with a platform feature.

## What may be implemented

Implement only high-confidence, behavior-preserving candidates whose benefit is
larger than their migration and regression risk. Prefer, in order:

1. delete code proved unnecessary;
2. reuse an existing owner/helper;
3. consolidate a duplicated decision at its shared root cause;
4. remove needless indirection;
5. split a genuinely mixed-responsibility module only when the result is easier to
   discover and does not add ceremony.

Before each non-trivial change, add or identify the smallest characterization that
would fail if preserved behavior drifted. Make one coherent simplification at a time
and run its focused checks before continuing. Update affected comments, architecture
maps, API references, registrations, and lessons in the same change.

## Hard boundaries

- Preserve public behavior, exports, deprecation timing, and documented intentional
  SwiftUI differences. Breaking changes require a separate approved stage.
- Preserve property authority, scope ownership, error containment, deterministic
  headless decisions, native adapter boundaries, accessibility, and every supported
  input paradigm.
- Do not add dependencies, compatibility layers, feature flags, speculative
  abstractions, broad renames, repository-wide formatting, or unrelated features.
- Do not replace clear code with compressed or clever code merely to reduce lines.
- Do not weaken tests, gates, workloads, evidence, or physical-device requirements.
- Record larger architectural opportunities as evidence-backed decision packets for
  Fable 5 or the user; do not smuggle them into cleanup.

## Verification and completion

Register `code-simplicity-cleanup` in the existing gate manifest before implementation
with honest pending checks. Re-run the full suite, registration/API drift, every
affected prior gate, and baseline performance regressions. For any visible, input,
layout, adapter, or lifecycle change, run the existing Studio scenario through the
real adapter; use the canonical five-view device matrix when layout can change.
Physical-only behavior remains pending rather than inferred.

Store before/after evidence for public surface, relevant traces and geometry,
resource/lifecycle counts, and affected performance scenes. Line/module counts may be
reported as descriptive evidence but are never pass targets.

Give a fresh-context phase-gate verifier the goal, baseline, candidate ledger, changed
files, and raw results without the implementer's conclusions. Architecture review is
required; add reactive-runtime or Roblox-platform review only when those areas
changed. Resolve requirement-affecting findings and rerun affected evidence.

Completion requires:

- `lune run tools/lune/gate code-simplicity-cleanup` exits zero and writes
  `artifacts/code-simplicity-cleanup/gate.json`;
- every implemented candidate has a preserved-behavior check and before/after proof;
- the full suite, registration, affected prior gates, and performance regressions are
  green;
- Studio-visible changes have real-adapter evidence;
- public API/deprecations and framework/game ownership boundaries are unchanged;
- the ledger records implemented, retained, rejected, and escalated candidates in
  clear language;
- documentation matches the simplified code.

The final report leads with what was deleted or consolidated, what was deliberately
retained and why, exact verification results and artifact paths, and any separate
decision packets. “No worthwhile cleanup found” is a valid successful result when the
audit and evidence support it.
