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
their drift checks pass, the platform-language scan and intentional-failure proof
pass, fresh readers can use the clear documentation, affected Studio behavior is
proven, and prior behavior and performance remain intact. Do not publish or package
a release in this stage.
