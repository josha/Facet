# Workstream D — the Roblox Package release channel

Built 2026-08-30 against `docs/plans/distribution-readiness.md` § "Roblox Package
release channel" and `artifacts/distribution-readiness/execution-plan.md` §2 D5,
D6, plus the coordinator's route addendum. **No cloud call was made in this
workstream.** Every network path is implemented in full and was exercised only
against an injected fake transport or in dry run.

Facts about the platform are cited from
`artifacts/distribution-readiness/research/platform-sources.md` (fetched
2026-08-30) and are labelled where they change a design decision.

---

## 1. What was built

| Path | What |
|---|---|
| `tools/build_model.sh` | **extended**, not replaced — the same single Rojo mapping, plus one named child, the `.rbxmx` twin, the manifest, and an opt-in publisher place |
| `tools/package.py` | the program: build, status, verify, create, publish, rollback, stamp, identity, stage, manifest, `--selftest`. Standard library only |
| `tools/package.sh` | a four-line wrapper over it |
| `tools/release.sh` | the protected manual release: worktree at an exact commit → gate → publish → receipt → checklist |
| `tools/lune/package_canary.luau` | the packaged-consumer canary |
| `package/facet-package.json` | non-secret config; `creator` and `assetId` are `null` until the owner checkpoint |
| `package/README.md` | the maintainer interface reference |
| `package/receipts/.gitkeep` | where receipts land; none exist, because nothing has been published |
| `.github/workflows/release.yml` | `workflow_dispatch` only, protected `release` environment, refuses forks and non-owner actors |

`.gitignore` needed no edit: it already ignores `build/`, which covers
`build/.stage/` (the generated distribution metadata) and `build/.canary/` (the
canary's extraction directory). Confirmed with `git check-ignore -v`.

### The artifact

One `ModuleScript` named `Facet`, 29 root children, of which 28 are the shipped
`src/` tree and one is `Distribution`:

```
Facet (ModuleScript)
├── Distribution (Folder)
│   ├── @Version, @SourceCommit, @SourceHash, @BuildSchema, @Repository
│   ├── LICENSE (StringValue, 1066 chars — the root LICENSE verbatim)
│   └── THIRD_PARTY_NOTICES (StringValue, 15410 chars)
├── async/ client/ controls/ core/ env/ focus/ input/ layout/ motion/
├── present/ preview/ render/ replication/ themes/ tokens/   (15 Folders)
└── blueprint, blueprint_schema, class_contract, measure, mount, num, paths,
    rect, region_expand, row_capability, spec_guard, text_distance,
    virtual_extents                                          (leaf ModuleScripts)
```

Read back from the built `.rbxmx` under Lune: root is `Facet`/`ModuleScript`;
`Distribution` is a `Folder` whose five attributes survive serialization intact
(`Version 0.10.0`, `BuildSchema facet-package/1`, the commit, the source hash,
the repository URL); both `StringValue` children are non-empty.

`check_library_purity.py` still passes: it looks for scripts, and a `StringValue`
is not a script.

---

## 2. Determinism — **Rojo output IS byte-deterministic here**

Measured on Rojo 7.7.0 (rokit-pinned), Lune 0.10.4, macOS.

| Measurement | Result |
|---|---|
| Three consecutive builds of one tree, `.rbxm` | identical sha256 (`7a248fd1…` ×3 at `558470b0`; re-measured at final HEAD `5d55cfb`, `ae7b54e9…` ×3) |
| Three consecutive builds, `.rbxmx` | identical sha256 (`73a91470…` ×3), and `cmp` reports no difference |
| Manifest `bodyHash` across builds | identical |
| Same measurement **before** the `Distribution` child existed | also identical — the staging directory did not introduce nondeterminism |

The one thing that moves between builds is the input that is *supposed* to move.
A rebuild after HEAD advanced differed at exactly one place — byte 5,185,547, the
base64 `AttributesSerialize` blob — and the decoded difference was the
`SourceCommit` attribute (`558470b0…-dirty` → `bb9944bd…-dirty`) and nothing
else. The attribute blob itself serializes keys in sorted order, so it is stable.

Two consequences:

- **No build time is in the artifact.** That is what makes the above true, and it
  is why the time of a release lives in the receipt instead.
- **The manifest is still the comparison basis for the build-drift guard.**
  `artifactSha256` would work today; `bodyHash` — a sha256 over the sorted
  instance list with per-script source hashes — is used because it is over the
  *semantic* content, so it survives a future Rojo that reorders referents, and
  because it is the number a human can act on when a build drifts. Both are
  recorded in the manifest.

---

## 3. Tree inspection

`tools/package.sh verify` asks two questions of the built model, and both have to
be asked. Present: every shipped `src/**/*.luau` exists as a `ModuleScript` at
its expected path, and every intermediate directory as a `Folder`. Absent:
nothing else is in the model at all, and nothing whose path contains `tests`,
`examples`, `vendor`, `bench`, `spikes`, `fusion_adapter`, `imperative` or
`.spec` is in it by name.

At HEAD `f092312`:

```
[ ok ] build: 189 instances, 171 modules
[ ok ] tree inspection: 171 modules and 15 folders present, nothing else
```

189 = 171 ModuleScripts + 16 Folders (15 from `src/` plus `Distribution`) + 2
StringValues.

**Proven to bite**, by planting a `fusion_adapter` ModuleScript directly into
`build/Facet.rbxmx` and rebuilding the manifest from the tampered file:

```
- UNEXPECTED instance in the model: Facet/fusion_adapter (ModuleScript)
- FORBIDDEN in the distribution: Facet/fusion_adapter (contains 'fusion_adapter')
```

…and in the other direction, by deleting one instance from the manifest and
downgrading another's class:

```
- missing from the model: Facet/env/environment (from src/env/environment.luau)
- Facet/mount is a Folder, not a ModuleScript
```

The same planted model reddens the canary:

```
package_canary: FAIL (1 problem(s))
  - the extracted tree ships no vendor / fusion_adapter / imperative / spec file
```

A note on timing: workstream K's removal of `src/core/fusion_adapter.luau`,
`src/core/imperative.luau` and `vendor/` landed while this workstream was in
flight (the module count fell 173 → 171 mid-session). The forbidden-name rule was
written to fail on them and would have failed had they still been present; it now
passes because they are gone, which is the correct reading of the same check.

---

## 4. Commands run, with their result lines

All at HEAD `f092312` (working tree dirty — several workstreams are active in it).
The whole battery was re-run at the final HEAD `5d55cfb` with identical verdicts:
selftest PASS, build 189/171, verify PASS on all five rows, create 6 refusals,
publish 7 refusals, `stylua --check tools` clean.

| Command | Result |
|---|---|
| `python3 tools/package.py --selftest` | **PASS**, exit 0 — 21 mutation cases over 18 refusal codes, every one biting exactly its own refusal and nothing else; 0 wrong; both all-good fact sets clean |
| `tools/package.sh stamp` | exit 0 — wrote `studio_verification` `{status: verified, by, date, notes}` onto a temp receipt; exit 1 without `--studio-verified` |
| `tools/package.sh identity` | exit 0 — the sha256 the gate-evidence guard compares against |
| `tools/package.sh build` | exit 0 — 189 instances, 171 modules, body `e6729c0e414f…`, artifact `3b1f9323…` |
| `tools/package.sh verify` | **PASS**, exit 0 — build ok, tree inspection ok, notices ok, purity ok, canary ok |
| `tools/package.sh status` | exit 0 — version 0.10.0, commit `f092312…-dirty`, assetId unset, tree DIRTY, no receipts, CHANGELOG.md mentions 0.10.0, gate evidence absent |
| `tools/package.sh create` (dry run) | exit 0, **6 refusals**, no network |
| `tools/package.sh publish` (dry run) | exit 0, **7 refusals**, no network |
| `tools/package.sh rollback` | exit 0 — printed both procedures, uploaded nothing |
| `tools/build_model.sh --publisher` | exit 0 — `build/FacetPublisher.rbxl`; read back under Lune, `ReplicatedStorage.Facet` is the ModuleScript with `Distribution.Version = 0.10.0` |
| `tools/release.sh` × 5 | refused each precondition: no args → exit 2; unknown commit → exit 1; dirty tree → exit 1; clean clone with no key → exit 1; clean clone with a key but no assetId → exit 1 |
| `stylua --check tools` | clean |

### The dry-run refusals, verbatim

`create`:

```
- api-key-missing: ROBLOX_API_KEY is not set in the environment. It is read from the
  environment ONLY — never a keys file, never a cookie — and it is never printed or
  written to a receipt.
- dirty-tree: the working tree has uncommitted changes; a release must be an exact commit
- commit-mismatch: --commit <sha> is required and must equal HEAD
- version-mismatch: --version <x.y.z> is required and must equal Facet.VERSION
- creator-unset: package/facet-package.json has no creator; it is filled at the owner checkpoint
- gate-evidence-missing: no release-gate evidence at artifacts/verify/latest-release.json;
  the release tier must run first
```

`publish` adds:

```
- asset-id-missing: package/facet-package.json records no assetId; run create first
```

Both printed the exact request that would be sent — for the studio route, the
read-back `GET`; with `--route open-cloud`, the full `POST /v1/assets` multipart
with the `request` JSON shown and the file part named, sized and hashed but never
dumped. The `x-api-key` header prints as `<redacted — never printed>` in every
path.

### The canary's own result lines

```
[ ok ] the model's one root is named Facet (read Facet)
[ ok ] the root is a ModuleScript (read ModuleScript)
       extracted 171 script(s) to build/.canary/Facet
[ ok ] the extracted tree ships no vendor / fusion_adapter / imperative / spec file
[ ok ] Facet.Distribution is a Folder (read Folder)
[ ok ] Distribution.BuildSchema is facet-package/1 (read facet-package/1)
[ ok ] Facet.Distribution.LICENSE is a non-empty StringValue
[ ok ] Facet.Distribution.THIRD_PARTY_NOTICES is a non-empty StringValue
[ ok ] the packaged Facet.VERSION (0.10.0) equals Distribution.Version (0.10.0)
[ ok ] the screen mounts: Text and Button both exist
[ ok ] a theme applies and reaches paint AND geometry: textSize 16 -> 30, height 20 -> 36
[ ok ] the button fires through the presenter's input path (taps = 1)
[ ok ] a signal update reaches the rendered text (read Changed)
[ ok ] a viewport change re-solves the surface (390 -> 1180 wide)
[ ok ] a preferred-text change re-reserves the type (36 -> 72 tall)
[ ok ] lap 1..3: live instances return to 0; core observers/scopes return to 3/0
```

Two measurement notes worth keeping, because both cost a round:

- **A hugging child does not follow the window.** The first viewport assertion
  measured the `Text`, which hugs its content inside a `VStack`, and read 70 → 70
  across a 390 → 1180 change. The surface is what follows the viewport; the
  assertion moved to `/Canary`.
- **`preferredTextSize` is a multiplicative reservation, not a paint value.** The
  engine applies the player's preference as an additive px offset at draw time
  (`src/themes/snapshot.luau`: "folding the preference in here is the
  double-application defect"), so `textSize` on the node does not move and the
  honest observable is the reserved height (36 → 72 at a factor of 2). It is also
  a number, not the enum name a first attempt passed.

---

## 5. Two routes, one interface

The coordinator's addendum, grounded in the research note, changed one thing: the
Open Cloud **update** path is not documented for our file type, so it cannot be
the default.

- FACT — the Assets API supported-types table, Model row: "Will be uploaded as
  packages." This one sentence is the entire documented bridge between Open Cloud
  and Studio's Package system (research note §1.3, §2.6).
- FACT — the same usage guide: "Currently, you can only update the asset content
  for `.fbx` files." Facet's artifact is an `.rbxm` (§1.4).
- FACT — twice in the same table: "`.rbxm` or `.rbxmx` files edited outside of
  Roblox Studio might not upload or function" (§1.3).
- FACT — `packages.md` never mentions Open Cloud, HTTP, or any non-Studio upload
  path at all (§2.6).

So `route` in `package/facet-package.json` selects between:

- **`studio` (the default)** — build `build/FacetPublisher.rbxl` from the artifact
  itself, print the exact Convert-to-Package / Publish-to-Package steps, and use
  the API only for what it *is* documented for: `GET /v1/assets/{id}` to verify
  the id a human hands back on create, and `GET /v1/assets/{id}/versions` polled
  until a version newer than the last receipt appears on publish.
- **`open-cloud`** — `POST /v1/assets` and `PATCH /v1/assets/{id}`, both multipart
  `request` + `fileContent`, both polling `GET /v1/operations/{id}` with 1→15 s
  backoff. Implemented in full, switched on the day the spike proves it.

The publisher place is **not** a second model source: its Rojo project's tree is
`ReplicatedStorage/Facet: {"$path": "build/Facet.rbxm"}`, so it consumes the
built artifact. It is emitted by `tools/build_model.sh --publisher`, which keeps
every Rojo project for the distribution in one file.

`rollback` prints both mechanisms and uploads nothing: the Studio Versions-tab
restore, and the dry-run form of `POST /v1/assets/{id}/versions:rollback` with its
`assetVersion` part, scopes and rate limit. It says plainly that the two version
sequences are not proved to be the same sequence.

---

## 6. The guards

One pure function, `decide(facts) -> [Refusal]`, that reads no file, makes no
call and prints nothing. That is what makes every refusal testable in
milliseconds without a network. 18 codes:

`api-key-missing`, `dirty-tree`, `commit-mismatch`, `version-mismatch`,
`build-drift`, `creator-unset`, `creator-mismatch`, `asset-id-present`,
`asset-id-missing`, `asset-id-mismatch`, `gate-evidence-missing`,
`gate-evidence-failed`, `gate-identity-mismatch`, `operation-in-flight`,
`cloud-revision-newer`, `version-not-advanced`, `version-hash-conflict`,
`moderation-not-approved`.

`--selftest` builds an all-good fact set per operation, asserts it produces no
refusal, then mutates exactly one key at a time and asserts the result is
**exactly** the expected refusal — a mutation that fired for a second reason is a
failure, not a pass. 21 cases, 0 wrong.

The end-to-end fake-transport test runs in two passes, and the first is the
important one:

- **Pass A** runs `create --confirm` with the *real* guards against whatever
  state the working tree is in and asserts the transport was **never touched**.
  That is the proof that guards run *before* the call rather than beside it.
- **Pass B** injects a decider that returns no refusal — the same injection seam
  as the transport — and drives the request path: `POST` → operation pending →
  operation done → assetId 424242 written into a **temporary** config, then
  `PATCH` → operation done → a receipt at revision 2 in a temporary receipts
  directory. The test then asserts the real `package/facet-package.json` still
  records no assetId, and that the API key string appears nowhere in the receipt.

The fake serves the proto-style spellings on purpose (`ASSET_TYPE_MODEL`,
`MODERATION_STATE_APPROVED`). The docs contradict themselves here — the schema
table says `Model` / `Approved`, the usage guide's worked example returns the
prefixed constants, and the research note does not reconcile them (§1.6) — so the
moderation guard accepts both spellings and the asset-type read-back matches on a
substring rather than equality.

### Secret handling

`ROBLOX_API_KEY` is read from `os.environ` in exactly one function and nowhere
else. No keys file is consulted, no cookie is accepted, no argument carries it.
It is never printed (the dry run shows `x-api-key: <redacted — never printed>`),
never written to a receipt (asserted by the selftest), and never logged. The only
statement the tool makes about it is whether it is set.

### The gate-evidence contract

The verification coordinator (D7) is another workstream and its artifact does not
exist yet, so this channel **defines the shape and fails closed**:
`artifacts/verify/latest-release.json`, `{schema: "facet-verify-run/1", tier,
status, identity, commit, version, sourceHash, completedAt}`, with `status ==
"PASS"` and `identity` equal to this release's identity. Identity is published as
a command — `tools/package.sh identity` prints
`sha256("facet-release-gate/1|" + version + "|" + commit + "|" + sourceHash)` —
so the coordinator stamps the same string rather than guessing at it. At HEAD
`f092312` the file is absent and both `create` and `publish` refuse, which is the
intended state.

---

## 7. Open questions for the Studio spike

These are the questions the documentation does not answer and a live session
must. They are exactly the questions that decide whether `route` can move from
`studio` to `open-cloud`, and they are drawn from the research note's own §2.6
and §7.

1. **Does a Model created by `POST /v1/assets` carry a `PackageLink` when
   inserted?** The only documented bridge is "Will be uploaded as packages"
   (§1.3). `packages.md` describes package creation exclusively as the Studio
   Convert-to-Package action and never mentions Open Cloud (§2.6). Insert the
   POST-created asset into a clean place and look for a `PackageLink` child with
   a `PackageId`, a `VersionNumber` and a `Status`.
2. **Does a `.rbxm` `PATCH` to an existing Model asset succeed at all?** The
   usage guide says content updates currently work for `.fbx` only (§1.4), and
   Roblox separately warns that `.rbxm` files edited outside Studio "might not
   upload or function" (§1.3). If it succeeds, record the returned operation and
   the resulting `revisionId`; if it fails, record the status and body, because
   that is the fact that keeps the studio route as the default.
3. **Does a Studio "Publish to Package" show up in `GET /v1/assets/{id}/versions`?**
   The studio publish route polls that list to detect the human's publish and
   write the receipt from it. If Studio publishes do not appear there, the studio
   route needs a different completion signal and the receipt loses its
   `assetRevision`.
4. **Are Package versions and Asset revisions the same sequence?** `rollback`
   prints two mechanisms — Studio's Versions-tab restore and Open Cloud's
   `versions:rollback` — and currently tells the reader to roll back on the route
   they published on, because nothing documents that the two operate on one
   sequence (§1.7, §2.4).
5. **Does an Open-Cloud-authored revision reach an `AutoUpdate` copy?** The
   documented Studio behavior is that `AutoUpdate` is opt-in per `PackageLink`,
   that the game "periodically checks for new updates while a place is open", and
   that a locally modified copy has `AutoUpdate` disabled and is *skipped* by
   mass updates rather than overwritten (§2.3). Whether an Open-Cloud revision
   participates in that mechanism is undocumented in both directions.
6. **What are the live wire formats for `assetType` and `moderationState`?** The
   schema table and the worked example disagree (§1.6). The tool accepts both
   today; the spike should record which one the API actually returns so a later
   reader is not left with a defensive guess.

Two smaller ones, recorded so they are not rediscovered:

- **Ownership is irreversible.** "Ownership transfers are not supported by the
  asset system, so carefully consider the owner when creating a package" (§2.1).
  `creator.type` / `creator.id` is therefore an owner-checkpoint decision, and a
  dry run prints `<unset — owner checkpoint>` rather than defaulting.
- **`InsertService:LoadLocalAsset` does not exist** in the current engine
  reference (§6). Any verification plan that assumed a local-asset insertion path
  needs `InsertService:LoadAsset` (owned assets) or the Toolbox instead.

---

## 8. Boundaries kept

- One Rojo mapping for the distribution, in `tools/build_model.sh`, extended
  rather than replaced. The publisher place's project is emitted by the same
  script and consumes the built `.rbxm`.
- `tools/build_model.sh [output]` still works exactly as before, and
  `check_library_purity.py` — which calls it with a temporary `.rbxmx` — still
  passes.
- No file outside this workstream's ownership was edited. `src/**`,
  `tests/lib/testkit.luau`, `tests/run.luau`, `tools/test.sh`,
  `tools/lune/gate_manifest.luau`, `phases.json`, `README.md` and `docs/**` were
  read but never written.
- Gate rows DR-13, DR-14 and DR-15 in `tools/lune/gate_manifest.luau` describe
  this work and remain `PENDING`; that file belongs to another workstream and was
  not touched.
- Nothing was pushed.
