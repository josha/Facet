# Public documentation refresh — what was done and what proves it

Workstream **F** of `distribution-readiness`: public documentation, root files,
the agent onboarding kit, the standalone consumer, and continuous integration.
Run 2026-08-30 from `GameStudio/ui/Facet`, against a working tree several other
workstreams were editing at the same time.

Binding text: `docs/plans/distribution-readiness.md` §"Public repository
boundary", §"Documentation and installation", §"Agent onboarding kit", and
`artifacts/distribution-readiness/execution-plan.md` §2 rows D2, D4–D7, D11.

## 1. Files created

| Path | Lines | What it is |
|---|---|---|
| `LICENSE` | 21 | The MIT text, with the candidate line `Copyright (c) 2026 Josh Anon`. Nothing inside the file marks it unconfirmed; the owner packet carries that. |
| `THIRD_PARTY_NOTICES.md` | 342 | Five sections: Facet's own art, the SCOWL word data with its complete verbatim notice, the fonts Facet names but never ships, the documentation the comparison chapter quotes, and the toolchain. |
| `CHANGELOG.md` | 97 | Keep-a-Changelog form. An `Unreleased` section for this stage's user-visible changes, and a `0.10.0` section derived from `ADR-0011` and `ADR-0040` and marked "not yet published". |
| `CONTRIBUTING.md` | 166 | Toolchain setup, where a change goes, the four verification tiers, the product-language and clear-writing scans, tests-fail-first, what a good change looks like, and what is not a contributor's job. |
| `SECURITY.md` | 66 | GitHub private vulnerability reporting on the repository, latest release supported, an honest response expectation, and a scope section that says plainly what a client-side library can and cannot be responsible for. |
| `AGENTS.md` | 174 | The routing table: where every answer lives, how to build a screen, how to choose a render target without overclaiming, what belongs to a game, the workflow and tiers, and the forbidden shortcuts. |
| `skills/use-facet/SKILL.md` | 53 | Frontmatter carries only `name` and `description`. The body is an eight-step loop that routes to `AGENTS.md` and the guides. |
| `examples/consumer/default.project.json` | 54 | A standalone Rojo project. Maps `../../src` to `ReplicatedStorage.Facet`, `src/screen.luau` to `ReplicatedStorage.FacetConsumerScreen`, `src/main.client.luau` to `StarterPlayer.StarterPlayerScripts.FacetConsumer`, and sets `Workspace.PlayerScriptsUseInputActionSystem`. |
| `examples/consumer/README.md` | 57 | How to build and run it, what is in it, what it demonstrates, and where its proof is. |
| `examples/consumer/src/screen.luau` | 140 | The screen: state, a memo, and the blueprint. Takes `Facet` as an argument so both hosts mount the identical description. |
| `examples/consumer/src/main.client.luau` | 69 | Wait for the DataModel, stand up a host, present, tear down on the Close button or after a timer. |
| `tests/consumer_standalone.spec.luau` | 286 | Twelve cases over that same module. Registered in `tests/run.luau`. |
| `tools/lune/check_links.luau` + `check_links_cli.luau` | 370 + 51 | The link checker and its command. |
| `tools/relink_archived.py` | 205 | `--check` / `--fix` for the mechanical link repair in `docs/adr/` and `docs/lessons/`. |
| `.github/workflows/ci.yml` | 79 | Continuous integration. |
| `.github/PULL_REQUEST_TEMPLATE.md` | 35 | What changed, the tier run and its result line, documentation, consumer impact. |
| `.github/ISSUE_TEMPLATE/bug_report.md` | 40 | Repro, expected against actual, `Facet.VERSION`, install route, device and input class. |
| `.github/ISSUE_TEMPLATE/feature_request.md` | 38 | The screen being built, what was tried, why it belongs in Facet, and where it must work. |

## 2. Files rewritten or repaired

- **`README.md`** — rewritten to the plan's root requirements: what Facet does,
  the three surfaces it draws on, what its evidence covers and what it does not,
  four install routes in the plan's order (Package first), the five-minute
  screen, examples, the documentation map, the development commands, versioning,
  and the contribution, security and licence pointers. Every reference to an
  internal plan, a stage name or a gate id is gone.
- **`docs/guide/README.md`** — the reading-order table gains chapter 14 in the
  line workstream E2 supplied verbatim; a short block after the table points at
  the consumer project and the Package install; the verification section leads
  with the four tiers; the paragraph that required an internal execution
  contract now states the rule and points at `CONTRIBUTING.md`.
- **`docs/guide/03-getting-started.md`** — the Studio callout had its sentences
  interleaved and did not read (the instruction was split in half by an
  unrelated paragraph); it is restored to one instruction followed by one aside.
  The no-Rojo aside names the Package route, and a new §3.6 points at
  `examples/consumer/`.
- **`docs/guide/08-without-rojo.md`** — a new §8.2 makes the official Roblox
  Package option A: how to insert it, the `PackageLink` warning, reading the
  version from `Facet.VERSION` and from the `Distribution` folder's `Version` /
  `SourceCommit` / `SourceHash` attributes, *Get Latest Package*, the version
  history, and the AutoUpdate rules below. Sections 8.2–8.9 became 8.3–8.10 and
  every internal cross-reference moved with them.
- **`docs/guide/{02,04,05,07,09,10,11,12}.md` and `docs/extending/*`** — every
  citation of a plan, a handoff note or a stage evidence packet a public reader
  cannot open is now a sentence that stands by itself, and gate wording names
  the tiers.
- **`docs/MAINTAINERS.md`** — a new closing section 5 names the four tiers, says
  a working-tier result is not evidence a change is ready, keeps the release
  tier with the release, and points at guide 11 for what a headless run cannot
  see. Nothing else in the file was touched.
- **`docs/reference/api.md`** — link repairs only: one anchor that named a
  heading that does not exist (`#uistroke` → `#stroke`), and one link into
  `docs/plans/` turned into plain text.
- **`docs/adr/`, `docs/lessons/`** — the mechanical repair below, plus two
  renamed decision records whose links had rotted
  (`ADR-0037-controls-namespace.md` → `ADR-0037-public-call-shapes.md`,
  `ADR-0019-theme-package-schema.md` → `ADR-0019-theme-packages.md`).
- **`rokit.toml`** — Lune 0.10.4 and StyLua 2.5.2 added to the pin, at the
  versions already in use. Verified: `rokit install --no-trust-check` resolves
  both and `lune --version` / `stylua --version` report the pinned numbers.

## 3. Link-repair counts

| Measure | Before | After |
|---|---|---|
| Markdown links into archived material, `docs/guide/` + `docs/extending/` | 7 | 0 |
| Any reference to an archived path, `docs/guide/` + `docs/extending/` | 45 | 7 |
| Markdown links into archived material, `docs/adr/` + `docs/lessons/` | 7 | 0 |
| Genuinely broken links and anchors found in documents that stay public | 4 | 0 |

The seven remaining archived-path references in the guide and the playbooks are
**output paths**, not reading material: they name where a run writes its own
evidence (`artifacts/device-emulator-sweep/rows/<cell>.json`,
`artifacts/performance-stress-places/studio/`, `artifacts/studio/`), plus one
live gate command in `09-custom-themes.md` that reads a checked-in theme-sync
dump. Those commands keep working in a public clone; changing them would break
the gate they document.

Those four were a dead heading anchor in `docs/reference/api.md` (`#uistroke`,
which is `#stroke`), two links to decision records that had been renamed, and one
link from the API reference into `docs/plans/`. A further four sat in
`docs/reference/sponsor-view-parity.md`, which is itself leaving the tree, so the
checker no longer scans it.

`tools/relink_archived.py --fix` performed the `docs/adr/` and `docs/lessons/`
repair: **7 links in 5 files**, out of 149 links across 132 documents. The
guide, the playbooks, the root files and the API reference were repaired by
hand, because their sentences needed rewriting rather than annotating.

## 4. The standalone consumer proof

`examples/consumer/src/screen.luau` is required two ways: by
`main.client.luau` through the instance tree, and by
`tests/consumer_standalone.spec.luau` by path. Both mount the identical
description.

```
lune run tests/run_one consumer_standalone   ->   12 passed
```

The twelve cases prove: every node mounts with a real rect; the label reads out
of the signal; a committed theme package repaints the accent tint to the
package's own accent colour (a colour the example never names); a press on Bump
through `adapter.tap` raises the count and repaints the label; a signal write
repaints with no press; the toggle carries the screen's own signal; Close
reports itself; the button stack arranges differently at 390x844 and 1440x900; a
viewport change on the mounted surface re-solves it with the node count
unchanged; a `preferredTextSize` change grows the label that declares no text
size; teardown returns `observers` and `scopes` to their pre-screen baseline;
and the render target is left with zero roots.

The project also builds:

```
rojo build examples/consumer/default.project.json -o <tmp>/Facet-Consumer.rbxl   ->   built, 2.78 MB
```

`lune run tools/lune/check_boundary` passes with the consumer in place: 426
consumer files scanned, no internal reach. The consumer requires the library
root and `client.host`, which is a blessed client entry point.

**One deliberate deviation from the brief**, recorded because it is a real
finding: the project file declares
`"PlayerScriptsUseInputActionSystem": "Enabled"`, not `true`. That is the form
every other Facet project file uses and the form Rojo 7.7.0 builds; it is an
enum-valued property, and `true` is not the value.

**One defect the proof found**, now fixed in both hosts: disposing the host
while a surface is still presented leaves that surface's observers alive on the
core. The teardown order is `presenter.dismiss(handle)`, then the screen's
scope, then `host.dispose()`, and the baseline case is what reports a
regression.

## 5. Continuous integration

`.github/workflows/ci.yml` — on push to `main` and on every pull request, one
`ubuntu-latest` job with `concurrency.cancel-in-progress`, `permissions:
contents: read`, and **no secrets**:

1. checkout, then `actions/setup-python` at 3.12;
2. install Rokit with the one-liner from its own README, and put
   `$HOME/.rokit/bin` on `$GITHUB_PATH`;
3. `rokit install --no-trust-check` — which now brings Rojo, luau-lsp, Lune and
   StyLua, because the last two joined `rokit.toml` in this workstream;
4. print every tool's version;
5. `stylua --check src tests tools bench examples`;
6. `tools/verify.sh full` when that file is executable, `./run-tests.sh`
   otherwise;
7. `python3 tools/check_brand_drift.py`;
8. `lune run tools/lune/check_links_cli`;
9. `tools/build_model.sh`, then `python3 tools/check_library_purity.py`.

The workflow's YAML was parsed and its structure inspected. It has **not** been
executed on a GitHub runner — that cannot happen before the repository is
pushed, and this stage does not push. The two facts a runner could still
disprove are that the Rokit install script works unattended on `ubuntu-latest`,
and that `check_brand_drift.py`'s place builds complete inside the 45-minute
job timeout.

`.github/workflows/release.yml` belongs to another workstream and was not
touched.

## 6. Every check, with its result line

All run from `GameStudio/ui/Facet` on 2026-08-30, at commit `f632021` unless
noted.

```
python3 tools/check_doc_style.py
  check_doc_style: PASS — 24 documents; no over-long instruction step, no
  unexpanded acronym, no internal shorthand (486 warnings, never fatal)

lune run tools/lune/check_docs_cli
  check_docs: PASS (9 documents, 78 surface anchors, 3 comparison citations,
  167 local links, 14 themes exports documented, 24 scenario steps,
  11 example packages, 17 asset files, 10 stale phrases absent)

lune run tools/lune/check_links_cli
  check_links: PASS (163 documents, 639 relative links, 149 heading anchors)

lune run tools/lune/check_links_cli -- --selftest
  check_links --selftest: PASS — a dead link and an archived-material link are
  both reported, and the tree itself still passes

python3 tools/relink_archived.py --check
  relink_archived: PASS — 132 documents, 142 links, none pointing into
  archived material

lune run tools/lune/check_boundary
  boundary: PASS (171 src files, 426 consumer files)

lune run tools/lune/check_registration_cli
  check_registration: PASS (41 controls, 105 exports documented,
  299 specs registered, 19 interactive controls prove four-input,
  19 prove the paradigm axis)

lune run tools/lune/check_maintainer_map_cli
  check_maintainer_map: PASS (19 areas covering 29 src entries, 71 named specs,
  19 scenarios, 42 gate rows, 7 boundary rules, 20 public seams,
  50 local links, 7 playbooks linked)

stylua --check src tests tools bench examples
  PASS (no output)

lune run tests/run_one consumer_standalone
  12 passed

./run-tests.sh --fast
  7159 passed, 2 failed  <- BEFORE the fix in §7; both were one root cause

tools/test.sh 7000
  test: PASS passed=7883   (artifacts/test.json, 0 failed)
```

The suite count moves by a few cases from hour to hour while other workstreams
land; 7883 is this workstream's final reading.

## 7. What is red, and whose it is

**`python3 tools/check_brand_drift.py` FAILS**, and **none of the matches is in
a file this workstream owns**. Two readings, both taken here:

- at commit `f632021`, **12 matches**: `docs/plans/facet-consolidated-roadmap.md`
  (2), the owner's roadmap, which leaves the public tree; and
  `tools/lune/gate_manifest.luau` (10), the gate manifest, which the
  verification-graph workstream is retiring and which also leaves the tree;
- re-read after that workstream regenerated its converted graph, **189
  matches**: the same 12, plus about 177 inside the uncommitted
  `tools/lune/verify/graph.json`, whose converted rows carry the old manifest's
  prose. That file is workstream T's and is being edited as this is written;
  the director has raised it with that workstream directly. This workstream did
  not touch it.

The cause is workstream E1 removing the retired comparison document's entry from
the guard's allowlist while both of those files still name it. Both files are in
the archived set, so the scan goes green once workstream C archives them. This
workstream's two contributions to that list were removed: both link guards used
to name the four retired reference documents literally, and now express the same
rule as an allowlist — `docs/reference/api.md` and `docs/reference/constitution.md`
are public, everything else under `docs/reference/` is archived. That is more
robust as well as quieter: a research document added and archived later needs no
edit to either guard.

**Two suite cases went red during the run and are fixed.** Both had one cause:
removing the archived path from `docs/extending/new-theme.md` also removed the
string `acceptance-ledger.md`, which `check_docs` requires the theme playbook to
name. The playbook names it again, without offering a link to it, and both cases
are green in the 7883 above.

## 8. What could not be verified here

- **The CI workflow has never run.** See §5.
- **The Package install instructions describe behaviour nobody has exercised
  yet.** Everything in guide §8.2 and in the README's Package section is taken
  from `artifacts/distribution-readiness/research/platform-sources.md`, which
  cites Roblox's own `packages.md` — `AutoUpdate` false at creation, disabled
  and ignored on a modified copy, mass updates skipping and reporting modified
  copies, *Get Latest Package* / *Get Latest For Selected Packages*, the
  version history and restore, and the four edits that do not count as
  modifications. **The asset does not exist**, so none of it has been observed
  on a real package. The research note also records an open question the Roblox
  documentation does not answer: whether an Open-Cloud-updated model produces a
  new *Package* version at all. No claim in the public documents depends on that
  question either way.
- **The asset id is stated as pending everywhere**, and every place that would
  carry it points at `package/facet-package.json`, where `assetId` and `creator`
  are still `null`.
- **The physical-device evidence claim** in the README is a restatement of
  `docs/guide/11-device-verification.md`: three physical classes declared,
  each carrying zero rows, device budgets marked unmeasured. It was not
  re-measured here.
- **`docs/guide/14-choosing-a-ui-library.md`** belongs to workstream E2. This
  workstream only pasted the two link lines that workstream supplied in
  `artifacts/distribution-readiness/guide-links.md`, verbatim.
- **The third-party notices** were reconciled against
  `artifacts/distribution-readiness/audit/THIRD_PARTY_NOTICES.draft.md` after it
  landed. The audit confirms the SCOWL section is already complete and verbatim,
  and that no section is owed for the removed vendored library provided its
  deletion lands in the published commit. The draft's two optional sections
  (fonts, quoted documentation) were added. If `vendor/` ships after all, the
  draft's §1 is the exact text required and this file does not carry it.

## 9. Commits

```
e5f7d37  Give the repository the public front door a stranger can read on its own
2f79278  The guide stands on its own, and the Package is the install it recommends
6974daa  A decision record no longer promises a file the reader cannot open
aa880ce  Every link a published document offers now resolves, and a check says so
cf33f8e  A standalone project a stranger can build, and a spec that mounts the same screen
c5466dd  Continuous integration runs the same commands a contributor runs
5e492bd  The maintainer map says which verification tier proves a change
044d07b  Point the public documents at the package reference and the comparison chapter
f632021  The reference documents that stay public are an allowlist, not a denylist
```

Every one was made with `tools/commit_isolated.py`, path- or marker-scoped.
Nothing was pushed.
