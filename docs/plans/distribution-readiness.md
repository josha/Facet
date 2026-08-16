# LuauUI public repository readiness

**Status:** Planned after the release-candidate and example-product passes.

## Purpose

Prepare the existing private GitHub repository, `josha/LuauUI`, to become LuauUI's
canonical public source distribution. Users can install LuauUI from an ordinary Git
clone/Rojo mapping, a source copy, or one official Roblox Package with a stable asset
ID. The repository is the source of truth; the Package is a required, derived
distribution artifact for creators who work mainly in Studio.

This stage changes the local repository into a public-ready project. It does not push,
change repository visibility, publish a release, delete remote data, or rewrite remote
history. After one explicit owner/credential checkpoint, it may create the private
LuauUI Package asset and prove an update. The owner makes the repository public and
enables the free Creator Store listing through the final release checklist.

## Decisions

- Use the existing `https://github.com/josha/LuauUI` repository. Do not create a
  second distribution repository.
- Keep Git source canonical. The Package contains the checked, generated
  `build/LuauUI.rbxm` runtime tree plus non-executable license/source metadata, never
  hand-edited code, examples, tests, docs, or a parallel source copy.
- Create exactly one official LuauUI Package asset and keep its stable asset ID in a
  checked, non-secret distribution manifest. Updating LuauUI creates a new version of
  that asset; it must never silently create another asset.
- Before first creation, ask once for the immutable Roblox owner type/ID and approval
  of the display name, description, private asset creation, and intended free Creator
  Store listing. Package ownership cannot be transferred; do not infer it from Git or
  local credentials. Store API keys only in the environment or protected secret store.
- License original LuauUI work under the MIT License. Put the standard text in the
  root `LICENSE` file. Use an exact copyright-holder line that the owner has approved.
  Do not infer a legal identity from a Git username or commit address.
- Keep each third-party work under its own license. Preserve the vendored Fusion MIT
  license and create `THIRD_PARTY_NOTICES.md` for all code, fonts, images, audio, and
  other assets that require notice.
- If ownership, contribution rights, or asset provenance conflicts with MIT release,
  remove or replace the material when safe. Otherwise, stop public release and give
  the owner a precise evidence packet. Do not silently relicense it.

MIT is the selected project license, not a claim that every repository file was
created by LuauUI. The provenance ledger defines each exception.

## Public repository boundary

Define three audiences before changing the tree:

1. **library users** need source, public types, a quick start, guides, API reference,
   examples, theme authoring, compatibility, and upgrades;
2. **contributors** need architecture, extension guides, tests, development commands,
   decisions, issue rules, and current platform constraints; and
3. **internal maintainers** may keep plans, raw reviews, prompts, profiler captures,
   and historical handoffs, but these do not belong in the public branch tip.

The public branch should have a familiar, shallow entry surface:

- `README.md`, `LICENSE`, `THIRD_PARTY_NOTICES.md`, `CHANGELOG.md`,
  `CONTRIBUTING.md`, `SECURITY.md`, `AGENTS.md`, and the normal Git/tooling files;
- `src/`, required `assets/`, and licensed `vendor/` material;
- public `examples/`, `docs/guide/`, `docs/reference/`, architecture decisions, and
  contributor extension documents;
- the Step 13.5 example manifest, shared tutorial/showcase sources, curated standalone
  projects including the world-terminal fixture, and redistribution notices for
  generated dictionary data;
- useful `tests/`, `bench/`, `tools/`, project files, and reproducible build inputs;
- the package build/status/publish helper and non-secret asset manifest, but no keys or
  local credential files;
- `skills/use-luauui/SKILL.md`; and
- `.github/` continuous-integration, pull-request, and issue templates that match the
  real local workflow.

Use an explicit public allowlist. Before removing internal material from the branch
tip, preserve it outside this Git repository in a private archive with a manifest and
checksums. Do not hide private material in another branch or tag: every pushed ref is
part of the repository that may become public. Do not destroy the only copy.

Preserve Step 13's product-language boundary and clear-writing standard and Step
13.5's one-manifest example boundary. Public files
must not restore retired vendor language, branded paths, internal shorthand, or
unclear legacy text. Keep any allowed comparison separate, optional, and
non-authoritative.

## Repository-wide privacy and provenance audit

Freeze the local and remote state before editing: remote URL, visibility, default
branch, branches, tags, releases, Actions runs and artifacts, issues, discussions,
wiki, Pages state, current commit, status, and tracked file inventory. Never discard
uncommitted user work.

Audit the complete Git object history and every remote-visible surface, not only the
current files. Search for secrets, credentials, personal or absolute paths, private
place and universe IDs, Rascal Rally code or copy, proprietary assets, large generated
files, and material without known redistribution rights. Classify each match as:

- safe public history;
- remove from the branch tip but safe to retain as historical context;
- must purge before visibility changes; or
- owner or counsel decision required.

Changing a private repository to public exposes its code and Actions history. If a
must-purge item exists anywhere in reachable history, a normal cleanup commit is not
enough. Build and verify a clean-history candidate locally, but do not force-push,
delete refs, or change visibility. Put the exact remote migration and recovery steps
in the owner packet. Public release stays blocked until the owner authorizes and
performs the destructive remote operation.

## Documentation and installation

The repository root must explain what LuauUI does, its supported Roblox environments,
current evidence limits, installation, a five-minute screen, examples, documentation
map, development commands, versioning, compatibility, contribution policy, security
reporting, and license. State the verified `SurfaceGui` scope precisely. Do not turn a
world-fixed two-dimensional surface into an unproved VR, ray, hand, gaze, performance,
device, or accessibility claim.

Document direct Git/Rojo use, source copy, the rebuilt `.rbxm`, and the official
Package. Make the Package the recommended no-Rojo install, with its asset ID and
Creator Store link easy to find, but do not make that ID part of the Luau runtime API.
Explain *Get Latest Package*, version checking, and that AutoUpdate is opt-in and stops
for a locally modified copy. Recommend reviewed/manual updates for production games
and AutoUpdate only where automatically accepting the newest compatible version is
intentional. Add a standalone consumer project that proves mount, theme, input,
adaptive layout, preferred text, teardown, and no Rascal Rally or parent-workspace
imports.

## Roblox Package release channel

Extend the existing `tools/build_model.sh`; do not replace its Rojo mapping or create
a second model builder. The artifact remains one `ModuleScript` named `LuauUI` with
the supported runtime tree beneath it. Add release metadata that does not affect its
public API: `LuauUI.VERSION`, source commit, normalized source-tree hash, and build
schema. Include the full MIT notice and any notice required by material actually in
the Package through a plainly named, non-executable child or equivalent metadata that
survives insertion. Verify that every required runtime child is present and no test,
example, private file, or development dependency entered the model.

Provide one documented maintainer interface with at least these safe operations:

- **build** — generate the model and a semantic instance/source manifest;
- **status/verify** — rebuild, inspect the tree, run the packaged-consumer canary, and
  report whether the current source/version differs from the last published receipt;
- **create** — one-time private asset creation, refused if an asset ID already exists;
- **publish** — update only the configured asset ID and record the returned operation,
  asset revision, version, commit, source hash, artifact hash, timestamp, and actor in
  a machine-readable receipt; and
- **rollback instructions** — select an existing Roblox package version; never upload
  an old tree as an undocumented new version.

Build and verify are offline/default. Create/publish require an explicit confirmation
flag, a clean approved source commit, matching `LuauUI.VERSION`, green release gates,
the configured creator and asset, and a narrowly scoped Open Cloud credential supplied
through an environment variable. Refuse a missing/mismatched owner, asset ID, version,
hash, dirty source, stale build, failed moderation, in-flight operation, or cloud
revision newer than the local receipt. Never print or persist a secret, use a Roblox
session cookie, or publish from an untrusted pull request.

Pull-request drift checks prove the local artifact matches source; they do not demand
a cloud publish or version bump for every development commit. The release command
must refuse when the current VERSION already exists in the recorded Package history
with a different source hash, when VERSION did not advance under the semver policy,
or when changelog/deprecation records do not match the release.

Prefer the current Open Cloud Assets API because it can create and version Model
assets, which Roblox documents as uploaded packages. Treat that route as unproved for
this generated file until a Studio spike inserts the exact uploaded asset and confirms
real `PackageLink` behavior. Roblox warns that `.rbxm` files produced outside Studio
may fail to upload or run. If the spike fails, retain the same build/status/receipt
contract but use a small canonical publisher place and Roblox Studio's Convert/Publish
to Package workflow for the external step. Do not call an ordinary model a Package.

Create the real asset privately only after the owner checkpoint. Record the returned
asset ID/creator in the public manifest. Insert it by ID into a clean Studio place,
move it to `ReplicatedStorage`, require it, compare its version/tree/hash with source,
and exercise mount, theme, input, update, and teardown. Prove a later publish updates
the same asset and that an unmodified opted-in copy receives it while a modified copy
is reported rather than overwritten. Keep Rascal Rally on its authorized direct-source
integration; package proof is an additional consumer, not a migration.

On changes to runtime source, required assets, versioning, or the model builder, local
and pull-request checks must rebuild and verify package drift without contacting
Roblox. Add a protected, manually dispatched release workflow (or equivalently guarded
single command) that checks out an exact commit, reruns the release gate, publishes
that immutable artifact, polls completion, verifies the cloud revision in Studio, and
stores its receipt. It must not publish automatically on every commit or from forks.

Prepare a free Creator Store listing with accurate MIT/source/version links and no
unsupported claims. Because Step 14 does not make the Git repository public, enabling
that listing remains an ordered owner action immediately after repository visibility
and public-CI verification. The release packet must contain the private Package asset
ID, listing draft, exact activation step, and rollback/unlist consequences.

## Test and gate simplification

The current verification system is too expensive for the size of the library. At the
2026-08-16 planning baseline, `gate_manifest.luau` names `./run-tests.sh` about 230
times and `prior_gates.sh` about 50 times across 29 registered phases. Many checks run
the same complete suite, then search its human transcript for one case name. A later
gate replays many earlier gates, which replay the same producers again. Preserve the
coverage and negative controls; remove the repeated work and fragile transcript
coupling.

Measure before redesigning. On a documented quiet machine, record wall/CPU time,
invocation count, input/output identity, artifact writes, and the slowest specs for:
the fast and full suites, every unique gate producer, a representative late gate, and
the complete prior-gate sweep. Build a machine-readable graph:

`requirement -> canonical evidence producer -> result IDs -> gate consumers -> inputs`.

Classify duplicate execution, duplicate assertions, whole-tree scans repeated per
case, cross-product fixtures that rebuild identical setup, historical gates that only
restate living requirements, and commands that must remain isolated because they
measure performance, Studio, hardware, networking, or mutable external state.

Replace repeated shell transcript searches with structured test results. Each spec and
case needs a stable result ID, status, duration, requirement IDs, source identity, and
diagnostic. The complete deterministic suite runs once for an exact source identity.
Gate rows query those structured results and verify that the producer completed; they
do not start the suite again or depend on a sentence in its human output. Human names
may improve without silently breaking a gate.

Create one release-run coordinator that treats verification as a directed acyclic
graph. It executes each unique producer at most once, then evaluates every applicable
gate from that run's structured results. A standalone gate may ask the coordinator for
missing dependencies, but it must reuse a current in-run result instead of recursively
restarting earlier gates. Replace `prior_gates.sh` replay with reevaluation of every
earlier requirement against the same current run. A checked-in old PASS is never
evidence for changed source.

Result reuse requires an exact key that includes normalized relevant source and asset
hashes, test/manifest code, pinned toolchain, command/options, required environment
class, and declared fixture inputs. Reject a stale, truncated, partial, failed,
manually edited, wrong-toolchain, or wrong-environment result. Performance, Studio,
physical-device, moderation, and network results keep their existing evidence classes
and cannot be upgraded by a headless cache. Default to rerun when dependency ownership
is uncertain.

Keep clear commands for four purposes:

- **affected** — the smallest safe local set from an explicit dependency map; unknown
  files fall back to the broader tier;
- **fast** — the current deterministic inner-loop spine;
- **full** — every deterministic spec exactly once; and
- **release** — the full suite plus each unique scanner, build, fault/soak,
  performance, Studio, package, documentation, and Rascal Rally producer required by
  the release graph.

Show which tier ran, why each producer was selected, the slowest work, reused results,
invalidation reasons, and the exact smallest rerun command. Do not let affected/fast
output masquerade as full/release evidence. The Rascal Rally suite and each package or
Studio canary also run at most once per matching source identity in one release run.

Parallelize only independent processes with isolated temporary/artifact paths and a
deterministic merge. Serialize performance measurements, Studio sessions, package
mutation, and any producer that shares external state. Cap concurrency from measured
machine capacity so faster scheduling does not create flaky timing results. Where a
source scanner or large fixture dominates, scan/build once and evaluate its independent
assertions in memory; keep distinct result IDs and useful failures.

Do not remove a test only because it is slow or overlaps another title. For every
deleted or merged check, map its requirement, failure direction, fixture, and negative
control to a canonical surviving producer. Use a frozen pass/fail corpus and targeted
mutations to prove the old and new systems return the same verdict for real defects.
Add mutations for cache invalidation, missing registration, truncated suite, changed
test ID, stale toolchain, bad artifact, and a failed producer. The new coordinator and
query layer must prove they can fail before any old path is retired.

Set final budgets from the measured baseline, but require these structural outcomes:
the full deterministic suite runs once, every other unique expensive producer runs at
most once, and prior-gate evaluation adds only cheap result validation. Record cold and
warm timings and percentage reduction. If the automated headless release run remains
longer than 20 minutes on the documented machine, keep profiling and simplifying or
record the irreducible producers with owner, evidence class, cost, and optimization
trigger. Studio, physical-device, moderation, and network waiting are reported
separately rather than hidden inside the headless number.

Update contributor and agent guidance so an ordinary change uses the affected/fast
loop, a pre-merge change uses full verification, and a release uses the one coordinator.
Archive historical gate prose after its living requirements and evidence links move
to the current ledger. Keep concise, human-readable diagnostics; the gate manifest
must not remain an implementation diary.

## Agent onboarding kit

Create root `AGENTS.md` as the portable baseline for agents that build with or change
LuauUI. Keep it concise and link to public sources of truth. It must tell an agent:

- where to find the quick start, capability catalog, API, examples, architecture,
  styling, input, device verification, accessibility, and extension guides;
- how to choose public layouts and controls, bind state, style through native
  StyleSheets and theme packages, and rely on LuauUI for adaptation, focus, input,
  motion, scrolling, and lifecycle;
- how to choose screen, billboard, or interactive world-surface presentation and find
  the walk-up-terminal recipe without implying declarative 3D or VR support;
- how to keep domain state and content in a game while putting reusable mechanisms in
  LuauUI;
- the build, test, documentation, Studio, and Rascal Rally consumer-lockstep workflow,
  including local package build/status for relevant changes and cloud publish only for
  an approved release;
- when to use affected, fast, full, or release verification; how to understand a
  selected/reused producer; and how to run the smallest trustworthy failure rerun; and
- forbidden shortcuts: internal imports, raw GUI substitutes, screen-local input,
  focus, or layout systems, device-name branches, and game-local workarounds for a
  framework promise.

Create a thin Agent Skills-compatible `skills/use-luauui/SKILL.md`. Trigger it for
building, changing, debugging, styling, or testing Roblox UI with LuauUI. Include only
the essential workflow and route details to public guides. Keep frontmatter to `name`
and `description` unless a supported host requires a thin adapter. Do not create a
second manual. `AGENTS.md` must work when skill discovery is unavailable.

## Verification

Register `distribution-readiness` before implementation. Add checks for the public
allowlist, secrets and private data, third-party notices, required root files, stale
links, documented public-surface drift, agent-link drift, generated-file policy, and
repository size. Add the test-graph, single-execution, structured-result, invalidation,
coverage-map, and time-budget checks above. Prove each important guard rejects a
temporary violation.

Create a local candidate commit without changing the remote. Produce the public tree
twice and compare manifests and checksums except documented nondeterminism. Test a
fresh local clone with no parent-workspace imports. Run the quick start, standalone
consumer, tests, documentation links, boundary checks, and real-adapter mount, input,
theme, adaptation, geometry, accessibility, and teardown proof. Keep Rascal Rally's
direct-source integration and game-side contract test synchronized.

Rebuild every declared tutorial and curated standalone place from the public clone.
Verify that their common manifest, theme and motion controls, dictionary provenance,
world-terminal fixture, public `surface_target`, and generated-output policy survived
repository cleanup. Run the terminal's real-adapter mount, theme, input-engagement,
world-result, and teardown canary. Do not ship retired place outputs or restore
parallel example registries.

Build the Package from that same clone and compare its semantic tree and source hash
with the clone, `.rbxm`, standalone consumer, and private cloud copy. Run a deliberately
stale-source, wrong-asset-ID, wrong-owner, dirty-tree, missing-secret, and dry-run
mutation against the release helper; each must refuse before network mutation.

Give only the candidate repository and public docs to two fresh agents:

1. one builds a small adaptive, themed, stateful screen with public APIs; and
2. one diagnoses or extends a bounded behavior through the documented workflow.

Fix failures caused by structure or instructions. The agents must not need the
private archive, Rascal Rally, or conversation history.

## Owner release packet

Produce one short packet with:

- candidate commit, manifest, checksums, repository-size summary, gate result, license
  and provenance results, Package asset ID/revision/receipt, and all remaining
  decisions, plus old/new verification invocation counts, timings, requirement parity,
  and the slowest remaining producers;
- the audited branch, tag, history, Actions, release, issue, wiki, and Pages state;
- the exact copyright-holder line for confirmation if it was not already recorded;
- repository description, topics, default branch, protection/ruleset, security, and
  community-profile settings to apply; and
- an ordered publish-and-rollback checklist. It must include the visibility change,
  verification of license detection and public CI, enabling the free Package listing,
  verifying install/Get Latest, and rechecking protections that GitHub changes or
  disables during a private-to-public conversion.

After approval, make the existing repository public first, then enable the free
Package listing. Tagged source archives or rebuilt `.rbxm` files can also be GitHub
Release assets. All are derived from Git; none becomes a second source of truth.

## Platform sources to recheck at execution

- [Roblox Packages](https://create.roblox.com/docs/projects/assets/packages) — owner,
  `PackageLink`, publishing, Get Latest, AutoUpdate, modified-copy behavior, history,
  and permissions.
- [Open Cloud Assets usage](https://create.roblox.com/docs/cloud/guides/usage-assets)
  — Model create/update, operation polling, supported files, credentials, and the
  warning for files produced outside Studio.
- [Creator Store distribution](https://create.roblox.com/docs/production/creator-store)
  — free listing, public availability, metadata, ownership, and eligibility.

These pages describe current platform behavior; the Studio insertion/update proof is
still required. If the API or Studio behavior differs, update this plan and record the
evidence before mutating the real asset.

## Gate

`distribution-readiness` passes when the existing repository has a minimal and useful
public branch tip, MIT and third-party notices are accurate, a fresh clone works,
public and agent documentation succeeds without private context, the full-history and
remote-surface audits have no unresolved must-purge item, prior gates stay green,
Rascal Rally remains synchronized, the private Package has a stable recorded asset ID
and a proved guarded update path, every living requirement maps to one current
producer, the full suite/unique release producers run once per identity, old/new
mutation verdicts agree, the headless budget is met or every irreducible excess is
owned, and the owner packet is complete. The repository and Creator Store listing
remain private. Pushing Git, changing visibility, enabling the listing, publishing a
GitHub release, deleting remote data, or rewriting remote history are outside this
gate. Creating and updating the one private Package is in scope only after the
explicit owner checkpoint.
