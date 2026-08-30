# Distribution readiness — execution plan

Stage `distribution-readiness` (roadmap Step 14). Opened 2026-08-30 at `27c0afd`
(suite baseline: **7875 passed / 0 failed / 267 s**, `tools/test.sh`).

Binding scope: `docs/plans/distribution-readiness.md` (the owner edited it live at
10:37 on 2026-08-30 — the working-tree version is the one this plan follows) plus the
owner's mid-run correction reproduced verbatim in §0. This file is the execution plan:
what is decided, who does what, in what order, and what proves it. It is internal
maintainer material and goes to the private archive with the rest of `artifacts/`.

## 0. Owner correction (2026-08-30, binding)

> Facet must not be built on Fusion in any way. The current intended architecture is
> already a custom reactive core: `Facet.newCore = customCore.new`, and ADR-0002
> selected `src/core/custom.luau`. The Fusion adapter and vendored Fusion copy are
> rejected bake-off/reference artifacts, not Facet's foundation.
>
> 1. No Facet runtime, Roblox Package, example, skill, public API, or Rascal Rally code
>    may require or depend on Fusion.
> 2. Inspect the generated `build/Facet.rbxm`, not just reachable imports. The current
>    model builder maps all of `src/`, so ensure `src/core/fusion_adapter.luau`,
>    `vendor/Fusion`, and other Fusion-only implementation artifacts do not enter the
>    Package.
> 3. Archive the Fusion adapter, vendored copy, deep comparison, and historical
>    benchmark evidence outside Git before removing them from the public product tree.
>    Move any still-living Facet requirements into neutral tests or architecture
>    documents first.
> 4. Update tests, gates, build mappings, notices, and documentation accordingly. Do not
>    weaken tests for Facet's custom core. Add a hard check that rejects Fusion
>    dependencies from `src/`, generated models, examples, skills, and Rascal Rally.
> 5. The short public Facet/React Luau/Fusion/Vide guide may still describe Fusion as a
>    separate alternative using current primary sources. It must say Facet has its own
>    fine-grained reactive core. Never call Fusion Facet's foundation, core, dependency,
>    or implementation.
> 6. Do not claim comparative speed unless there is an isolated, fair benchmark. Such a
>    benchmark must remain a development-only fixture outside Facet's runtime and
>    Package; otherwise describe the performance models and state that no matched
>    measurement exists.
> 7. Rebuild and inspect the Package, run a fresh-clone consumer, and prove Facet works
>    with no Fusion files available.

The earlier goal text "Facet's Fusion core" is superseded by this. The code agrees:
`src/init.luau` binds `newCore` to `src/core/custom.luau`; `vendor/Fusion/VENDOR.md`
itself says the vendored copy does not ship.

## 1. Facts frozen at stage open

| Item | State |
|---|---|
| Remote | `https://github.com/josha/LuauUI.git`, **private**, viewer `ADMIN`, repo id `1320732857` / `R_kgDOTrjIuQ` |
| Target name | `josha/Facet` — **available** (404 on 2026-08-30) |
| Remote surfaces | branch `main` only; 0 remote tags; 0 releases; 0 Actions runs; 0 issues; wiki off; no Pages; no webhooks; no Actions secrets; sole collaborator `josha`; rulesets/branch protection unavailable on this plan (403) |
| Local | `main` == `origin/main` == `27c0afd`; 1091 commits, one author; local tag `luauui-step8-baseline` (not on remote); packs 234 MB; 1788 tracked files; 14 tracked `examples/places/*.rbxl` (≈50 MB at tip, many historical revisions) |
| Uncommitted user work | `docs/plans/distribution-readiness.md`, `docs/plans/facet-consolidated-roadmap.md` (owner's live edits — preserved, never overwritten by this stage; committed only once the owner stops editing) |
| Toolchain | Lune 0.10.4, Rojo 7.7.0 (rokit), StyLua 2.5.2, Python 3 |
| Gate system | `tools/lune/gate_manifest.luau` 4271 lines, 32 phases, 504 rows; 241 `suite_transcript.sh` greps; 35 `prior_gates.sh` rows; suite ≈267 s; static battery ≈140 s per sweep |
| Open Cloud key | `ROBLOX_API_KEY` (assets read+write) already exists outside Git for `tools/upload_icons.py`; the Package tooling reads a key from the environment only |
| Studio MCP | not connected at stage open — needed for the Package spike after the checkpoint |
| Copyright line | none recorded anywhere in the repo → owner checkpoint item |

## 2. Decisions (Fable tier, made once)

D1. **Private archive** lives at `GameStudio/ui/Facet-private-archive/` — a sibling of
the repo, outside Git, inside the owner's Dropbox. Layout mirrors repo paths;
`MANIFEST.json` (path, sha256, bytes, origin commit) + `SHA256SUMS`. Written by
`tools/archive_private.py`; the public boundary is enforced by
`tools/check_public_allowlist.py` (exact allowlist, selftest that plants a stray file).

D2. **Public allowlist (tip).** Keep: root docs (`README.md LICENSE
THIRD_PARTY_NOTICES.md CHANGELOG.md CONTRIBUTING.md SECURITY.md AGENTS.md`),
`.gitignore rokit.toml run-tests.sh requirements.json`, `src/`, `assets/`,
`examples/` (+ new `examples/consumer/`), `docs/guide/`, `docs/reference/{api,constitution}.md`,
`docs/adr/`, `docs/extending/`, `docs/MAINTAINERS.md`, `docs/lessons/`, `tests/`,
`bench/`, `tools/` (minus `_probe_*`, `_tmp`), `skills/`, `.github/`, `package/`
(manifest + receipts), the verification graph. Archive (remove from tip, keep
history): `docs/plans/`, `docs/handoff/`, `docs/research/`, `docs/INVENTORY.md`,
`docs/reference/{swiftui-parity,fusion-comparison,react-lua-comparison,sponsor-view-parity}.md`,
`artifacts/` (except the frozen flat-render baseline any current producer still reads),
`.superpowers/`, `ui_todo.md`, `sweep.luau`, `vendor/`, `src/core/fusion_adapter.luau`,
`tests/fusion_vendor.spec.luau`, `tests/lib/fusion_*.luau`, `tools/lune/_probe_*.luau`,
`tools/lune/_tmp/`, `phases.json` + `gate_manifest.luau` (replaced by the graph; their
prose is archived). Owner decision: the 14 tracked `.rbxl` places (bulk).

D3. **Fusion excision (§0).** `src/core/imperative.luau` is also a non-shipping bake-off
arm and moves to `bench/cores/imperative.luau` so the Package contains runtime only.
Conformance keeps running against the custom core in every suite run (unchanged) and
against the imperative arm through the bench path. ADR-0002 stays as the decision
record with its evidence links pointing at the archive. `tools/check_no_fusion.py` is
the hard check: scans `src/`, `examples/`, `skills/`, `tests/`, `bench/`, the built
`.rbxmx` scripts, and `games/RascalRally/code/{src,tests}` (when present) for any
`Fusion` require/identifier/path (word-bounded, comments included except a
per-line `-- allow-vendor-name` marker is NOT offered — the name simply must not be
there; the dictionary words `fusion` in `examples/gallery/examples/words/*` are
data, matched only as whole-line entries and excluded structurally); selftest plants a
require and a bare identifier and must fail both.

D4. **Comparison docs.** Exactly one public comparison: `docs/guide/14-choosing-a-ui-library.md`
(Facet, React Luau, Fusion, Vide; pinned versions + research date; FACT / MEASURED /
INFERENCE labels; no status/popularity claims; React Bindings explained; "Facet has
its own fine-grained reactive core"; no relative speed claims — no matched benchmark
exists, say so). `check_brand_drift.py`'s vendor allowlist admits vendor names in this
one file only. The deep SwiftUI report is refreshed privately into the archive.

D5. **Package artifact.** `tools/build_model.sh` is extended, not replaced: the same
Rojo project gains one extra child `Facet.Distribution` (a `Folder` from a generated
staging dir `build/.stage/Distribution/`) carrying attributes `Version`,
`SourceCommit`, `SourceHash`, `BuildSchema = facet-package/1`, `Repository`, and two
`StringValue` children `LICENSE` and `THIRD_PARTY_NOTICES` (from the root files). No
build time in the artifact (reproducibility); time goes in the receipt. A semantic
manifest `build/Facet.manifest.json` lists every instance (path, class, source
sha256) plus version/commit/hash/artifact sha256, from the `.rbxmx` twin. Runtime API
unchanged (`Facet.VERSION` already exists).

D6. **One package interface**: `tools/package.sh {build|status|verify|create|publish|rollback|stamp}`
(thin wrapper over `tools/package.py`). `build/status/verify` are offline and default.
`create`/`publish` are dry-run unless `--confirm`; they require `ROBLOX_API_KEY` from
the environment only (never a file, never printed), a clean tree, `--commit` == HEAD,
`--version` == `Facet.VERSION`, a fresh build whose hash matches, `package/facet-package.json`
creator + asset id set (create refuses when an id exists; publish refuses when it does
not), a green `release` run at the same identity, no in-flight operation, and a cloud
revision not newer than the last receipt. Receipts: `package/receipts/<version>-<sha7>.json`.
`rollback` prints the Studio version-history procedure and never re-uploads.
`tools/release.sh <version> <commit>` is the protected manual release: worktree at the
exact commit → `tools/verify.sh release` → `package.sh publish --confirm` → poll →
read back → receipt (with `studio_verification: pending` until `stamp`). A
`.github/workflows/release.yml` (`workflow_dispatch`, protected environment, refuses
forks) wraps the same command; `ci.yml` runs `tools/verify.sh full` on push/PR.

D7. **Verification graph** replaces the manifest. `tools/verify.sh {affected|fast|full|release} [--gate <phase>] [--explain]`
is the one coordinator. Producers (suite, each scanner, each build, bench, soak/faults/
fuzz, package verify, docs/link checks, RascalRally suite, Studio/perf/device rows as
declared evidence classes) run **at most once per exact identity** — identity =
sha256(normalized inputs content ∥ producer command+options ∥ toolchain pins ∥
environment class ∥ declared fixture inputs). Results are structured JSON under
`artifacts/verify/results/<producer>/<identity>.json` with a body hash; the suite emits
per-case results from `tests/lib/testkit.luau` (`{id, suite, name, status, ms,
error}`, id = `<spec path>::<describe>::<it>`; an optional explicit `id` in `it()`'s
third argument overrides it so human names can change). Rows in `tools/lune/verify/graph.luau`
map `requirement → producer → result ids → gate view`. Every current phase survives as
a view (so `tools/gate.sh <phase>` still answers) but is evaluated from the one run;
`prior_gates.sh` is retired. Reuse is refused for stale identity, truncated/partial
(case count below the registered spec count), failed, wrong toolchain, wrong
environment class, or body-hash mismatch (manual edit). Perf/Studio/device/network
results keep their evidence class and are never upgraded by a headless cache.
Deterministic producers run in parallel (cap = min(4, cores/4)) with isolated temp
dirs; perf, Studio, package mutation, and anything sharing external state are
serialized. Affected tier = producers whose declared inputs match changed paths;
unknown paths → full.

D8. **Result-ID conversion.** The 241 transcript greps become result-id lookups against
the suite result file (a missing id is a loud FAIL — that is the "changed test ID"
mutation). Rows that only pin the state of a historical ledger document (a PASS_*
string in an `artifacts/**/acceptance.md`) are historical: their living requirement is
either already covered by a running producer (mapped, kept) or is a record of a past
decision (archived with the phase prose; listed in the coverage map with the reason).
Nothing is dropped without a row in `artifacts/distribution-readiness/verification/coverage-map.md`
naming requirement, failure direction, fixture, negative control, and the surviving
producer.

D9. **Mutation parity.** The old path (`tools/gate.sh <phase>` from the manifest) stays
runnable until parity is proven, then is archived. Corpus: at least 12 mutations —
broken focus case, unregistered spec (silent zero), truncated suite (simulated
main-thread yield), renamed case, corrupted result file, stale toolchain string,
missing evidence artifact, failed scanner, planted brand drift, planted Fusion require,
dirty-identity cache hit attempt, partial result (case count short). Each must go red
on both paths; recorded with commands.

D10. **Budget.** Release headless run ≤ 20 min on the documented machine (Mac16,11);
cold and warm timings recorded; anything irreducible gets owner/evidence class/cost/
trigger. Studio, device, moderation, network waits reported separately.

D11. **Copyright/MIT.** `LICENSE` is staged with the candidate line
`Copyright (c) 2026 Josh Anon` (the sole commit author's display name) **marked
unconfirmed** in the packet; the gate row `license-copyright-approved` stays PENDING
until the owner confirms the exact line at the checkpoint. Nothing is inferred as legal
identity; the repo stays private meanwhile.

D12. **Owner checkpoint (one batch, end of local work):** copyright line; repo rename
authority (old/new URL, credential, rollback); Package creator type/id, display name,
description, private creation approval, listing intent; credential scope
(`ROBLOX_API_KEY` env, assets read+write, IP allowlist); the `.rbxl` bulk decision;
committing the owner's two plan edits; the Fusion-archive confirmation; SwiftUI history
stays (no rewrite). Until then: no push, no rename, no asset creation, no visibility
change.

## 3. Workstreams and ownership (disjoint files; commit per completion with `tools/commit_isolated.py`)

| ID | Work | Owner | Owns (paths) |
|---|---|---|---|
| A | Register gate rows (PENDING), freeze state, this plan | director | `phases.json`, `gate_manifest.luau` (registration block only), `artifacts/distribution-readiness/{execution-plan,freeze}.md` |
| B | Full-history + remote privacy/provenance/bulk audit; THIRD_PARTY_NOTICES draft | Opus (running) | `artifacts/distribution-readiness/audit/` |
| R | Platform doc research (Open Cloud Assets, Packages, Creator Store, GitHub rename) | Sonnet (running) | `artifacts/distribution-readiness/research/platform-sources.md` |
| K | Fusion excision (§0): archive, remove, `check_no_fusion.py`, bench/conformance/doctor/boundary updates, comment rewrites | Opus | `src/core/{fusion_adapter,imperative,README}`, `vendor/`, `bench/`, `tests/conformance/`, `tests/fusion_vendor.spec.luau`, `tests/lib/fusion_*`, `tools/doctor.sh`, `tools/lune/check_boundary.luau`, `tools/lune/check_scenario_requires.luau`, `tools/lune/studio_sync.luau`, `tools/check_no_fusion.py`, `tools/archive_private.py` (first version), comment lines naming Fusion in `src/`, `tests/`, `examples/`, RascalRally tests |
| E1 | SwiftUI report refresh → archive; migrate the 40 references to living public sources; remove the tracked copy and links | Opus | `docs/reference/swiftui-parity.md` (delete), reference lines in `src/`, `tests/`, `tools/lune/check_docs.luau`, `tools/check_brand_drift.py`, `tools/lune/check_flat_baseline.luau`, `tools/lune/triage_overflow_waivers.luau`, `tests/lib/tiers.luau`, `docs/MAINTAINERS.md`, `docs/INVENTORY.md`, `docs/adr/ADR-0035`, `docs/lessons/*`, `docs/plans/*` (links only) |
| E2 | Public framework-choice guide from primary sources | Opus | `docs/guide/14-choosing-a-ui-library.md`, `check_brand_drift.py` vendor allowlist entry for that file only |
| D | Package channel: `build_model.sh` extension, manifest, `package.py/.sh`, receipts, `release.sh`, `.github/workflows/release.yml`, packaged-consumer canary, refusal tests | Opus | `tools/build_model.sh`, `tools/package.*`, `tools/release.sh`, `package/`, `tools/lune/package_canary.luau`, `tests/package_tooling.spec.luau`, `.github/workflows/release.yml` |
| F | Public docs + root files + `AGENTS.md` + `skills/use-facet/SKILL.md` + `examples/consumer/` + `.github/` CI/templates + link checker | Opus | `README.md`, `LICENSE`, `THIRD_PARTY_NOTICES.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`, `AGENTS.md`, `skills/`, `docs/guide/**` (except 14), `docs/reference/api.md` (Package/install sections + link fixes), `docs/extending/**`, `docs/MAINTAINERS.md` (sections 3–4 only, after E1), `examples/consumer/`, `.github/{workflows/ci.yml,PULL_REQUEST_TEMPLATE.md,ISSUE_TEMPLATE/}`, `tools/lune/check_links.luau` |
| T | Verification graph, structured results, identity, coordinator, tiers, manifest conversion, mutation parity, budget, prior-gates retirement | Opus (long-lived) | `tests/lib/testkit.luau`, `tests/run*.luau` (runner tail), `tools/verify.sh`, `tools/lune/verify/**`, `tools/gate.sh`, `tools/test.sh`, `tools/suite_transcript.sh`, `tools/prior_gates.sh`, `tools/lune/gate*.luau`, `tools/check_manifest_integrity.py`, `artifacts/distribution-readiness/verification/` |
| C | Allowlist check + archival execution + link repair (after K/E1/E2/D/F/T land) | director + Opus | `tools/check_public_allowlist.py`, `distribution/allowlist.txt`, the archive |
| V | Candidate commit, reproducibility (tree built twice), fresh clone, guard mutations, RascalRally sync, place rebuilds, 3 fresh-agent proofs, RED-TEAM, owner packet, gate exit 0 | director + fresh agents | `artifacts/distribution-readiness/{verification,packet}/` |
| P | After checkpoint: rename, Package spike, create, Studio proof, same-ID update, AutoUpdate/modified-copy proof, receipt | director (Studio MCP + owner) | `package/`, receipts, packet |

Order: A → {B, R, K, E1, E2, D, F, T in parallel} → C → V → checkpoint → P.

## 4. Acceptance rows (registered in the gate; all PENDING at registration)

See `tools/lune/gate_manifest.luau["distribution-readiness"]` — 34 rows: DR-1 registration-before-work,
DR-2 freeze, DR-3 history audit no must-purge, DR-4 provenance + notices, DR-5 license
root files, DR-6 public allowlist + archive checksums, DR-7 no-Fusion hard check +
Package inspection, DR-8 SwiftUI report archived + links removed + living contracts
moved, DR-9 framework-choice guide checks, DR-10 README/guide/API/install docs refreshed
+ stale-link scan, DR-11 `AGENTS.md` + skill route without duplication, DR-12
standalone consumer proof, DR-13 package build metadata + semantic manifest, DR-14
package interface refusals (stale source, wrong asset id, wrong owner, dirty tree,
missing secret, dry-run), DR-15 release command guarded, DR-16 structured results +
result-id lookups, DR-17 exact-identity single execution, DR-18 invalidation rejects
stale/partial/edited, DR-19 tiers + explain output, DR-20 coverage map (no silent
loss), DR-21 mutation parity old/new, DR-22 timings + budget, DR-23 prior-gates
reevaluation replaces replay, DR-24 RascalRally once per identity + sync ledger, DR-25
reproducible public tree twice, DR-26 fresh clone works (no parent-workspace imports),
DR-27 example places rebuilt from the clone, DR-28 Package built from the clone matches,
DR-29 fresh-agent builds a screen, DR-30 fresh-agent extends/diagnoses, DR-31 fresh
reviewer chooses from the guide, DR-32 owner packet complete, DR-33 private Package id
+ same-id update + AutoUpdate/modified-copy proof (after checkpoint), DR-34 repository
rename verified (after checkpoint).
