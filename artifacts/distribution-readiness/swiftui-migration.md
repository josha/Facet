# Migrating off the private comparison document — what moved, and what still bites

**Workstream E1, 2026-08-30.** `docs/reference/swiftui-parity.md` (2384 lines)
was product research. It is now in the checksummed private archive outside Git
(`artifacts/distribution-readiness/swiftui-archive-receipt.md` carries the path,
size and digest) and the tracked copy is removed from the branch tip.

**Nothing public depends on it any more.** Before the removal, every still-living
Facet requirement, decision or measurement it carried was moved into a neutral
public source, and every check that read it was repointed at that source with the
same failure direction. This document is the record of both halves.

## 1. Every reference site, and where its requirement lives now

Twenty-one sites referenced the archived document or the gate-evidence directories
named after its stage. Each row names the living thing the reference carried, its
new public home, and how a break is still caught.

| # | Reference site | The living requirement / decision it carried | New public home | How the check still bites |
|---|---|---|---|---|
| 1 | `src/controls/progress_view.luau` (Path2D clipping comment) | MEASURED platform fact: `ClipsDescendants` does not crop a `Path2D`, so a themed ring must be bounded by arithmetic rather than by its host | The reading stays in the comment with its date; it now cites `tests/progress_circular.spec.luau` and `docs/reference/api.md` (`newProgressView`, circular presentation) | `tests/progress_circular.spec.luau` asserts the arc sits at `CIRCULAR_RADIUS` of the half-extent and the stroke fits the remainder, at every size a theme may author. A ring that could paint outside its own box reddens the suite |
| 2 | `src/controls/native_scroll_binding.luau` (census comment) | The API-footgun finding that made the engine scroll mirror auto-bind: five of nine callers outside the tests forgot the post-`present` call | The census result stays in the comment; it now cites `tests/native_scroll_autobind.spec.luau` and `docs/reference/api.md` (`bindNativeScroll`) | The spec mounts a virtualized collection with **no** consumer call and asserts the window follows an engine scroll. Removing the auto-bind reddens it |
| 3 | `src/controls/table.luau` (prefix-sum comment) | The design rule: three copies of one arithmetic is the same defect class as the four duplicated gesture implementations | Stated in the comment in its own terms, with the sibling precedent already named there (`virtual_grid.luau`, "Two intercepts differing only in a direction pair…") | `tests/virtual_extents.spec.luau` and Table's own geometry specs assert one index answers every where-is-row-*n* question; a second local loop that disagreed would redden them |
| 4 | `src/client/haptics.luau` (enum-throw comment) | MEASURED engine facts: `Enum.HapticEffectType` indexing throws on a bad name, and the probe lies with zero pads attached | `docs/research/2026-08-12-haptics-engine-facts.md` (already the canonical record, cited now) plus `tests/haptics.spec.luau` | The spec pins the defensive by-name resolution and the tri-state capability probe; removing the `pcall` or defaulting to `Custom` reddens it |
| 5 | `tests/native_scroll_autobind.spec.luau` (header) | Same as row 2, from the test side | Header keeps the measurement and its date, and names `docs/reference/api.md` (`bindNativeScroll`) as the public contract | The spec's own cases |
| 6 | `tests/control_feedback.spec.luau` (header) | That every check in the file was mutation-tested — i.e. none is a check that proves nothing | The claim is stated in the header in its own terms and points at `docs/reference/api.md` (`UI.sensoryFeedback`, the twelve-verb taxonomy) for the behaviour | The file's cases, which the gate greps by name |
| 7 | `tests/progress_circular.spec.luau` (invariant comment) | Same platform fact as row 1 | The comment now points at `docs/reference/api.md` and at `src/controls/progress_view.luau`, which carries the reading in full | The case the comment sits on |
| 8 | `tests/overflow_sweep.spec.luau` (theme-tier comment, ×2) | The tier decision: the axis is the eight shipped **packages**, not the twelve themes, at every viewport plus the largest preference on the two narrowest | The comment states the measurement and its date, and names the two live instruments: `themeCoverage` at the bottom of the same file, and `tests/lib/theme_sweep_ledger.luau` | `themeCoverage` **fails when the documented list and the executing code disagree** — it was already the enforcing half, and it is now the cited one |
| 9 | `tests/overflow_sweep.spec.luau` (waiver output path) | Where the readability triage writes its report | `artifacts/overflow-waivers/waiver-readability.txt` (see row 13) | The instrument writes there; the comment names the same path |
| 10 | `tests/geometry_solve_coalescing.spec.luau` (O-20 comment) | MEASURED: a modal over a plain tree costs one solve; a surface with a layout prop bound to a viewport memo cost three | The comment names the reproducing instrument, `lune run tools/lune/_probe_modal_solves` | The spec's own solve-count assertions, which fail if the coalescing regresses |
| 11 | `tests/theme_docs.spec.luau` (the citation gate's spec) | That the citation gate *bites* — five failure directions, each proven by a fixture | Rewritten against `docs/guide/14-choosing-a-ui-library.md`; see §2 | Seven cases, six of them negative controls driven through `fileOverrides`, so the machinery is proven on any tree |
| 12 | `tests/fixtures/retired/README.md` (gate row table) | Which earned gate rows still require the retired Wardrobe fixture | The row names `reference-apps-reproved` and tells the reader to read the stage id out of `tools/lune/gate_manifest.luau` rather than from the table | `gate_manifest`'s own row, and the two suite greps it names, still run |
| 13 | `tests/lib/tiers.luau` (tier-cost comment) | The measured spec-cost distribution the tier threshold was chosen from | The comment names the reproducing instrument, `lune run tools/lune/time_specs`, and the drift checker `tools/lune/check_tier_costs` | `check_tier_costs` fails when a spec's real cost crosses the threshold its row claims |
| 14 | `tools/lune/triage_overflow_waivers.luau` (header + write) | Where the instrument's report goes | Output moved to `artifacts/overflow-waivers/waiver-readability.txt`, and the tool now creates its own output directory (`writeFile` does not create parents, and this runs by hand on trees that never ran it) | Running the tool writes the file; `tests/overflow_sweep.spec.luau` names the same path |
| 15 | `tools/lune/check_flat_baseline.luau` (findings comment) | Two findings: a red check cannot report the next defect, and a count that does not decompose is one | `docs/lessons/a-red-check-cannot-report-the-next-defect.md` — already the public home, now the only pointer | The lesson is a shipped document; the checker's own decomposed reporting is what the lesson describes |
| 16 | `tools/lune/check_docs.luau` §9 (the citation gate) | **The comparison-citation contract.** See §2 — this is the substantial one | `docs/guide/14-choosing-a-ui-library.md`, via `COMPARISON_DOCS` | Four rules, all live; proven by six negative-control cases |
| 17 | `tools/lune/check_docs.luau` `FORBIDDEN` (stale-phrase entry) | That `Facet.themes` is public surface, so no document may say there is no reusable theme-package API | Already enforced, in a public home, by the **same checker's §2**: every member of the live `Facet.themes` export block must be documented in `docs/reference/api.md` | Proven below (§3): deleting a `themes.*` entry from `api.md` reddens `check_docs` by name |
| 18 | `tools/check_brand_drift.py` (allowlist + constant + reachability guard) | Content exception 1: the one dedicated comparison document | **Removed.** The exception's own removal rule was "never (it IS the exception)" — but the exception is gone with its subject. The remaining exceptions are the marked `docs/guide/**` comparison block and the library-choice chapter, each named file by file | The guard now refuses that path like any other. `GATE_IDS` is matched **by shape** (`…-parity-round<n>`, `…-reference-app-validation`) instead of by the retired stage name, so the guard's own source no longer carries the name it exists to keep out |
| 19 | `docs/MAINTAINERS.md` (`gates` column, 9 ids across 7 rows) | Which gate row pins each production area | The nine ids naming the retired stage were dropped; **every one of the seven rows keeps at least one real gate id**, and the map's own checker enforces that | `tools/lune/check_maintainer_map.luau` rule 7 fails a row that cites **no** gate, and fails any id the manifest does not define. It reports 42 gate rows, above the spec's floor of 40 |
| 20 | `docs/INVENTORY.md` (the Milestone-1 stage row) | That the M1/M2/M3 gate stage was registered *after* the mission closed — the finding is the lateness, not the name | The row's key cell now names "the Milestone-1 catch-up stage" and tells the reader to read its id out of the manifest; the "parity doc's falsifiability" check in the cell now says the document was archived and points here | The row is a record, not a check |
| 21 | `docs/adr/ADR-0035-preferred-transparency.md` and `docs/lessons/a-red-check-cannot-report-the-next-defect.md` | Pointers to a stage's owed-row ledger and to a mutation transcript | Each sentence now says the evidence is archived with that stage's gate record, and the record stands on what it states itself | `ADR-0035`'s decision is enforced by `tests/preferred_transparency.spec.luau`; the lesson is prose and always was |

### Two public sentences were added, and no more

Neither `docs/reference/api.md` nor `docs/guide/01-concepts.md` /
`02-architecture.md` needed a new paragraph: **every living contract the archived
document carried already had a public home** — an ADR, `api.md`, a lesson, a
research record, or the spec that proves it. The only new public prose is inside
the comment and header lines listed above, each of which stays in the file it
was already in.

## 2. The citation gate: the one check whose subject moved

`tools/lune/check_docs.luau` §9 used to read the archived document and enforce
its `[SW-nn]` / §16 convention. That convention belonged to that document. **The
contract underneath it did not**, and it is the one that survives: *a comparison
document must let a reader check it.*

The public comparison document that replaces it —
`docs/guide/14-choosing-a-ui-library.md`, added by a concurrent workstream —
keeps that contract in a different and better-suited shape (a `[FACT]` /
`[INFERENCE]` label on every claim, and a §14.6 Sources table pinning each
project to a version, tag or commit with its links and a fetch date). §9 was
rewritten to that shape, driven by a **list** (`COMPARISON_DOCS`) rather than a
hard-coded path, so the rule outlives its subject a second time:

| Rule | Fails when | Negative control |
|---|---|---|
| **9a — every framework it compares against is sourced** | a library the document names never appears on a line that also carries an `https://` URL | `fails when a framework it compares against carries no source URL` |
| **9b — the comparison is dated** | no `YYYY-MM-DD` anywhere in the document | `fails when the comparison carries no ISO research date` |
| **9c — the comparison is pinned** | the document names no version, tag, release or commit for what it read | `fails when the comparison pins no version, tag or commit` |
| **9d — reasoning is marked apart from reading** | the document never labels a claim an inference | `fails when the comparison never marks a claim as an inference` |

Two properties worth stating plainly:

- **It bites live, today.** `lune run tools/lune/check_docs_cli` reports
  `3 comparison citations` — one per library the public guide sources. Break any
  of the four rules in that file and the command goes red naming the rule.
- **It bites on a tree where no comparison document exists.** A listed document
  that is absent is skipped and reported through `counts.comparisonDocs`; every
  failure direction is still proven, because the six negative controls drive the
  checker through `fileOverrides` rather than against whatever is on disk. A
  hollow section is therefore visible rather than indistinguishable from a
  passing one.

**What did not survive, stated rather than hidden.** The old gate checked
citations **per row**; the new comparison is a matrix rather than a verdict
table, so per-row granularity has no subject. The new rules are per *framework*,
per *document*. `CITATION_EXEMPT` — the self-expiring debt list — is gone with
the two rows it excused, both of which were in the archived document. Nothing
about the public tree is less checked than it was: the archived document is the
only thing that lost a check, and it is no longer in the public tree.

## 3. Proof that each repointed check still reddens

Every claim below was executed in this session.

| Check | Proof it bites |
|---|---|
| `check_docs` §9, all four rules | Six negative-control cases in `tests/theme_docs.spec.luau`, each asserting exactly one named problem. All six pass (they redden the checker on demand); the seventh asserts the well-formed fixture is clean and that the document was actually read (`comparisonDocs == 1`, `citations == 3`) |
| `check_docs` §2 (the home of row 17's contract) | The checker reads the live `themes = { … }` export block out of `src/init.luau` and requires a `themes.<name>` entry in `docs/reference/api.md` for each. It reports `14 themes exports documented`; `tests/theme_docs.spec.luau` drives it with an `api.md` override missing one and asserts the named failure |
| `check_maintainer_map` (row 19) | Rule 7 refuses a row that cites no gate and refuses an id the manifest does not define; `tests/maintainer_map.spec.luau` plants one fault per obligation across twenty cases and requires each to be named. The checker reports 42 gate rows against the spec's floor of 40 |
| `triage_overflow_waivers` (row 14) | Runs by hand and writes `artifacts/overflow-waivers/waiver-readability.txt`, creating the directory first |
| `check_brand_drift` (row 18) | **Demonstrated directly, not by selftest.** Removing the allowlist entry turned the guard from PASS to FAIL naming the ten `gate_manifest.luau` lines that had been excused by it — that transition IS the proof the entry was load-bearing and that the guard now refuses the archived document's path like any other. `--selftest` cannot complete on this tree: it plants faults, restores, and then requires the restored tree to be clean, and the tree carries 189 matches this workstream does not own (§5.5). It exits 1 with `SELFTEST FAIL — restored tree not clean`, before reaching its own verdict |

## 4. Command results, run at the end of this workstream

| Command | Result |
|---|---|
| `stylua --check src tests tools bench examples` | **PASS** (exit 0, no output) |
| `lune run tools/lune/check_docs_cli` | **PASS** — 9 documents, 78 surface anchors, **3 comparison citations**, 167 local links, 14 themes exports documented, 24 scenario steps, 11 example packages, 17 asset files, 10 stale phrases absent |
| `lune run tools/lune/check_maintainer_map_cli` | **PASS** — 19 areas, 71 named specs, **42 gate rows**, 7 boundary rules, 20 public seams, 48 local links, 7 playbooks |
| `python3 tools/check_doc_style.py` | **PASS** — 24 documents; no over-long instruction step, no unexpanded acronym, no internal shorthand |
| `./run-tests.sh --fast` | **PASS — 7161 passed, 0 failed.** An earlier run of this tier read 7147/2; both failures were a single pre-existing red at `HEAD` owned elsewhere (`docs/extending/new-theme.md` had lost the `acceptance-ledger.md` mention that `check_docs`' playbook anchor list requires), and its owner fixed it before the judged full run |
| `tools/test.sh 7000` | **PASS — 7883 passed, 0 failed** (`artifacts/test.json`, fingerprint `36323d766bc6…`, `cached: false`) |
| `python3 tools/check_brand_drift.py --skip-builds` | **FAIL — 172 matches, none in a file this workstream owns.** Attribution in §5.5 |

## 5. Left for the verification agent — the exact rows and lines

`grep -rIl 'swiftui-parity' . --exclude-dir=.git --exclude-dir=artifacts` (minus
`docs/plans/**`, which is archived wholesale later) returns **three** files:
`phases.json`, `tools/lune/gate_manifest.luau`, and `tools/lune/verify/graph.json`.
**None is owned by this workstream.** All three belong to the verification
workstream.

### 5.1 `tools/lune/gate_manifest.luau` — 10 lines

Every one names `docs/reference/swiftui-parity.md`, which no longer exists, so
each is a **broken gate row regardless of the brand guard**.

| Line | What it does | What it needs |
|---|---|---|
| 633 | the eight-checker battery row: `… && grep -q 'measured per-preference constants' docs/reference/swiftui-parity.md` | drop that clause; the Dynamic Type measurement is documented at `docs/guide/05-styling.md` and pinned by `tests/large_text_layout.spec.luau` and `tests/preferred_text_seam.spec.luau` |
| 3190 | `parity-doc-falsifiable` `run` — four suite greps on `tests/theme_docs.spec.luau` case names **that no longer exist**, plus three `grep -qF` clauses against the deleted document | repoint at the new case names (below) or retire the row |
| 3191 | `parity-doc-falsifiable` `evidence = "docs/reference/swiftui-parity.md"` | point at `artifacts/distribution-readiness/swiftui-migration.md` (this file) or at `docs/guide/14-choosing-a-ui-library.md` |
| 3373 | `grep -qF "conditional refusal with a" / "incremental-arrange reuse skip…" / "ships **no** flow"` against the deleted document | the flow-wrap decision is stated in `src/layout/solver.luau` and pinned by `tests/flow_wrap.spec.luau` |
| 3386 | `grep -qF "SW-130" / "SW-131"` against the deleted document | the circular-progress contract is in `docs/reference/api.md` and pinned by `tests/progress_circular.spec.luau` |
| 3398 | `for c in SW-136 … SW-142; do grep -qF "\| **$c** \|" …` plus three symbol greps | the symbols are in `docs/reference/api.md`; `check_docs` already reconciles the export table against it |
| 3730 | `grep -qF "MODE of one arithmetic, not a second layout" / "The control gained an axis without gaining any arithmetic"` | the grid-flow decision is in `src/layout/grid.luau` and pinned by `tests/grid_column_flow.spec.luau` |
| 3736 | `grep -q "itemExtent = .measured." / ! grep -q "but never .ask the row."` | `docs/reference/api.md` (`newVirtualList`, `itemExtent`) and `tests/virtual_list_measured_extents.spec.luau` |
| 3841 | `grep -q "SW-153"` | `docs/reference/api.md` (`newTabView`) and `tests/tab_view.spec.luau` |
| 4322 | a `note` string quoting the path as the thing that must be deleted | reword to name this migration record; the deletion is done |

**The four `tests/theme_docs.spec.luau` case names line 3190 greps are gone.**
Their replacements, in order:

| Old case name (greps now fail) | New case name |
|---|---|
| `the live comparison document passes, and cites a substantial body of pages` | `the live tree's comparison document passes, and an absent one is not an error` |
| `fails when a verdict row asserts something uncited about the compared framework` | `fails when a framework it compares against carries no source URL` |
| `fails when the parity document loses the citation convention itself` | `fails when the comparison never marks a claim as an inference` |
| `passes on a minimal well-formed document (the fixture is not accidentally red)` | `passes on a minimal well-formed document, and reports that it read it` |

Also removed, with no replacement (their subject was the archived document's
`[SW-nn]`/§16 convention): `fails when a cited id has no §16 row to resolve
against`, `fails when a §16 row is defined but nothing cites it`, `fails when a
citation carries no vendor URL, no quote, or no date`, `fails when an exemption
stops matching, or when the row it excused gets cited`, `names the citation
obligations in the CLI's --list output` (renamed to `names the sourcing
obligations in the CLI's --list output`). Three new cases exist: `fails when the
comparison carries no ISO research date` and `fails when the comparison pins no
version, tag or commit`, plus the well-formed case above.

### 5.2 `phases.json` — 8 lines

Lines 211, 214, 217, 218, 227, 230, 233, 234, 235, 238, 241, 242 carry the stage
ids `swiftui-parity-round2/3/4` as `next`, `gate`, `artifactDir` and
`gateArtifact` values. They are stage ids, not document links, and each is also
the name of a frozen `artifacts/` directory. **They are not broken** — they are
the last public carrier of the retired stage name. Renaming them means renaming
the `artifacts/` directories too, which is the "gate/evidence archive" step the
allowlist's removal rules already point at.

### 5.3 One generated file from the verification workstream

| File | Note |
|---|---|
| `tools/lune/verify/graph.json` (untracked) | A generated graph of the gate manifest. It inherits every stage id and every `run` string from §5.1, so it carries ~48 vendor matches **plus rule-1 old-brand matches** (`luauui-…`), and it is the largest single contributor to the brand-drift failure. It needs its own allowlist entry, or to be generated outside the scanned tree. Regenerating it after §5.1 is repointed removes the vendor half but not the old-brand half |

Three other files carried the string mid-session and their owners cleared them
before this record closed: `tools/lune/check_links.luau` (an allowlist of link
targets), `tools/lune/verify/convert_manifest.py` (which had already written
*"the row pins `docs/reference/swiftui-parity.md`, which workstream E1 is
moving; repointed when `artifacts/distribution-readiness/swiftui-migration.md`
lands"* — it has landed), and `tools/relink_archived.py`. All three read zero
now.

### 5.4 `docs/plans/facet-consolidated-roadmap.md`

Two matches (lines 1641, 1808) are new, uncommitted plan prose naming the
compared framework in a file that **is** scanned for rule 2
(`VENDOR_HISTORY_MAINTAINED`, which carves the roadmap back in as maintained,
current-facing surface); owned by whoever wrote them.

### 5.5 Brand-drift attribution, exactly

`python3 tools/check_brand_drift.py --skip-builds` exits 1 with **172 matches**.
The guard prints 60 rows and then `… and 112 more`. Of the 60 shown:

| File | Rows shown | Owner |
|---|---|---|
| `tools/lune/verify/graph.json` | 48, including **rule-1 old-brand** matches (`luauui-…`), and the truncated remainder continues in this same file (its line numbers run past the last row printed) | verification workstream — this file needs its own allowlist entry, or to be generated outside the scanned tree |
| `tools/lune/gate_manifest.luau` | 10 | verification workstream (§5.1) |
| `docs/plans/facet-consolidated-roadmap.md` | 2 | plan-editing workstream (§5.4) |

**Zero matches are in a file this workstream owns**, and this workstream's edits
removed an allowlist entry rather than adding one: the entry that excused
gate-manifest run strings for opening the comparison document by its real path.
Its stated removal rule was *"when the comparison document retires"*, and it has.
Excusing a path to a deleted file would have masked ten broken gate rows.

## 6. Git history

This comparison is product research, not sensitive data. **No Git history was
rewritten, and none is proposed.** Every revision of
`docs/reference/swiftui-parity.md` before 2026-08-30 remains reachable in this
repository's history, and the owner packet must say so plainly. Removing them
from all public history would be a separate destructive-history decision needing
its own verified candidate and rollback plan.
