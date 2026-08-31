# The Facet Package release channel — maintainer reference

Facet ships as **one** official Roblox Package with a stable asset ID. This
directory holds the non-secret configuration for that package and the receipt
for every publish. Everything here is for maintainers; a consumer never needs to
read it.

Git is canonical. Every fact about a release is derived from the repository —
the version from `src/init.luau`, the commit from `git rev-parse HEAD`, the
source hash from the `src/**/*.luau` tree — and every number a human types is
checked against the repository before anything is sent.

**No asset exists yet.** `assetId` and `creator` in `facet-package.json` are
`null` and stay that way until the owner checkpoint. `create` and `publish` are
implemented in full and refuse to run until then.

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

`tools/package.sh` is a wrapper; the program is `tools/package.py`, which has no
dependencies outside the Python standard library.

**`build`, `status` and `verify` are offline** and are the everyday commands.
They contact nothing and need no credential.

The verdict table prints three states, not two: `[REFUSE]` failed, `[  ok  ]`
was compared and passed, `[ n/a  ]` had nothing to compare — a publish-only
guard under `create`, a receipt comparison with no receipt, a moderation state
nobody has read yet. A guard that did not run never reads as one that passed.

**`create` and `publish` are dry runs by default.** A dry run prints the exact
request that would be sent — method, URL, multipart field names, the request
JSON, and the file part named with its size and hash but never its contents —
plus every guard's verdict, and exits 0 without touching the network. `--confirm`
is the only way a request is made, and it is refused unless every guard passes.

### build

Runs `tools/build_model.sh`, which is the **one** Rojo mapping for the
distribution and must stay that way. It produces:

- `build/Facet.rbxm` — the artifact: one `ModuleScript` named `Facet` with the
  whole shipped `src/` tree beneath it;
- `build/Facet.rbxmx` — the same tree as XML, because a binary `.rbxm` is
  LZ4-chunked and nothing can read its scripts as text;
- `build/Facet.manifest.json` — the semantic manifest (below);
- `build/.stage/Distribution/` — the generated release metadata, regenerated on
  every build and never edited by hand.

`build/` is gitignored, so none of it is ever committed.

`tools/build_model.sh --publisher` additionally builds
`build/FacetPublisher.rbxl`, the canonical publisher place: one place whose
`ReplicatedStorage.Facet` is the artifact this build just produced. It consumes
the built model rather than mapping `src/` a second time.

### What travels inside the Package

`Facet.Distribution` is a `Folder` child of the root module carrying five
attributes and two `StringValue` children:

| Attribute | Value |
|---|---|
| `Version` | `Facet.VERSION` from `src/init.luau` |
| `SourceCommit` | `git rev-parse HEAD`, suffixed `-dirty` when `git status --porcelain -- src` is non-empty |
| `SourceHash` | sha256 over the sorted shipped source (below) |
| `BuildSchema` | `facet-package/1` |
| `Repository` | `https://github.com/josha/Facet` |

| Child | Value |
|---|---|
| `LICENSE` | the root `LICENSE` file verbatim |
| `THIRD_PARTY_NOTICES` | the root `THIRD_PARTY_NOTICES.md` verbatim |

There is deliberately **no build time** in the artifact. Two builds of one commit
must produce the same bytes; the time of a release lives in its receipt. Measured
on Rojo 7.7.0: three consecutive builds of one tree produce byte-identical
`.rbxm` and `.rbxmx` files, and the only thing that moves between commits is the
`SourceCommit` attribute.

`SourceHash` is sha256 over the sorted list of `src/**/*.luau` (excluding
`*.spec.luau`, which the model does not ship), feeding `<relpath>\n` followed by
the file's bytes with CRLF normalized to LF. Path-then-content means a rename
changes the hash even when no byte of code moved — which is honest, because a
rename moves an instance in the shipped tree.

### The manifest

`build/Facet.manifest.json` is read off the `.rbxmx` twin:

```json
{
  "schema": "facet-package-manifest/1",
  "version": "0.10.0",
  "sourceCommit": "<sha>[-dirty]",
  "sourceHash": "<sha256>",
  "artifact": "build/Facet.rbxm",
  "artifactSha256": "<sha256>",
  "instanceCount": 189,
  "moduleCount": 171,
  "bodyHash": "<sha256 over the instance list>",
  "instances": [ { "path": "Facet/env/environment", "className": "ModuleScript", "sourceSha256": "…" }, … ]
}
```

`bodyHash` is the comparison basis for the build-drift guard. Rojo is
byte-deterministic here, so `artifactSha256` would also do — but the body hash is
over the *semantic* content, so it survives a future Rojo that reorders
referents, and it is the number a human can reason about when a build drifts.

### status

Rebuilds, then reports version, commit, source hash and artifact hash against the
newest receipt: whether the source has drifted since the last publish, whether
the tree is dirty, whether `VERSION` advanced under semver, whether `CHANGELOG.md`
mentions the version, and whether the release-gate evidence attests this exact
tree.

### verify

Build, then four checks:

1. **tree inspection** — every shipped `src/**/*.luau` is present as a
   `ModuleScript` at the expected path, every intermediate directory is a
   `Folder`, `Facet/Distribution` and both of its `StringValue` children are
   present (the release metadata and the MIT text are required, not merely
   tolerated), and *nothing else* is in the model. Anything unexpected fails, and
   anything whose path contains `tests`, `examples`, `vendor`, `bench`,
   `spikes`, `fusion_adapter`, `imperative` or `.spec` fails by name.
2. **distribution notices** — reports if `LICENSE` / `THIRD_PARTY_NOTICES` fell
   back to placeholder text.
3. **`tools/check_library_purity.py`** — the shipped library names no reference
   theme package in code.
4. **the packaged-consumer canary** (`tools/lune/package_canary.luau`) — extracts
   every ModuleScript back out of `build/Facet.rbxmx` into a directory tree,
   `require`s *that* tree, and mounts a real screen through it: a theme moves
   both paint and geometry, a button fires through the presenter's input path, a
   signal update reaches the rendered props, a viewport change re-solves the
   surface, a preferred-text change re-reserves the type, and three
   mount/dismiss laps leave the adapter's live instances and the core's
   observer/scope registries at the same floor. It also asserts the packaged
   `Facet.VERSION` equals the `Version` attribute on `Facet.Distribution` — the
   one thing a manifest built from source cannot check, because Roblox
   serializes attributes to a binary blob.

### The two routes

`route` in `facet-package.json` selects how the asset is minted and updated.
There are two because the platform documentation supports the create half of the
API path and not the update half — see *Why two routes* below.

|  | `studio` (default) | `open-cloud` |
|---|---|---|
| create | build the publisher place, print the Convert-to-Package steps, then `GET /v1/assets/{id}` to verify the id a human hands back | `POST /v1/assets` (multipart `request` + `fileContent`), poll `GET /v1/operations/{id}` |
| publish | read the asset's current version number, rebuild the publisher place, print the Publish-to-Package steps, then poll `GET /v1/assets/{id}/versions` until the number differs from that pre-publish baseline | `PATCH /v1/assets/{id}`, poll `GET /v1/operations/{id}` |
| read-back | `GET` asset + latest version, recorded in the receipt | same |

Both routes run **the same guards before a single instruction is printed or a
single call is made.**

The configured route is a recorded decision, not a default. `--route` can
override it for one invocation, but only together with `--allow-route-override`
— otherwise the run refuses with `route-override`. `tools/release.sh` forwards
its trailing arguments to `package.sh`, so without that guard a bare `--route
open-cloud` could arrive from two layers away and turn an approved Studio
release into an unapproved `PATCH`.

On the studio route the baseline is read **before** the manual steps are printed,
and a release is recorded only on a positive edge away from it. Comparing against
the last receipt instead meant that a first publish — no receipts yet — accepted
the version already sitting on the asset and recorded a release that never
happened. If the version list cannot be read, the command refuses and asks for
`--baseline-revision <n>` rather than guessing.

### rollback

Prints; never uploads. Re-uploading an old tree would mint a *new* revision whose
contents are old — a version history that lies. Both real mechanisms select an
*existing* version instead:

- **Studio** — Package Options → Package Details → Versions tab → checkmark the
  version → Submit. Restoring does not reset package attributes.
- **Open Cloud** — `POST /v1/assets/{id}/versions:rollback` with a multipart
  `assetVersion` of `assets/{id}/versions/{n}`.

The two sequences are not proved to be the same sequence. Until the Studio spike
answers that, roll back on the same route the version was published on.

### stamp

```
tools/package.sh stamp --receipt package/receipts/<file>.json \
    --studio-verified --by "<who>" --notes "<what you saw>"
```

A receipt is written with `studio_verification.status = "pending"`. A human opens
Studio, inserts the package by ID, checks it, and stamps the receipt. Nothing
automates this, because nothing can.

---

## The guards

Every refusal below is a case in `decide(facts)` — one pure function that reads
no file, makes no call and prints nothing, so each refusal is proven by a test
that runs in milliseconds and never touches a network
(`python3 tools/package.py --selftest`).

| Code | Refuses when |
|---|---|
| `api-key-missing` | `ROBLOX_API_KEY` is not in the environment |
| `dirty-tree` | `git status --porcelain` is non-empty |
| `commit-mismatch` | `--commit` is absent or is not `HEAD` |
| `version-mismatch` | `--version` is absent or is not `Facet.VERSION` |
| `build-drift` | there is no `build/Facet.manifest.json`, or a fresh build's body hash differs from the one it records |
| `creator-unset` | `facet-package.json` has no creator |
| `creator-mismatch` | `--creator-id` / `--creator-type` disagree with the config |
| `asset-id-present` | `create` when an `assetId` already exists |
| `asset-id-missing` | `publish` when no `assetId` exists |
| `asset-id-mismatch` | `--asset-id` disagrees with the config |
| `route-override` | `--route` disagrees with the configured route and `--allow-route-override` was not given |
| `gate-evidence-missing` | `artifacts/verify/latest-release.json` is absent, unreadable, or carries no `gateEvidence` |
| `gate-evidence-schema` | the evidence declares a different schema |
| `gate-evidence-tier` | the evidence is not from a `release` run |
| `gate-evidence-failed` | the evidence's `status` is not `PASS` |
| `gate-evidence-dirty` | the evidence records `treeDirty: true` |
| `gate-evidence-commit` | the evidence attests a different commit |
| `gate-evidence-source` | the evidence attests a different source hash |
| `operation-in-flight` | the newest receipt records an `operationPath` with no `assetRevision` |
| `cloud-revision-newer` | the asset's cloud revision differs from the newest receipt's |
| `version-not-advanced` | `VERSION` did not advance under semver past the last receipt |
| `version-hash-conflict` | this `VERSION` was already published from a different source hash |
| `moderation-not-approved` | the read-back's moderation state is not approved |

**The secret rule.** `ROBLOX_API_KEY` is read from the environment and from
nowhere else — never a keys file, never a Roblox session cookie, never an
argument. It is never printed, never written to a receipt, and never logged. The
only thing the tool will say about it is whether it is set.

### The gate evidence file

The release-gate guard reads `artifacts/verify/latest-release.json`, written by
the verification coordinator (`tools/verify.sh release`), and takes **one object
out of it**: `gateEvidence`.

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

`decide()` compares, field by field:

| Field | Must be |
|---|---|
| `schema` | `facet-release-gate/1` |
| `tier` | `release` — a `fast` or `affected` run never authorizes a publish |
| `status` | `PASS` |
| `treeDirty` | `false` — the gate must have run on a clean tree for its result to describe this commit |
| `commit` | equal to `--commit` (compared once `--commit` is known to equal `HEAD`, so a wrong argument is reported once, by `commit-mismatch`, rather than twice) |
| `sourceHash` | equal to the source hash of the tree being built |

It **fails closed**. Absent, unreadable, or present with no `gateEvidence` object
all refuse identically, because all three mean the same thing: nothing here
authorizes a publish. `status` reports which of the three it is.

Every comparison is against a fact this tool derives for itself, so there is no
shared recipe for the two sides to disagree about. There used to be one — the
guard compared a locally computed
`sha256("facet-release-gate/1|" + version + "|" + commit + "|" + sourceHash)`
against an `identity` field that no code anywhere wrote, which made `publish`
unreachable; the selftest was green only because it fabricated the file it was
about to read. The selftest now asserts the opposite property directly: evidence
written the way the coordinator writes it, against this repository's real commit
and source hash, clears every gate check.

---

## Receipts

One JSON file per publish, at `package/receipts/<version>-<sha7>.json`:

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

`assetRevision` records whatever the API returned — `revisionId` is documented as
equivalent to the version number; the studio route records the version path
instead. Receipts are the record of what was published, so they are committed.

Each publish also appends a one-line summary to `versions` in
`facet-package.json` (`version`, `sourceCommit`, `assetRevision`, `publishedAt`),
so a reader of the config sees the release history without opening a directory of
receipts. The receipts remain the authority.

---

## The release procedure

```
tools/release.sh <version> <commit>
```

It refuses an unknown commit, a dirty tree, a missing `ROBLOX_API_KEY` and an
unconfigured asset id; then it checks the named commit out into a throwaway git
worktree, reruns the release gate there (`tools/verify.sh release` if that script
exists, otherwise `tools/test.sh`, recording which), builds in the worktree so
the drift guard has a recorded manifest to compare against, runs
`tools/package.sh publish --confirm` with every guard still in force, polls and
reads back, copies both the new receipt and `package/facet-package.json` into the
main tree, prints the Studio verification checklist and the exact `stamp`
command, and removes the worktree. It never pushes.

Two details of the copy-back are worth knowing. A receipt is selected by
**content** — a `publishedAt` at or after a watermark taken before publishing —
not by having a name the main tree has not seen, because a receipt is named
`<version>-<sha7>` and republishing the same version from the same commit reuses
the name. And the config is copied back only when it differs from the main tree's
in `assetId` and `versions` alone; a disagreement anywhere else refuses and names
the fields that moved.

`.github/workflows/release.yml` is the same command behind three separate stops:
`workflow_dispatch` only (never a push), a protected `release` environment, and a
first step that refuses a fork or an actor who is not the repository owner. It
uploads the receipt as a workflow artifact.

### How the asset ID is recorded

`create` writes `assetId` into `facet-package.json` — on the studio route only
after a `GET` confirms the id names a Model owned by the configured creator.
Everything afterwards refuses to touch any other id. The ID is configuration and
documentation only; it is never part of Facet's Luau runtime API.

Ownership is chosen once. Roblox's Packages documentation is explicit:
"Ownership transfers are not supported by the asset system, so carefully consider
the owner when creating a package." That is why `creator` is an owner-checkpoint
field and why a dry run prints `<unset — owner checkpoint>` rather than guessing.

---

## Why two routes

From the platform research note
(`artifacts/distribution-readiness/research/platform-sources.md`, fetched
2026-08-30):

- The Assets API's supported-types table says a Model "Will be uploaded as
  packages" — one sentence, and the only documented bridge between Open Cloud and
  Studio's Package system.
- The same guide says "Currently, you can only update the asset content for
  `.fbx` files." Facet's artifact is an `.rbxm`, so the API's **create** path is
  documented for our file type and its **update** path is not.
- Roblox warns, twice, that "`.rbxm` or `.rbxmx` files edited outside of Roblox
  Studio might not upload or function."
- `packages.md` never mentions Open Cloud at all. Nothing documents whether an
  Open-Cloud-created Model carries a `PackageLink`, or whether a `PATCH` bumps
  the Package version that `AutoUpdate` copies follow.

So the default is `studio`: mint and publish through the Studio UI, which is the
only documented Package mechanism, and use the API for the parts it *is*
documented for — reading the asset and its version list. The `open-cloud` route
is implemented in full and switched on the day the spike proves it works.

`AutoUpdate` is opt-in per copy and is *disabled and ignored* the moment a copy is
locally modified; such a copy is skipped by mass updates and reported, never
overwritten.
