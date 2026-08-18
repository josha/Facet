# Facet release-candidate review, rename, and remediation

**Date:** 2026-08-13  
**Updated:** 2026-08-17
**Status:** Planned after the functional proof stages.

## Purpose

Run a fresh-context, whole-framework review before preparing a public distribution.
This is not a confirmation pass. The reviewer tries to find correctness, lifecycle,
architecture, platform, API, documentation, and performance defects that the staged
acceptance gates may have missed. It also prepares the code for future maintainers:
a person or agent should be able to find the correct owner, add a feature through the
established pattern, and prove the result without reconstructing project history.

This stage also completes the framework's pre-public rename from **LuauUI** to
**Facet**. Facet is the permanent product, package, module, documentation, and
profiling identity. Use `Facet` for the product, repository, root folder, ModuleScript,
and public Luau binding; use lowercase `facet` only where a tool requires a slug. The
plain-language promise is “One interface, shaped for every player.” The old name is
migration input, not a second brand.

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
- performance cliffs in solving, updating, adapter commits, and rendering; per-frame
  allocation/writes; resource leaks; and sibling regressions.

Report every issue, including uncertain and low-severity ones. A declared missing
feature is not a defect unless the current API or documentation claims it works.

## Canonical identity: Facet

Facet is the owner-selected name. Before mass edits, record a current collision and
rights check for the GitHub target, Roblox/Creator Store and common Roblox package
surfaces, major code hosts, and relevant trademark databases. A confirmed conflict
blocks external release and produces evidence for the owner; the agent must not choose
a different brand on its own.

Freeze a machine-readable rename inventory before editing. Include every case and
separator form of the old name in tracked paths and contents, generated outputs,
Studio object names, Luau symbols and types, require paths, Rojo mappings, project and
build files, test and gate IDs, artifact directories, environment/config names,
profiler labels, telemetry and diagnostics, documentation links, agent registrations,
skills, repository metadata, and Rascal Rally. Classify each match as current source,
generated output, persistent/external identifier, immutable evidence, or Git/remote
metadata. Count it before and after.

Use history-preserving moves to rename `GameStudio/ui/LuauUI` to
`GameStudio/ui/Facet` and every maintained file whose name contains the old brand,
including this roadmap, agent stubs, Sponsor documents, example places, model/package
outputs, and `skills/use-luauui`. Rename the required ModuleScript and public binding
to `Facet`; canonical calls read `Facet.UI...`, `Facet.Controls...`, or another shape
chosen by the naming ADR. Rebuild binary/generated outputs from renamed source. Do not
patch serialized binaries or generated manifests by blind text replacement.

Update both Rascal Rally Rojo projects, source imports, types, fixtures, tests, Studio
labels, diagnostics, build mappings, and Sponsor code in the same change. Rename the
production selector to a neutral or Facet name while preserving its exact default and
the legacy Sponsor rollback. If any DataStore key, Attribute, analytics event, cloud
asset, or other externally stored name can outlive this checkout, use one isolated
dual-read/single-write migration manifest with an owner and removal trigger. Do not
silently strand live data or keep the old brand as an ordinary alias.

Update build, test, documentation, and artifact tools so a clean checkout at the new
path works without symlinks or the old folder. Rename current profile scopes and
scenario IDs so new captures say Facet; preserve old raw captures as historical
evidence and label their framework version rather than rewriting them. Produce a
temporary redirect/migration note only where an already-consumed external path needs
it. The GitHub remote rename is a Step 14 owner-checkpoint action: this stage prepares
and verifies the exact local target and remote-change packet but does not mutate the
remote, publish, or create a package.

Before the drift gate, rewrite this roadmap and later-stage plans so they use Facet and
read the old remote URL only from the approved migration packet. The temporary rename
instructions must not leave the retired brand scattered through maintained docs.

After regeneration, run a case-insensitive old-name drift check across the maintained
and distributable tree, including paths and relevant serialized object names. The only
permitted matches are one short rename ADR, the explicit external migration manifest,
and immutable raw evidence stored outside the release surface. Each exception needs a
reason and removal rule. Prove the guard fails on temporary old-name content and an
old-name path. A clean clone/build/test/Studio run from `GameStudio/ui/Facet` and both
Rascal Rally projects must pass before broader remediation continues.

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

## Maintainability and safe expansion

Review the repository from the viewpoint of the next maintainer, not only the current
implementation. A future change should have one obvious owner, one established API
shape, one extension path, and one proof path. Refactor internal code when that makes
these answers simpler and more reliable. Public behavior, identity, cleanup, failure
semantics, and measured hot-path performance must remain stable unless a confirmed
defect requires a documented compatible correction.

Create or refresh one human-readable maintainer guide. It must map each production
area to its responsibility, public seam, internal owner, allowed dependency direction,
tests, Studio scenario, gate, and extension playbook or scaffold. It must answer common
questions directly: where a control, layout, modifier, engine property, render target,
input behavior, theme feature, example, or test helper belongs. Generate inventories
from code where practical; do not create a second hand-maintained API catalog.

For each subsystem, look for these maintenance failures:

- one module owns unrelated jobs or changes for unrelated reasons;
- a feature requires edits to several parallel registries or switch statements that
  can drift;
- callers reach internal modules because the documented seam is incomplete;
- construction, ownership, teardown, errors, or performance limits are implicit;
- names, paths, types, and tests do not make the responsibility discoverable;
- an extension playbook, scaffold, registration rule, or example produces a shape
  different from current production code;
- tests depend on hidden order, time, global state, or unexplained fixtures; or
- a safe local change requires repository history, an old plan, or conversation
  context to understand.

Fix confirmed failures rather than only documenting them. Split a mixed-responsibility
module at a stable boundary; collapse parallel registries into one source of truth;
make dependencies explicit; improve public types and diagnostics; add a narrow helper
or scaffold only when it has a current caller; and delete obsolete compatibility or
test machinery when policy allows. Avoid tiny forwarding files, speculative layers,
or abstraction whose main result is more navigation. Record any large module kept
whole with a concrete cohesion, lifecycle, performance, or readability reason.

Update the extension playbooks and scaffold output to match the cleaned code. Add
structural checks for the important boundaries: forbidden dependency direction,
unregistered public surface, parallel registries, internal consumer imports, missing
teardown proof, and docs/scaffold drift. A check must have an intentional failing case;
do not add a heuristic score that cannot explain how to fix a result.

Run two disposable fresh-context exercises using only the maintained repository and
its public contributor guidance:

1. A fresh agent adds a `ColorWell`-style composite: a visible color bucket or swatch
   opens a small palette picker when activated. It uses public Facet seams, every
   supported input class, focus and dismissal, theme roles, accessibility, tests,
   registration, a Studio fixture, and cleanup. A small fixed palette is enough; this
   exercise must not grow into a production color-editor feature.
2. A different fresh agent diagnoses and repairs a seeded bounded defect, identifies
   the correct owner, adds the smallest regression test, and runs the right gates.

Do not merge the artificial extension or seeded defect. Keep only improvements to the
real code, tools, tests, and guidance that the exercises reveal. Record wrong turns,
missing context, duplicated edits, internal imports, and unnecessary retries as
maintainability findings. Fix them and rerun both exercises until each agent succeeds
without conversation history or private hints.

## Adding a control must be easy

Rewrite `docs/extending/new-control.md` as an ELI5 path that both a Roblox developer
and an agent can follow. Keep the first successful control small. Put deeper contract
and conformance detail in a linked reference checklist so the first page does not read
like an internal gate transcript. Explain, in order: choose primitive versus composite;
name the control and spec; scaffold it; compose public primitives; bind caller-owned
state; add input, focus, accessibility, theme, motion, and cleanup; register it once;
write red-first tests; play it in Studio; update public docs; and run the right gate.
Every command needs a plain explanation, expected result, and useful failure message.

Make the scaffold produce the canonical current shape and update every necessary
registry from one declared control record where practical. A contributor must not
have to discover several parallel lists or copy an unrelated control. Preserve a
small expert checklist for uncommon engine-backed, async, virtualized, or transient
controls. Run the `ColorWell` exercise once as a fresh agent and once through a separate
verifier that follows only the human-facing steps. Keep the guide, scaffold, fixture
template, and improvements it reveals; do not ship the exercise as a public control
unless it independently meets a real product need.

## Public names and call shapes

Reopen the public-name rules with real call sites and autocomplete in mind. Inventory
every top-level export and group primitives, composites, services, pure helpers,
controllers, and advanced namespaces. Start with awkward examples such as
the old `LuauUI.newTable(LuauUI, core, spec)`. Judge discoverability, consistency,
redundant arguments, lifecycle meaning, and how easily a new author predicts the next
name.

Do not add `Facet` to every item: the module already provides the namespace, so
`Facet.FacetTable` repeats it. Test a role namespace such as
`Facet.Controls.Table(core, spec)` as the leading candidate for built-in composite
controls, while `Facet.UI.Button { ... }` remains a primitive and `newX` remains
available where object creation and ownership are the important fact. This is a
candidate, not a predetermined verdict. Compare it with a consistent flat alternative
using representative screens, the extension exercise, autocomplete, types, and the
cost of migration.

Record one naming ADR and make the chosen surface coherent before distribution. Fix
compatible problems now. For a rename, keep the old call working through the existing
deprecation policy, make the new form canonical in types/docs/scaffolds/examples,
prevent new old-form call sites, and update Rascal Rally in the same change. Do not
keep two permanent first-class vocabularies or perform a cosmetic rename without a
measurable authoring benefit.

This is the later decision point for the larger naming proposals that the API-
consistency stage intentionally deferred. It authorizes an evidence-backed compatible
migration, not an unversioned breaking cleanup.

## Plain source comments

Audit maintained production code, tests, examples, and tools for comments that a
human Roblox developer cannot understand on first reading. Write conceptually simple
explanations. “ELI5” means explain the idea and reason in ordinary language; it does
not mean remove exact API names, mathematical terms, or necessary platform detail.
Define a necessary technical term once, then use it consistently.

Prefer code that explains *what* through names and types. Use comments for *why*: the
responsibility, invariant, lifecycle rule, engine limitation, non-obvious algorithm,
failure behavior, or measured tradeoff. A module header should briefly state what the
module owns, what it receives and returns, and what must clean it up. A difficult
algorithm may use a small example or diagram when that is clearer than prose.

Remove or rewrite comments that contain:

- agent-only shorthand, prompt language, verifier instructions, or assumed private
  reasoning;
- unexplained gate IDs, finding codes, phase labels, evidence-row names, or acronyms;
- implementation diaries, dated bug stories, blame, or long accounts of how the code
  reached its current state;
- jokes, metaphors, dramatic warnings, vague pronouns, or terms that exist only in an
  old plan; or
- line-by-line narration that repeats simple code without explaining a constraint.

Move durable historical decisions into a neutral ADR or lesson when history is needed
to prevent a regression. Link it from one short source comment. Keep precise measured
facts when they still govern behavior, but state the condition and consequence in
plain language. Update or delete a comment whenever the code makes it false.

Use review and targeted scans to find likely shorthand and stale references. Do not
enforce a comment-count target, reject technical vocabulary blindly, or require a
comment on every function. Include source comments in the fresh human-reader and
agent exercises; if either reader cannot explain the rule and make the safe change,
fix the code structure or comment instead of teaching repository folklore.

## Input architecture

Use Roblox's [Input Action System](https://create.roblox.com/docs/input/input-action-system)
(`InputContext`, `InputAction`, and `InputBinding`) as Facet's semantic input and
command-binding authority. `InputActionService` is not an engine class; use the exact
Roblox names in code and documentation. Enable `Workspace.PlayerScriptsUseInputActionSystem`
in every supported project/place where Facet owns navigation actions.

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

## Sensory feedback and default haptic language

Re-audit Facet's sensory-feedback declaration, event taxonomy, control phases, and
client adapter against the current official
[SwiftUI `SensoryFeedback`](https://developer.apple.com/documentation/swiftui/sensoryfeedback)
semantics and Roblox's current
[`HapticEffect`](https://create.roblox.com/docs/reference/engine/classes/HapticEffect)
API. Record the comparison in `docs/reference/swiftui-parity.md`; maintained runtime
code, tests, examples, and non-comparison documents must use Facet and Roblox terms.
Apple does not publish reusable waveform values, so do not copy, reverse engineer, or
claim an identical waveform. Match the semantic role and perceived character with an
original Facet design.

When a game enables Facet's haptics adapter, interactive controls must have three
standard feedback phases:

- **press:** one short, crisp contact when the primary action goes down;
- **release:** one lighter, distinct response when that same action completes a valid
  release; a canceled press must not sound like a successful release; and
- **select:** one subtle tick when a choice or discrete value changes, not for passive
  pointer hover or each rendered frame.

Ship original, named default waveforms for these phases through Roblox
`HapticEffectType.Custom` and `SetWaveformKeys`. Keep waveform data in one typed,
documented sensory profile. A game can replace a phase, use a Roblox preset, or silence
it without rewriting a control. If custom waveforms are unavailable or rejected, use
a documented native-preset fallback that keeps the phases as distinct as the platform
allows. Do not use the superseded `HapticService` playback API.

Define phase timing once in the control/responder path for pointer, touch, keyboard,
and gamepad. Use native button hooks and the Input Action System where they provide the
needed lifecycle. Do not add a parallel raw-input router. Prevent a native button
effect and feedback-bus event from playing the same phase twice. Repeat, drag-away,
cancel, focus movement, rapid selection, disabled controls, remount, and input-method
switches need explicit outcomes. Coalesce high-frequency value changes without a late
or phantom pulse.

Keep haptics game-opt-in and disabled until the game enables the adapter. Once enabled,
the three phase defaults work without per-control declarations; the existing semantic
modifier can override or silence them. Preserve honest supported, unsupported, and
unknown reporting. Pool effects, allocate nothing per pulse, bound concurrent effects,
and destroy every effect, property assignment, and connection on disable or teardown.
Update all affected controls, the sensory demo, the authoring guide, API reference,
Rascal Rally integration, and performance lab.

Add red-first unit and real-adapter tests for exact waveform keys, phase order, one
pulse per cause, cancellation, overrides, fallback, coalescing, pooling, and cleanup.
Play a calibration surface in Studio across touch proxy, pointer, keyboard, and
gamepad, but do not call Studio evidence a feel test. Prepare a paired physical-device
review on an iPhone against a minimal native SwiftUI reference and also sample Android
and gamepad hardware. Tune for comparable subtlety, duration, separation, and fatigue,
not numeric imitation. Store device/build/settings and reviewer results. Until a human
feels both on the same device, label perceived similarity `PENDING_DEVICE`, never
`PASS`; this pending row must be visible in the Step 14 release packet.

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

Facet must explain itself in Roblox and Facet terms. It must not use another UI
framework, vendor, operating system, sample app, or trade dress as the name or the
reason for a feature.

Audit all maintained Facet source and comments, tests and tools, examples, filenames,
identifiers, links, and documents. Remove references to Apple and SwiftUI products,
platforms, samples, terminology, and websites from that surface. Use neutral names
such as `compact touch`, `desktop pointer`, `glossy`, `flat`, or the exact Facet API
name. Do not rename a stable Facet API only because another framework uses the same
generic name. Follow the deprecation policy if a current Facet identifier itself
contains a vendor name.

There are only two content exceptions:

1. `docs/reference/swiftui-parity.md` remains the dedicated comparison document.
2. `docs/guide/**` can contain a short, clearly labeled comparison for readers who
   know another framework. The comparison must be factual and optional. It must not
   define the Facet contract or replace a Roblox-first explanation.

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

- Write for a Roblox developer who has no Facet history.
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

## Release performance requalification

Refresh the existing performance-lab source and self-contained `.rbxl`; do not create
a second lab unless measured isolation requires it. Verify its scenarios, native
reference, deterministic reset, counters, profile labels, build command, and guide
still match the current runtime. It must separately expose initial solve/layout,
resize/text/theme reflow, fine-grained one-item updates, batched collection churn,
steady scrolling, adapter commits/Instance writes, engine UI/render preparation, and
idle/teardown. Keep workload size, content, visual fidelity, input, and accessibility
constant between comparisons.

Use Studio MCP plus the current Roblox performance-profiling/LibMP skill to run the
lab, collect repeated MicroProfiler baselines, and inspect the named scopes. Separate
reactive propagation, measurement/solve, arrangement, adapter commit, engine UI
preparation/render, resources, and unrelated Studio cost. For each framework-owned hot
spot, state a falsifiable cause, make the smallest safe optimization, rerun tests and
the same captures, and compare distributions rather than one best frame. Check that a
faster update does not make mount, layout, render, memory, cleanup, another theme, or
Rascal Rally worse.

Continue until no measured actionable framework bottleneck remains within the stage's
behavior and compatibility constraints. Do not force a code change when the profile
shows engine cost or noise. Record rejected and inconclusive attempts. Leave current
place artifacts, capture files, derived summaries, reproducible settings, before/after
results, and the next low-end Android capture instructions. Studio evidence supports
optimization but does not prove physical-device performance.

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
guards, sensory waveform/phase checks, naming/deprecation checks, maintainer/scaffold/
comment checks, the disposable exercise reports, performance-lab build/captures,
affected prior gates, Rascal Rally consumer checks, and representative real-adapter
Studio scenarios. Give independent
architecture, reactive-runtime, Roblox-platform, performance, and phase-gate reviewers
the raw baseline, ledger, diff, and artifacts.

The gate passes when there are no unresolved confirmed blocker/high defects, every
other finding has an explicit disposition, all fixes have regression evidence, Facet
is the canonical identity throughout the renamed source/distribution/Rascal Rally
trees, the old-name path/content negative controls pass with only approved migration
and immutable-evidence exceptions, a clean build runs from `GameStudio/ui/Facet`, the
categorized guide catalog and exhaustive API reference match the public surface and
their drift checks pass, the platform-language scan and intentional-failure proof
pass, every two-or-more similarity finding is consolidated or has a concrete recorded
reason, Input Action System owns semantic commands with only proved/allowlisted legacy
service exceptions, the maintainer map/playbooks/scaffolds match the cleaned code,
plain source comments contain no unexplained agent or project shorthand, the
`ColorWell` authoring proof and both fresh-context maintenance exercises pass, the
naming ADR is implemented with compatible migration, fresh readers can use the clear
documentation, enabled haptics provide one configurable pooled press/release/select
default with correct timing, fallback, and teardown, the rebuilt performance place and
repeated Studio profiles prove every framework optimization without workload drift,
affected Studio behavior is proven, and prior behavior and performance remain intact.
Perceived waveform similarity can remain `PENDING_DEVICE` only with the complete
paired-device packet above. Do not publish or package a release in this stage.
