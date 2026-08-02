# LuauUI release-candidate review and remediation

**Status:** Planned after the functional proof stages.

## Purpose

Run a fresh-context, whole-framework review before preparing a public distribution.
This is not a confirmation pass. The reviewer tries to find correctness, lifecycle,
architecture, platform, API, documentation, and performance defects that the staged
acceptance gates may have missed.

## Review method

Use a fresh Fable 5 lead that did not implement the preceding stages. Before editing,
freeze the source/build identity, public API, test/gate results, representative Studio
scenarios, lifecycle counters, and performance baselines. Create a complete finding
ledger with severity and confidence.

Review the full production surface and its blast radius:

- reactive transactions, dependencies, errors, ownership, disposal, and churn;
- blueprint validation, mounted identity, dirty propagation, solver correctness, and
  property authority;
- native render/style/theme adapters, failure fallbacks, and Roblox capability claims;
- focus, responder/input arbitration, keyboard/touch/gamepad/hybrid behavior, modal
  isolation, and teardown;
- controls, collections, motion, async resources, replication adapters, and public
  extension seams;
- API consistency against the constitution, types, deprecations, examples, guides,
  generated references, and package boundaries;
- performance cliffs, per-frame allocation/writes, resource leaks, and sibling
  regressions.

Report every issue, including uncertain and low-severity ones. A declared missing
feature is not a defect unless the current API or documentation claims it works.

## Public guide completeness

Rebuild the documentation inventory from current exports, schemas, registrations,
and working examples rather than trusting the old guide. `docs/guide/README.md` must
contain a human-readable, categorized list of every currently supported public
capability, including:

- layout and composition primitives;
- display, input, and value controls;
- collections, scrolling, selection, reorder, and drag/drop;
- presentation, navigation, focus, input, adaptation, and accessibility;
- styling, theme packages, rich skinning, animation, and feedback;
- reactive state, lifecycle, async resources, replication, render targets, and
  authoring/testing tools.

The index may link to a dedicated catalog chapter for detail, but the guide index
itself must name the available items so a new Roblox author can discover them. Each
item links to its guide or API entry and states important availability or evidence
limits without internal shorthand. Remove stale or aspirational entries that appear
shipped. Keep `docs/reference/api.md` exhaustive for properties, callbacks, defaults,
and return values; the guide explains when and why to use the feature with small
examples.

Extend the documentation/public-surface drift check so every public export,
constructor, control registration, and supported extension category appears in the
catalog and reference, and removed or renamed items cannot linger silently.

## Remediation

Fable owns diagnosis and disposition. Reproduce live-observable defects before fixing
them. Dispatch a fix to Opus only after its cause, interface, test, and completion
evidence are unambiguous. Keep fixes narrow; do not add parity features, broad
refactors, or release polish inside the review.

Every confirmed blocker/high issue is fixed and rerun. Medium/low findings are fixed
when safe or recorded with owner, reason, risk, and a later trigger. Requirement or
public-contract findings cannot be waved through as notes.

## Gate

Register `release-candidate-review`. Run focused and full suites, fuzz/fault/soak and
performance checks, registration/docs/boundary checks, affected prior gates, and
representative real-adapter Studio scenarios. Give independent architecture,
reactive-runtime, Roblox-platform, and phase-gate reviewers the raw baseline, ledger,
diff, and artifacts.

The gate passes when there are no unresolved confirmed blocker/high defects, every
other finding has an explicit disposition, all fixes have regression evidence, the
categorized guide catalog and exhaustive API reference match the public surface and
their drift checks pass, affected Studio behavior is proven, and prior behavior and
performance remain intact. Do not publish or package a release in this stage.
