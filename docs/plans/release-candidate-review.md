# LuauUI release-candidate review and remediation

**Date:** 2026-08-13  
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

## Engineering quality and reuse

Review the implementation as a software library, not only as a set of passing
features. Check responsibility and dependency direction, names and public types,
state ownership, mutation boundaries, failure handling, cleanup, hot-path cost, dead
code, test seams, and generated-versus-authored boundaries.

Two or more similar implementation chunks create a reuse finding. This includes
copied code and separate helpers, controls, adapters, or pipelines that perform the
same job with small variations. For each finding:

1. identify the shared responsibility, callers, invariants, lifecycle, error behavior,
   and performance needs;
2. reuse an existing mechanism when it already owns that responsibility;
3. otherwise extract one named, typed mechanism at the narrowest stable layer;
4. migrate every affected caller and delete the superseded paths; and
5. prove public behavior, identity, cleanup, diagnostics, and performance did not
   regress.

Consolidate by default. Keep separate implementations only when a shared mechanism
would merge different semantics, reverse a dependency, add more branching or
indirection than it removes, obscure a tutorial, or harm a measured hot path. Record
that concrete reason in the finding ledger. “They may diverge later” is not enough.
Do not introduce a generic abstraction with only an imagined future caller.

Apply the same review to substantial test, example, and tool infrastructure. Keep a
small local test setup when sharing it would make the behavior under test harder to
read. Add focused structural guards for each important consolidated seam so a second
production path cannot return silently. Do not use a raw duplication percentage or
line-count target as a substitute for design review.

## Input architecture

Use Roblox's [Input Action System](https://create.roblox.com/docs/input/input-action-system)
(`InputContext`, `InputAction`, and `InputBinding`) as LuauUI's semantic input and
command-binding authority. `InputActionService` is not an engine class; use the exact
Roblox names in code and documentation. Enable `Workspace.PlayerScriptsUseInputActionSystem`
in every supported project/place where LuauUI owns navigation actions.

Inventory every direct use of `ContextActionService`, `UserInputService`, raw key or
button events, and parallel action routing in source, examples, tools, and Rascal
Rally integration. Classify each use as semantic action routing, environment/capability
observation, raw pointer or keyboard geometry, engine interoperability/diagnosis, or
test-only injection.

Move semantic action routing, priority, sinking, device bindings, and context lifetime
to the Input Action System. Do not use `ContextActionService` or
`UserInputService.InputBegan`/`InputEnded` as a second command path. Recheck all
existing contention probes and legacy PlayerScripts repairs; prior need is not proof
that they remain necessary.

Keep a legacy service call only when the current Input Action System cannot provide
the required fact or mechanism. For every exception, record the missing capability,
official source or Studio disproof, exact adapter owner, consumers, teardown, and
removal trigger. Keep it in one named adapter or diagnostic allowlist and expose a
pure injected fact above that boundary. Examples and game screens cannot call legacy
input services directly.

Add drift checks that reject new direct legacy action bindings or unlisted service
access. Prove action contexts enable, prioritize, sink, switch, and destroy correctly;
all supported keyboard, pointer/touch, and gamepad paths deliver one semantic action;
text entry and gameplay keep their inputs; and no old and new path fires together.
Use current official Roblox documentation and visible Studio evidence because this
platform surface can change.

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

## Product-language independence

LuauUI must explain itself in Roblox and LuauUI terms. It must not use another UI
framework, vendor, operating system, sample app, or trade dress as the name or the
reason for a feature.

Audit all maintained LuauUI source and comments, tests and tools, examples, filenames,
identifiers, links, and documents. Remove references to Apple and SwiftUI products,
platforms, samples, terminology, and websites from that surface. Use neutral names
such as `compact touch`, `desktop pointer`, `glossy`, `flat`, or the exact LuauUI API
name. Do not rename a stable LuauUI API only because another framework uses the same
generic name. Follow the deprecation policy if a current LuauUI identifier itself
contains a vendor name.

There are only two content exceptions:

1. `docs/reference/swiftui-parity.md` remains the dedicated comparison document.
2. `docs/guide/**` can contain a short, clearly labeled comparison for readers who
   know another framework. The comparison must be factual and optional. It must not
   define the LuauUI contract or replace a Roblox-first explanation.

No other current document can link to or name that comparison. Current code,
examples, tests, tools, filenames, gate names, scenarios, and comments must use
neutral language. Immutable raw evidence can remain outside the maintained and shared
surface when changing it would damage provenance, but current material must not use
its branded name. Move lasting decisions into neutral ADRs or guides before retiring
or moving an old plan. Repair every link, registry, artifact producer, and consumer
affected by a rename.

The execution prompt and this temporary plan state the prohibited names so the agent
can perform the cleanup. After the agent consumes them, it must replace or move these
instructions so the final scan of maintained `code/examples/docs` passes. A private
machine-readable match list may exist only inside the guard that enforces this rule;
it is not product prose and must not ship as user documentation.

Add a case-insensitive drift check with an exact path/block allowlist. It must catch
brand words, domains, platform/sample names, branded filenames, and new links outside
the two exceptions. Prove the check fails on one temporary violation, then restore
the tree and prove it passes.

## Clear technical writing

Use an ASD-STE100-inspired house style for every document a person is expected to
read. This is a clarity standard, not a claim of formal ASD-STE100 certification.
Use the official standard and FAQ as the source:

- [ASD-STE100 Issue 9](https://www.asd-ste100.org/assets/files/ASD-STE100_ISSUE9.pdf)
- [ASD-STE100 FAQ](https://www.asd-ste100.org/STE_faq.html)

Apply these rules:

- Write for a Roblox developer who has no LuauUI history.
- Use one term for one concept. Define each necessary technical term at first use.
- Use active voice and concrete verbs. Tell the reader who does the action.
- Put one instruction in each numbered step and one main idea in each sentence.
- Target at most 20 words for an instruction and 25 words for a description. Split a
  sentence when the limit does not improve meaning. Keep descriptive paragraphs to
  six sentences or fewer.
- Put a condition before the action it controls. Use lists for real sequences or
  choices.
- Avoid idioms, jokes, marketing language, vague pronouns, hidden negatives,
  unexplained acronyms, internal phase codes, and shorthand such as a bare artifact
  row ID. Replace jargon with plain words, or define the project-specific technical
  noun or verb.
- Keep API identifiers, Roblox class names, commands, paths, and code exact. Explain
  them in plain language instead of changing them.

Automated checks can enforce the measurable parts and report likely long or unclear
text. They must not reject code blocks, tables, links, or necessary technical names
with a brittle grammar score. A fresh Roblox author and a fresh agent must each use
only the public docs to complete a small task and explain the relevant concept. Fix
every failure caused by unclear wording or navigation.

## Remediation

Fable owns diagnosis and disposition. Reproduce live-observable defects before fixing
them. Dispatch a fix to Opus only after its cause, interface, test, and completion
evidence are unambiguous. Do not add parity features, speculative redesigns, or
release polish. Evidence-backed reuse consolidation and Input Action System migration
are authorized even when they update several callers; keep their responsibility and
public behavior narrow.

Every confirmed blocker/high issue is fixed and rerun. Medium/low findings are fixed
when safe or recorded with owner, reason, risk, and a later trigger. Requirement or
public-contract findings cannot be waved through as notes.

## Gate

Register `release-candidate-review`. Run focused and full suites, fuzz/fault/soak and
performance checks, registration/docs/boundary checks, reuse and input-authority
guards, affected prior gates, Rascal Rally consumer checks, and representative
real-adapter Studio scenarios. Give independent architecture, reactive-runtime,
Roblox-platform, and phase-gate reviewers the raw baseline, ledger, diff, and
artifacts.

The gate passes when there are no unresolved confirmed blocker/high defects, every
other finding has an explicit disposition, all fixes have regression evidence, the
categorized guide catalog and exhaustive API reference match the public surface and
their drift checks pass, the platform-language scan and intentional-failure proof
pass, every two-or-more similarity finding is consolidated or has a concrete recorded
reason, Input Action System owns semantic commands with only proved/allowlisted legacy
service exceptions, fresh readers can use the clear documentation, affected Studio
behavior is proven, and prior behavior and performance remain intact. Do not publish
or package a release in this stage.
