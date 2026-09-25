# The Facet Package release channel: maintainer reference

Facet ships as **one** official Roblox Package with a stable asset ID. This
directory holds the non-secret configuration for that package and the receipt
of each publish. This document is for maintainers. A consumer does not need to
read it.

Git is canonical. The tool derives each fact about a release from the
repository:

- the version from `src/init.luau`,
- the commit from `git rev-parse HEAD`,
- the source hash from the `src/**/*.luau` tree.

The tool checks each number that a person types against the repository before
it sends anything.

**No asset exists yet.** `assetId` and `creator` in `facet-package.json` are
`null`. They stay `null` until the owner checkpoint. `create` and `publish` are
fully implemented. Until then, they refuse to run.

---

## The commands

```
tools/package.sh build      rebuild build/Facet.rbxm + build/Facet.manifest.json
tools/package.sh status     this tree against the last receipt
tools/package.sh verify     build + tree inspection + purity + packaged canary
tools/package.sh create     mint the asset       (DRY RUN unless --confirm)
tools/package.sh publish    push a new revision  (DRY RUN unless --confirm)
tools/package.sh rollback   print both rollback procedures; never uploads
tools/package.sh stamp      record a Studio verification on a receipt
```

`tools/package.sh` is a wrapper. The program is `tools/package.py`. It uses only
the Python standard library.

**`build`, `status` and `verify` are offline.** They are the everyday commands.
They contact nothing and need no credential.

The verdict table prints three states:

- `[REFUSE]`: the guard failed.
- `[  ok  ]`: the guard compared and passed.
- `[ n/a  ]`: the guard had nothing to compare. Examples are a publish-only
  guard under `create`, a receipt comparison with no receipt, and a moderation
  state that nobody has read yet.

A guard that did not run never looks like a guard that passed.

**`create` and `publish` are dry runs by default.** A dry run prints the exact
request that it would send: the method, the URL, the multipart field names and
the request JSON. It names the file part with its size and hash, but never
prints its contents. It also prints the verdict of each guard. Then it exits
with 0 and does not use the network. Only `--confirm` sends a request, and
`--confirm` is refused unless every guard passes.

### build

`build` runs `tools/build_model.sh`. This script is the **only** Rojo mapping for
the distribution. Keep it the only one. It makes these files:

- `build/Facet.rbxm`: the artifact. It is one `ModuleScript` named `Facet`
  with the whole shipped `src/` tree under it.
- `build/Facet.rbxmx`: the same tree as XML. A binary `.rbxm` is LZ4-chunked,
  and no tool can read its scripts as text.
- `build/Facet.manifest.json`: the semantic manifest (see below).
- `build/.stage/Distribution/`: the generated release metadata. Each build
  makes it again. Do not edit it by hand.

`build/` is in `.gitignore`. Nothing in it is committed.

`tools/build_model.sh --publisher` also builds `build/FacetPublisher.rbxl`, the
canonical publisher place. In this place, `ReplicatedStorage.Facet` is the
artifact that the same build made. The script uses the built model. It does not
map `src/` a second time.

### What travels inside the Package

`Facet.Distribution` is a `Folder` child of the root module. It has five
attributes and two `StringValue` children.

| Attribute | Value |
|---|---|
| `Version` | `Facet.VERSION` from `src/init.luau` |
| `SourceCommit` | `git rev-parse HEAD`, with the suffix `-dirty` when `git status --porcelain -- src` is not empty |
| `SourceHash` | sha256 over the sorted shipped source (see below) |
| `BuildSchema` | `facet-package/1` |
| `Repository` | `https://github.com/josha/Facet` |

| Child | Value |
|---|---|
| `LICENSE` | the root `LICENSE` file, unchanged |
| `THIRD_PARTY_NOTICES` | the root `THIRD_PARTY_NOTICES.md`, unchanged |

The artifact deliberately contains **no build time**. Two builds of one commit
must make the same bytes. The receipt records the time of a release. Measured
on Rojo 7.7.0, three consecutive builds of one tree make byte-identical `.rbxm`
and `.rbxmx` files. Between commits, only the `SourceCommit` attribute changes.

`SourceHash` is sha256 over the sorted list of `src/**/*.luau`. It excludes
`*.spec.luau`, because the model does not ship those files. For each file, the
hash reads `<relpath>\n` and then the bytes of the file, with CRLF changed to
LF. Because the path comes before the content, a rename changes the hash even
when no code changes. This is correct, because a rename moves an instance in
the shipped tree.

### The manifest

The tool reads `build/Facet.manifest.json` from the `.rbxmx` twin:

```json
{
  "schema": "facet-package-manifest/1",
  "version": "0.12.0",
  "sourceCommit": "<sha>[-dirty]",
  "sourceHash": "<sha256>",
  "artifact": "build/Facet.rbxm",
  "artifactSha256": "<sha256>",
  "instanceCount": 110,
  "moduleCount": 99,
  "bodyHash": "<sha256 over the instance list>",
  "instances": [ { "path": "Facet/ui/inputs", "className": "ModuleScript", "sourceSha256": "…" }, … ]
}
```

`bodyHash` is the comparison basis for the build-drift guard. Rojo is
byte-deterministic here, so `artifactSha256` can also do this work. But the body
hash covers the *semantic* content. Thus it survives a future Rojo that
reorders referents. It is also the number that a person can reason about when a
build drifts.

### status

`status` builds again. Then it compares the version, commit, source hash and
artifact hash with the newest receipt. It reports:

- whether the source changed since the last publish,
- whether the tree is dirty,
- whether `VERSION` advanced under semver,
- whether `CHANGELOG.md` mentions the version,
- whether the release-gate evidence attests this exact tree.

### verify

`verify` builds, and then runs four checks:

1. **Tree inspection.** Every shipped `src/**/*.luau` must be a `ModuleScript`
   at the expected path. Every intermediate directory must be a `Folder`.
   `Facet/Distribution` and its two `StringValue` children must be present. The
   release metadata and the MIT text are required. *Nothing else* can be in
   the model. Anything unexpected fails. A path with the segment `tests`,
   `examples`, `vendor`, `bench` or `spikes` fails by name. The exception is
   the approved Compose vendor paths that `src/vendor/compose/UPSTREAM.lock`
   lists. A path that contains `fusion_adapter`, `imperative` or `.spec` also
   fails by name.
2. **Distribution notices.** The check reports if `LICENSE` or
   `THIRD_PARTY_NOTICES` fell back to placeholder text.
3. **`tools/check_library_purity.py`.** The shipped library must not name a
   reference theme package in code.
4. **The packaged-consumer canary** (`tools/lune/package_canary.luau`). The
   canary extracts every ModuleScript from `build/Facet.rbxmx` into a directory
   tree. It checks these items:
   - The model has one root, a `ModuleScript` named `Facet`.
   - Every instance name is a usable, unique, single path segment.
   - The extracted tree ships only approved Compose vendor files, and no
     rejected core or spec file.
   - The packaged `Facet.VERSION` equals the `Version` attribute on
     `Facet.Distribution`. A manifest built from source cannot check this,
     because Roblox serializes attributes to a binary blob.

   Then the canary `require`s the extracted tree and mounts a real screen
   through a native runtime three times. Each lap checks these items:
   - The native control tree mounts.
   - Native activation reaches the callback.
   - Compose updates native text.
   - The native theme rules are linked.
   - After the mount stops, the owned scene is removed and the owned input
     connection is released.

### The two routes

`route` in `facet-package.json` selects how the tool mints and updates the
asset. There are two routes because the platform documentation supports the
create half of the API path but not the update half. See *Why two routes*
below.

|  | `studio` (default) | `open-cloud` |
|---|---|---|
| create | Build the publisher place, print the Convert-to-Package steps, then `GET /v1/assets/{id}` to verify the id that a person gives back. | `POST /v1/assets` (multipart `request` + `fileContent`), poll `GET /v1/operations/{id}`. |
| publish | Read the current version number of the asset, build the publisher place again, print the Publish-to-Package steps, then poll `GET /v1/assets/{id}/versions` until the number differs from that pre-publish baseline. | `PATCH /v1/assets/{id}`, poll `GET /v1/operations/{id}`. |
| read-back | `GET` the asset and the latest version, recorded in the receipt. | The same. |

Both routes run **the same guards before they print an instruction or make a
call.**

The configured route is a recorded decision, not a default. `--route` can
override it for one invocation, but only together with `--allow-route-override`.
Otherwise the run refuses with `route-override`. `tools/release.sh` forwards its
trailing arguments to `package.sh`. Without that guard, a bare
`--route open-cloud` could arrive from two layers away and change an approved
Studio release into an unapproved `PATCH`.

On the studio route, the tool reads the baseline **before** it prints the
manual steps. It records a release only on a positive change from that
baseline. A comparison with the last receipt was wrong: on a first publish,
with no receipts, it accepted the version already on the asset and recorded a
release that did not occur. If the tool cannot read the version list, it
refuses and asks for `--baseline-revision <n>`. It does not guess.

### rollback

`rollback` prints the procedures. It never uploads. An upload of an old tree
would mint a *new* revision with old contents, and the version history would
be false. Both real mechanisms select an *existing* version:

- **Studio:** Package Options → Package Details → Versions tab → select the
  checkmark of the version → Submit. A restore does not reset the package
  attributes.
- **Open Cloud:** `POST /v1/assets/{id}/versions:rollback` with a multipart
  `assetVersion` of `assets/{id}/versions/{n}`.

Nobody has proved that the two sequences are the same. Until the Studio spike
answers that question, roll back on the route that published the version.

### stamp

```
tools/package.sh stamp --receipt package/receipts/<file>.json \
    --studio-verified --by "<who>" --notes "<what you saw>"
```

The tool writes each receipt with `studio_verification.status = "pending"`. A
person opens Studio, inserts the package by ID, checks it and stamps the
receipt. Nothing automates this step, because no automation can do it.

---

## The guards

Each refusal below is a case in `decide(facts)`. This is one pure function. It
reads no file, makes no call and prints nothing. Thus a test proves each
refusal in milliseconds, without the network
(`python3 tools/package.py --selftest`).

| Code | Refuses when |
|---|---|
| `api-key-missing` | `ROBLOX_API_KEY` is not in the environment |
| `dirty-tree` | `git status --porcelain` is not empty |
| `commit-mismatch` | `--commit` is absent or is not `HEAD` |
| `version-mismatch` | `--version` is absent or is not `Facet.VERSION` |
| `build-drift` | there is no `build/Facet.manifest.json`, or the body hash of a fresh build differs from the recorded one |
| `creator-unset` | `facet-package.json` has no creator |
| `creator-mismatch` | `--creator-id` or `--creator-type` disagrees with the config |
| `asset-id-present` | `create` runs when an `assetId` already exists |
| `asset-id-missing` | `publish` runs when no `assetId` exists |
| `asset-id-mismatch` | `--asset-id` disagrees with the config |
| `route-override` | `--route` disagrees with the configured route and `--allow-route-override` is absent |
| `gate-evidence-missing` | `artifacts/verify/latest-release.json` is absent or unreadable, or has no `gateEvidence` |
| `gate-evidence-schema` | the evidence declares a different schema |
| `gate-evidence-tier` | the evidence is not from a `release` run |
| `gate-evidence-failed` | the `status` of the evidence is not `PASS` |
| `gate-evidence-dirty` | the evidence records `treeDirty: true` |
| `gate-evidence-commit` | the evidence attests a different commit |
| `gate-evidence-source` | the evidence attests a different source hash |
| `operation-in-flight` | the newest receipt records an `operationPath` with no `assetRevision` |
| `cloud-revision-newer` | the cloud revision of the asset differs from the revision in the newest receipt |
| `version-not-advanced` | `VERSION` did not advance under semver past the last receipt |
| `version-hash-conflict` | this `VERSION` was already published from a different source hash |
| `moderation-not-approved` | the moderation state in the read-back is not approved |

**The secret rule.** The tool reads `ROBLOX_API_KEY` only from the environment.
It never reads a keys file, a Roblox session cookie or an argument. It never
prints the key, writes it to a receipt or logs it. The tool only says whether
the key is set.

### The gate evidence file

The release-gate guard reads `artifacts/verify/latest-release.json` and takes
**one object from it**: `gateEvidence`.

**Current gap:** on this branch, no producer writes
`artifacts/verify/latest-release.json`. `tools/verify.sh release` writes
`artifacts/verify/native/report.json`, which has no `gateEvidence`. Thus the
guard refuses every `publish` with `gate-evidence-missing` until a producer of
this file is restored. The format below is the format that the guard expects.

```json
{
  "…the coordinator's own verify-run fields…": "…",
  "gateEvidence": {
    "schema": "facet-release-gate/1",
    "tier": "release",
    "status": "PASS",
    "commit": "<sha>",
    "treeDirty": false,
    "sourceHash": "<sha256>",
    "completedAt": "2026-08-30T00:00:00Z"
  }
}
```

`decide()` compares each field:

| Field | Must be |
|---|---|
| `schema` | `facet-release-gate/1` |
| `tier` | `release`. A `fast` or `affected` run never authorizes a publish. |
| `status` | `PASS` |
| `treeDirty` | `false`. The gate must run on a clean tree for its result to describe this commit. |
| `commit` | equal to `--commit`. The guard compares it only after `--commit` is known to equal `HEAD`. Thus `commit-mismatch` reports a wrong argument once, not twice. |
| `sourceHash` | equal to the source hash of the tree that is built |

The guard **fails closed**. An absent file, an unreadable file and a file with
no `gateEvidence` object all refuse in the same way. All three mean that
nothing authorizes a publish. `status` reports which of the three
occurred.

Each comparison is against a fact that this tool derives itself. Thus there is
no shared recipe for the two sides to disagree about. Previously there was one:
the guard compared a locally computed
`sha256("facet-release-gate/1|" + version + "|" + commit + "|" + sourceHash)`
against an `identity` field that no code wrote. This made `publish`
unreachable. The self-test passed only because it made the file that it then
read. The self-test now writes an evidence file in the expected format. The
file has the real commit and source hash of this repository. The self-test
asserts that this file clears every gate check. This proves the guard logic. It does not prove that a
verification run writes the file (see the current gap above).

---

## Receipts

There is one JSON file for each publish, at
`package/receipts/<version>-<sha7>.json`:

```json
{
  "schema": "facet-package-receipt/1",
  "version": "0.11.0",
  "sourceCommit": "<sha>",
  "sourceHash": "<sha256>",
  "artifactSha256": "<sha256>",
  "assetId": 0,
  "operationId": "…",
  "operationPath": "operations/…",
  "assetRevision": { "revisionId": "2", "revisionCreateTime": "…" },
  "moderation": "Approved",
  "publishedAt": "2026-…Z",
  "actor": "…",
  "route": "studio",
  "toolchain": { "rojo": "…", "lune": "…" },
  "gateRun": { "schema": "…", "tier": "release", "status": "PASS", "commit": "…", "treeDirty": false, "sourceHash": "…", "completedAt": "…" },
  "studio_verification": { "status": "pending", "by": null, "date": null, "notes": null }
}
```

`assetRevision` records the value that the API returned. The documentation
states that `revisionId` is equivalent to the version number. The studio route
records the version path instead. Receipts are the record of what was
published, so they are committed.

Each publish also adds a one-line summary to `versions` in
`facet-package.json` (`version`, `sourceCommit`, `assetRevision`,
`publishedAt`). Thus a reader of the config sees the release history without
opening the receipts directory. The receipts stay the authority.

---

## The release procedure

```
tools/release.sh <version> <commit>
```

The script does these steps:

1. It refuses an unknown commit, a dirty tree, a missing `ROBLOX_API_KEY` and
   an unconfigured asset id.
2. It checks out the named commit into a temporary git worktree.
3. It runs the release gate again in that worktree. It uses
   `tools/verify.sh release` if that script exists, otherwise `tools/test.sh`,
   and records which one it used.
4. It builds in the worktree, so that the drift guard has a recorded manifest
   to compare against.
5. It runs `tools/package.sh publish --confirm` with every guard still active.
6. It polls and reads back.
7. It copies the new receipt and `package/facet-package.json` into the main
   tree.
8. It prints the Studio verification checklist and the exact `stamp` command.
9. It removes the worktree.

It never pushes.

Two details of the copy-back are important:

- The script selects a receipt by **content**: a `publishedAt` at or after a
  watermark that it takes before it publishes. It does not select a receipt by
  a name that the main tree has not seen. A receipt is named
  `<version>-<sha7>`, so a second publish of the same version from the same
  commit uses the same name.
- The script copies the config back only when it differs from the config in
  the main tree in `assetId` and `versions` alone. A difference anywhere else
  causes a refusal that names the fields that changed.

`.github/workflows/release.yml` runs the same command behind three separate
stops:

- `workflow_dispatch` only, never a push,
- a protected `release` environment,
- a first step that refuses a fork, or an actor who is not the repository
  owner.

It uploads the receipt as a workflow artifact.

### How the asset ID is recorded

`create` writes `assetId` into `facet-package.json`. On the studio route, it
does this only after a `GET` confirms that the id names a Model that the
configured creator owns. After that, every command refuses to touch any other
id. The ID is only configuration and documentation. It is never part of the
Facet Luau runtime API.

Choose ownership once. The Roblox Packages documentation is explicit:
"Ownership transfers are not supported by the asset system". For this reason,
`creator` is an owner-checkpoint field, and a dry run prints
`<unset — owner checkpoint>`. It does not guess.

---

## Why two routes

These points come from the platform research note
(`artifacts/distribution-readiness/research/platform-sources.md`, fetched
2026-08-30):

- The supported-types table of the Assets API says that a Model "Will be
  uploaded as packages". This one sentence is the only documented bridge
  between Open Cloud and the Studio Package system.
- The same guide says that only `.fbx` asset content can be updated at this
  time. The Facet artifact is an `.rbxm`. Thus the API **create** path is
  documented for this file type, and the **update** path is not.
- Roblox warns two times that `.rbxm` and `.rbxmx` files edited outside Roblox
  Studio might not upload or function.
- `packages.md` does not mention Open Cloud. Nothing documents whether a Model
  created through Open Cloud has a `PackageLink`. Nothing documents whether a
  `PATCH` increments the Package version that `AutoUpdate` copies follow.

Thus the default is `studio`. Mint and publish through the Studio UI, which is
the only documented Package mechanism. Use the API only for the parts that it
*does* document: reading the asset and its version list. The `open-cloud`
route is fully implemented. It becomes active when the spike proves that it
works.

`AutoUpdate` is opt-in for each copy. It is *disabled and ignored* when a copy
is locally modified. Mass updates skip such a copy and report it. They never
overwrite it.
