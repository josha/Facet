# Internalizing the decision records — what moved, and what proves it

**Workstream G, 2026-08-30.** The owner ruled (recorded in
`artifacts/distribution-readiness/execution-plan.md` §2 D2) that every decision
record and stage artifact is internal: `docs/adr/` (62 records plus two rubric
JSON files) and `docs/lessons/` (70 written-up defects) leave the public branch
tip for the checksummed private archive, and **no public file may cite one** — by
path, by identifier, or by lesson filename.

This document is the record of both halves: where each living rule went, and what
still catches a break.

## 1. What left, and where it is

| Path | Files | Where it is now |
|---|---|---|
| `docs/adr/` | 64 (62 records + `foundation-rubric.json` + `pilot-rubric.json`) | `Facet-private-archive/docs/adr/`, checksummed |
| `docs/lessons/` | 70 | `Facet-private-archive/docs/lessons/`, checksummed |
| `tools/lune/decision.luau`, `tools/decision.sh` | 2 | `Facet-private-archive/tools/`, checksummed — the record *generator* is internal machinery and goes with the trees it wrote into |

`python3 tools/archive_private.py archive …` copied 136 files; `verify` then
reported **OK — 218 file(s), 1,945,265 bytes**. The removal is commit
`5ceca8f`, made with `git commit -- <paths>` so the shared index agrees (a
`git status` afterwards shows no stray staged deletion of mine).

## 2. Citation sweep — counts per area

Every count is lines carrying `ADR-nnnn`, `docs/adr/` or `docs/lessons/`,
measured with `git grep -c` at the stage baseline `811427e` and again now.

| Area | Lines before | Files | Lines now |
|---|---|---|---|
| `src/` | 892 | 129 | 0 |
| `tests/` | 537 | 178 | 0 |
| `examples/` (text) | 223 | 70 | 0 |
| `bench/` | 5 | 3 | 0 |
| `tools/` (excluding the verification graph and gate manifest) | 126 | 41 | 0 |
| `docs/guide/` | 37 | 11 | 0 |
| `docs/reference/api.md` | 114 | 1 | 0 |
| `docs/reference/constitution.md` | 5 | 1 | 0 |
| `docs/extending/` | 20 | 6 | 0 |
| `README.md` | 3 | 1 | 0 |
| `AGENTS.md` | 4 | 1 | 0 |
| `CONTRIBUTING.md` | 1 | 1 | 0 |
| `CHANGELOG.md` | 13 | 1 | 0 |
| `.github/` | 1 | 1 | 0 |
| `requirements.json` | 4 | 1 | 0 |
| **Total** | **1,985** | **446** | **0** |

A second pass then removed the *bare* references — "the ADR", "an ADR",
"docs/lessons" with no filename — that the identifier pattern cannot see. Fifty
sites across `src/`, `tests/`, `examples/`, `tools/` and the public documents
(commit `22ca958`), including one genuinely broken link: `docs/MAINTAINERS.md`
pointed at `adr/`, which no longer resolves.

Style: a comment that already stated its rule simply lost the pointer; a comment
where the identifier carried the meaning gained the rule in plain words, with
every measured number kept verbatim. Nothing that was a *measurement* was
dropped.

## 3. Living-rule folds — old record to public home

These are the records that carried contributor-facing policy a public page
pointed at. Each rule now lives in a public page, in plain text.

| Record | The rule it carried | New public home |
|---|---|---|
| ADR-0011 (semantic versioning and deprecation) | semver shape; the pre-1.0 minor/patch rules; the 1.0 cut criteria; what "public surface" means; the `Facet.DEPRECATIONS` schema and its one-minor window; removal only in a minor or major; diagnosed-not-preserved | **`CONTRIBUTING.md` §6 "Versioning and deprecation"** (new section). `docs/reference/constitution.md` §14, `README.md`, `AGENTS.md`, `docs/guide/08-without-rojo.md` and `docs/reference/api.md` all point there now |
| ADR-0040 (breaking changes may ride an unreleased version) | the pre-release clause, and the row-by-row register of the 39 behavior changes riding the unreleased `0.10.0` | **`CHANGELOG.md` §`[0.10.0]`, "Behavior changes riding this unreleased version"** — all 39 rows, in plain language, with every measured number kept. The clause itself is in `CONTRIBUTING.md` §6 and restated in constitution §14 |
| ADR-0037 (composite controls live at `Facet.Controls.<Name>(core, spec)`) | the public call shape; `Facet.new<X>` stays for infrastructure; no item repeats the product's name; no rename for a generic word another framework uses | **`docs/reference/constitution.md` §2 (naming) and §3 (constructors)** — §3 gained the public call shape, §2 gained the two naming refusals |
| ADR-0019 + ADR-0020 (theme packages; rich skinning), cited by `docs/extending/new-theme.md` as required reading | six integration rulings a package author is held to (the touch floor clamps hit geometry not visuals; one controller per environment; two targets on one package share a sheet; gradients are palette; metric-derived paint follows a live edit in the same commit; contributed metrics resolve at build time), plus the fallback-target degradation | **`docs/extending/new-theme.md` §0 "Six rules the theme system holds you to"** (new), with the fallback-target paragraph after it. The image-driven half now points at `docs/guide/10-rich-skinning.md` and `docs/extending/skinned-control.md` |
| ADR-0009 (billboard target), cited by `docs/extending/new-render-target.md` | which module is the contract | the playbook now names `src/render/target_contract.luau` directly |
| ADR-0013 / ADR-0015, cited by `docs/extending/new-control.md` | the four-input bar; what mounting gives for free; affordances derive from the live class set, never `preferredInput` alone | stated in the playbook's own steps |
| ADR-0063 (world surface target), cited by `docs/extending/new-platform-mode.md` and `AGENTS.md` | the measured occlusion fact (geometry in front blocks input; `AlwaysOnTop = true` defeats it, which is why `surface_target` pins it false) | the playbook's gate table states the measurement itself; `CHANGELOG.md`'s `[0.10.0]` Added entry carries the same fact |
| ADR-0011 as the version's prose home (read by `check_docs`) | "the current version, restated in prose, must equal `Facet.VERSION`" | **`CHANGELOG.md`'s newest numbered heading** — see §4.2 |

Workstream E1's repointing into ADR texts is undone the same way: the two
contracts it had left in `ADR-0035` and `ADR-0040` (the preference decision and
the breaking register) are in `CHANGELOG.md` and the specs that prove them, and
the one lesson it named as `check_flat_baseline`'s "public home" is now stated in
that checker's own header.

## 4. Retired and narrowed checks — for the verification agent's coverage map

### 4.1 Checks whose subject was the leaving tree

| Check | What was retired | Why it is not a weakening |
|---|---|---|
| `tools/check_comment_codes.py` | **Route 2 retired.** A private code used to resolve if its comment block cited an `ADR-nnnn` that existed as a file. That route, `_adr_numbers()`, and the `ADR`/`SW` entries in `PUBLIC_PREFIX` are gone | A record a reader cannot open is not a referent. Three sites that resolved only through it were rewritten to define their code in plain language; two `SW-nn` ids in `src/controls/virtual_grid.luau` (which the retired `SW` prefix had been excusing) were deleted. `TOTAL_CEILING` **lowered 25 → 23**, the ratchet's own rule. Selftest rewritten and passing: a planted `TP-A12` is an orphan, the same code defined in its block **or named beside a shipped document** is resolvable |
| `tools/check_brand_drift.py` | `_adr_files()`, `_ADR_REF`, the ADR branch of `_references()`, the `("docs/adr/", …)` `VENDOR_HISTORY` exclusion and **five allowlist entries** for named ADR files | The reachability walk followed ADR numbers out of shipped pages; no shipped page carries one now. Removing the exclusion and the allowlist entries makes the guard *stricter*, and it is what took this command's failure from 172 matches to 3 |
| `tools/check_doc_style.py` | `"ADR"` removed from `COMMON` and from `SHORTHAND_ALLOW` (whose stated reason — "the guide cites them by number on purpose" — is now false); the failure message no longer offers "cite an ADR by number" | A re-introduced `ADR-nn` token in a public document is now internal shorthand and fails. Selftest still passes |
| `tools/lune/decision.luau`, `tools/decision.sh` | archived and removed | The generator only ever wrote into `docs/adr/` |

### 4.2 Checks repointed at a public home, with the same failure direction

| Check | Was | Is | Proof it still bites |
|---|---|---|---|
| `check_docs` §7b VERSION_DOCS | read `Current version: **x.y.z**` out of `docs/adr/ADR-0011-…` | reads `CHANGELOG.md`'s newest numbered heading, `## %[([%d%.]+)%]` | **Demonstrated**: editing that heading to `0.9.9` turned the checker red naming `CHANGELOG.md: says the current version is '0.9.9' but Facet.VERSION is '0.10.0'`; restoring it returned PASS |
| `tests/api_surface.spec.luau` "the published policy exists…" | `fs.readFile("docs/adr/ADR-0011-…")`, asserting MAJOR/deprecation and that it names `Facet.VERSION` | reads `CONTRIBUTING.md` for the policy words **and** `CHANGELOG.md` for the version, `string.match(changelog, "## %[([%d%.]+)%]")` | The case runs green; the changelog half is the same pin `check_docs` proves above |
| `tests/api_surface.spec.luau` "every surface the register records…" | read the ADR's `B-1`/`B-2` rows | reads `CHANGELOG.md` rows 1, 2 and the pre-release policy sentence | **Demonstrated**: three separate mutations of `CHANGELOG.md` (the `UI.AdaptiveStack.axis` row, the `UI.Grid` row, the policy sentence) each reddened this case; restoring returned 11 passed |
| `tests/native_style_default.spec.luau` "the flip is RECORDED…" | read the ADR's `B-15` row | reads `CHANGELOG.md` for `native_style.DEFAULT_ENABLED` and `` `nativeStyle = false` `` | **Demonstrated**: renaming the constant in the changelog, and separately removing the opt-out spelling, each reddened it |
| `tests/picker_segments.spec.luau` "the register records it…" | one pattern binding `\| B-20 \|` to its own row text | one literal binding the subject to its claim: `` `newPicker`'s activation order is now **one transaction** `` | **Demonstrated**: rewording that clause in the changelog reddened it. The 2026-08-22 discipline (bind the subject to the claim, never two loose substrings) is kept and stated in the case |
| `tests/tab_view.spec.luau` "the register records it…" | `\| B-21 \|` plus a loose "centred scroller" | two literals from one changelog row, subject then claim | The row was reworded so subject and claim sit on one line each |
| `tests/spatial.spec.luau` "no shipped document claims VR support" | the guarded set included `docs/adr/ADR-0021-spatial-seam.md`, which was the only file supplying the non-vacuity denials | the ADR is dropped from the set; `docs/extending/new-platform-mode.md` now states the denial plainly ("Nothing in this repository is a claim of VR support, and no shipped document may become one") | **Demonstrated**: the case went red when the ADR left (denials fell to zero) and green once the playbook carried the sentence; planting `Facet supports VR today.` in `docs/guide/README.md` reddens it |
| `tools/lune/check_links.luau` | scanned `docs/adr` and `docs/lessons`, and allowed links into them | both are removed from `SCANNED_DIRS` and **added to `ARCHIVED_PREFIXES`** | `--selftest` PASS: a dead link and an archived-material link are both reported, and the tree still passes |
| `tools/relink_archived.py` | scanned only `docs/adr` and `docs/lessons` — its whole subject | `ARCHIVED_PREFIXES` gains both; `SCANNED_DIRS` becomes the published trees (`docs/guide`, `docs/extending`, `docs/reference`), and a `docs/reference/` file that is not on the public list is skipped because it is archived material itself | `--check` found 45 stragglers, all of which this sweep rewrote by hand rather than annotating; it now reports **PASS — 24 documents, 375 links, none pointing into archived material** |
| `tests/paint_extensions.spec.luau`, `tests/foreign.spec.luau` | two source pins that quoted text this sweep changed (`===== PAINT CLAIMS (ADR-0022 Decision 6)`; an error message naming `ADR-0024`) | pin the surviving text (`===== PAINT CLAIMS ==`; `contentRoot`) | Both files green |

### 4.3 Checks that only *mentioned* the trees in prose — scan roots unchanged

Read and confirmed to scan nothing under `docs/adr` or `docs/lessons`:
`check_no_screen_key_bindings.py`, `check_input_authority.py` (scans `src`,
`examples`), `check_perf_gate_evidence.py`, `check_traversal_evidence.py`
(pins `docs/plans/…`), `check_source_size.py` (pins `docs/handoff/…`),
`tools/lune/check_scenario_requires.luau`, `tools/lune/check_flat_baseline.luau`.
Their prose citations were rewritten; no root was narrowed, because none of them
had reached into the leaving trees.

### 4.4 Renamed spec case names — 55 of them

A `describe` or `it` whose name contained a record identifier had to be renamed.
The suite count is unchanged (7,883), but any producer that looks a case up **by
name** needs the new spelling. The full old-to-new list is below.

| File | Kind | Old | New |
|---|---|---|---|
| `tests/adaptive.spec.luau` | describe | `ADR-0027: platformChrome states the L, not its bounding box` | `platformChrome states the L, not its bounding box` |
| `tests/adaptive.spec.luau` | describe | `ADR-0023 regression pin: the width facts are byte-unchanged` | `regression pin: the width facts are byte-unchanged` |
| `tests/adaptive.spec.luau` | describe | `ADR-0023: height and orientation are facts, not device names` | `height and orientation are facts, not device names` |
| `tests/adaptive.spec.luau` | describe | `director item 5: adaptive.effectiveDisplaySize (ADR-0058)` | `director item 5: adaptive.effectiveDisplaySize` |
| `tests/api_surface.spec.luau` | describe | `semantic versioning and deprecation (ADR-0011)` | `semantic versioning and deprecation` |
| `tests/api_surface.spec.luau` | it | `the semver/deprecation ADR exists and states the policy` | `the published policy exists and states the rules the ledger is built on` |
| `tests/api_surface.spec.luau` | it | `deprecations are a machine-readable ledger with the ADR's required fields` | `deprecations are a machine-readable ledger with the policy's required fields` |
| `tests/api_surface.spec.luau` | describe | `the public SHAPE a breaking change moves (ADR-0040)` | `the public SHAPE a breaking change moves` |
| `tests/api_surface.spec.luau` | it | `every surface ADR-0040 records as breaking is really in the pinned shape` | `every surface the register records as breaking is really in the pinned shape` |
| `tests/authored_presentation.spec.luau` | describe | `authored presentation B — the composition rule (ADR-0026 Decision 2)` | `authored presentation B — the composition rule` |
| `tests/authoring.spec.luau` | it | `every diagnosed property is in the ADR-0011 ledger with all required fields` | `every diagnosed property is in the deprecation ledger with all required fields` |
| `tests/button_shape.spec.luau` | it | `refuses an asset id in \`icon\` — a control never names an asset (ADR-0020 R4)` | `refuses an asset id in \`icon\` — a control never names an asset` |
| `tests/composition.spec.luau` | describe | `ADR-0023: the arrangement is chosen from the BOX, on both axes` | `the arrangement is chosen from the BOX, on both axes` |
| `tests/composition.spec.luau` | describe | `ADR-0023: step down before dropping, both in descending rank` | `step down before dropping, both in descending rank` |
| `tests/composition.spec.luau` | describe | `ADR-0023: floors are content, and absolute` | `floors are content, and absolute` |
| `tests/composition.spec.luau` | describe | `ADR-0023: slack flows to fill; reserved holds; empty is absent` | `slack flows to fill; reserved holds; empty is absent` |
| `tests/composition.spec.luau` | describe | `ADR-0023 rule 9 (DV6-2): an all-empty lane COLLAPSES and gives up its width` | `rule 9 (DV6-2): an all-empty lane COLLAPSES and gives up its width` |
| `tests/composition.spec.luau` | describe | `ADR-0023 (2026-07-31): a group may SPAN the composition as its own row` | `2026-07-31: a group may SPAN the composition as its own row` |
| `tests/composition.spec.luau` | describe | `ADR-0023: exactly one scroll region` | `exactly one scroll region` |
| `tests/composition.spec.luau` | describe | `ADR-0023: a bad declaration is refused where it is written` | `a bad declaration is refused where it is written` |
| `tests/composition.spec.luau` | describe | `ADR-0023: the resolution is deterministic and dumpable` | `the resolution is deterministic and dumpable` |
| `tests/composition.spec.luau` | describe | `ADR-0023: UI.Composition, mounted` | `UI.Composition, mounted` |
| `tests/composition_exclusions.spec.luau` | it | `...and the bottom-anchored zone lands INSIDE the composition, on a phone (ADR-0056)` | `...and the bottom-anchored zone lands INSIDE the composition, on a phone` |
| `tests/controls_namespace.spec.luau` | describe | `ADR-0037: the Controls namespace` | `the Controls namespace` |
| `tests/controls_namespace.spec.luau` | it | `exports exactly the nineteen composite controls the ADR names, and nothing else` | `exports exactly the nineteen composite controls the namespace names, and nothing else` |
| `tests/controls_namespace.spec.luau` | it | `every old-form builder carries its ADR-0037 deprecation row` | `every old-form builder carries its deprecation row` |
| `tests/drag_public.spec.luau` | it | `falls back to the ADR-0008 pointer capture when the engine has no detector` | `falls back to the framework pointer capture when the engine has no detector` |
| `tests/edge_floor.spec.luau` | it | `a literal-number edgeFloor floors bottom/left/right, never top (ADR-0027)` | `a literal-number edgeFloor floors bottom/left/right, never top` |
| `tests/hint_no_remount.spec.luau` | describe | `hint changes without remount (ADR-0004)` | `hint changes without remount` |
| `tests/hud_chrome_rotation.spec.luau` | describe | `ADR-0027 + director item 4: the APP's chrome is reserved per column` | `director item 4: the APP's chrome is reserved per column` |
| `tests/hud_composition.spec.luau` | describe | `ADR-0025: the nine anchors PARTITION the screen` | `the nine anchors PARTITION the screen` |
| `tests/hud_composition.spec.luau` | describe | `ADR-0025 Decision 2: holdsLane pins a column that has nothing in it` | `holdsLane pins a column that has nothing in it` |
| `tests/hud_composition.spec.luau` | describe | `ADR-0027: the \`topbar\` zone is a span row, and it is free when unused` | `the \`topbar\` zone is a span row, and it is free when unused` |
| `tests/hud_composition.spec.luau` | describe | `ADR-0025: a height shrink DEGRADES, in rank order` | `a height shrink DEGRADES, in rank order` |
| `tests/hud_composition.spec.luau` | describe | `ADR-0025 Decision 3: a zone painting over its neighbour is REPORTED` | `a zone painting over its neighbour is REPORTED` |
| `tests/hud_composition.spec.luau` | describe | `ADR-0025: a mounted HUD loses 200px of height` | `a mounted HUD loses 200px of height` |
| `tests/hud_composition.spec.luau` | describe | `ADR-0027: nothing the HUD paints lands on the platform's own controls` | `nothing the HUD paints lands on the platform's own controls` |
| `tests/interaction_tokens.spec.luau` | it | `publishes the three ADR-0014 bands presenter.luau's own comment states` | `publishes the three bands presenter.luau's own comment states` |
| `tests/native_style_default.spec.luau` | describe | `the library default paint path (ADR-0040 B-15)` | `the library default paint path` |
| `tests/native_style_default.spec.luau` | it | `the flip is RECORDED in ADR-0040, which is what makes it legal` | `the flip is RECORDED in the changelog, which is what makes it legal` |
| `tests/nested_tree_pins.spec.luau` | describe | `ADR-0032 D3: the depth-first z counter IS Sibling paint order` | `the depth-first z counter IS Sibling paint order` |
| `tests/nested_tree_pins.spec.luau` | describe | `ADR-0032 Consequences: tapAt and the z counter cannot disagree` | `tapAt and the z counter cannot disagree` |
| `tests/nested_tree_pins.spec.luau` | describe | `ADR-0032 D4/D5: the framework writes ONE node, the engine carries the subtree` | `the framework writes ONE node, the engine carries the subtree` |
| `tests/nested_tree_pins.spec.luau` | describe | `ADR-0032: a host's rect lands BEFORE its descendants', or they re-base against a ghost` | `a host's rect lands BEFORE its descendants', or they re-base against a ghost` |
| `tests/picker_segments.spec.luau` | it | `the register records it: ADR-0040 carries the one-turn row` | `the register records it: the changelog carries the one-turn row` |
| `tests/prefix_tests.spec.luau` | describe | `a prefix test cannot disagree with the prefix it tests (ADR-0038 fallout)` | `a prefix test cannot disagree with the prefix it tests (rename fallout)` |
| `tests/space_tight_step.spec.luau` | describe | `space.tight — the missing spacing step (ADR-0047)` | `space.tight — the missing spacing step` |
| `tests/surface_overlap.spec.luau` | describe | `cross-surface overlap: the covering set (ADR-0026's hand-off)` | `cross-surface overlap: the covering set` |
| `tests/tab_view.spec.luau` | it | `the register records it: ADR-0040 carries the hug-band row` | `the register records it: the changelog carries the hug-band row` |
| `tests/tab_view.spec.luau` | it | `the shoulders are UNBOUND while focus sits off the strip — the ADR-0013 hazard` | `the shoulders are UNBOUND while focus sits off the strip — the auto-wiring hazard` |
| `tests/theme_chrome.spec.luau` | it | `maps the renderer's existing hints to the ADR-0019 slot vocabulary` | `maps the renderer's existing hints to the theme slot vocabulary` |
| `tests/theme_package.spec.luau` | describe | `theme package: namespaced contribution coverage (ADR-0019 §1)` | `theme package: namespaced contribution coverage` |
| `tests/theme_roles.spec.luau` | describe | `text_metrics: canonical font-descriptor keys (ADR-0019 §6)` | `text_metrics: canonical font-descriptor keys` |
| `tests/theme_snapshot.spec.luau` | describe | `themes.resolve: composition happens exactly once, in ADR order` | `themes.resolve: composition happens exactly once, in the declared order` |
| `tests/virtual_grid_input.spec.luau` | it | `VirtualGrid keyboard: the focus dump REPORTS the second axis (ADR-0030)` | `VirtualGrid keyboard: the focus dump REPORTS the second axis` |
| `tests/virtual_list_axis.spec.luau` | it | `rowHeight / viewportHeight still work UNCHANGED — the deprecated aliases (ADR-0011)` | `rowHeight / viewportHeight still work UNCHANGED — the deprecated aliases` |
| `tests/with_animation.spec.luau` | describe | `withAnimation: a registered CURVE drives the flight (ADR-0033)` | `withAnimation: a registered CURVE drives the flight` |

One case name in `docs/extending/new-theme.md`'s pass condition moved with its
spec: `"theme package: namespaced contribution coverage (ADR-0019 §1)"` →
`"theme package: namespaced contribution coverage"`, in both places.

## 5. `requirements.json` — the outcome

Consumers were checked first (`grep -rn requirements.json tools tests`):
`tools/lune/verify/convert_manifest.py` reads `id`, `title` and `firstGate`;
`tools/check_comment_codes.py` reads the file as text to resolve requirement
ids; `tools/check_brand_drift.py` scans it; `tools/doctor.sh` checks only that
it exists. **Nothing reads the per-requirement `spec` field or the top-level
`source` field.** So the four record citations were neutralized in place rather
than the fields removed:

- `UI-INPUT-002`'s `note`: "deferred from phase-0 by ADR-0004 …" → "deferred
  from phase-0 …";
- `UI-INPUT-003`'s `title`: "Split test harness (ADR-0004): …" → "Split test
  harness: …";
- `UI-PARADIGM-001`'s `spec`: dropped the trailing "; ADR-0015";
- `UI-WORLD-001`'s `spec`: "ADR-0009 riders" → "the billboard riders".

The file still parses (`json.load`) and `check_comment_codes` still resolves
every `UI-…` id through it.

## 6. Rascal Rally — the lines that pointed into the Facet tree

Rascal Rally keeps its own `docs/lessons/` and its own internal references; only
lines citing a **Facet** record path were broken by this removal. Nine, in eight
files, fixed in commit `a72cccc`:

| File | Was | Now |
|---|---|---|
| `src/client/GaragePilotScreen.luau:4` | `GameStudio/ui/Facet/docs/adr/ADR-0005-phase3-pilot-selection.md` | "selected by rubric" |
| `src/client/FacetSponsor/init.luau:2796` | `docs/lessons/the-solver-already-told-you.md` | "the solver already told you" |
| `tests/facet_racer_list.spec.luau:699` | `.../docs/lessons/a-forty-four-pixel-floor-under-an-eight-pixel-divider.md` | "a 44px touch floor under an 8px divider" |
| `tests/facet_stack_arrange_contract.spec.luau:135` | `Facet docs/lessons/the-solver-already-told-you.md` | "ASK THE SOLVER — it already told you" |
| `tests/facet_nested_tree_consumer_contract.spec.luau:2` | `Facet docs/adr/ADR-0032-nested-instance-tree.md` | "Facet's nested instance tree" |
| `tests/facet_presenter_seam_contract.spec.luau:4` | `docs/adr/ADR-0053-presenter-seam-family.md` | "items 13/23/24, task W3-D" |
| `tests/facet_presenter_seam_contract.spec.luau:132` | `docs/adr/ADR-0053-… §3` | the formula is quoted directly, unchanged |
| `tests/facet_foreign_seam_contract.spec.luau:4` | `.../docs/adr/ADR-0034-foreign-instance-seam.md` | `GameStudio/ui/Facet/docs/reference/api.md §Foreign` |
| `tests/facet_theme_paint_contract.spec.luau:233` | `.../docs/lessons/a-default-valued-write-never-claims.md` | "a default-valued write claims nothing" |

`./run-tests.sh` in `games/RascalRally/code`: **3541 passed**.
`stylua --check src tests`: clean.

## 7. Proofs — every result line

| Command | Result |
|---|---|
| `grep -rInE 'ADR-[0-9]{4}\|docs/adr/\|docs/lessons/' src tests examples bench tools docs/guide docs/reference/api.md docs/reference/constitution.md docs/extending docs/MAINTAINERS.md README.md CONTRIBUTING.md SECURITY.md CHANGELOG.md AGENTS.md skills package .github` | **4 lines, all allowed and all in this workstream's own leaving-set declarations**: `tools/lune/check_links.luau:67-68` and `tools/relink_archived.py:42-43`, each the two path literals `"docs/adr/"` and `"docs/lessons/"`. Plus 377 lines in two files this workstream does not own: `tools/lune/verify/graph.json` (261) and `tools/lune/gate_manifest.luau` (116) |
| `python3 tools/check_public_allowlist.py --report` | `docs/adr` and `docs/lessons` appear **zero** times — they are no longer tracked. The command itself still FAILs on 615 stray paths (`docs/plans`, `docs/handoff`, `artifacts/`, `ui_todo.md`, …) that belong to other workstreams |
| `python3 tools/archive_private.py verify` | **OK — 218 file(s), 1,945,265 bytes** |
| `lune run tools/lune/check_links_cli` | **PASS** — 31 documents, 458 relative links, 155 heading anchors |
| `lune run tools/lune/check_links_cli -- --selftest` | **PASS** — a dead link and an archived-material link are both reported, and the tree itself still passes |
| `lune run tools/lune/check_docs_cli` | **PASS** — 9 documents, 78 surface anchors, 3 comparison citations, 166 local links, 14 themes exports documented, 24 scenario steps, 11 example packages, 17 asset files, 10 stale phrases absent |
| `python3 tools/check_doc_style.py` | **PASS** — 24 documents; no over-long instruction step, no unexpanded acronym, no internal shorthand |
| `python3 tools/check_doc_style.py --selftest` | **PASS** |
| `python3 tools/check_brand_drift.py --skip-builds` | **FAIL — 3 old-brand matches, none in a file this workstream owns**: `docs/plans/facet-consolidated-roadmap.md:1641,1808` (the plan-editing workstream) and `tools/lune/verify/mutation_parity.py:213` (the verification workstream). It was 172 before this sweep |
| `python3 tools/check_comment_codes.py` | **PASS** — 0 orphans (ceiling 0), 23 resolvable (ceiling 23) across 19 files; routes `{defined-in-block: 22, docs/reference/api.md: 1}` |
| `python3 tools/check_comment_codes.py --selftest` | **PASS** |
| `python3 tools/relink_archived.py --check` | **PASS** — 24 documents, 375 links, none pointing into archived material |
| `lune run tools/lune/check_boundary` | **PASS** — 171 src files, 426 consumer files |
| `lune run tools/lune/check_registration_cli` | **PASS** — 41 controls, 105 exports documented, 299 specs registered, 19 prove four-input, 19 prove the paradigm axis |
| `lune run tools/lune/check_maintainer_map_cli` | **PASS** — 19 areas, 71 named specs, 42 gate rows, 7 boundary rules, 20 public seams, 50 local links, 7 playbooks |
| `python3 tools/check_no_fusion.py` | **PASS** — no Fusion name, require, path or vendored directory |
| `stylua --check src tests tools bench examples` | **PASS** (exit 0, no output) |
| `./run-tests.sh --fast` | **PASS — 7161 passed, 0 failed** |
| `tools/test.sh 7000` | **PASS — 7883 passed** (`artifacts/test.json`), the same count as the stage baseline |
| Rascal Rally `./run-tests.sh` | **PASS — 3541 passed** |

## 8. One documentation change the owner asked for mid-run

The introductory snippets taught `padding = 16, gap = 8` — a literal number is the
documented theme-independent escape hatch, so the first thing a reader copied was
the escape hatch. All five now read `padding = "m", gap = "s"`
(`README.md`, `docs/guide/01-concepts.md`, `docs/guide/03-getting-started.md`
twice, `docs/guide/08-without-rojo.md`), and `01-concepts.md` gained one sentence
saying what the tokens mean and that a plain number is legal but fixed.
`examples/consumer/src/screen.luau` already used tokens and is unchanged;
`tests/consumer_standalone.spec.luau` is green. The token form was proved
equivalent at Studio Neutral by mounting the exact snippet: label rect `(16, 16)`,
button at `y = 44` — the same geometry the literals produced, now following a
theme swap and the ten-foot ladder.

## 9. Left for the director

- `tools/lune/verify/graph.json` (261 lines) and `tools/lune/gate_manifest.luau`
  (116 lines) still carry record identifiers and `docs/adr/` paths. Both belong
  to the verification workstream; every clause in them that pinned a decision
  record now pins a file that does not exist.
- `check_public_allowlist` is still red on 615 stray paths owned by other
  workstreams; `docs/adr` and `docs/lessons` are not among them.
- `check_brand_drift` is red on 3 matches, listed above by pathname, none of them
  this workstream's.
