# Verification parity with main

This page compares the verification of the native cutover with the
verification on `main`. It compares test assertions, not file names. It
also compares the verification producers. The data is in
[`tools/lune/verification_parity.json`](../../tools/lune/verification_parity.json).
[Verification scope](18-verification-scope.md) records the earlier,
file-level audit.

## Result

Verification on the candidate is weaker than on `main`. The candidate does
not verify some behavior that it still promises. The sections below show
where.

- 894 main cases test behavior that `api.md`, a guide or `src`
  still promises, but no candidate case tested it. The parity tests close
  884 of these cases. One case moved to class c, because `api.md`
  no longer makes its promise. 3 cases remain. Only a live check with a
  real drag can close them. See [Gap list](#gap-list).
- 408 of the 3,908 covered cases have a weaker
  candidate assertion. Usually one candidate case replaces several main
  edge cases.
- 1,312 cases moved to a Roblox Engine or Compose mechanism. For
  126 of them (39 contracts), no candidate test and no live Studio
  record show that Facet uses the mechanism correctly. See
  [Engine mechanism tests](#engine-mechanism-tests).
- Of 130 main `full` producers, no producer is a gap and no producer is a
  weaker replacement. The five Studio producers of the performance lab have
  their evidence. See [Producers](#producers).
- A complete run writes `artifacts/verify/latest-<tier>.json` with release
  gate evidence. `tools/package.sh publish` reads the `release` file and
  refuses anything but a clean, passing run of the same source.
- The audit found 10 defects in `src` and 3 in the examples. All of them
  are fixed. The parity tests found and fixed 18 more defects in `src` and
  7 more in the examples. [Fixed after the audit](#fixed-after-the-audit)
  names the test for each fix.

## Method

1. Load `tests/run.luau` at the baseline with registration recorded and
   execution suppressed. This gives 10,848 cases in 500 spec files.
2. Read each main spec. Group its cases into behavioral contracts. A
   contract is a behavior that a game author can rely on.
3. Classify each contract against the candidate tests, `api.md`, the guides
   and `src`.
4. Open each cited candidate case and confirm its assertion. Do not trust
   the candidate coverage ledger.
5. Probe the reported defects again at the recheck commit.

| Item | Value |
|---|---|
| Baseline | `a8c8895673c0745506908b66dc89f8cead6b66f3` |
| Candidate audited | `131e9dc7` |
| Candidate rechecked | `eddfa580` |
| Main cases | 10,848 |
| Contracts | 2,290 |
| Candidate cases at recheck | 675 |

Another session changed `src` during the audit. Some defects were fixed
during the audit. [Fixed during the audit](#fixed-during-the-audit) lists
them. A gap can also close after the audited commit. Check the gap against
the current tests before you write a test.

## Classes

| Class | Meaning | Contracts | Main cases (audit) | Main cases (with new tests) |
|---|---|---:|---:|---:|
| a | Covered by a candidate case | 1717 | 2,294 | 4,095 |
| b | Retired. The Roblox Engine or Compose owns the mechanism | 255 | 1,581 | 1,301 |
| c | Retired. The feature or code was deleted and is not promised | 842 | 6,079 | 6,015 |
| d | Gap. A promise remains and no candidate case verifies it | 1 | 894 | 3 |

The contract counts and the main-case counts with new tests are the sums over
the contracts in `tools/lune/verification_parity.json`. They include the
contracts with a `mainBaseline` field, which record main cases that main added
after the baseline.

Class c is the largest class. Most of it tested the deleted solver,
renderer, focus graph, input system, presenter, paint layer and their seams.
Those checks cannot run against the native implementation. Their retirement
is correct when the public API no longer makes the promise.

## Contract groups

"Weaker" counts the covered cases with a weaker candidate assertion. The
last column names the candidate specs that the group cites most.

| Group | Main cases | a | Weaker | b | c | d | Candidate coverage |
|---|---:|---:|---:|---:|---:|---:|---|
| Reactive core | 64 | 23 | 0 | 4 | 37 | 0 | `native_compose_contract`, `native_public_surface`, `native_navigation` |
| Lifetime and ownership | 333 | 158 | 3 | 6 | 169 | 0 | `native_conformance`, `native_stress`, `native_themes_media` |
| Layout and geometry | 1,400 | 296 | 112 | 204 | 900 | 0 | `native_inputs`, `native_navigation`, `native_parity_navigation` |
| Text measurement and fit | 510 | 100 | 43 | 233 | 177 | 0 | `native_inputs`, `native_collections`, `native_parity_navigation` |
| Focus and selection | 547 | 168 | 38 | 222 | 157 | 0 | `native_navigation`, `native_collections`, `native_inputs` |
| Input actions | 344 | 132 | 6 | 90 | 122 | 0 | `native_inputs`, `native_navigation`, `native_collections` |
| Pointer, touch and drag | 393 | 94 | 2 | 88 | 211 | 0 | `native_collections`, `native_radial_controls`, `native_virtual_monitors` |
| Scrolling | 332 | 125 | 7 | 90 | 117 | 0 | `native_collections`, `native_gallery_collections`, `native_virtual_monitors` |
| Motion | 596 | 174 | 5 | 18 | 404 | 0 | `native_themes_media`, `native_navigation`, `native_inputs` |
| Paint and theming | 739 | 260 | 21 | 33 | 446 | 0 | `native_themes_media`, `native_inputs`, `native_navigation` |
| Theme packages | 394 | 162 | 9 | 0 | 232 | 0 | `native_themes_media`, `native_inputs`, `native_gallery_shell` |
| Icons and media | 255 | 120 | 2 | 37 | 98 | 0 | `native_themes_media`, `native_stress`, `native_public_surface` |
| Action controls | 414 | 117 | 9 | 0 | 297 | 0 | `native_inputs`, `native_navigation`, `native_themes_media` |
| Value controls | 299 | 269 | 14 | 0 | 30 | 0 | `native_inputs`, `native_parity_controls`, `native_themes_media` |
| Text input | 173 | 124 | 14 | 28 | 21 | 0 | `native_inputs`, `native_navigation`, `native_collections` |
| Menus and pickers | 231 | 192 | 37 | 0 | 39 | 0 | `native_navigation`, `native_parity_navigation`, `radial_geometry` |
| Navigation containers | 90 | 87 | 5 | 1 | 2 | 0 | `native_navigation`, `native_gallery_shell`, `native_radial_controls` |
| Presented surfaces | 333 | 169 | 16 | 5 | 159 | 0 | `native_navigation`, `native_parity_navigation`, `native_gallery_parity` |
| Virtual collections | 224 | 169 | 1 | 3 | 52 | 0 | `native_collections`, `native_gallery_collections`, `native_perf_principles` |
| Tables | 156 | 97 | 0 | 1 | 58 | 0 | `native_collections`, `native_gallery_workflows`, `native_gallery_collections` |
| Row actions | 264 | 162 | 13 | 0 | 99 | 3 | `native_collections`, `native_parity_controls`, `native_gallery_workflows` |
| HUD and world targets | 171 | 58 | 0 | 48 | 65 | 0 | `native_hud`, `native_themes_media`, `native_outpost_terminal` |
| Adaptive environment | 427 | 84 | 5 | 49 | 294 | 0 | `native_navigation`, `native_parity_navigation`, `native_radial_controls` |
| Public surface | 373 | 93 | 0 | 0 | 280 | 0 | `native_conformance`, `native_registration`, `native_parity_gaps` |
| Docs, examples and tooling | 513 | 51 | 0 | 0 | 462 | 0 | `native_documentation`, `native_registration`, `scenario_require_paths` |
| Gallery and examples | 442 | 257 | 47 | 113 | 72 | 0 | `native_gallery`, `native_games`, `native_gallery_collections` |
| Reference apps | 327 | 152 | 0 | 22 | 153 | 0 | `native_reference_apps`, `native_outpost_rules`, `scenario_require_paths` |
| Performance | 792 | 84 | 6 | 4 | 704 | 0 | `native_perf_principles`, `native_themes_media`, `native_perf_lab` |
| Replication and server state | 55 | 31 | 0 | 0 | 24 | 0 | `native_outpost_terminal`, `native_stress`, `native_gallery` |
| Error handling and refusals | 253 | 111 | 10 | 2 | 140 | 0 | `native_navigation`, `native_parity_navigation`, `native_parity_gaps` |

## Where verification is weaker

### Geometry and native mechanisms

The headless engine does not solve Roblox layout or text bounds. Main tested
its own solver. Thus the candidate has no headless oracle for these
results:

- final positions and sizes of controls,
- text fit and truncation at the largest text size,
- safe-area and top-bar insets,
- the fit of the showcase on each viewport (`overflow_sweep`, 124 cases),
- selection visuals and scroll-into-view geometry.

`tools/lune/parity_blockers.json` still lists one pending live risk: haptic
motor output on a physical phone and gamepad. The `coverage` producer fails
for this reason. Studio shows only that the controls request the effects.

The live Studio harness in `tools/studio/live` records engine evidence for 424
contracts (1,586 main cases) in the `liveEvidence` field of each contract. The
results are in `artifacts/studio-live`. The runs use the console and phone
device emulators, a fixed stage size for each case, and the Medium text size.
Earlier runs used 844x369 and 388x824 at the Medium and Largest text sizes.
The harness found these defects, and the branch fixes them:

- The collection toolbar took the whole page on a short landscape phone, so
  the list had no height.
- The gallery shell reserved a fixed 56 px, and a taller Settings button
  overlapped the demo tabs.
- A top callout with no room above covered its anchor.
- A circle Button with a Size on one axis only collapsed to 0x0.
- A stretched stack child was only as wide as the widest child.
- The last cell of a Grid wrapped to a new line because of rounding.
- The automatic Picker kept clipped segments for long labels.
- An Alert did not take the selection when its screen reached the
  `PlayerGui` after the first frame.
- Callouts and help plates were placed against the whole layer, not inside
  `overlayParent`.
- The reference apps' notice line was wider than the screen.
- A Pagination page slot, the StepIndicator number circle, a hugging ZStack
  with end alignment, the scaled container tiles, the affixed Notice
  reservation, the settings row columns, a lifted Card in a grid, a menu
  landing row, the popover body height, the hero media height, a picker built
  open, and a collection focus restore before a `PlayerGui` did not match the
  main behavior.

A later recheck fixed these defects:

- A wrapped label in an automatic-size chain inside a scroller was cut to the
  height of the scroller window. The Sheet, Dialog, Popover, Alert and
  multiline field bodies now measure their content in a tall frame and set
  the canvas from it.
- The Pagination row did not take the selection from a control that is not
  above or below it. The row now takes the selection and gives it to the
  current page.
- The category bar gave a wide label to its trailing accessory, and a tab
  word that did not fit at the caption size was cut. The accessory is an
  icon in a bottom bar, a crowded bottom bar scrolls, and a fitted word
  steps down until the engine reports that it fits.
- A lifted card changed the measured row size, and the selection box of a
  cell grew from its corner. The row is measured without the lift, and the
  selection box grows from its center.
- The error mark was taller than its message line, and a field title could
  keep a stale height after the style sheet set its text size. The mark
  follows the line, and the title is measured again on a later frame.
- A multiline field did not scroll to the caret line. The viewport now
  follows the caret.
- The ColorPicker format strip grew with its own segments, a segment was
  38 px tall, and the plane bubble was cut at the top of the plane. The
  strip has a fixed height that keeps each segment at 44 px, and the bubble
  moves beside the finger when there is no room above it.
- A click on the avatar of a menu row did not select the row. The avatar
  no longer takes the input.
- The mouse points of the port suites included the top bar inset, so the
  clicks missed. The Studio input tools take points in the same space as
  `AbsolutePosition`.

Live findings that remain are in the `liveFinding` field of 1 contract:

- A click on the painted track of a rotated Slider does not move a handle
  when the point is outside the unrotated box of the track. The engine
  hit-tests the track in that box (`post-pickers-102`).

[Device verification](11-device-verification.md#live-assertion-harness)
describes the harness and its limits.

### Workloads

| Main workload | Main size | Candidate |
|---|---|---|
| Scheduler fuzz | 400 seeded cases | None. Compose owns the scheduler. Its own tests do not run here. |
| Layout fuzz | 400 cases and 60 adversarial cases | None. Roblox layout is not fuzzed. |
| Replication fuzz | 400 seeded cases | 400 seeded deliveries against an example model |
| Fault scenarios | 9 scenarios, 200 iterations each | 200 seeded async fault storms and 200 preference storms |
| Soak | Presenter and scene soak fixtures | 200 modal cycles and 100 structural cycles, twice |
| Accessibility and localization corpus | Corpus CLI and fixtures | `native_a11y_l10n_corpus`: accessible names of 36 controls and every gallery demo; 14 strings through 20 text controls |

### Ledger quality

The audit recorded 187 disagreements with the candidate
coverage ledger (`tools/lune/coverage_*.json`). These are the common types:

- The ledger cites a case that does not assert the mapped behavior.
- The ledger calls a spec a retired mechanism, but `api.md` still promises
  the behavior.
- The ledger calls a deleted module "replaced".
- The ledger hides a changed behavior in `retiredAssertions`.

The `replacement-cases` producer only checks that cited cases pass. It does
not check that they assert the behavior.

## Producers

Main ran 130 producers in its `full` tier. The table below gives the status
of each one after the producer restoration. The data is in `producers.rows`.

| Status | Main `full` producers |
|---|---:|
| Equivalent candidate producer | 52 |
| Replaced by a different check | 16 |
| Replaced by a weaker check | 0 |
| Producer runs; its live evidence is not recorded | 0 |
| Retired with its subject | 62 |
| Total | 130 |

No main producer is a gap now. Each main producer is equivalent, replaced,
or retired with its subject.

### How the candidate runs its producers

`tools/verify.sh <tier>` runs every producer whose tiers include that tier.
Use `--explain` to see each selected producer, its environment, its tiers and
the main producers that it replaces.

- A producer that exits 0 passes.
- A studio or device producer that exits 2 reports `FAIL_ENVIRONMENT`. Its
  live evidence is not recorded in this checkout.
- A perf producer that exits 2 reports `FAIL_ENVIRONMENT`. A host timing
  budget failed. With `--reference-host`, the same result is `FAIL`.
- Any other exit code is `FAIL`.
- The `full` tier reports `FAIL_ENVIRONMENT` and continues. The `release`
  tier stops on it.

Main put `perf` and `bench` in the `release` tier only, and its `full` tier
read a recorded report. The candidate runs `perf` and `bench` in `full`, and
then checks the report of the same run.

At the producer recheck, `tools/verify.sh full --explain` selected 71
producers: 61 passed, 9 reported `FAIL_ENVIRONMENT` and 1 failed. The failure
is `coverage`, because `tools/lune/parity_blockers.json` lists three pending
live risks. The `FAIL_ENVIRONMENT` results are the five Studio evidence modes,
the missing cited artifacts of `live-evidence`, and the host timing results of
`perf`, `bench` and the `perf-gate` evidence mode. The host ran several Roblox
Studio sessions during the run, so its timings are not reference timings.

### Equivalent producers

| Main producer | Candidate producer | Tier | Note |
|---|---|---|---|
| `check_public_surface` | `public-surface` | full, release | Snapshot of the public surface in tools/public_surface.txt, including the controls table and exported types. |
| `build_model` | `model-build` | full, release | Moved from a CI-only step into the full tier. |
| `build_places` | `standalone-builds` | full, release |  |
| `build_reference_places` | `reference-builds` | full, release |  |
| `build_themes` | `theme-builds` | full, release |  |
| `build_word_lists-check` | `word-data` | full, release |  |
| `build_word_lists-selftest` | `word-data-selftest` | full, release |  |
| `check_experiment_markers` | `experiment-markers` | fast, full, release |  |
| `check_brand_drift` | `brand-drift` | full, release | Old-brand and vendor-name rules; the sibling game and studio trees are skipped when absent. |
| `check_brand_drift-selftest` | `brand-drift-selftest` | full, release |  |
| `check_brand_drift-skip-builds` | `brand-drift-skip-builds` | full, release |  |
| `check_call_shape_drift` | `call-shape-drift` | full, release | Refuses calls to constructors and scaffolding that the native API removed, in examples, bench, tests and doc snippets. |
| `check_call_shape_drift-selftest` | `call-shape-drift-selftest` | full, release |  |
| `check_doc_style` | `doc-style` | full, release | Scans docs/guide, docs/extending, README.md and docs/MAINTAINERS.md. |
| `check_doc_style-selftest` | `doc-style-selftest` | full, release | See check_doc_style. |
| `check_library_purity` | `package-purity` | full, release |  |
| `check_links_cli` | `links` | full, release |  |
| `check_links_cli-selftest` | `links-selftest` | full, release |  |
| `check_maintainer_map_cli` | `maintainer-map` | full, release | Checks the native module areas, the proof table and the repository table. |
| `check_maintainer_map_cli-selftest` | `maintainer-map-selftest` | full, release | See check_maintainer_map_cli. |
| `check_no_fusion` | `no-fusion` | fast, full, release |  |
| `check_no_fusion-selftest` | `no-fusion-selftest` | fast, full, release | Tool exists and passes; not run. |
| `check_no_screen_key_bindings` | `screen-key-bindings` | fast, full, release | Refuses raw key handling in example screens and doc snippets. |
| `check_no_screen_key_bindings-selftest` | `screen-key-bindings-selftest` | fast, full, release |  |
| `check_perf_budgets` | `perf-budgets` | full, release |  |
| `check_perf_captures` | `perf-captures` | full, release | Reads the lab capture schema and versions from examples/performance/lab. No capture row is recorded yet. |
| `check_perf_gate_evidence-budgets` | `perf-gate-evidence-budgets` | full, release |  |
| `check_perf_gate_evidence-falsifiable` | `perf-gate-evidence-falsifiable` | release | Release tier, after prove-perf-gate injects an 8x regression into lab-dense-scroll. |
| `check_perf_gate_evidence-headless-linkage` | `perf-gate-evidence-headless-linkage` | full, release | Checks linkage; the timing verdict belongs to the perf-gate mode. |
| `check_perf_gate_evidence-perf-gate` | `perf-gate-evidence-perf-gate` | full, release | A host timing failure is FAIL_ENVIRONMENT except on the reference host. |
| `check_perf_metrics` | `perf-metrics` | full, release |  |
| `check_perf_place` | `perf-place` | full, release | Checks the native performance place and that its workloads are byte-identical to the headless bench. |
| `check_perf_scenes` | `perf-scenes` | full, release | Native workload counters: the radial opens six sectors and settles closed each sample; dense-motion moves every spring; control-motion reports each trigger. |
| `check_perf_scenes-themes` | `perf-scenes-themes` | full, release | Native StyleRule differential replaces the solver movedRects count; Engine geometry is not solved headlessly. |
| `check_public_allowlist` | `public-allowlist` | full, release |  |
| `check_source_size` | `source-size` | full, release |  |
| `check_theme_drift_cli` | `theme-drift` | full, release | Refuses theme-owned literals in src/ui controls. |
| `check_types` | `types` | full, release |  |
| `check_types-selftest` | `types-selftest` | full, release |  |
| `doctor` | `doctor` | full, release |  |
| `package-verify` | `package-verify` | full, release | Runs tools/package.sh verify as one producer. |
| `stylua-check-check-src-tests-tools-bench-examples` | `format` | fast, full, release |  |
| `stylua-check-check-src-tests-tools-examples` | `format` | fast, full, release | Subsumed by the wider format producer. |
| `suite` | `suite` | fast, full, release | Runs 33+1 native specs (674 cases) instead of 496 specs (10,848 cases). See the contract table. |
| `package-selftest` | `package-selftest` | full, release |  |

### Replaced producers

| Main producer | Candidate producer | Tier | Note |
|---|---|---|---|
| `check_boundary` | `architecture` | fast, full, release | Private-require scan for examples and bench only; tests may require src/ui directly. |
| `check_comment_codes` | `comments` | fast, full, release | Zero-comment policy replaces comment codes. |
| `check_comment_codes-selftest` | `comments-selftest` | fast, full, release |  |
| `check_device_captures` | `live-evidence` | full, release | check_live_evidence.py validates each record in tools/lune/parity_blockers.json: required fields, cited cases, commits and evidence class. |
| `check_device_sweep-selftest` | `live-evidence-selftest` | full, release | live-evidence-selftest plants malformed records and requires each rule to fail. |
| `check_docs_cli` | `call-shape-drift` | full, release | native_documentation spec plus call-shape-drift, which checks every lua and luau snippet in docs against the native API. |
| `check_eq6_evidence` | `live-evidence` | full, release | See check_device_captures. |
| `check_manifest_integrity` | `replacement-cases` | fast, full, release | The gate manifest is deleted. replacement-cases reads each cited case verdict from the structured suite result, not from a grep. |
| `check_matrix_rows` | `live-evidence` | full, release | See check_device_captures. |
| `check_registration_cli` | `suite` | fast, full, release |  |
| `check_row_actions_matrix` | `live-evidence` | full, release | See check_device_captures. |
| `check_traversal_evidence` | `live-evidence` | full, release | See check_device_captures. |
| `check_xp_matrix` | `live-evidence` | full, release | See check_device_captures. |
| `corpus_cli` | `suite` | fast, full, release | native_a11y_l10n_corpus spec in the suite: accessible names of controls and gallery demos, and a localization string corpus. |
| `verify-selftest` | `verification-selftest` | fast, full, release |  |

### Former weaker replacements

These four producers were weaker than on `main`. They are now at the
strength of `main`, or their subject is deleted.

| Main producer | Candidate producer | Tier | Note |
|---|---|---|---|
| `check_example_drift_cli` | `example-drift`, `example-drift-selftest` | full, release | `tools/check_example_drift.py` scans the tutorial and reference examples for a literal `TextSize`, a literal paint colour, a raw colour, an unknown `textRole` and an engine reach-around. Each allowed literal has a reason, and a stale entry fails. |
| `faults` | `suite` (`native_stress`) | fast, full, release | Six of the nine main scenarios run at 200 iterations or more: async storms, locale and UTF8 text, preferred input switches, teardown and the covered modal dismissal. The other three tested deleted subjects: the Facet scheduler (now Compose), the Facet resource cache and the Facet environment facts. |
| `fuzz-replication` | `suite` (`native_stress`) | fast, full, release | Retired. `src/replication` is deleted. The example authority model converges under 400 seeded deliveries, the same count as `main`. |
| `soak` | `suite` (`native_stress`) | fast, full, release | The same two fixtures as `main`: 200 modal cycles and 100 structural cycles, each twice, with a census after each cycle. |

### Producers with Studio evidence

These producers run in `full` and `release`. Each one reads the Studio
captures of the native performance lab under
`artifacts/performance-stress-places/studio`. The lab place is
`examples/performance.project.json`, and `workspace.FacetPerfLabAPI` drives
it (`select`, `theme`, `clean`, `run`, `stop`, `capture`). The capture schema
is in `examples/performance/lab/capture.luau`. A capture row records the
theme, the preferred text size and the viewport. All five producers pass.
See [the lab in Roblox Studio](19-paired-performance.md#the-performance-lab-in-roblox-studio).

| Main producer | Candidate producer | Tier | Evidence |
|---|---|---|---|
| `check_perf_gate_evidence-studio` | `perf-gate-evidence-studio` | full, release | Eight clean Studio captures at the current workload versions. |
| `check_perf_gate_evidence-native-reference` | `perf-gate-evidence-native-reference` | full, release | Three clean `dense-scroll-native` captures and five clean `dense-scroll` captures at seed 1 and 2,000 rows. |
| `check_perf_gate_evidence-theme-cost` | `perf-gate-evidence-theme-cost` | full, release | Clean `dense-scroll` captures with the neutral package and with `fantasy_ornate`. |
| `check_perf_gate_evidence-large-text` | `perf-gate-evidence-large-text` | full, release | Captures at the Medium and the Largest preferred text sizes. |
| `check_perf_gate_evidence-device-matrix` | `perf-gate-evidence-device-matrix` | full, release | Five emulator captures: phone portrait and landscape, a 720p handheld, a console and a 768x1024 handheld. |

### Retired producers

| Main producer | Note |
|---|---|
| `check_elision_census` | Adapter elision is deleted. |
| `check_flat_baseline` | Flat baseline of the deleted renderer. |
| `check_input_authority` | Facet input system deleted; Roblox InputAction owns input. |
| `check_input_authority-selftest` |  |
| `check_perf_gate_evidence-prior-gates` | The prior-gate sweep and its gate manifest were deleted with the phase gates. |
| `check_perf_gate_evidence-scopes` | Facet microprofiler scopes (src/core/profile.luau) were deleted. Compose owns its own profile module. |
| `check_prop_parity_cli` | Deleted primitive property table. |
| `check_reuse_ledger` | Deleted instance reuse ledger. |
| `check_reuse_ledger-selftest` |  |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-a1-b7f5d0` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-a4-478080` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-c1-73e76f` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-c2-725d54` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-d1-1c5ceb` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-d3-46e41d` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-d4-9a25f3` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-d5-329c3e` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-f1-d7b43f` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-l1-edbdee` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-l2-dcc9ef` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-l3-fed491` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-m1-c62ec7` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-m2-5a0768` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-m4-9a0448` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-m5-8cdae7` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-m6-a9c408` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-m7-c31a70` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-m8-45ab23` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-p1-71afb8` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-p2-a5c718` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-p3-1a56dc` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-p4-d3903b` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-p5-f34f1a` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-t1-006c64` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-t2-1fee50` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-t3-b16b62` | Sponsor framework gap rows describe deleted main features. |
| `check_sf_rows-artifacts-sponsor-framework-gaps-rows-sf-w1-e07115` | Sponsor framework gap rows describe deleted main features. |
| `check_spike-artifacts-declarative-3d-architecture-costs-61165b` | Historical Studio spike receipts for the deleted architecture. |
| `check_spike-artifacts-declarative-3d-architecture-studio-694f2a` | Historical Studio spike receipts for the deleted architecture. |
| `check_spike-artifacts-studio-expansion-textinput-probe-j-378ee4` | Historical Studio spike receipts for the deleted architecture. |
| `check_spike-artifacts-studio-ias-spike-json-api-surface-c265ac` | Historical Studio spike receipts for the deleted architecture. |
| `check_spike-artifacts-studio-part2-table-phaseb-json-pla-c5d328` | Historical Studio spike receipts for the deleted architecture. |
| `check_spike-artifacts-studio-phase1-gallery-json-engine-4934a9` | Historical Studio spike receipts for the deleted architecture. |
| `check_spike-artifacts-studio-phase2-port-drive-json-flag-f8d169` | Historical Studio spike receipts for the deleted architecture. |
| `check_spike-artifacts-studio-phase2-port-drive-json-real-9df8e9` | Historical Studio spike receipts for the deleted architecture. |
| `check_spike-artifacts-studio-property-authority-spike-js-0120ab` | Historical Studio spike receipts for the deleted architecture. |
| `check_surface_ledger` | Deleted surface ledger. |
| `check_verdicts-artifacts-expansion-textinput-platform-resea-b2e918` | Historical phase verdict receipts. |
| `check_verdicts-artifacts-part-2-opus-verification-json-PASS-1ef0c4` | Historical phase verdict receipts. |
| `check_verdicts-artifacts-phase-0-opus-verification-json-PAS-86d658` | Historical phase verdict receipts. |
| `check_verdicts-artifacts-phase-1-opus-verification-json-PAS-0becfb` | Historical phase verdict receipts. |
| `check_verdicts-artifacts-phase-2-opus-verification-json-PAS-6c97e1` | Historical phase verdict receipts. |
| `check_verdicts-artifacts-phase-3-opus-verification-json-PAS-0bd394` | Historical phase verdict receipts. |
| `check_verdicts-artifacts-phase-4-opus-verification-json-ALL-6c8acd` | Historical phase verdict receipts. |
| `fuzz-layout` | The Facet solver no longer exists; Roblox layout is not fuzzed headlessly. |
| `fuzz-scheduler` | Compose owns the scheduler; the vendored snapshot is hash-checked (vendor) but its own tests are not run here. |
| `rascalrally-suite` | Downstream game suite; maintainer lockstep, external. |
| `suite_cache_selftest` | The native runner has no result cache. |
| `theme_sync_cli-dump-artifacts-theme-packages-and-skinning-t-6f81a3` | Deleted theme sync tool. |
| `archive-integrity` | External private archive; environment-specific. |
| `studio-specialist-docs` | External studio tree check. |

### Release evidence

A complete `full` or `release` run writes `artifacts/verify/latest-<tier>.json`.
Its `gateEvidence` object holds the tier, the status, the commit, whether the
tree was dirty when the run started, and the package source hash.
`tools/package.sh publish` reads `artifacts/verify/latest-release.json`. It
refuses a missing file, another tier, a failed status, a dirty tree and a
different source hash. Only a clean, passing `release` run allows a publish.
The `release` tier adds `prove-perf-gate` and the `falsifiable` evidence mode.

### CI

CI runs the `fast` and `full` tiers on `ubuntu-latest` and on the pinned
`macos-15` runner. The `macos-15` lane uses `--reference-host`, so a timing budget
failure fails that lane. On Ubuntu, a timing budget failure is
`FAIL_ENVIRONMENT`. Both lanes then build the distributable model and check
its purity.

## Defects found

All audit defects are fixed. [Fixed after the audit](#fixed-after-the-audit)
names the test that covers each one. The table keeps the original
reproductions for reference.

| ID | File | Defect | Failing test |
|---|---|---|---|
| `B1` | `src/ui/collections.luau` | wrapFocus does not wrap arrow or D-pad navigation | Mount a VirtualList of 5 rows with wrapFocus = true and focus = {}. Set AbsoluteWindowSize to (200, 100). Call focus.focus(5). Fire FacetCollectionDown.CollectionDown.Pressed. Expect focus.current to be 1. Actual: 5. The arrow actions call focusScope.move, which ignores wrap; only focus.next wraps. |
| `B2` | `src/ui/collection_row_actions.luau` | Full swipe runs an action on an unmeasured row | Mount RowActions with one trailing action and do not set AbsoluteSize. Fire DragStart (100, 0), DragContinue (85, 0), DragEnd. Expect no action. Actual: the action runs, because abs(0) >= 0 * 0.7. |
| `B3` | `src/ui/collection_row_actions.luau` | A kept row stays collapsed after a destructive action | Mount RowActions with open = "trailing", a destructive Delete action and reducedMotion = true. Set AbsoluteSize (300, 40). Activate Delete and keep the row (the server refuses). Set open to "trailing" and activate Delete again. Expect a second commit and a usable row. Actual: committing is never cleared, the UIDragDetector stays disabled and the second commit does not run. |
| `B4` | `src/ui/inputs.luau` | A number TextInput commits after its parse callback disables it | Mount TextInput with presentation = "number", enabled cell true, and parse that sets enabled to false. Capture focus, set Text to "5", release focus with submit. Expect no onCommit and numericValue 2. Actual: onCommit runs and numericValue becomes 5. |
| `B5` | `src/ui/inputs.luau` | onPointerCancel alone never fires | Mount Button with only onPointerCancel. Fire InputBegan (MouseButton1) and MouseLeave. Expect one call. Actual: zero. The listeners connect only when repeatDelay, repeatInterval, onPointerDown or onPointerUp is present. |
| `B6` | `src/ui/inputs.luau` | Input controls ignore GuiService.ReducedMotionEnabled | Set GuiService.ReducedMotionEnabled = true and do not pass the reducedMotion factory option. Mount Button with pop = true, fire Activated and heartbeat 0.1. Expect UIScale.Scale 1. Actual: the pop animates. The StyleSheet and the navigation surfaces follow GuiService; Button pop, the validation pulse and the busy dots do not. |
| `B7` | `src/ui/collections.luau` | A readable follow option is accepted and ignored | Mount VirtualList with follow = Compose.cell("end"). Expect an error, because api.md says follow is static and an unsupported option causes an error. Actual: it mounts and behaves as follow = "none". |
| `B8` | `src/ui/media.luau` | Label with an icon returns a Frame | Mount Label with text and icon. Expect a TextLabel root, as api.md says. Actual: a Frame. |
| `B9` | `src/ui/media.luau` | ProgressView endLabel hides the showValue readout | Mount ProgressView with value 0.5, showValue = true and endLabel = "End". Expect a "50%" text. Actual: no text shows the value. |
| `B10` | `src/ui/inputs.luau` | Button corners rejects a readable, but Badge corners accepts one | Mount Button with corners = Compose.cell("square"). Expect it to mount, the same as Badge. Actual: an error. api.md does not say that corners is static. Low severity. |
| `E1` | `examples/gallery/examples/05_word_game.luau` | Word-game keys and the active row no longer show state by paint | Mount the word game and guess RULES against REACT. Expect key_R and key_U to carry different surfaces, and the active row to carry an outline. Actual: the surface formulas are computed and never applied. |
| `E2` | `examples/gallery/examples/02_playlist_table.luau` | Playlist plays a track on one click; its hint says double-click | Mount the playlist and fire one RowHit.Activated with MouseButton1. Expect selection only. Actual: nowPlaying changes. |

### Fixed after the audit

Each fix has a headless test. The test failed before the fix.

| ID | Fix | Test |
|---|---|---|
| `B1` | Arrow and D-pad focus wrap at the two ends when `wrapFocus` is set. A list wraps only along its scrolling axis. | native_collections: wraps arrow and D-pad focus at both ends when wrapFocus is set |
| `B2` | A full swipe commits or opens a tray only after the row has a measured width. | native_collections: never commits or opens a full swipe on an unmeasured row |
| `B3` | When the owner sets `open` after a destructive action, the row restores and accepts input again. | native_collections: restores a kept row after a destructive action so it can commit again |
| `B4` | A number commit stops when a callback disables the input. | native_inputs: does not commit a number TextInput that its parse callback disables |
| `B5` | `onPointerCancel` alone connects the pointer listeners. | native_inputs: reports a pointer cancel when onPointerCancel is the only pointer option |
| `B6` | Control motion follows `GuiService.ReducedMotionEnabled` or the factory option. | native_inputs: follows GuiService.ReducedMotionEnabled for pop, validation pulse and busy dots |
| `B7` | A readable `follow` changes the policy. Unknown values cause an error. | native_collections: follows a readable follow policy while the viewport stays at the end |
| `B8` | `api.md` states the Frame root of a Label with an icon. | native_themes_media: returns the Label root that api.md states, with and without an icon |
| `B9` | The value readout and `endLabel` show together. | native_themes_media: shows the showValue readout beside a ProgressView endLabel |
| `B10` | Button `corners` accepts a readable. | native_inputs: accepts a readable Button corners value and follows it |
| `E1` | Word-game keys and tiles use theme status tags. An accent outline marks the active row. | native_games: paints key and tile state through theme status tags and outlines the active row |
| `E2` | With a selection, one click selects. A double click, Return, a gamepad press or a touch tap activates. | native_gallery: selects a playlist row on one click and plays it on a double click or Return |
| `E3` | The ornate gauge and custom control fixtures use the current controls and read the theme package. | native_themes_media: mounts the namespaced control fixtures with the current controls |

### Fixed during the audit

The concurrent session fixed these reported defects before the recheck:

- `91702428`: Transparent tap-away catchers became opaque at PreferredTransparency 0; the theme scrim did not reach the modal scrim.
- `f2929ef1`: Picker valueAlignment was inert; Stepper used text glyphs; Badge corners did not follow a readable.
- `8781d9f8`: define accepted malformed type roles and unknown shadow presets; unreadable selected-label contrast passed.
- `8b19bba9`: corners layers ignored layer.asset; derived packages kept stale state art; skinned toggle fills were outranked.
- `3aa388a5`: Alert shortcut "cancelAction" and non-table transitions were silently ignored.

### Fixed with the paint and theme tests

A test in the new paint and theme specs showed each of these defects. The
same change fixes it.

| ID | File | Defect |
|---|---|---|
| `B11` | `src/ui/nav_menu.luau` | A Picker with `indicator = "none"` removed every selection cue. The chosen option now keeps its static current tags. |
| `B12` | `src/ui/themes.luau` | The transparency preference scaled dividers, soft fills, current-choice fills and package rules. At preference 0, an accent caption sat on an opaque accent fill. Now the preference scales only the scrim. |
| `B13` | `src/ui/media.luau` | Label accepted an unknown `textRole` and added an inert tag. Now it causes an error. |
| `B14` | `src/ui/themes.luau` | A package that set `body` and `control` but not `strong` or `numeral` got the neutral face for them. Now `define` derives them from the package face. |
| `E1` | `examples/gallery/examples/05_word_game.luau` | The word-game keys and the active row did not show their state. The keys now use Button appearances, and the active row has an outline. The caret has the empty color, so the caret mark is the cue. |
| `E4` | `examples/gallery/scenarios/status_indicator.luau` | The guide label used `textRole = "secondary"`. It now uses `role = "secondary"`. |
| `E5` | `examples/gallery/scenarios/recipes_common.luau`, `examples/gallery/examples/06_tile_game.luau` | The recipe dividers used a fixed inset and color. They now use the theme spacing, hairline and `facet-divider` paint. A pending crossword tile now has an outline. A committed tile does not. |

### Fixed with the control and navigation tests

A test in the new control and navigation specs showed each of these
defects. The same change fixes it. `bugs` in the data file has each
reproduction.

| ID | File | Defect |
|---|---|---|
| `B2` | `src/ui/collection_row_actions.luau` | Full swipe runs an action on an unmeasured row. |
| `B3` | `src/ui/collection_row_actions.luau` | A kept row stays collapsed after a destructive action. |
| `B9` | `src/ui/media.luau` | ProgressView endLabel hides the showValue readout. |
| `B15` | `src/ui/collection_row_actions.luau` | A write to the open cell of a coordinated row closed at once. |
| `B16` | `src/ui/collection_row_actions.luau` | A selected table row could not reach its row actions. |
| `B17` | `src/ui/collection_reorder.luau` | A horizontal keyboard move stepped with Up and Down only. |
| `B18` | `src/ui/nav_menu.luau` | A menu opened by a selection player selected the panel. |
| `B19` | `src/ui/nav_menu.luau` | Picker refused a readable indicator that holds nil. |
| `B20` | `src/ui/inputs.luau` | Rating and LevelPicker published values outside their run. |
| `B21` | `src/ui/inputs.luau` | Toggle accepted a read-only mixed state without onChange. |

### Fixed with the reference-app, example and control tests

A test in `tests/native_parity_apps.spec.luau` or
`tests/native_parity_media.spec.luau` shows each of these defects. The same
change fixes it.

| ID | File | Defect |
|---|---|---|
| `B1` | `src/ui/collections.luau` | `wrapFocus` did not wrap arrow or D-pad focus. Now it wraps at both ends along the pressed axis. |
| `B4` | `src/ui/inputs.luau` | A TextInput committed after its `parse`, `format` or `validate` callback disabled or removed it. Now the commit stops. |
| `B5` | `src/ui/inputs.luau` | A Button with only `onPointerCancel` never received the cancel. |
| `B6` | `src/ui/inputs.luau` | Button pop, busy dots and the validation pulse ignored `GuiService.ReducedMotionEnabled`. Now they follow it. |
| `B7` | `src/ui/collections.luau` | A readable `follow` mounted and acted as `none`. Now it causes an error. |
| `AB1` | `src/ui/nav_menu.luau` | ComboBox accepted a value that is not a string and missing `options`. |
| `AB2` | `src/ui/inputs.luau` | Button accepted any `imageFraming` value. A table was treated as `crop`. |
| `AB3` | `src/ui/collections.luau`, `src/ui/collection_table.luau` | `onActivate` did not receive the native input or click count, so a list could not tell one click from a double click. A double click also turned a multi-select row off again. |
| `AB4` | `src/ui/nav_radial.luau` | A ring with `follow = "fixed"` changed its hole when the anchor clearance changed. |
| `AB5` | `src/ui/nav_radial.luau` | The list presentation showed two navigation controls for the `root` and `close` centers. The Center button said "Back" where it closes the menu. |
| `AB6` | `src/init.luau` | The package did not export the RadialMenu contract types, although `api.md` promises the contract of each control. |
| `AB7` | `src/ui/nav_pages.luau` | A NavigationStack built its root page before it refused a malformed transition. |
| `AB8` | `src/ui/nav_modal.luau` | Removing an open modal left the selection on its destroyed control. Studio may clear it natively. The fake engine does not. |
| `E2` | `examples/gallery/examples/02_playlist_table.luau` | One click played a track. Now a double click, Return or a touch tap plays it. |
| `E3` | `examples/themes/ornate_gauge.luau`, `examples/themes/custom_control.luau` | The fixture blueprints called deleted constructors. They now build native nodes. |
| `AE1` | `examples/reference/*/init.luau` | Each app gave a native signal connection to `Compose.cleanup`, which refuses it. With a heartbeat or GuiService, the app did not mount. |
| `AE2` | `examples/reference/p1_glade/init.luau`, `examples/reference/p4_foyer/init.luau` | The Fresh Start and Invite alerts did not present. Alert calls a function title as a payload factory, and the apps gave a `(use)` readable. |
| `AE3` | `examples/reference/p2_cartwheel/init.luau` | A rejected brew command lost its reason, so the player saw the fallback text. |
| `AE4` | `examples/reference/p2_cartwheel/init.luau` | The brew actions stayed active while their command was pending. |
| `AE5` | `examples/gallery/scenarios/skeleton.luau` | The motion commands called an undefined function. The recipe now drives the gallery motion preference. |
| `AE6` | `examples/gallery/scenarios/adaptive_controls.luau` | A grid layout set `LayoutOrder` from an undefined global. |
| `AE7` | `examples/gallery/client/init.client.luau` | An empty `Facet_Scenario` with `Facet_Example` loaded the example as a fixture. The boot choice is now `catalogue.boot` in `demo_picker.luau`. |
| `AD1` | `docs/guide/README.md` | The guide index linked one of the seven extension playbooks. |

### Fixed with the stronger assertion tests

A case in a `tests/native_parity_weaker_*.spec.luau` file shows each of these
defects. The same change fixes it.

| ID | File | Defect |
|---|---|---|
| `WA1` | `examples/gallery/examples/02_playlist_table.luau` | The Rating column showed a resize grip and took resize keys, but the readout said that Rating is locked. The column now sets `resizable = false`. |
| `WA2` | `src/ui/collection_table.luau` | With editing on and a destructive row action, the row cells moved right by the edit gutter, but the header did not. The Table now adds the widest row edit gutter to the header position and width, the collapse room and the canvas width. |
| `WA3` | `src/ui/collection_snap.luau` | A flick without a pointer press (wheel, trackpad or engine momentum) started from a stale offset. A fast flick up from row 8 went to the top, and a flick down after a snap did not advance. A scroll from rest now starts at the resting offset. |
| `WA4` | `src/ui/collection_row_actions.luau` | A row stayed open and kept the shared open-row claim when the actions of its open side became empty. When the actions came back, the tray opened again without a swipe. The row now closes when its open side has no actions. |
| `WA5` | `examples/gallery/scenarios/action_controls.luau` | The Distant TV preview scales the gallery by 1.5, but the action controls demo read the unscaled viewport width. At 1440 px the Showroom and Race Setup sections stayed side by side under the preview. The gallery now gives demos `ctx.sceneViewport`, the viewport divided by the preview scale, and the demo reads it. |
| `WA6` | `src/ui/collections.luau` | VirtualList and VirtualGrid wrote an equal CanvasSize again on each scroll and on each edit to a row outside the window. Table wrote its outer Size, body Size, body CanvasSize and header Position again on each vertical scroll. These properties now bind to the numeric extent and the horizontal scroll offset, so only a real change writes. |
| `WA7` | `src/ui/media.luau` | AvatarGroup kept the old resource lease and image when the resource of a member changed under the same id. A member with a resource is now keyed by its id and its resource, so only that face mounts again with a new lease. |
| `WB1` | `src/ui/input_value.luau` | The default value format showed `-0` for a value between -0.005 and 0. |
| `WB2` | `src/ui/media.luau` | Badge accepted an incorrect `iconPosition` and put the icon on the leading side. |
| `WB3` | `src/ui/media.luau` | Badge and StatusIndicator read a `false` status as `neutral`. Now it causes an error. |
| `WB4` | `src/ui/media.luau` | StatusIndicator ignored `name`. Now `name` sets the accessible label. |
| `WB5` | `src/ui/inputs.luau` | The Rating and Slider value actions had a lower priority than the collection arrows. In a VirtualList or Table row, the arrow keys did not change the value. |
| `WB6` | `src/ui/inputs.luau` | ShortcutHint raised an error when the native key service failed. Now it shows the key name. |
| `WB7` | `src/ui/inputs.luau` | ShortcutHint accepted an unknown `over` option, and `separator` with `action`. |
| `WB8` | `src/ui/inputs.luau` | The Stepper buttons and the TextInput clear button were less than 44 px high. |
| `WB9` | `src/ui/nav_menu.luau` | The current cascade submenu level overlapped its parent level. |
| `WB10` | `src/ui/nav_menu.luau` | Picker accepted incorrect callback, flag and option field types. |
| `WB11` | `src/ui/nav_menu.luau` | A `navigationLink` Picker dropped the native properties of its trigger. |
| `WB12` | `src/ui/nav_radial.luau` | RadialMenu Back left the selection on the removed child item. Now it selects the parent item. |
| `WB13` | `src/ui/nav_radial.luau` | After a pointer press on the launcher with no native echo, the launcher ignored the next gamepad or keyboard activation. |
| `WB14` | `src/ui/nav_pages.luau` | A TabView with `retention = "top"` lost the focus bookmark of an evicted page. |

### Fixed with the final gap tests

A case in the table of [Final gap tests](#final-gap-tests) shows each of
these defects. The same change fixes it. `bugs` in the data file has each
reproduction.

| ID | File | Defect |
|---|---|---|
| `B22` | `src/ui/context.luau` | A theme metric that was not finite stopped the construction of a control. A metric that is not finite now falls back to the neutral metric, as a missing metric does. |
| `B23` | `src/ui/collection_row_actions.luau` | A destructive commit that removed its row left a heartbeat connection after dispose. The row now settles before it runs the action. |
| `E6` | `examples/gallery/scenarios/collection_demo.luau` | A short landscape kept the collection title. The title is now hidden when the viewport is less than 480 pixels high. |
| `E7` | `examples/gallery/scenarios/demo_tabs.luau` | The shoulders did not page the showcase inner tabs from page content. The inner tab views now set `shoulderNavigation = "content"`. |
| `E8` | `examples/reference/p3_sipworks/init.luau`, `examples/reference/p3_sipworks/content/strings.luau` | Sipworks wrote most player copy as literals, so a locale switch kept it in English. The copy is now in the locale table. |

## Gaps closed by this audit

[`tests/native_parity_gaps.spec.luau`](../../tests/native_parity_gaps.spec.luau)
adds these cases:

| Candidate case | Closes | Main cases | Also partly covers |
|---|---|---:|---|
| keeps the changelog release heading equal to Facet.VERSION | `apps-115` | 1 | - |
| refuses an unknown lower-case option on every public constructor | `collections-221`, `mech1-26`, `mech3-44`, `themes-P1-97` | 33 | - |
| shows button help when gamepad selection rests on the button and hides it on deselection | `inputs-91`, `mech3-70` | 4 | - |
| disables a stepper direction at its bound and refuses the step | `inputs-214` | 2 | - |
| reports a failed alert body to the onError factory option and dismisses once | `mech1-114` | 1 | - |
| tags a disabled button for the theme disabled rule and lets a package retune it | `mech2-24` | 3 | - |
| keeps at most the documented number of pooled row hosts | `mech2-31` | 2 | - |
| fills the controls table with indexOfKey, placementOf and offsetOf | `mech2-86` | 2 | - |
| refuses malformed documented options with a named error | `navigation-2-24`, `navigation-3-45`, `navigation-4-10`, `navigation-5-28` | 8 | `apps-198`, `collections-129`, `inputs-43`, `inputs-104`, `inputs-150`, `inputs-188`, `navigation-3-81`, `navigation-4-45` |
| delivers onActivate with the item and key and skips disabled rows | - | 0 | `collections-184` |
| wraps rating activation to zero only when allowZero and ignores a disabled rating | - | 0 | `inputs-156` |

The producer restoration adds one more case, in `native_themes_media`:

| Candidate case | Closes | Main cases | Also partly covers |
|---|---|---:|---|
| mounts the namespaced control fixtures with the current constructors | `themes-P5-12` | 3 | - |

[`tests/native_parity_paint.spec.luau`](../../tests/native_parity_paint.spec.luau)
closes every gap in the paint and theming group. A contract that two cases
close counts once, in the first row.

| Candidate case | Closes | Main cases | Also partly covers |
|---|---|---:|---|
| compiles the button role and appearance vocabulary to palette rules above their base states | paint-02, paint-08, paint-110, paint-119, `themes-P2-39` | 13 | - |
| tags each button role, appearance and corner choice for the matching rule | paint-02, paint-08, paint-119 | 0 | - |
| moves the picker current-option tags with the selection and the indicator choice | navigation-3-50, paint-29 | 9 | - |
| keeps the picker menu catcher invisible at every background preference | navigation-4-12 | 3 | - |
| marks the selected tab by placement and indicator choice | navigation-5-22 | 1 | - |
| paints every value-control own slot solid in every shipped package and palette | paint-106, `themes-P2-32`, `themes-P2-34`, `themes-P4-25` | 7 | - |
| tags unskinned value-control slots for their own paint and keeps the tags when skinned | paint-75, `themes-P5-28` | 4 | `themes-P5-35` |
| repaints corner radii and type roles in place when package metrics change | paint-114, `themes-P2-21`, `themes-P5-42` | 6 | - |
| compiles every type role to native font rules and tags labels with their role | `themes-P3-10` | 5 | paint-148 |
| compiles palette chrome gradients to UIGradient rules and removes them with the palette | `themes-P2-09`, `themes-P3-12`, `themes-P5-13` | 6 | - |
| orders rule priority by declaration with states after rests and package rules last | `themes-P2-11` | 2 | - |
| keeps an icon badge icon through reactive status paint and switches badge appearances | themes-P1-47, themes-P1-49 | 2 | - |
| skins the badge seal from the package badge slot and removes it with the package | `themes-P2-16` | 4 | - |
| blends a bound dimmed async image and restores it | themes-P1-125 | 1 | - |
| lets per-view slider images replace the theme skin on that node only | `themes-P2-25`, inputs-227 | 7 | `themes-P4-10` |
| leaves icon tint and transparency to the style sheet | `themes-P2-63` | 1 | - |
| keeps the selected label readable on the selection fill and its sampled art in every shipped theme | `themes-P5-23`, `themes-P5-46` | 7 | - |
| treats a garbage transparency preference as the identity | `themes-P5-48` | 2 | - |
| scales only the scrim backdrop by the transparency preference | `themes-P5-49` | 8 | - |
| insets and paints the recipe dividers from the installed theme | apps2-221 | 1 | - |
| marks the active word row and pending crossword tiles without relying on color | apps2-19, apps2-26 | 6 | - |
| selects every tag the framework emits with a rule in every shipped sheet | `themes-P5-41` | 9 | - |

`keeps a transparent menu catcher transparent at every background preference`
in `native_navigation` also covers navigation-4-12.

[`tests/native_parity_themes.spec.luau`](../../tests/native_parity_themes.spec.luau)
closes every gap in the theme packages group.

| Candidate case | Closes | Main cases | Also partly covers |
|---|---|---:|---|
| derives unauthored strong and numeral roles from the package face | paint-152 | 3 | - |
| authors circular and spinner metrics in every reference package across a twofold span | themes-P1-69 | 10 | - |
| answers the progress metrics from neutral for a package that authors none | themes-P1-70 | 1 | - |
| resolves content and contentId to the same skin and icon image | `themes-P2-01` | 2 | `themes-P3-22` |
| refuses an unknown text role and follows a bound role | `themes-P3-26` | 1 | - |
| inherits unrestated base values in a derived package and gates it as strictly | `themes-P4-29` | 2 | - |
| rejects non-finite theme numbers with the field path | `themes-P4-33` | 1 | `themes-P4-42` |
| paints omitted semantic pairs from the neutral fallbacks in every palette | `themes-P4-37` | 3 | - |
| falls back to default art for unstated states and ranks disabled over pressed over hover over selected | `themes-P4-46` | 1 | - |
| shows the derived default art in a state the derived package no longer declares | `themes-P4-50` | 1 | - |
| exercises every declared theme class of each reference package against neutral | `themes-P5-03` | 13 | - |
| names declared rbxassetid assets in every chrome and icon recipe | `themes-P5-04` | 5 | - |
| compiles and skins a full stack when a declared asset is bogus | `themes-P5-05` | 2 | - |
| declares distinct success and warning pairs in every reference palette | `themes-P5-15` | 2 | - |
| pairs touch and pointer metrics, hover art and the tile stripe | `themes-P5-22` | 5 | - |
| loads only shipping theme package modules from the gallery theme folder | apps2-118 | 3 | - |
| lists Neutral first then names, keeps the installed package on reselection and selects a palette | apps2-117 | 3 | - |

### Control and navigation parity tests

[`tests/native_parity_controls.spec.luau`](../../tests/native_parity_controls.spec.luau)
and
[`tests/native_parity_navigation.spec.luau`](../../tests/native_parity_navigation.spec.luau)
close 117 contracts with 254 main cases. They cover the value
controls, the input actions, the row actions, Menu, TabView, Picker, Sheet,
Callout and Alert. A contract that several cases close counts its main cases
on its first case.

| Spec | Candidate case | Closes | Main cases | Also partly covers |
|---|---|---|---:|---|
| `native_parity_controls` | repaints a chip in place, refuses incomplete chips and honors live and inherited disabled | inputs-55, inputs-57, inputs-61, inputs-72 | 5 | - |
| `native_parity_controls` | stops a held value adjustment when a modal takes input and waits for a fresh press | inputs-81 | 3 | - |
| `native_parity_controls` | refuses malformed level picker and rating declarations with named errors | inputs-104, inputs-150 | 7 | - |
| `native_parity_controls` | publishes level values inside the declared run and paints glyphs in place | inputs-105, inputs-109, inputs-151, inputs-152 | 7 | - |
| `native_parity_controls` | refuses pointer, drag and focused adjustment on a disabled level picker, rating and slider | inputs-114, inputs-156, inputs-224 | 4 | - |
| `native_parity_controls` | requires a request callback for a read-only toggle value or mixed state | inputs-202 | 2 | - |
| `native_parity_controls` | edits the consumer's caller-owned sound value through its toggle | apps2-02 | 1 | - |
| `native_parity_controls` | shows a bar value readout beside its label, keeps the end label with it and applies thickness | paint-42, paint-44 | 4 | - |
| `native_parity_controls` | mounts and removes a live badge caption while keeping its icon and plate | themes-P1-53 | 1 | - |
| `native_parity_controls` | sizes skeleton and status indicator rungs live and recovers from an illegal rung | themes-P1-89, themes-P1-91, themes-P1-114 | 3 | - |
| `native_parity_controls` | puts per-view slider artwork ahead of the theme skin and keeps the theme skin without it | `themes-P4-10` | 5 | - |
| `native_parity_controls` | drops the toggle pill under skin art, restores it without art and keeps the knob geometry | `themes-P5-35` | 5 | - |
| `native_parity_controls` | recovers a kept row after a destructive commit so a later commit runs again | collections-72 | 1 | - |
| `native_parity_controls` | closes an open row on another row's gesture or menu, the Cancel key, and unmount | collections-77, collections-287 | 4 | - |
| `native_parity_controls` | toggles the row menu with Shift+Return, reveals it with ButtonX and dismisses it with the row | collections-84, collections-86, collections-287 | 8 | - |
| `native_parity_controls` | moves pad selection into a revealed tray and back, and deletes once from either key | collections-187, collections-287 | 9 | - |
| `native_parity_controls` | keeps a destructive commit running through a sibling gesture and a table scroll | collections-89, collections-287 | 2 | - |
| `native_parity_controls` | declines row gestures until actions exist and keeps the drag detector off without them | collections-282 | 1 | - |
| `native_parity_controls` | coordinates table row trays, closes them on body scroll and deletes from a focused row | collections-170, collections-173, collections-194 | 14 | - |
| `native_parity_controls` | refuses a reorder that would displace a pinned row and accepts one that keeps it in place | collections-121 | 1 | - |
| `native_parity_controls` | cancels an armed keyboard move when keyboard and gamepad both leave and keeps it when a pointer arrives | collections-40 | 2 | - |
| `native_parity_controls` | reorders a horizontal list along X by pointer, autoscroll and Left and Right stepping | collections-256 | 4 | - |
| `native_parity_controls` | finds the insertion slot from measured midpoints on ragged rows | collections-303 | 1 | - |
| `native_parity_controls` | binds modifier shortcuts only with their modifier and adds the unmodified dialog key | inputs-101 | 5 | - |
| `native_parity_controls` | activates a selected button once per Activate action press and once per native activation | - | 0 | apps-163 |
| `native_parity_controls` | moves radial selection and the commit candidate together on the D-pad and returns to it after the stick | apps2-184 | 2 | - |
| `native_parity_controls` | combines table row actions with reorder handles, editing, refresh and disposal | collections-170 | 0 | - |
| `native_parity_controls` | closes a swiped playlist tray when the table scrolls | - | 0 | apps2-35 |
| `native_parity_controls` | never commits or opens a row that has no measured width | collections-114 | 2 | - |
| `native_parity_controls` | keeps Delete and swipes inert while the row menu is open and leaks nothing across menu toggles | collections-51, collections-82 | 5 | - |
| `native_parity_navigation` | pages tabs with the shoulders from the strip, wraps there and clamps when paging from content | navigation-4-63, navigation-5-13 | 4 | - |
| `native_parity_navigation` | pages the inner tab view from nested content, clamps at its boundary and leaves the outer tabs | navigation-4-65 | 1 | - |
| `native_parity_navigation` | builds only visited tabs and disposes departing pages under top retention | navigation-5-17, navigation-5-18 | 6 | - |
| `native_parity_navigation` | resolves a nested tab view to a top band and keeps nesting balanced after a failed page | navigation-5-08 | 3 | - |
| `native_parity_navigation` | places sidebar head and foot accessories around the strip and passes the placement to builders | navigation-5-35 | 3 | - |
| `native_parity_navigation` | docks trailing and above-bar accessories against the band and re-homes them with the placement | navigation-5-36, navigation-5-38, navigation-5-40 | 7 | - |
| `native_parity_navigation` | refuses unknown accessory slots, non-function builders, unhostable slots and malformed transitions | navigation-5-26, navigation-5-42, navigation-5-52 | 6 | - |
| `native_parity_navigation` | uses a plain native frame and hides the old page immediately when transition is false | navigation-5-25, navigation-5-50 | 2 | - |
| `native_parity_navigation` | labels tabs by id, keeps icon-only names accessible and badges unselected tabs in place | navigation-5-21 | 3 | - |
| `native_parity_navigation` | underlines the selected top tab by default, fills bottom and sidebar tabs and follows the indicator | - | 0 | - |
| `native_parity_navigation` | keeps every tab at the 44 pixel target floor and reads a bound text size and rail width | navigation-5-23, navigation-5-30, navigation-5-31 | 4 | - |
| `native_parity_navigation` | reveals an offscreen selected tab once and never scrolls for a visible one | navigation-5-06 | 2 | - |
| `native_parity_navigation` | keeps the strip, the page and its owner across placement changes and round trips | navigation-1-02 | 3 | - |
| `native_parity_navigation` | moves adaptable tabs to a top band while a gamepad is the preferred input | navigation-1-03 | 1 | - |
| `native_parity_navigation` | orders customized tabs, skips stale ids, protects required tabs and falls back from a hidden selection | navigation-4-61 | 1 | - |
| `native_parity_navigation` | keeps a retained tab's scroll position on return and resets it when restoreScroll is off | navigation-4-67 | 1 | - |
| `native_parity_navigation` | opens a menu only through its declared triggers and binds the keyboard and gamepad chords | navigation-2-27 | 5 | - |
| `native_parity_navigation` | opens a wholly disabled menu and keeps it open when a disabled item is activated | navigation-2-29 | 2 | - |
| `native_parity_navigation` | unwinds submenus one level at a time and enters a branch only from a focused branch row | navigation-2-31, navigation-2-37, navigation-2-44 | 6 | - |
| `native_parity_navigation` | follows the presentation option and touch input between the menu and sheet idioms | navigation-2-32, navigation-2-36, navigation-2-39 | 7 | - |
| `native_parity_navigation` | toggles nested checked items in both idioms and releases every level with the trigger | navigation-2-38, navigation-2-72 | 4 | - |
| `native_parity_navigation` | anchors the menu panel below its trigger, sizes it from the widest row and keeps it inside the viewport | navigation-3-76, navigation-3-87 | 4 | - |
| `native_parity_navigation` | keeps a picker and menu tap-away catcher invisible at every background preference | navigation-5-54 | 2 | - |
| `native_parity_navigation` | picks from a vertical radio group and moves the current paint with the selection and indicator | navigation-3-86 | 1 | - |
| `native_parity_navigation` | sizes segments by fill or hug without replacing them and refuses unknown sizing | navigation-3-63 | 4 | - |
| `native_parity_navigation` | refuses malformed picker options, labels, icons, indicators, axes and styles | apps-198, navigation-3-52, navigation-3-55, navigation-3-81, navigation-4-18, navigation-4-35 | 10 | - |
| `native_parity_navigation` | resolves the automatic picker by width, description, count, input and query | navigation-2-23, navigation-3-74 | 5 | - |
| `native_parity_navigation` | never shows a selection redirected inside onChange to observers | navigation-3-70 | 1 | - |
| `native_parity_navigation` | closes a menu picker by trigger or Back without changing the selection | navigation-3-77 | 1 | - |
| `native_parity_navigation` | refuses unknown and duplicate sheet detents and a read-only detent source | navigation-4-45 | 1 | - |
| `native_parity_navigation` | dismisses a sheet dragged below its smallest detent and keeps a 44 pixel grabber | navigation-4-40 | 1 | - |
| `native_parity_navigation` | continues a grab during a detent change from the painted height | navigation-4-48 | 1 | - |
| `native_parity_navigation` | gates callout eligibility on sessions, seen and feature use and refuses a missing onRetire | navigation-1-54, navigation-1-55 | 5 | - |
| `native_parity_navigation` | frees the callout queue slot when the showing callout is disposed | navigation-1-61 | 1 | - |
| `native_parity_navigation` | aligns a callout to the anchor edges, flips it above near the bottom and omits an unrequested tail | navigation-1-40, navigation-1-43 | 4 | - |
| `native_parity_navigation` | keeps device names out of the control sources | navigation-1-63 | 1 | - |
| `native_parity_navigation` | adds a default OK action and keeps an alert open on outside taps and custom content buttons | navigation-1-26, navigation-1-29, navigation-2-61 | 3 | - |
| `native_parity_navigation` | refuses misspelled alert fields, duplicate action ids, two cancel actions and malformed transitions | navigation-1-28, navigation-1-35 | 4 | - |
| `native_parity_navigation` | lays out alert actions in a row with the cancel action first and stacks them for long labels | navigation-1-16, navigation-1-20, navigation-3-31 | 7 | - |
| `native_parity_navigation` | grows an alert message to its content when the card has room and bounds it when it does not | navigation-1-19 | 4 | - |
| `native_parity_navigation` | mounts an alert title only while it has visible text and wraps a long title across the card | navigation-1-38 | 4 | - |
| `native_parity_navigation` | releases an open alert with its owner and returns selection to the opener | navigation-1-25 | 1 | - |
| `native_parity_navigation` | opens each menu scenario card only through its printed routes and runs nothing from the blocked card | navigation-2-51, navigation-2-53, navigation-2-57 | 9 | - |
| `native_parity_navigation` | keeps the callout scenario reset chip on screen at the 44 pixel floor and resets the session | navigation-1-66 | 1 | - |

The cases also assert navigation-3-50, navigation-4-12 and navigation-5-22.
These contracts are in the paint and theming group, and the paint parity
tests close them.

These gaps close only in part. A live Studio check must show the rest:

- apps-163: One physical Return press on a selected Button must reach
  `onActivate` once. The Activate InputAction and native `Activated` can both
  see the press.
- apps2-35: A swipe on a playlist row must not also fire `RowHit.Activated`
  and play the track.
- collections-84: Shift+Return on a focused row must open the row menu. The
  focused content Button has an Activate context at priority 5000 on Return.
  RowActionsToggle has priority 300.

navigation-3-84 moved to class c. `api.md` no longer listed the Picker
`valueAlignment` option. The foundation parity port restored the option with
`start` and `end` for a labelled menu. See [Foundation parity](#foundation-parity).

### Reference app, example and media parity tests

[`tests/native_parity_apps.spec.luau`](../../tests/native_parity_apps.spec.luau)
and [`tests/native_parity_media.spec.luau`](../../tests/native_parity_media.spec.luau)
close these contracts. The data file names the case for each contract.

| Spec | Block | Closes | Main cases |
|---|---|---|---:|
| `native_parity_apps` | Glade | apps-04, apps-06, apps-07, apps-09, apps-12, apps-13, apps-14, apps-15, apps-17, apps-19, apps-23, apps-25, apps-28, apps-31, apps-33 | 34 |
| `native_parity_apps` | Cartwheel | apps-37, apps-39, apps-41, apps-44, apps-47, apps-49, apps-53, apps-55, apps-57, apps-60, apps-64, apps-65, apps-67 | 27 |
| `native_parity_apps` | Sipworks | apps-72, apps-73, apps-75, apps-78, apps-82, apps-83, apps-85, apps-87, apps-94, apps-96 | 21 |
| `native_parity_apps` | Foyer | apps-100, apps-104, apps-108, apps-109 | 10 |
| `native_parity_apps` | Gallery examples | apps2-02, apps2-08, apps2-20, apps2-29, apps2-42, apps2-46, apps2-73, apps2-74 | 28 |
| `native_parity_apps` | Gallery shell | apps2-82, apps2-83, apps2-115, apps2-92, apps2-101, apps2-107 | 18 |
| `native_parity_apps` | Gallery recipes | themes-P1-31, themes-P1-45, themes-P1-52, themes-P1-95, themes-P1-116, inputs-176, apps2-230 | 9 |
| `native_parity_apps` | Gallery layouts | apps2-49, apps2-61 | 3 |
| `native_parity_apps` | Outpost terminal | apps2-128, apps2-132 | 7 |
| `native_parity_apps` | Performance lab | apps2-139, apps2-148 | 2 |
| `native_parity_apps` | Documentation and tooling | apps2-158, apps2-236, apps2-80 | 6 |
| `native_parity_apps` | Table | apps2-167, apps2-179, apps2-177, apps2-178 | 11 |
| `native_parity_apps` | Playlist example | apps2-33, apps2-37, apps2-172, apps2-174 | 9 |
| `native_parity_apps` | RadialMenu | apps2-190, apps2-192, apps2-200, apps2-202, apps2-208, apps2-212, apps2-215 | 11 |
| `native_parity_apps` | Quick actions example | apps2-224, apps2-194 | 13 |
| `native_parity_apps` | Public surface, catalog and theme corpus | apps-117, paint-140, paint-143, mech3-55, `themes-P4-43`, `themes-P4-44`, `themes-P5-12` | 26 |
| `native_parity_apps` | Menu scenario copy | navigation-2-57 | 1 |
| `native_parity_media` | progress motion | paint-37, themes-P1-75, themes-P1-76, themes-P1-78, paint-41, themes-P1-69 | 21 |
| `native_parity_media` | badge | themes-P1-47, themes-P1-48, themes-P1-49, themes-P1-53 | 4 |
| `native_parity_media` | avatar | themes-P1-23, themes-P1-25, themes-P1-40 | 3 |
| `native_parity_media` | skeleton and status indicator | themes-P1-89, themes-P1-91, themes-P1-92, themes-P1-114 | 4 |
| `native_parity_media` | async image and stage | themes-P1-125, themes-P1-101 | 2 |
| `native_parity_media` | icons | paint-24, `themes-P2-48`, `themes-P2-43`, `themes-P3-22`, paint-79 | 7 |
| `native_parity_media` | refusals | inputs-29, inputs-43, inputs-67, inputs-73, inputs-197, paint-06, navigation-2-09 | 16 |
| `native_parity_media` | controls | inputs-25, inputs-162, inputs-17, inputs-26, paint-16, paint-60, inputs-93, inputs-185, inputs-188, inputs-196, apps-179, apps-146 | 26 |
| `native_parity_media` | icon coverage | paint-53, paint-54, `themes-P2-54` | 14 |
| `native_parity_apps` | Collections | collections-21, collections-128, collections-129, collections-134, collections-136, collections-139, collections-184, collections-207, collections-216, collections-302, collections-225, collections-230, collections-232, collections-244, collections-234, collections-245, collections-250, collections-255, collections-253, collections-263, collections-270, mech1-130 | 39 |
| `native_parity_apps` | NavigationStack and CollapsibleView | navigation-3-04, navigation-3-24, navigation-3-15, navigation-3-16, navigation-3-17, navigation-3-23, navigation-2-04 | 12 |

### Stronger assertions for weaker contracts

These specs add sibling cases for covered contracts whose candidate
assertion was weaker than the main assertion. "Equal" lists the
contracts that now assert all that main asserted and that is still
promised. The `weaker` field of these contracts is removed. "Still
weaker" lists the contracts that get more assertions, but that still
need a Roblox layout result from a live Studio check, or that keep a
product difference from main. Their `weaker` field names the missing
assertion. A contract that gets no new case is not in this table. Its
`weaker` field tells why.

| Spec | Group | Equal | Main cases | Still weaker | Main cases |
|---|---|---|---:|---|---:|
| `native_parity_weaker_apps` | Docs, examples and tooling | `apps2-78`, `mech1-76`, `paint-139` | 11 | - | 0 |
| `native_parity_weaker_apps` | Reference apps | `apps-01`, `apps-03`, `apps-34`, `apps-35`, `apps-40`, `apps-43`, `apps-51`, `apps-69`, `apps-77`, `apps-79`, `apps-81`, `apps-85`, `apps-93`, `apps-94`, `apps-97`, `apps-99`, `apps-103`, `apps-106`, `apps-107` | 43 | `apps-82` | 2 |
| `native_parity_weaker_gallery` | Gallery and examples | `apps2-17`, `apps2-66`, `apps2-102`, `apps2-114`, `apps2-195`, `apps2-261`, `apps2-285`, `collections-109`, `mech2-26`, `navigation-2-50`, `navigation-3-32`, `navigation-3-36`, `navigation-5-45`, `paint-47`, `paint-125` | 75 | `apps2-01`, `apps2-86`, `apps-193`, `collections-101`, `inputs-77`, `mech2-25`, `mech3-20`, `navigation-1-65` | 45 |
| `native_parity_weaker_hud` | HUD and world targets | `apps2-130`, `apps-215`, `themes-P1-102` | 4 | `apps-206`, `apps-210`, `apps-214`, `apps-218`, `apps-221`, `apps-234`, `themes-P1-11`, `themes-P1-14` | 30 |
| `native_parity_weaker_hud` | Replication and server state | `apps2-41`, `apps2-127` | 14 | - | 0 |
| `native_parity_weaker_rows` | Row actions | `apps2-38`, `apps2-40`, `apps2-265`, `collections-57`, `collections-61`, `collections-65`, `collections-67`, `collections-76`, `collections-88`, `collections-116`, `collections-120`, `collections-122`, `collections-145`, `collections-168`, `collections-281`, `collections-284`, `inputs-58` | 82 | `apps2-39`, `collections-11`, `collections-53` | 19 |
| `native_parity_weaker_scrolling` | Scrolling | `apps2-267`, `apps-225`, `apps-231`, `collections-03`, `collections-15`, `collections-32`, `collections-125`, `collections-127`, `collections-176`, `collections-183`, `collections-231`, `collections-242`, `navigation-5-05` | 50 | `collections-262`, `navigation-1-18` | 7 |
| `native_parity_weaker_tables` | Tables | `apps2-168`, `apps2-171`, `apps2-173`, `apps-242`, `collections-36`, `collections-37`, `collections-137`, `collections-142`, `collections-144`, `collections-151`, `collections-164`, `inputs-06` | 34 | `apps2-175`, `collections-133`, `collections-134`, `collections-203`, `collections-207` | 9 |
| `native_parity_weaker_virtual` | Virtual collections | `apps2-141`, `apps2-243`, `apps-122`, `collections-07`, `collections-09`, `collections-19`, `collections-20`, `collections-208`, `collections-222`, `collections-223`, `collections-240`, `collections-249`, `collections-258`, `collections-274`, `collections-296`, `collections-299`, `collections-300`, `collections-305`, `mech1-72`, `mech1-96`, `mech2-30`, `mech3-03`, `mech3-97`, `themes-P1-35` | 121 | `apps2-57`, `apps2-231`, `navigation-4-68` | 6 |
| `native_parity_weaker_values` | Value controls | `apps-129`, `apps-167`, `apps2-36`, `apps2-254`, `inputs-03`, `inputs-53`, `inputs-113`, `inputs-115`, `inputs-119`, `inputs-155`, `inputs-177`, `inputs-200`, `inputs-201`, `inputs-203`, `inputs-204`, `inputs-212`, `inputs-215`, `navigation-3-66`, `navigation-3-67`, `navigation-4-27`, `navigation-4-32`, `paint-19`, `paint-45`, `themes-P1-50`, `themes-P1-51`, `themes-P1-54`, `themes-P1-63`, `themes-P1-80`, `themes-P1-109`, `themes-P1-110`, `themes-P1-115`, `themes-P4-24`, `themes-P5-37` | 120 | `mech3-14`, `themes-P5-29` | 8 |
| `native_parity_weaker_actions` | Action controls | `apps2-65`, `apps2-219`, `inputs-02`, `inputs-16`, `inputs-35`, `inputs-38`, `inputs-74`, `inputs-76`, `inputs-87`, `mech1-25`, `mech2-23`, `mech3-69`, `navigation-2-14`, `navigation-2-73`, `navigation-3-40`, `navigation-4-50`, `navigation-4-51`, `paint-07` | 48 | `navigation-2-17`, `paint-04` | 9 |
| `native_parity_weaker_actions` | Text input | `apps2-28`, `apps2-31`, `apps2-263`, `inputs-07`, `inputs-138`, `inputs-179`, `inputs-180`, `inputs-182`, `inputs-184` | 26 | - | 0 |
| `native_parity_weaker_focus` | Focus and selection | `apps-137`, `apps-147`, `apps-159`, `apps-185`, `apps2-179`, `apps2-185`, `apps2-276`, `collections-17`, `collections-147`, `collections-149`, `collections-196`, `collections-259`, `inputs-158`, `navigation-1-13`, `navigation-1-57`, `navigation-2-18`, `navigation-2-63`, `navigation-4-41`, `navigation-5-12` | 46 | `apps-160`, `apps-181` | 3 |
| `native_parity_weaker_focus` | Input actions | `apps2-210`, `collections-79`, `inputs-19`, `inputs-167`, `inputs-171`, `inputs-172`, `navigation-2-67`, `navigation-3-21`, `navigation-4-36`, `navigation-4-66` | 35 | `apps-162`, `collections-84`, `navigation-4-38` | 13 |
| `native_parity_weaker_menus` | Menus and pickers | `apps-135`, `apps-136`, `apps-195`, `apps-197`, `apps-198`, `apps2-121`, `apps2-269`, `collections-81`, `collections-82`, `navigation-1-08`, `navigation-2-26`, `navigation-2-34`, `navigation-2-35`, `navigation-2-40`, `navigation-2-54`, `navigation-3-75`, `navigation-3-78`, `navigation-3-82`, `navigation-4-01`, `navigation-4-02`, `navigation-4-03`, `navigation-4-04`, `navigation-4-19`, `navigation-4-21`, `navigation-4-55` | 50 | `apps-196`, `apps-237`, `navigation-3-85` | 8 |
| `native_parity_weaker_navigation` | Navigation containers | `apps-189`, `apps-190`, `apps-191`, `apps-245`, `apps2-106`, `apps2-199`, `apps2-201`, `apps2-260`, `mech1-74`, `navigation-1-01`, `navigation-1-10`, `navigation-2-05`, `navigation-2-20`, `navigation-3-01`, `navigation-3-06`, `navigation-3-12`, `navigation-3-39`, `navigation-5-01`, `navigation-5-11`, `paint-33` | 32 | `apps2-225`, `navigation-4-60` | 4 |
| `native_parity_weaker_pointer` | Adaptive environment | `apps2-134`, `apps2-257`, `mech1-88`, `mech1-121`, `navigation-1-63`, `navigation-3-73`, `themes-P5-51` | 14 | `apps2-191` | 3 |
| `native_parity_weaker_pointer` | Pointer, touch and drag | `apps2-15`, `apps2-204`, `apps2-205`, `apps2-206`, `apps2-209`, `apps2-215`, `collections-70`, `collections-112`, `collections-177`, `inputs-117`, `inputs-157`, `mech1-42`, `mech2-107`, `navigation-2-28`, `navigation-4-39` | 48 | - | 0 |
| `native_parity_weaker_surfaces` | Presented surfaces | `apps2-226`, `apps2-255`, `apps2-270`, `inputs-12`, `inputs-90`, `mech3-89`, `navigation-1-11`, `navigation-1-23`, `navigation-1-50`, `navigation-1-59`, `navigation-2-02`, `navigation-2-30`, `navigation-2-65`, `navigation-2-69`, `navigation-2-70`, `navigation-3-08`, `navigation-4-37`, `navigation-4-47`, `navigation-5-53`, `navigation-5-55` | 48 | `apps2-44`, `apps2-247`, `mech1-120`, `mech2-104`, `mech3-87`, `navigation-1-14` | 33 |

### Restored main features

The owner restored five retired features in Facet. The cases in
`native_parity_restore` move these contracts from class c to class a. Each
contract has `restoredBy` set to `parity/restore`.

| Feature | Contracts | Main cases | Still weaker |
|---|---|---:|---|
| `UI.ErrorBoundary` on `Compose.boundary` | `mech1-115` | 8 | The presenter critical screen is not restored. |
| Table and list multi-select keys | `collections-150`, `collections-198` | 6 | A plain arrow moves the focus and does not select. |
| RowActions tray closes on an outside tap | `collections-78`, `collections-90`, `collections-285` | 13 | A press on the content of the open row keeps the tray open. |
| Label `textSize = "fit"` | `mech3-83` | 18 | The engine picks the size through `TextScaled`. The headless engine does not scale text. |
| Label `truncate = "middle"` | `mech2-46` | 14 | The headless engine measures with a fixed glyph width. |

Facet Neutral's `Light` palette is newer than the baseline. Its contract
`post-lab-02` moves from class d to class a. `native_parity_restore` checks
both palettes against the contrast gate, and the theme strength specs check
both palettes where they checked one before.

### Final gap tests

These cases close 19 of the last 22 gap contracts, with 47 main cases.

| Spec | Candidate case | Closes | Main cases |
|---|---|---|---:|
| `native_parity_themes` | terminates on a self-referential metrics table and rejects it as a cycle | `themes-P4-42` | 1 |
| `native_parity_themes` | slices the slider rail and paints a sliced = false thumb as a whole image | `themes-P2-23` | 2 |
| `native_parity_paint` | tints framework icons with the content role of each palette and never leaves them white | `themes-P2-38`, `themes-P2-46` | 2 |
| `native_parity_paint` | re-letters the icon on a status plate with the plate partner color as a direct child | `themes-P2-47`, `themes-P2-62` | 2 |
| `native_parity_paint` | compiles every type role to native font rules and tags labels with their role | paint-148 | 9 |
| `native_parity_gaps` | refuses picker selection and disclosure toggling while disabled and resumes when enabled | paint-30 | 2 |
| `native_parity_gaps` | estimates table rows from a regular control height that falls back when the theme metric is missing or not finite | collections-50 | 2 |
| `native_parity_gaps` | keeps the value when custom combo box validation unmounts the control | navigation-2-12 | 1 |
| `native_parity_navigation` | restores VirtualGrid and Table keys across a retained tab switch (three cases) | navigation-4-69 | 3 |
| `native_parity_navigation` | keeps both showcase tab levels at the 44 pixel floor, marks each selection and reveals once | navigation-5-47 | 5 |
| `native_parity_navigation` | pages each showcase tab strip by shoulder, traps the alert and restores its launcher on Back | apps2-232 | 2 |
| `native_gallery_collections` | opens the mail row menu with Shift+Return on a selected row and runs a chosen item | collections-102 | 1 |
| `native_gallery_collections` | reaches the mail table edit minus by selection and swipes a table row open without reordering | collections-106 | 2 |
| `native_gallery_collections` | mounts the virtual mail surface alone and swipes deletes and opens row menus from each input | collections-108 | 6 |
| `native_gallery_collections` | drops the mail heading on a short landscape and keeps the first row on every surface | collections-110 | 4 |
| `native_parity_media` | follows a readable alert source that moves in flight and keeps the last origin when it goes nil | apps-258 | 2 |
| `native_parity_apps` | draws every player-facing string from the locale table and relabels all of them on a locale switch | apps-70 | 1 |

`closeNote` in the data file records what each of these cases does not
prove:

- paint-148: The neutral package sets `strong` to Bold and `numeral` to
  Regular. On `main` they were SemiBold and Bold. A package that sets `body`
  or `control` gets the derivation that `api.md` describes.
- collections-108: The hosted gesture engine was deleted, so its laziness
  is not tested. TabView keeps visited pages, so the list page is hidden,
  not removed.
- collections-110 and apps2-232: The fake engine does no layout and does
  not move the selection. A live check must show that the first row is on
  the screen at 844x390 and that the D-pad reaches both tab strips.
- apps-70: The Sheet close button label "Done" is fixed English and has no
  option. The case skips it.

### Engine mechanism tests

These tests close class b contracts that had no candidate test and no live
record. A headless case moves the contract to class a. A live case adds
`liveEvidence` and the contract stays in class b. The live suites are in
`tools/studio/live/suites/classb_*.luau`. The results are in
`artifacts/studio-live/classb_*.json`. Each new headless case failed first
when its behavior was broken in `src` or in the example.

| Spec and live suite | Headless (class a) | Live | Main cases |
|---|---|---|---:|
| `native_parity_classb_collections` and `classb_collections` | `collections-29`, `collections-42`, `collections-54`, `collections-60`, `collections-73`, `collections-98`, `collections-140`, `collections-153`, `collections-154`, `collections-156`, `collections-174`, `collections-182`, `collections-189`, `collections-192`, `collections-197`, `collections-233`, `collections-243`, `collections-254`, `collections-264`, `collections-291` | `collections-29`, `collections-54`, `collections-60`, `collections-98`, `collections-140`, `collections-182`, `collections-233`, `collections-243`, `collections-264` | 50 |
| `classb_examples` (live only) | - | `apps2-05`, `apps2-27`, `apps2-131`, `apps2-166`, `apps2-180` | 6 |
| `native_parity_classb_input` and `classb_input` | `inputs-88`, `inputs-164`, `navigation-2-33`, `navigation-4-64` | - | 8 |
| `native_parity_classb_keyboard` and `classb_keyboard` | `apps-151`, `apps-161`, `apps-166`, `apps-180`, `apps-211`, `inputs-31`, `inputs-46`, `inputs-116`, `inputs-175`, `inputs-220` | `apps-151`, `apps-161`, `apps-166`, `apps-211`, `apps-222`, `apps-249`, `apps-255`, `inputs-31`, `inputs-46`, `inputs-69`, `inputs-116`, `inputs-121`, `inputs-159`, `inputs-175`, `inputs-187`, `inputs-220` | 61 |
| `native_parity_classb_navigation` and `classb_navigation` | `mech3-08`, `mech3-35`, `navigation-3-51`, `navigation-4-26`, `navigation-4-58`, `navigation-5-09`, `paint-87` | `mech3-08`, `mech3-35`, `navigation-2-06`, `navigation-3-19`, `navigation-3-44`, `navigation-3-48`, `navigation-3-51`, `navigation-4-26`, `navigation-4-58`, `navigation-5-20`, `paint-35`, `paint-43`, `paint-86` | 28 |
| `native_parity_classb_showcase` and `classb_showcase` | `apps2-244` | `apps2-222`, `apps2-228`, `apps2-279`, `apps2-282`, `post-showcase-04` | 10 |
| `native_parity_classb_themes` and `classb_themes` | `themes-P1-87`, `themes-P1-88`, `themes-P1-105`, `themes-P1-107`, `themes-P1-117` | `themes-P1-87`, `themes-P1-88`, `themes-P1-90`, `themes-P1-105`, `themes-P1-107`, `themes-P1-117`, `themes-P1-120`, `themes-P3-11`, `themes-P4-15` | 14 |

34 contracts (115 main cases) stay open: `apps2-43`, `apps2-45`, `apps2-48`, `apps2-52`, `apps2-10`, `apps2-68`, `apps2-94`, `apps2-142`, `apps2-169`, `apps-123`, `mech1-65`, `inputs-82`, `inputs-94`, `inputs-100`, `inputs-124`, `inputs-134`, `inputs-137`, `inputs-181`, `apps2-183`, `apps2-188`, `apps2-211`, `apps-192`, `paint-102`, `apps2-229`, `apps2-268`, `apps2-275`, `apps2-277`, `apps2-280`, `apps2-281`, `apps-24`, `apps-90`, `apps-102`, `navigation-1-37`, `paint-51`. Some of them have a partial live case. The work stopped before they were complete.

The owner retired 5 contracts that were candidates for retirement (class c, `retiredBy` is `parity/classb`): `navigation-4-43`, `post-overlays-131`, `paint-73`, `themes-P1-121`, `themes-P5-43`. [Retired promises](21-retirements.md) gives the reasons. The owner asked for `navigation-1-37` (a centred Alert title) and `paint-51` (a smaller icon in a small button) to be implemented. They stay open in class b.

## Proposed tests for the largest gaps

Each proposal is headless. Use the fake engine in `tests/lib/native_engine.luau`.

- **Control size.** Mount Button and ShortcutHint with `controlSize = "tiny"`. Expect an error that names compact, regular and large. Bind a cell and set an illegal value. Expect the last legal height.
- **Icons.** For each shipped package, call `checkCoverage` with every icon name that a control requests. Expect no missing name.
- **Tables.** Mount a Table with fixed and flexible columns. Set the viewport size. Expect the header and body column edges to match. Expect no resize grip on a column with `resizable = false`.
- **Collections.** Mount a horizontal VirtualList with focus. Fire Right. Expect the next key and a scroll into view. Mount with `snap = "item"` and scroll to the end. Expect the end offset.
- **Radial menu.** Mount RadialMenu with `follow = "fixed"`, `centerPassThrough = true` and `launcher = false`. Drive the D-pad and the commit action. Expect the selected item and one activation.
- **Error handling.** For each control family, pass each documented enumeration an unknown value. Expect a named error before a native node is created.
- **Reference apps.** Drive each reference app through its model and its mounted controls: Glade purchase and reset, Cartwheel brew states and guild name rejection, Sipworks search and plurals, Foyer badge and loader.

## Gap list

This contract (3 main cases) still has a promise and no candidate case that
proves all of it. It has a partial headless case. Only a live check with a
real pointer or touch drag can prove the rest, because the Studio input tools
do not send `InputChanged` while a button is held.

| ID | Group | Main cases | Contract | Live check |
|---|---|---:|---|---|
| apps2-35 | row-actions | 3 | Scrolling the page closes a swiped-open tray; a swipe never plays the track (touch and mouse) | A swipe on a playlist row does not also fire `RowHit.Activated`. |

The live harness closed `apps-163` (one Return press on a selected Button
reaches `onActivate` once) and `navigation-1-69` (nothing on the callout page
crosses a lateral edge at 390, 768, 1280 and 1920 px).

## Main cases after the baseline

Some cases were added on `main` after the baseline. Each family records them here and in `postBaseline` of the data file. `totals.contracts` and `totals.contractsByClass` count every contract, the post-baseline families included.

### Content and navigation

`main` added these cases after the baseline, up to `bc9a56a6`. They cover the content and navigation controls. The family has 123 contracts and 135 main cases (a: 111, b: 6, c: 15, d: 3). A case in `needsLive` also needs a live Studio check. The candidate specs are `native_pagination`, `native_step_indicator`, `native_vote`, `native_card` and `native_content_navigation`.

| Contract | Main spec | Main cases | Class | Candidate cases | Note |
|---|---|---:|---|---|---|
| post-pagination-01 | `pagination` | 1 | a | `shows the seven-slot pattern near each edge and in the middle, and a gap of one shows the page` |  |
| post-pagination-02 | `pagination` | 1 | a | `mounts the window, marks the current page and proposes without writing` |  |
| post-pagination-03 | `pagination` | 1 | a | `keeps the overlapping page nodes when the window moves` |  |
| post-pagination-04 | `pagination` | 1 | a | `shows zero pages as inert context and one page with no enabled navigation` |  |
| post-pagination-05 | `pagination` | 1 | a | `follows the flags of an unknown count, shows the page label and never a last page` |  |
| post-pagination-06 | `pagination` | 1 | a | `shows an outside page clamped with a diagnostic and never writes it back` |  |
| post-pagination-07 | `pagination` | 1 | a | `refuses malformed construction and keeps the last legal value for a late one` | Main refused width = hug; the native control refuses AutomaticSize on X, the equivalent native declaration. |
| post-pagination-08 | `pagination` | 1 | a | `drops the farthest boundary page, then the farthest neighbour, then shows the label as room narrows` | Proven live in `ports_content/pagination-fit-narrows-in-order`. |
| post-pagination-09 | `pagination` | 1 | b | - | Proven live in `ports_content/pagination-hug-matches-fill`. |
| post-pagination-10 | `pagination` | 1 | a | `reverses the row once in rtl and keeps the meaning of previous and next` |  |
| post-pagination-11 | `pagination` | 1 | a | `hands the selection of a page that leaves the window to the current page` | Arrival from the neighbours is native gamepad selection and is not simulated headlessly. Live evidence after the recheck. |
| post-pagination-12 | `pagination` | 1 | a | `hands the selection of an arrow that disables at an edge to the current page` |  |
| post-pagination-13 | `pagination` | 1 | a | `gives every page and arrow a slot at the target floor and a compact plate centred in it` | Proven live in `ports_content/pagination-targets-separate-and-centred`. |
| post-pagination-14 | `pagination` | 1 | a | `gives every page and arrow a slot at the target floor and a compact plate centred in it` | Proven live in `ports_content/pagination-targets-separate-and-centred`. |
| post-pagination-15 | `pagination` | 1 | a | `keeps the label reservation while the label gains a digit, ltr and rtl, known and unknown` | Proven live in `ports_content/pagination-arrows-hold-still`. |
| post-pagination-16 | `pagination` | 1 | a | `leaves no stop inside the row when the count drops to zero` | The landing on a live neighbour is native selection. Live evidence after the recheck. |
| post-pagination-17 | `pagination` | 1 | a | `stays safe when a callback changes the count and removes the control` |  |
| post-pagination-18 | `pagination` | 1 | a | `follows an accepted page in the Paging scenario context and changes nothing on a refusal` |  |
| post-step-01 | `step_indicator` | 1 | a | `makes only navigable, enabled steps with onSelect into Buttons and the rest into content` |  |
| post-step-02 | `step_indicator` | 1 | a | `moves the underline and the summary only with current, and a refused selection changes nothing` | Live evidence does not cover this part: The spring is skipped (noted) if GuiService.ReducedMotionEnabled is on in the session. Proven live in `ports_content/steps-underline-follows-and-springs`. |
| post-step-03 | `step_indicator` | 1 | a | `stretches the row cells to one height on one top edge` | Live evidence does not cover this part: The spring is skipped (noted) if GuiService.ReducedMotionEnabled is on in the session. Proven live in `ports_content/steps-underline-follows-and-springs`. |
| post-step-04 | `step_indicator` | 1 | a | `keeps the own cue and state word of an errored or completed current step` |  |
| post-step-05 | `step_indicator` | 1 | a | `keeps the number marker a circle when the text grows` | Live evidence does not cover this part: The largest preferred text size: scripts cannot set PreferredTextSize, so the circle is checked at the session's text size (Medium) only. Proven live in `ports_content/steps-number-marker-is-a-circle`. |
| post-step-06 | `step_indicator` | 1 | a | `never guesses a missing current and rebuilds empty and repopulated lists` |  |
| post-step-07 | `step_indicator` | 1 | a | `keeps each step node across a reorder and renumbers it` | Live evidence does not cover this part: The spring is skipped (noted) if GuiService.ReducedMotionEnabled is on in the session. Proven live in `ports_content/steps-underline-follows-and-springs`. |
| post-step-08 | `step_indicator` | 1 | a | `refuses conflicts at construction and keeps the last legal snapshot later` |  |
| post-step-09 | `step_indicator` | 1 | a | `shows Step n of m and a list that selects through the same path when the width is narrow` | The list is a UI.Menu anchored to the Steps trigger, not a UI.Popover; Popover is not a control of this family. |
| post-step-10 | `step_indicator` | 1 | a | `follows its offer both ways between the row and the summary, for fill and hug` | Live evidence does not cover this part: The Narrow copy's form at 1280 px is noted, not asserted. Proven live in `ports_content/steps-form-fits-the-offer`. |
| post-step-11 | `step_indicator` | 1 | b | - | Live evidence does not cover this part: The Narrow copy's form at 1280 px is noted, not asserted. Proven live in `ports_content/steps-form-fits-the-offer`. |
| post-step-12 | `step_indicator` | 1 | a | `leaves nothing open when a callback removes the control` |  |
| post-step-13 | `step_indicator` | 1 | a | `moves the narrow summary with a row selection in the Steps scenario and refuses both` |  |
| post-vote-01 | `vote` | 1 | a | `accepts, swaps in one change, and proposes none when the chosen side is pressed again` |  |
| post-vote-02 | `vote` | 1 | a | `never paints a refused proposal and never touches the caller's cell` |  |
| post-vote-03 | `vote` | 1 | a | `proposes from a selected side through the keyboard Activate action` | Live evidence does not cover this part: ButtonA itself: the input tools send it as a keyboard key; Return exercises the same native activation of the selected side. D-pad is proven by the Right arrow key. Proven live in `ports_content/vote-pad-reaches-and-proposes`. |
| post-vote-04 | `vote` | 1 | a | `reads a function value and keeps the last legal paint for an invalid late value` |  |
| post-vote-05 | `vote` | 1 | a | `leaves no stale state when a callback removes the vote` |  |
| post-vote-06 | `vote` | 1 | a | `shows a read-only choice with nothing to press or select and uses ordinary disabled paint` |  |
| post-vote-07 | `vote` | 1 | a | `refuses to become interactive without onChange` | The native Vote draws its own segment Buttons with the Picker segment tags, so no private Picker seam exists to guard. |
| post-vote-08 | `vote` | 1 | a | `keeps two votes and a chip as separate targets at the floor, with a disclosed summary` | Proven live in `ports_content/vote-targets-separate`. |
| post-vote-09 | `vote` | 1 | a | `repaints the Choices vote only from its caller's value and follows the summary` |  |
| post-card-01 | `card` | 1 | a | `refuses malformed specs before building anything` |  |
| post-card-02 | `card` | 1 | a | `keeps body, primary and More as sibling targets so one press runs one intent` |  |
| post-card-03 | `card` | 1 | a | `gives an informational body no activation target and keeps its actions at rest` |  |
| post-card-04 | `card` | 1 | a | `keeps the semantics of disabled cards and busy actions` |  |
| post-card-05 | `card` | 1 | a | `keeps the last legal paint for an invalid late title or image and recovers` |  |
| post-card-06 | `card` | 1 | a | `leaves nothing behind when a callback removes its own card` | Main checked the presenter focus scope name; the native case checks that the card and its Cancel context are gone. |
| post-card-07 | `card` | 1 | a | `reveals on a pointer within and keeps the action plate in the card's layout` | The plate stays visible, laid out and ordered after the body, and the root Size never changes; the solved rectangles need Studio. |
| post-card-08 | `card` | 1 | a | `measures the envelope height at rest, before anything reveals` | The root AbsoluteSize is injected. |
| post-card-09 | `card` | 1 | a | `keeps hidden actions out of reach at rest and lets a selected body reveal them` |  |
| post-card-10 | `card` | 1 | a | `reveals on focus within, keeps it when the pointer leaves and ends it when focus leaves` | The Tab walk is native selection; the case moves GuiService.SelectedObject. |
| post-card-11 | `card` | 1 | a | `holds the reveal while its menu is open and releases it when the menu closes` | Live evidence does not cover this part: ButtonA, ButtonB and ButtonY cannot be sent: Return stands in for A (same native activation), leaveActions() is called directly for B, and ButtonY-on-More / B-returns-to-More for the open menu (post-card-11) is not checked. Proven live in `ports_content/card-keys-enter-and-stay-inside`. |
| post-card-12 | `card` | 1 | a | `keeps the reveal while a press is held on an action after the pointer leaves` | The press is the native GuiState of the action Button, set directly. |
| post-card-13 | `card` | 1 | a | `keeps the actions at rest while touch is present and runs the body on the first tap` |  |
| post-card-14 | `card` | 1 | a | `takes no tap on hidden actions and never fires a press cut off by disabling` |  |
| post-card-15 | `card` | 1 | a | `retargets the fade from where it is on a rapid reversal` |  |
| post-card-16 | `card` | 1 | a | `reveals the action row at rest with reveal always` |  |
| post-card-17 | `card` | 1 | a | `follows a live change of the measured envelope while revealed` | The measured root height is injected; a real theme and text change needs Studio. |
| post-card-18 | `card` | 1 | a | `lifts the card with a raised shadow for hover, selection and a held press and lands it after` |  |
| post-card-19 | `card` | 1 | a | `lifts a card with no body action without a shadow` |  |
| post-card-20 | `card` | 1 | a | `puts the card lift on its grid browse stop so the selection ring marks the lifted card` |  |
| post-card-21 | `card` | 1 | a | `keeps only the raised shadow under reduced motion` | The ten-foot half is retired: the native architecture deleted the viewing-distance profile and its tenFootFocusScale, so no focus lift competes with the card scale. |
| post-card-22 | `card` | 1 | a | `reveals only the card whose grid browse stop is selected and moves with the selection` | A parked focus without a painted ring does not exist natively: a pointer session has no GuiService.SelectedObject. |
| post-card-23 | `card` | 1 | a | `enters the actions at the first action, traps the selection and restores the stop on Cancel` | Live evidence does not cover this part: ButtonA, ButtonB and ButtonY cannot be sent: Return stands in for A (same native activation), leaveActions() is called directly for B, and ButtonY-on-More / B-returns-to-More for the open menu (post-card-11) is not checked. Proven live in `ports_content/card-keys-enter-and-stay-inside`. |
| post-card-24 | `card` | 1 | a | `leaves no trap, menu or controls behind when an entered card is removed or replaced` |  |
| post-card-25 | `card` | 1 | a | `recycles an entered card scrolled out of the window without stranding its trap` |  |
| post-card-26 | `card` | 1 | a | `keeps separate cards and entries in two grids with identical keys` |  |
| post-card-27 | `card` | 1 | a | `keeps a half gutter at the outer edges of a grid so a lifted corner card is not clipped` | The scenario step enters and Play runs; that each line holds its card and plate needs the native layout. Live evidence after the recheck. |
| post-card-28 | `card` | 1 | a | `keeps a half gutter at the outer edges of a grid so a lifted corner card is not clipped` | The half-gutter padding, lane width, canvas extent and both scroll ends are asserted; the lifted footprint against the clip is a live check. Live evidence after the recheck. |
| post-card-29 | `card` | 1 | a | `keeps the mounted cards and their controls bounded across a thousand items` |  |
| post-grid-01 | `virtual_grid` | 1 | a | `collections-222 a grid windows whole lines, a tall line alone, and a short last line keeps its lanes` |  |
| post-grid-02 | `virtual_grid` | 1 | a | `collections-222 a grid windows whole lines, a tall line alone, and a short last line keeps its lanes` |  |
| post-grid-03 | `virtual_grid` | 1 | a | `collections-222 a grid windows whole lines, a tall line alone, and a short last line keeps its lanes` |  |
| post-grid-04 | `virtual_grid` | 1 | a | `collections-222 a grid windows whole lines, a tall line alone, and a short last line keeps its lanes` |  |
| post-grid-05 | `virtual_grid` | 1 | a | `collections-240 a horizontal grid sizes its x canvas, stacks lines rightward and splits lanes by the cross extent` |  |
| post-grid-06 | `virtual_grid` | 1 | a | `collections-222 a grid windows whole lines, a tall line alone, and a short last line keeps its lanes` |  |
| post-grid-07 | `virtual_hgrid` | 1 | a | `collections-240 a horizontal grid sizes its x canvas, stacks lines rightward and splits lanes by the cross extent` |  |
| post-menu-01 | `menu` | 1 | a | `opens on ButtonA, closes on ButtonB with the selection back on the trigger, and opens again` | ButtonA is the native Activated event of the trigger; ButtonB is the ModalBack action. |
| post-menu-02 | `menu` | 1 | a | `places the root panel by edge and align and keeps bottom and start when they are absent` | Live evidence does not cover this part: Uses a fixture Menu with edge/align (the Menus scenario has none). Proven live in `ports_content/menu-edge-and-align-place-the-panel`. |
| post-menu-03 | `menu` | 1 | a | `sets the floating panel width from width` |  |
| post-menu-04 | `menu` | 1 | a | `keeps the panel width for rows with a badge, a shortcut label or a section heading` |  |
| post-menu-05 | `menu` | 1 | a | `leads plain rows like accessory rows and gives every row the target floor` | Live evidence does not cover this part: Uses a fixture bounded Menu with plain, badge, shortcut and meta rows (the Menus scenario has no bounded menu). Proven live in `ports_content/menu-rows-floor-and-lead`. |
| post-menu-06 | `menu` | 1 | a | `bounds a floating panel by the screen so a long list scrolls` |  |
| post-menu-07 | `menu` | 1 | a | `opens a level on its selected row, centred in the scrolled list` | Proven live in `ports_content/menu-lands-on-selected-and-walks-bounded`. |
| post-menu-08 | `menu` | 1 | a | `bounds the whole panel by maxHeight while the rows keep their ids and activation` | Proven live in `ports_content/menu-lands-on-selected-and-walks-bounded`. |
| post-menu-09 | `menu` | 1 | a | `keeps submenus anchored to their parent level in a bounded list` |  |
| post-menu-10 | `menu` | 1 | a | `shares one row recipe for badge, avatar, sectionTitle and a display-only shortcutLabel` |  |
| post-menu-11 | `menu` | 1 | a | `refuses malformed placement and bounds by name` | width is a number of pixels natively; main refused a bare number because it took a dimension table. The native control refuses 0 and a string. |
| post-menu-12 | `menu` | 4 | c | - | The solver path shape and its hairline card geometry are not native. Native rows are TextButtons named by id under MenuRows in a ScrollingFrame; the row fill is the native button background. |
| post-menu-13 | `menu_scenario` | 1 | c | - | A path rename of the solver tree only; the native scenario rows are found by id. |
| post-menu-14 | `stateful_menu` | 1 | c | - | A path rename of the solver tree only; native_parity_navigation toggles checked and selected rows by id. |
| post-menu-15 | `popup_button` | 1 | a | `carries a Picker option badge into its menu row as the count seal` | The badge reaches the menu row; a Picker option sectionTitle belongs to the Picker option type of the pickers family. |
| post-tab-01 | `tab_view` | 1 | a | `nests a TabView that a page builds later inside one of its branches` |  |
| post-tab-02 | `tab_view` | 1 | a | `paints a tab indicator as a StatusIndicator in its own tab and keeps it through every switch` |  |
| post-tab-03 | `tab_view` | 1 | a | `refuses a tab indicator that is not a StatusIndicator spec by name` |  |
| post-tab-04 | `tab_view` | 1 | a | `keeps a disabled tab in the strip and refuses its selection on every route` |  |
| post-tab-05 | `tab_view_scenario` | 4 | c | - | A path shape of the solver tree only; native tab rows are named TabRow-<id> when sections exist. |
| post-showcase-01 | `showcase_tabs` | 1 | a | `shrinks tab words toward the caption role in a filling bottom bar before they truncate` | The measured word width and the tab width are injected; the real glyph widths at 320 and 389 px need Studio. Live evidence after the recheck. |
| post-showcase-02 | `showcase_tabs` | 4 | a | `names the Status and Menus groups and the Paging and Steps tabs in All controls` | native_gallery mounts every all_controls tab; the category bar walk is the native TabView. |
| post-showcase-03 | `showcase_tabs` | 1 | b | - | Live evidence does not cover this part: Studio's xbox device reports Gamepad preferred input, so the gallery uses top bars rather than the desktop sidebar at 1542 x 1067. Proven live in `ports_content/choices-vote-row-inside-the-page`. |
| post-showcase-04 | `showcase_tabs` | 1 | b | - | Live evidence after the recheck. |
| post-showcase-05 | `showcase_tabs` | 1 | c | - | UI.ViewThatFits and the candidate solver were deleted (contracts mech1-04, mech1-126). A screen chooses a form with Compose.show on observed native bounds. |
| post-fits-01 | `container_memo` | 1 | c | - | UI.ViewThatFits was deleted with the solver (mech1-04, mech1-126); there is no candidate rule to verify. |
| post-lab-01 | `error_boundary` | 1 | c | - | UI.ErrorBoundary and the text primitive were deleted (mech1-115). Containment stays for presented Alert content and NavigationStack destinations; constructors take the native Name or the constructor name form. |
| post-lab-02 | `theme_package` | 3 | d | - |  |
| post-lab-03 | `tab_view` | 1 | a | `nests a TabView that a page builds later inside one of its branches` |  |
| post-lab-04 | `preview` | 1 | c | - | The environment and its preview were deleted with the application shell. The engine owns the preferred text size and transparency; Studio emulates them. The gallery previews only viewing distance. |
| post-lab-05 | `gallery_chrome` | 1 | c | - | The showcase settings have no device, orientation or input preview; the native gallery keeps only the viewing-distance preview. |
| post-lab-06 | `disclosure_group` | 1 | a | `closes up a collapsed outline section in a scroller and reopens it` | Live evidence does not cover this part: Uses a fixture of two DisclosureGroups in a ScrollingFrame; the Disclosure gallery page has no DisclosureGroup. Proven live in `ports_content/outline-section-closes-up`. |
| post-lab-07 | `api` | 1 | a | `fades a subtree as one group and keeps a transparent group laid out while removal closes up` | The native recipe is a CanvasGroup at GroupTransparency 1 with Interactable false; Compose.show removes the node. Guide 17 documents both. |
| post-navh-01 | `focus_chrome_mixed` | 2 | b | `yields native directional navigation at value bounds and rearms on focus return` | Native gamepad and arrow selection owns horizontal movement; a selected Slider or Stepper binds Left and Right only while it is selected and yields them at its bounds. No focus chrome host exists. |
| post-recipes-01 | `view_recipes` | 1 | a | `runs one activation in a styled group and disables it by inheritance` | Live evidence does not cover this part: Per-corner radii (09) are not native, only one UICorner radius is checked; selection of a button inside a hidden group (05) is noted, not asserted. Proven live in `ports_content/containers-recipes-draw-as-described`. |
| post-recipes-02 | `view_recipes` | 1 | a | `declares fixed, quarter and fill axes as native sizes and flex` | Live evidence does not cover this part: Per-corner radii (09) are not native, only one UICorner radius is checked; selection of a button inside a hidden group (05) is noted, not asserted. Proven live in `ports_content/containers-recipes-draw-as-described`. |
| post-recipes-03 | `view_recipes` | 1 | a | `sizes 1:1, 16:9 and 9:16 subjects inside the same 96 by 96 offer and centres them` | Live evidence does not cover this part: Per-corner radii (09) are not native, only one UICorner radius is checked; selection of a button inside a hidden group (05) is noted, not asserted. Proven live in `ports_content/containers-recipes-draw-as-described`. |
| post-recipes-04 | `view_recipes` | 1 | a | `scales paint with a UIScale while the declared box stays` | Live evidence does not cover this part: Per-corner radii (09) are not native, only one UICorner radius is checked; selection of a button inside a hidden group (05) is noted, not asserted. Proven live in `ports_content/containers-recipes-draw-as-described`. |
| post-recipes-05 | `view_recipes` | 1 | a | `fades a subtree as one group and keeps a transparent group laid out while removal closes up` | Live evidence does not cover this part: Per-corner radii (09) are not native, only one UICorner radius is checked; selection of a button inside a hidden group (05) is noted, not asserted. Proven live in `ports_content/containers-recipes-draw-as-described`. |
| post-recipes-06 | `view_recipes` | 1 | a | `moves a child through spare room with nine alignments` | Live evidence does not cover this part: Per-corner radii (09) are not native, only one UICorner radius is checked; selection of a button inside a hidden group (05) is noted, not asserted. Proven live in `ports_content/containers-recipes-draw-as-described`. |
| post-recipes-07 | `view_recipes` | 1 | a | `spaces siblings with a gap and moves only the named edges with padding` | Live evidence does not cover this part: Per-corner radii (09) are not native, only one UICorner radius is checked; selection of a button inside a hidden group (05) is noted, not asserted. Proven live in `ports_content/containers-recipes-draw-as-described`. |
| post-recipes-08 | `view_recipes` | 1 | a | `wraps a row to a second line, or keeps it on one line in a sideways scroller` | Live evidence does not cover this part: Per-corner radii (09) are not native, only one UICorner radius is checked; selection of a button inside a hidden group (05) is noted, not asserted. Proven live in `ports_content/containers-recipes-draw-as-described`. |
| post-recipes-09 | `view_recipes` | 1 | a | `rounds, strokes and shadows one node with native modifiers` | Live evidence does not cover this part: Per-corner radii (09) are not native, only one UICorner radius is checked; selection of a button inside a hidden group (05) is noted, not asserted. Proven live in `ports_content/containers-recipes-draw-as-described`. |
| post-recipes-10 | `recipes_common` | 1 | a | `insets and paints the recipe dividers from the installed theme` | The heavy line is three hairlines. The leading inset stays the theme space m; the icon-row inset and the 360 px card of main are not ported. |
| post-badge-01 | `badge` | 1 | a | `centres a count seal on the top-right corner of its host without changing the host` | The zero-size Corner frame, the centred anchor, 99+ and no selection stop are asserted; the painted centre needs Studio. |
| post-badge-02 | `badge` | 1 | a | `mirrors the seal to the top-left in rtl and shows true as a dot` |  |
| post-badge-03 | `badge` | 1 | a | `puts an icon tab count on the icon corner and keeps a text tab count in its words` | TabView icon tabs are covered; the segmented Picker icon option corner belongs to the pickers family. A text tab keeps the count in its words, not a separate pill. |

### Pickers and fields

`main` added these cases after the baseline, up to `bc9a56a6`. They cover the pickers and the fields: `UI.DateTimePicker`, `Facet.civilDate`, `UI.ColorPicker`, `UI.NumberInput`, the `UI.TextInput` field chrome, the Picker field forms, the Slider shapes, the Chip edit mode, the Toggle row and the text press. The family has 190 contracts and 194 main cases (a: 194). Each case in `needsLive` also needs a live Studio check. The candidate specs are `native_chip_edit`, `native_color_picker`, `native_date_time_picker`, `native_fields`, `native_number_input`, `native_picker_fields`, `native_picker_models`, `native_slider_shapes`, `native_text_press`, `native_toggle_row`.

| Contract | Main spec | Main cases | Class | Candidate cases | Note |
|---|---|---:|---|---|---|
| post-pickers-001 | `field_chrome` | 1 | a | `a field with no chrome keys keeps its native TextBox root` |  |
| post-pickers-002 | `field_chrome` | 1 | a | `the label sits above its field, and a tap or a finger on it puts the caret in the field` | The fake engine computes no layout; the rectangle is a live item in needs-live/port-pickers.json. Live evidence after the recheck. |
| post-pickers-003 | `field_chrome` | 1 | a | `a disabled field's label follows it: no press or hover affordance, live both ways` |  |
| post-pickers-004 | `field_chrome` | 1 | a | `the label adds no focus stop and reserves the touch floor in its own box` | Selectable flags replace the focus-order traversal; the hit-rectangle overlap is live. |
| post-pickers-005 | `field_chrome` | 1 | a | `the required mark is part of the label's words, bound or static; optional paints no word` | The wrapped-title width check at 320 px is live. Live evidence after the recheck. |
| post-pickers-006 | `field_chrome` | 1 | a | `an error replaces the hint, in the danger role, beside a mark, and the field holds still` |  |
| post-pickers-007 | `field_chrome` | 1 | a | `the error mark is floored at the icon rung and painted the message's colour` | The mark height against its line is live; the colour is read from the compiled StyleSheet rules. Live evidence after the recheck. |
| post-pickers-008 | `field_chrome` | 1 | a | `the caller's error outranks the numeric field's own rejection line` |  |
| post-pickers-009 | `field_chrome` | 1 | a | `both accessories sit inside the plate, and the clear keeps its room between them` | Proven live in `ports_pickers/fields-accessories`. |
| post-pickers-010 | `field_chrome` | 1 | a | `a static leading mark is not a stop; the clear and the trailing action are, in that order` | Selectable nodes in LayoutOrder replace the focus-graph traversal. |
| post-pickers-011 | `field_chrome` | 1 | a | `the trailing action and the clear fire on activation without changing the other` | Only Activated is fired; per-input routing is the native Button and is live. |
| post-pickers-012 | `field_chrome` | 1 | a | `the trailing action and the clear fire on activation without changing the other` | The clear is driven by Activated; the four input routes are native. |
| post-pickers-013 | `field_chrome` | 1 | a | `a search field keeps its leading mark beside a trailing action, and refuses a second one` | Proven live in `ports_pickers/fields-accessories`. |
| post-pickers-014 | `field_chrome` | 1 | a | `appearance paints the plate a published surface; a bound word repaints in place` |  |
| post-pickers-015 | `field_chrome` | 1 | a | `corners ride a native UICorner, and square is a radius of zero` |  |
| post-pickers-016 | `field_chrome` | 1 | a | `a named rung shrinks the plate, reserves a whole target, and the label still focuses` | Target height from Size offsets; the tap area is live. |
| post-pickers-017 | `field_chrome` | 1 | a | `an unknown chrome word is a build error that names the key` |  |
| post-pickers-018 | `field_chrome` | 1 | a | `closing the screen leaves no field node or connection behind` |  |
| post-pickers-019 | `number_input` | 1 | a | `it is the text engine with the number contract, and refuses a second presentation` |  |
| post-pickers-020 | `number_input` | 1 | a | `step must be finite and above zero, precision a whole count of places, units strings` |  |
| post-pickers-021 | `number_input` | 1 | a | `an incomplete draft reverts in silence, and says so only when the field is required` |  |
| post-pickers-022 | `number_input` | 1 | a | `the default parser is the strict grammar, not the language's own reader` |  |
| post-pickers-023 | `number_input` | 1 | a | `a commit reports the number first, and the string is only how it is written` |  |
| post-pickers-024 | `number_input` | 1 | a | `an out-of-range commit clamps and says clamped rather than refusing` |  |
| post-pickers-025 | `number_input` | 1 | a | `precision rounds half away from zero, at commit and never while typing` |  |
| post-pickers-026 | `number_input` | 1 | a | `a callback that disposes the control mid-commit leaves nothing half-written` |  |
| post-pickers-027 | `number_input` | 1 | a | `a prefix and a suffix stand beside the editor and never enter the draft` | Live evidence does not cover this part: The largest PreferredTextSize cannot be set by script; the 320 px check runs at the current text size. Proven live in `ports_pickers/number-units`. |
| post-pickers-028 | `number_input` | 1 | a | `a step button moves the value by one step and commits with submit` | The press is fired through Activated; the four input routes are the native Button. |
| post-pickers-029 | `number_input` | 1 | a | `a press goes through the typed path's rounding and clamping, bounded or not` |  |
| post-pickers-030 | `number_input` | 1 | a | `without a precision, presses land on the step's own places, never on float noise` |  |
| post-pickers-031 | `number_input` | 1 | a | `the step buttons are square targets at the touch floor and separate stops` | Live evidence does not cover this part: Gamepad D-pad is proven with the arrow keys (same native selection). Proven live in `ports_pickers/number-step-buttons`. |
| post-pickers-032 | `number_input` | 1 | a | `the step buttons are ordinary focus stops after the editor and its clear, and claim no arrows` | Live evidence does not cover this part: Gamepad D-pad is proven with the arrow keys (same native selection). Proven live in `ports_pickers/number-step-buttons`. |
| post-pickers-033 | `number_input` | 1 | a | `at the end of its range, read-only or disabled, the button says so and refuses` | Refusal is fired through Activated only. |
| post-pickers-034 | `number_input` | 1 | a | `closing the screen releases the numeric field and its buttons` |  |
| post-pickers-035 | `number_input` | 1 | a | `a field handed the arithmetic recipe commits the answer, and never runs the text` |  |
| post-pickers-036 | `number_input` | 1 | a | `four operators, parentheses, both spellings, and no division by zero` |  |
| post-pickers-037 | `number_input` | 1 | a | `it is total: length and nesting are bounded, so a hostile string answers nil` |  |
| post-pickers-038 | `number_input` | 1 | a | `a press that never promotes leaves the native tap and typing alone` |  |
| post-pickers-039 | `number_input` | 1 | a | `travel moves whole steps of the total, clamps, reports live and commits once at release` |  |
| post-pickers-040 | `number_input` | 1 | a | `a scrub lands on the step's own places, never on float noise` |  |
| post-pickers-041 | `number_input` | 1 | a | `a scrub over a typed draft starts from the committed number and discards the draft` |  |
| post-pickers-042 | `number_input` | 1 | a | `cancel, class loss, disable, readOnly and scrub off restore the snapshot without a commit` |  |
| post-pickers-043 | `number_input` | 1 | a | `a caller write mid-gesture ends it and the caller's number stands` |  |
| post-pickers-044 | `number_input` | 1 | a | `disposal mid-gesture restores the snapshot; an unscrubbable field adds no listener` |  |
| post-pickers-045 | `picker_fields` | 1 | a | `the required mark rides the label and the error replaces the hint beside a danger trigger` | Live evidence does not cover this part: The danger border colour is recorded as a note; the check is the facet-invalid tag. Proven live in `ports_pickers/picker-field-live`. |
| post-pickers-046 | `picker_fields` | 1 | a | `the hint line belongs to the picker: disposal releases it for every style` |  |
| post-pickers-047 | `picker_fields` | 1 | a | `a named rung shrinks the trigger, corners reach it, and it still opens` | The reserved target wrapper is not built for the trigger; the target is live. |
| post-pickers-048 | `picker_fields` | 1 | a | `the hint line belongs to the picker: disposal releases it for every style` |  |
| post-pickers-049 | `picker_fields` | 1 | a | `maxHeight bounds the whole panel, ordinary and searchable, and a bad cap is refused` | Live evidence does not cover this part: Uses a mounted copy of the Driver picker opened through isPresented with d10 chosen; mouse and touch opening are not driven. Proven live in `ports_pickers/picker-menu-scroll-live`. |
| post-pickers-050 | `picker_fields` | 1 | a | `a labelled menu picker stands its title above a trigger at the leading edge` | The retired placement warning channel does not exist; the field form is proven structurally instead. |
| post-pickers-051 | `picker_fields` | 1 | a | `opening lands on the selected row with gamepad or keyboard selection` | Live evidence does not cover this part: Uses a mounted copy of the Driver picker opened through isPresented with d10 chosen; mouse and touch opening are not driven. Proven live in `ports_pickers/picker-menu-scroll-live`. |
| post-pickers-052 | `picker_fields` | 1 | a | `an option avatar's keys are closed: a misspelt one is refused by name` |  |
| post-pickers-053 | `picker_fields` | 1 | a | `an avatar leads its row without a second stop or press, and a disabled row is unreachable` |  |
| post-pickers-054 | `picker_fields` | 1 | a | `an avatar leads its row without a second stop or press, and a disabled row is unreachable` | The panel width against its widest row is live. |
| post-pickers-055 | `picker_fields` | 1 | a | `an avatar leads its row without a second stop or press, and a disabled row is unreachable` | The long label containment is live. |
| post-pickers-056 | `picker_fields` | 1 | a | `appearance paints the track filled, stroked or not at all, live, and refuses a menu word` |  |
| post-pickers-057 | `picker_fields` | 1 | a | `an automatic picker keeps its appearance intent across a live family switch` | The family switch is driven by the measured width and the PreferredInput, not by an environment object. |
| post-pickers-058 | `picker_fields` | 1 | a | `corners reach the strip, and a rung shrinks the segments` | Live evidence does not cover this part: Hairline weight and the fill silhouette are paint; screen capture needed. Proven live in `ports_pickers/picker-segmented-live`. |
| post-pickers-059 | `picker_fields` | 1 | a | `indicatorPosition moves the radio mark to either edge, and belongs to the radio group only` |  |
| post-pickers-060 | `picker_fields` | 1 | a | `each option is a bordered card with its meta, the chosen one plated, on every input` | Selection is driven through Activated. |
| post-pickers-061 | `picker_fields` | 1 | a | `choosing the chosen card again clears it only when the selection is not required` |  |
| post-pickers-062 | `picker_fields` | 1 | a | `a row of cards wraps and long copy wraps inside its card; cards take no appearance` | Proven live in `ports_pickers/picker-cards-live`. |
| post-pickers-063 | `picker_fields` | 1 | a | `follows the caller's live option record: status changes and a removed mark goes` |  |
| post-pickers-064 | `native_text_press` | 1 | a | `a pointer focus selects at its own release, after the engine's release writes` |  |
| post-pickers-065 | `native_text_press` | 1 | a | `activation focus selects in Focused, and offsets are bytes` |  |
| post-pickers-066 | `native_text_press` | 1 | a | `none (the default) writes nothing on any focus` |  |
| post-pickers-067 | `native_text_press` | 1 | a | `blur before release, recycle and disabled cancel a pending selection` |  |
| post-pickers-068 | `native_text_press` | 1 | a | `a touch on a field with nothing to select or scrub adds no listener` |  |
| post-pickers-069 | `native_text_press` | 1 | a | `a policy change while focused applies at the next session` |  |
| post-pickers-070 | `native_text_press` | 1 | a | `a press under the slop is a native tap: focus and caret stay, nothing is promoted` |  |
| post-pickers-071 | `native_text_press` | 1 | a | `past the slop a horizontal drag releases focus and reports the total travel once to its end` |  |
| post-pickers-072 | `native_text_press` | 1 | a | `a vertical drag or a refused promotion stays native for the rest of the press` |  |
| post-pickers-073 | `native_text_press` | 1 | a | `Escape cancels, a recycle cancels, and a second finger never joins the first` |  |
| post-pickers-074 | `native_text_press` | 1 | a | `a mouse press whose release never came does not block the next scrub` |  |
| post-pickers-075 | `chip` | 4 | a | `a tag selects with no mark; editing shows the mark in its plate and activation removes, via pointer`; `a tag selects with no mark; editing shows the mark in its plate and activation removes, via touch`; `a tag selects with no mark; editing shows the mark in its plate and activation removes, via keyboard`; `a tag selects with no mark; editing shows the mark in its plate and activation removes, via gamepad` | Live evidence does not cover this part: Uses a mounted copy of the race tags with editing on; ButtonX is not driven (Delete runs the same RemoveChip action). Proven live in `ports_pickers/chip-edit-live`. |
| post-pickers-076 | `chip` | 1 | a | `Delete and Backspace remove the focused tag only while editing` |  |
| post-pickers-077 | `chip` | 1 | a | `one plate in skinned themes: the mark is text inside the tag, never its own button` |  |
| post-pickers-078 | `chip` | 1 | a | `a selectable tag that can be removed must say when it is editing` |  |
| post-pickers-079 | `chip` | 1 | a | `Delete or Backspace on the last of N tags removes exactly one and lands on the new last` | Live evidence does not cover this part: Uses a mounted copy of the race tags with editing on; ButtonX is not driven (Delete runs the same RemoveChip action). Proven live in `ports_pickers/chip-edit-live`. |
| post-pickers-080 | `chip` | 1 | a | `a held removal does not repeat after an input change, and inherited disabled refuses it` | The input-class change is modelled by a frame with the key still held. |
| post-pickers-081 | `picker_style` | 1 | a | `a searchable list's chosen row paints no wash and wears a check instead` |  |
| post-pickers-082 | `picker_style` | 1 | a | `a labelled menu picker stands its title above a trigger at the leading edge` | Live evidence does not cover this part: The danger border colour is recorded as a note; the check is the facet-invalid tag. Proven live in `ports_pickers/picker-field-live`. |
| post-pickers-083 | `picker_style` | 1 | a | `a navigation link keeps its title and value in one row` | One-line fit at a regular width is live. |
| post-pickers-084 | `picker_style` | 1 | a | `badge, meta and sectionTitle reach the menu engine from an automatic picker` |  |
| post-pickers-085 | `picker_sweep` | 1 | a | `maxHeight bounds the whole panel, ordinary and searchable, and a bad cap is refused` | Live evidence does not cover this part: Uses a mounted copy of the Driver picker opened through isPresented with d10 chosen; mouse and touch opening are not driven. Proven live in `ports_pickers/picker-menu-scroll-live`. |
| post-pickers-086 | `text_input` | 1 | a | `a read-only field keeps its stop and contrast, refuses every edit and commits nothing` |  |
| post-pickers-087 | `text_input` | 1 | a | `a function readOnly flips live on the same editor, keeping the draft and the edit` |  |
| post-pickers-088 | `text_input` | 1 | a | `enabled and readOnly compose onto TextEditable in either order and recover` | The composition is proven through the control, not through the retired screen_props adapter. |
| post-pickers-089 | `text_input` | 1 | a | `readOnly refuses anything but a boolean` |  |
| post-pickers-090 | `text_input` | 1 | a | `the selectOnFocus policy lands on the same editor, live, and an illegal live word keeps the last` |  |
| post-pickers-091 | `text_input` | 1 | a | `an unknown initial selectOnFocus word fails before mount` |  |
| post-pickers-092 | `text_input` | 1 | a | `the box is the count of lines it was told; one line is shorter and still multiline` | Viewport heights come from the typography metric; rendered line boxes are live. Live evidence after the recheck. |
| post-pickers-093 | `text_input` | 1 | a | `past the count the box holds still while the editor grows inside it, on the same editor` |  |
| post-pickers-094 | `text_input` | 1 | a | `an authored root size wins over the line count` |  |
| post-pickers-095 | `text_input` | 1 | a | `a line count is a multiline fact and a whole number of at least one` |  |
| post-pickers-096 | `toggle_presentations` | 1 | a | `a switch, bare or in a settings row, wears no plate and no control art` |  |
| post-pickers-097 | `toggle_presentations` | 1 | a | `a toggle settings row starts its content where a button row does, in every package` | Live evidence does not cover this part: Uses the Buttons tab SettingsRows (Equipment, Assist, Music), which is where the three row kinds stack; the hover state is not driven. Proven live in `ports_pickers/toggle-row-align`. |
| post-pickers-098 | `value_controls` | 1 | a | `a vertical track fills from the bottom edge and the thumb climbs as the value rises` | Proven live in `ports_pickers/slider-axis-live`. |
| post-pickers-099 | `value_controls` | 1 | a | `Up and Down adjust a vertical track and Left and Right do not` |  |
| post-pickers-100 | `value_controls` | 1 | a | `the arrow that lands the ring is not a value step; the next arrow is` | Live evidence does not cover this part: DPadUp is proven with the Up arrow key. Proven live in `ports_pickers/slider-landing-live`. |
| post-pickers-101 | `value_controls` | 1 | a | `every eighth of a turn reads the value the upright track would` |  |
| post-pickers-102 | `value_controls` | 1 | a | `a press on a scrolled track reads the painted position` | The scrolled track is modelled by moving AbsolutePosition. Live finding in `ports_pickers/slider-rotation-live`: at 135 and 270 degrees the click sets the upper handle to 80. |
| post-pickers-103 | `value_controls` | 1 | a | `a bound angle turns the paint live and the label and readout stay upright` |  |
| post-pickers-104 | `value_controls` | 1 | a | `both handles are touch-floor targets and the fill spans between them` | Live evidence does not cover this part: Dragging a handle past the other to minGap needs a pointer drag. Proven live in `ports_pickers/slider-range-live`. |
| post-pickers-105 | `value_controls` | 1 | a | `a thumb stops at the other one, and minGap holds them apart` | Live evidence does not cover this part: Dragging a handle past the other to minGap needs a pointer drag. Proven live in `ports_pickers/slider-range-live`. |
| post-pickers-106 | `value_controls` | 1 | a | `an arrow a thumb cannot use against its partner keeps the ring on that thumb` |  |
| post-pickers-107 | `value_controls` | 1 | a | `a press left of a coincident pair takes the lower thumb, and a press right takes the upper` |  |
| post-pickers-108 | `value_controls` | 1 | a | `a drag keeps the thumb it started with, even dragged past the other one` |  |
| post-pickers-109 | `value_controls` | 1 | a | `one commit per completed gesture, and it names the thumb that moved` |  |
| post-pickers-110 | `value_controls` | 1 | a | `keyboard: each thumb is its own stop, and the arrows adjust the one holding the ring` | Roblox has no Tab traversal; each handle is Selectable and the ring is set through GuiService.SelectedObject. |
| post-pickers-111 | `value_controls` | 1 | a | `gamepad: the arrows navigate until Activate engages, and Cancel gives them back` | Native selection moves between the handles; that move is live. |
| post-pickers-112 | `value_controls` | 1 | a | `losing the input class mid-drag restores both numbers, and the later move and release commit nothing` | The class loss is a PreferredInput change. |
| post-pickers-113 | `value_controls` | 1 | a | `losing the input class mid-drag restores both numbers, and the later move and release commit nothing` |  |
| post-pickers-114 | `value_controls` | 1 | a | `an authored pair the wrong way round is a spec error, not a silent swap` |  |
| post-pickers-115 | `value_controls` | 1 | a | `thumb none paints no handle and leaves every route open` |  |
| post-pickers-116 | `value_controls` | 1 | a | `thumb auto hides the handle at rest and shows it on focus, hover, drag and touch` |  |
| post-pickers-117 | `value_controls` | 1 | a | `thumb auto hides the handle at rest and shows it on focus, hover, drag and touch` |  |
| post-pickers-118 | `value_controls` | 1 | a | `a custom knob is built once per thumb, is told its value and rides it` | The knob floor is a UISizeConstraint; the solved footprint is live. |
| post-pickers-119 | `value_controls` | 1 | a | `a custom knob drops the theme slot and grows past the floor with its content` |  |
| post-pickers-120 | `value_controls` | 1 | a | `a named rung paints a thinner track inside the whole target` | The thinner rail is the paint; the reserved target is the 44 px track. |
| post-pickers-121 | `value_controls` | 1 | a | `thumb auto hides the handle at rest and shows it on focus, hover, drag and touch` |  |
| post-pickers-122 | `value_controls` | 1 | a | `a rung thins a vertical track and the column keeps its travel` |  |
| post-pickers-123 | `value_controls` | 1 | a | `an illegal pair arriving at run time keeps the last legal band and stays driveable` |  |
| post-pickers-124 | `value_controls` | 1 | a | `an illegal pair arriving at run time keeps the last legal band and stays driveable` |  |
| post-pickers-125 | `value_controls` | 1 | a | `an illegal pair arriving at run time keeps the last legal band and stays driveable` |  |
| post-pickers-126 | `value_controls` | 1 | a | `the axis and the other construction words refuse a readable` |  |
| post-pickers-127 | `value_controls` | 1 | a | `a knob is told its own thumb in a range, and each handle wears one` | Live evidence does not cover this part: Dragging a handle past the other to minGap needs a pointer drag. Proven live in `ports_pickers/slider-range-live`. |
| post-pickers-128 | `value_controls` | 1 | a | `a thumbImage beside a thumbContent names the collision, and so does a track pair` |  |
| post-pickers-129 | `value_controls` | 1 | a | `a keyboard Return on a handle does not latch the pad adjust mode` |  |
| post-pickers-130 | `value_controls` | 1 | a | `an initial NaN, a bad type and a bad gap are build errors` |  |
| post-pickers-131 | `value_controls` | 1 | a | `an initial NaN, a bad type and a bad gap are build errors` |  |
| post-pickers-132 | `value_controls` | 1 | a | `a knob is told its own thumb in a range, and each handle wears one`; `building, driving and disposing a shaped slider leaves no connection behind` |  |
| post-pickers-133 | `semantic_rows` | 2 | a | `a toggle settings row starts its content where a button row does, in every package` | Live evidence does not cover this part: Uses the Buttons tab SettingsRows (Equipment, Assist, Music), which is where the three row kinds stack; the hover state is not driven. Proven live in `ports_pickers/toggle-row-align`. |
| post-pickers-134 | `date_time_picker` | 1 | a | `counts leap years, clamps month arithmetic and rolls over years` |  |
| post-pickers-135 | `date_time_picker` | 1 | a | `lays six weeks from the week start, and a date-only value survives any fixed offset` |  |
| post-pickers-136 | `date_time_picker` | 1 | a | `writes and reads the numeric form in the locale's order; a non-date is refused, never moved` |  |
| post-pickers-137 | `date_time_picker` | 1 | a | `the default clock reads the player's local wall clock, not UTC` |  |
| post-pickers-138 | `date_time_picker` | 1 | a | `the calendar opens anchored on the chosen day's month; a pick commits once and closes` |  |
| post-pickers-139 | `date_time_picker` | 1 | a | `the year and month menus open on the shown ones and honour min/max (owner: opened at 1926)` | Live evidence does not cover this part: Gamepad ButtonA is replaced by Return, which drives the same native activation. Proven live in `ports_pickers/dtp-menu-centred`. |
| post-pickers-140 | `date_time_picker` | 1 | a | `a refused pick paints nothing; a disabled or out-of-bounds day is focusable, inert and struck` |  |
| post-pickers-141 | `date_time_picker` | 1 | a | `typed entry commits a date; a refused text stays with its error and commits nothing` | Live evidence does not cover this part: Opened with isPresented instead of a press on the calendar icon. Proven live in `ports_pickers/dtp-anchor-below`. |
| post-pickers-142 | `date_time_picker` | 1 | a | `a typed range reads back its own words in every locale order; a draft's typed text only proposes` |  |
| post-pickers-143 | `date_time_picker` | 1 | a | `keyboard and pad: the arrows walk the grid with its contribution attached, a row's end continues, L1/R1 page` |  |
| post-pickers-144 | `date_time_picker` | 1 | a | `the grid is one selection group; the arrows walk days across months; grey days are no stop; paging stops at the bounds` | Live evidence does not cover this part: D-pad is proven with the arrow keys; the picker is opened with isPresented, not a gamepad press. Proven live in `ports_pickers/dtp-native-navigation`. |
| post-pickers-145 | `date_time_picker` | 1 | a | `a draft on a TV: Down from any day leaves the months below; Up from the first row reaches the header` | Live evidence does not cover this part: D-pad is proven with the arrow keys; the picker is opened with isPresented, not a gamepad press. Proven live in `ports_pickers/dtp-native-navigation`. |
| post-pickers-146 | `date_time_picker` | 1 | a | `a pad sets a date and time: each pick commits, B keeps it and returns focus; a draft's B restores` |  |
| post-pickers-147 | `date_time_picker` | 1 | a | `time: hour and minute fields step on the minute grid, AM/PM flips, and a touch list sets both` |  |
| post-pickers-148 | `date_time_picker` | 1 | a | `the first pick anchors, an earlier second pick swaps, and onRangeCommit waits for both ends` | Live evidence does not cover this part: Colours are read with GetStyled against the Standard palette, not from pixels; the today ring colour is recorded as a note only. Proven live in `ports_pickers/dtp-paint`. |
| post-pickers-149 | `date_time_picker` | 1 | a | `presets clip to the bounds: outside is shown disabled, overlapping is clamped and enabled` |  |
| post-pickers-150 | `date_time_picker` | 1 | a | `draft: picks and presets propose live, only Apply commits, Cancel restores, Reset all clears` | Footer order is proven by LayoutOrder, parents and the SpaceBetween flex, and chip size by the compact controlSize, not by measured rectangles. |
| post-pickers-151 | `date_time_picker` | 1 | a | `a caller write during an open draft re-bases what Cancel restores` |  |
| post-pickers-152 | `date_time_picker` | 1 | a | `a range's end drags across days and panes, crossing swaps, release commits once (owner)` | Drag positions come from synthetic cell rectangles and fired InputBegan/InputChanged/InputEnded events (needs-live dtp-range-drag). |
| post-pickers-153 | `date_time_picker` | 1 | a | `a drafted range drags live but commits only on Apply` |  |
| post-pickers-154 | `date_time_picker` | 1 | a | `the Pickers scenario's window applies a preset only on Apply, and a refusal changes nothing` | The gallery Pickers scenario is not on this branch; the spec builds the same Race day and Season window flow inline instead of running the gallery scenario. |
| post-pickers-155 | `date_time_picker` | 1 | a | `a wide screen shows two consecutive months, and they stay consecutive through paging and bounds` | Proven live in `ports_pickers/dtp-grid-layout`. |
| post-pickers-156 | `date_time_picker` | 1 | a | `two time pickers on one page: Down from a picker's last week reaches ITS OWN hour field` |  |
| post-pickers-157 | `date_time_picker` | 1 | a | `phone portrait and landscape: the calendar fits, every day keeps the floor, Apply is on screen` | Headless proves the route, the 44x44 cell sizes and the surface capped to the screen height; on-screen fit and reachability are needs-live (dtp-phone-fit). Live evidence after the recheck. |
| post-pickers-158 | `date_time_picker` | 1 | a | `a single date's panel hugs its six weeks: no room kept for an absent hint, caption or footer` | Live evidence does not cover this part: No device gives KeyboardAndMouse preferred input; under the xbox default the Gamepad PageHint is legitimately present and the inset is measured from the last visible part. Proven live in `ports_pickers/dtp-panel-hugs`. |
| post-pickers-159 | `date_time_picker` | 1 | a | `the week starts where the caller says; a compact touch field opens a sheet with Done, ten feet a centred sheet` | Live evidence does not cover this part: Closing with B and the return of selection to the calendar icon: B cannot be sent. Relies on the xbox emulator reporting IsTenFootInterface() true, which is recorded in the first check. Proven live in `ports_pickers/dtp-ten-foot`. |
| post-pickers-160 | `date_time_picker` | 1 | a | `refuses a malformed contract at construction and quarantines a late bad value` |  |
| post-pickers-161 | `color_picker` | 1 | a | `parses #RGB, #RRGGBB and #RRGGBBAA (only with alpha) and formats engine bytes uppercase` |  |
| post-pickers-162 | `color_picker` | 1 | a | `keeps a grey's hue (and a black's saturation) through the engine conversion` |  |
| post-pickers-163 | `color_picker` | 1 | a | `a saturation round trip through the Sliders tab returns to the hue the player set` |  |
| post-pickers-164 | `color_picker` | 1 | a | `switching the readout twenty times never moves canonical, and a hex commit is the only write` |  |
| post-pickers-165 | `color_picker` | 1 | a | `a bare well is its swatch, named by its value; a labelled one is a form row` | Proven live in `ports_pickers/color-placement-real-layout`. |
| post-pickers-166 | `color_picker` | 1 | a | `the well opens an anchored panel on a roomy pointer screen; a refused swatch never paints` |  |
| post-pickers-167 | `color_picker` | 1 | a | `the panel never covers its well: below, else above, else beside, else shrunk` | Proven live in `ports_pickers/color-placement-real-layout`. |
| post-pickers-168 | `color_picker` | 1 | a | `the panel never covers its well: below, else above, else beside, else shrunk` | Proven live in `ports_pickers/color-placement-real-layout`. |
| post-pickers-169 | `color_picker` | 1 | a | `the panel keeps one height across every technique, on a pointer panel and a phone sheet` | Live evidence does not cover this part: Each tab is shown by opening a well whose first mode is that tab (same mode set) rather than pressing the mode picker. Proven live in `ports_pickers/color-hidden-technique-size`. |
| post-pickers-170 | `color_picker` | 1 | a | `the panel's height follows its room, never a height it once measured` | The room change is a ScreenGui AbsoluteSize change with injected content heights, not a real rotation. |
| post-pickers-171 | `color_picker` | 1 | a | `an accepted swatch commits once, marks the cell, and the swatch grid lays out rows of eight` | Live evidence does not cover this part: D-pad is proven with the arrow keys. Proven live in `ports_pickers/color-grid-wraps-two-dimensions`. |
| post-pickers-172 | `color_picker` | 1 | a | `saved colours: + proposes the current colour once; Edit removes by activate or Delete and hands the ring on` |  |
| post-pickers-173 | `color_picker` | 1 | a | `refuses a saved-colour callback that is not a function` |  |
| post-pickers-174 | `color_picker` | 1 | a | `a short swatch list keeps square target cells, and the default grid stays a hue per column` | Cell squareness is read from Size offsets, not solved rects. |
| post-pickers-175 | `color_picker` | 1 | a | `without draft every change commits live and B or an outside tap only closes, keeping it` |  |
| post-pickers-176 | `color_picker` | 1 | a | `draft: B and an outside tap discard, restoring the open-time colour; a caller write re-bases it` |  |
| post-pickers-177 | `color_picker` | 1 | a | `draft: gestures propose live but commit nothing; Apply commits once and Cancel restores` |  |
| post-pickers-178 | `color_picker` | 1 | a | `opens as a sheet with Done on a compact touch screen, and a centred sheet at ten feet with the plane` | Live evidence does not cover this part: B cannot be sent. D-pad is proven with the arrow keys. Relies on the xbox emulator reporting IsTenFootInterface() true, which is recorded in the first check. Proven live in `ports_pickers/color-ten-foot-center`. |
| post-pickers-179 | `color_picker` | 1 | a | `a drag tracks 1:1 in saturation and value, keeps the hue, and commits once at release` | Live evidence does not cover this part: Only the precondition is checked (the drag Surface covers the painted plane exactly); a drag cannot be sent, so 1:1 tracking is not checked. Proven live in `ports_pickers/color-plane-layers-and-ring`. |
| post-pickers-180 | `color_picker` | 1 | a | `the native drag detector follows the plane through a tab round trip` |  |
| post-pickers-181 | `color_picker` | 1 | a | `losing the pointer class mid-drag restores where the drag began` |  |
| post-pickers-182 | `color_picker` | 1 | a | `phone portrait and landscape: every target keeps the floor and Apply stays in the panel` | Apply staying on screen and inside the sheet body is proven structurally (Apply outside the scrolling Body, route by orientation); the solved rects are live (color-phone-sheet-apply-on-screen). Live evidence after the recheck. |
| post-pickers-183 | `color_picker` | 1 | a | `on touch the preview leads the panel, and a drag shows the colour in a bubble above the finger` | The bubble is not clamped to the room above the plane (main's bubbleRoom); readability near the top edge is live (color-touch-bubble-room). Live evidence after the recheck. |
| post-pickers-184 | `color_picker` | 1 | a | `the right stick steers the plane only while it holds focus, and a live hint says so` | The owner-size leak check is replaced by the engine heartbeat listener count; camera sinking is proven as InputContext.Sink = true, the camera itself is live (color-stick-sinks-camera). |
| post-pickers-185 | `color_picker` | 1 | a | `a committed line follows a commit, and a refusal changes nothing` | The gallery Pickers scenario itself is not ported to the native candidate; the test composes the same Trim well, team swatches, save cell, committed line and refusal switch in a screen. |
| post-pickers-186 | `color_picker` | 1 | a | `alpha mounts opacity, writes #RRGGBBAA, and shows the checker under a translucent colour` |  |
| post-pickers-187 | `color_picker` | 1 | a | `the Bricks tab names the chosen brick in a field above its grid` | 'Above' is proven by LayoutOrder in the Brick column, not by solved rects. |
| post-pickers-188 | `color_picker` | 1 | a | `the plane is two exact layers, the strips show what they select, and the thumbs are two-tone rings` | Live evidence does not cover this part: The ring structure (black 1 px, white 3 px, black 1 px) is checked on every ring; legibility on white, black and hues needs a screen capture. Proven live in `ports_pickers/color-plane-layers-and-ring`. |
| post-pickers-189 | `color_picker` | 1 | a | `empty shows the placeholder and the crossed plate; disabled keeps its colour and does not open` |  |
| post-pickers-190 | `color_picker` | 1 | a | `refuses a malformed contract at construction and quarantines a late bad value` |  |

### Foundation parity

`main` added these cases after `bc9a56a6`, up to `7c364ca0`. They cover the optional theme roles and metrics (`selection`, `onSelection`, `scrim`, `inverseSurface`, `onInverse`, `dimDisabledPlates`, `strongHairlineOpacity`, `controlSizes.xsmall`, `targetSizes.pointer` and `strokes.utility`), the pane and strong divider tags, and the control options Button `appearance = "inverse"`, `underline` and `textSize`, Toggle `appearance = "plain"` and `textSize`, DisclosureGroup `appearance = "outline"`, `textSize` and `indent`, TabView `controlSize`, Sheet `placement = "adaptive"` and Picker `valueAlignment = "start"`. The family has 38 contracts and 38 main cases (a: 32, c: 6). A case in `needsLive` also needs a live Studio check. The candidate spec is `native_foundation_parity`.

| Contract | Main spec | Main cases | Class | Candidate cases | Note |
|---|---|---:|---|---|---|
| post-port26-001 | `authoring` | 1 | c | - | The `surface` option and the blueprint schema are deleted. Paint is a StyleSheet tag; `facet-pane` is the pane. |
| post-port26-002 | `authoring` | 1 | c | - | The `surface` option and the blueprint schema are deleted. Paint is a StyleSheet tag; `facet-pane` is the pane. |
| post-port26-003 | `authoring` | 1 | c | - | The `surface` option and core.lastError are deleted. Paint is a StyleSheet tag. |
| post-port26-004 | `control_vocabulary` | 1 | a | `xsmall is one ladder step below compact unless the theme authors it, and a partial rung is refused` | The refusal message names the four rungs; there is no separate vocabulary table to read. |
| post-port26-005 | `control_vocabulary` | 1 | a | `xsmall is one ladder step below compact unless the theme authors it, and a partial rung is refused` |  |
| post-port26-006 | `control_vocabulary` | 1 | a | `xsmall is one ladder step below compact unless the theme authors it, and a partial rung is refused`, `the gallery shows the xsmall rung, the inverse and underlined links, the plain checkbox and the outline` | The native Button is its own hit area, so the 44 px footprint is not reserved; api.md says an xsmall button is a 28 px target. The controlSize attribute replaces the facet-size-xsmall tag. Live: `port26-xsmall-rung`. |
| post-port26-007 | `control_vocabulary` | 1 | a | `textSize reaches the label beside an icon and the plain label, as a role or a number` |  |
| post-port26-008 | `control_vocabulary` | 1 | a | `underline hover marks the escaped label while hovered or selected, and always marks it at rest`, `the gallery shows the xsmall rung, the inverse and underlined links, the plain checkbox and the outline` | Hover is the native GuiState set on the fake engine; the real pointer path is live. Live: `port26-underline-live`. |
| post-port26-009 | `control_vocabulary` | 1 | a | `floating menu rows take the pointer floor while the input is pointer-only, live both ways` | Ported to the floating Menu rows. A plain xsmall Button row has no reserved floor in the native model, so it is 28 px on every input. Hit rectangles and overlap are live. Live: `port26-dense-menu-rows`. |
| post-port26-010 | `control_vocabulary` | 1 | a | `floating menu rows take the pointer floor while the input is pointer-only, live both ways` | Ported to the floating Menu rows. A plain xsmall Button row stays 28 px under touch; api.md says to use xsmall only for pointer rows. Live: `port26-dense-menu-rows`. |
| post-port26-011 | `control_vocabulary` | 1 | a | `floating menu rows take the pointer floor while the input is pointer-only, live both ways` | Ported to the floating Menu rows through UserInputService TouchEnabled and GamepadEnabled; overlap is live. Live: `port26-dense-menu-rows`. |
| post-port26-012 | `control_vocabulary` | 1 | a | `targetSizes.pointer is refused below 24 and above the minimum` |  |
| post-port26-013 | `theme_chrome` | 1 | c | - | The metric-mapped rule census is deleted. The native sheet recompiles every rule from the package on a change, and xsmall has no separate corner rule. |
| post-port26-014 | `disclosure_group` | 1 | a | `an outline group has no expanded wash, a chosen role and an indented body`, `the gallery shows the xsmall rung, the inverse and underlined links, the plain checkbox and the outline` | The 16 px content offset is asserted as the UIPadding of RevealFade; the solved rectangle is live. Live: `port26-outline-indent`. |
| post-port26-015 | `foreign` | 1 | c | - | UI.Foreign and the surface option are deleted. |
| post-port26-016 | `stage` | 1 | c | - | The Stage surface option is deleted; the native Stage wears the facet-panel tag. |
| post-port26-017 | `menu` | 1 | a | `floating menu rows take the pointer floor while the input is pointer-only, live both ways` | Row heights are native Size offsets; hit rectangles and overlap are live. The rows are 44 px under the gamepad, not 46: the native row is fixed at the floor. Live: `port26-dense-menu-rows`. |
| post-port26-018 | `picker_style` | 1 | a | `a start-aligned title sits on one line beside its value, and hug sizing hugs the pair` | The one-line row, its wrap and its hug are native UIListLayout and AutomaticSize properties. The centred midlines, the 32 px gap, the 400 px width and the wrap at a large text size are live. Live: `port26-picker-start-inline`. |
| post-port26-019 | `picker_style` | 1 | a | `under touch the one-line trigger hugs its value, and end keeps the title above the trigger` | The trigger hugs its value through AutomaticSize; the 48 px width is live. Live: `port26-picker-touch-row`. |
| post-port26-020 | `picker_style` | 1 | a | `a Picker menu's rows take the pointer floor, and touch grows them back` | Row heights are native Size offsets; overlap is live. Live: `port26-dense-picker-rows`. |
| post-port26-021 | `preferred_transparency` | 1 | a | `a strong divider is three times the hairline unless the theme authors its opacity` | The native sheet scales only the scrim by the preference; the case shows that the strong divider keeps its transparency. |
| post-port26-022 | `preferred_transparency` | 1 | a | `a strong divider is three times the hairline unless the theme authors its opacity` | The census of partial backgrounds is replaced by the strong-divider and scrim values under a preference. |
| post-port26-023 | `preferred_transparency` | 1 | a | `a strong divider is three times the hairline unless the theme authors its opacity` | Only the scrim value changes with preferredTransparency in the native sheet. |
| post-port26-024 | `sheet_parts` | 1 | a | `a roomy pointer screen docks the sheet at the side edge; touch and compact keep the bottom` | The right edge at the room width and the slide are live; the case asserts the anchor, the position scale and FacetPlacement. Live: `port26-sheet-adaptive`. |
| post-port26-025 | `tab_view` | 1 | a | `each tab paints at the rung height while the strip keeps the touch floor` | Heights are native Size offsets; the centring in the strip is live. Live: `port26-tab-rung`. |
| post-port26-026 | `theme_optional_roles` | 1 | a | `Neutral keeps its accent pair, its black scrim and no mark, plate or outline rule` | The native unset scrim stays black (the candidate paint), not surface. The selection ink is the accent pair as on main. |
| post-port26-027 | `theme_optional_roles` | 1 | a | `authored selection, onSelection and scrim reach the switch, slider, underline, tick and backdrop`, `a mounted Slider fill, tab underline and switch track resolve the authored ink` | There is no tint role vocabulary or StyleSheet token table in the native theme; the rule colours carry the authored roles. |
| post-port26-028 | `theme_optional_roles` | 1 | a | `a mounted Slider fill, tab underline and switch track resolve the authored ink` | Resolved from the compiled rules against the mounted tags; engine paint is live. Live: `port26-selection-marks`. |
| post-port26-029 | `theme_optional_roles` | 1 | a | `Neutral keeps its accent pair, its black scrim and no mark, plate or outline rule`, `a chosen Chip, a checked box and a selected link row wear the authored ink, also under hover`, `without an authored selection a chosen Chip keeps the selected-row wash` | The native sheet always emits a base mark rule that paints the selected wash; hover, press and link rules appear only when selection is authored. |
| post-port26-030 | `theme_optional_roles` | 1 | a | `a chosen Chip, a checked box and a selected link row wear the authored ink, also under hover` | The checked box is the facet-toggle-on indicator, which reads the selection ink. Live: `port26-selection-marks`. |
| post-port26-031 | `theme_optional_roles` | 1 | a | `a chosen Chip, a checked box and a selected link row wear the authored ink, also under hover` | The tag is added when the Chip is built; there is no separate adapter classification pass. |
| post-port26-032 | `theme_optional_roles` | 1 | a | `dimDisabledPlates fades each plate toward the page, after every interaction rule` | Live: `port26-dim-disabled-plates`. |
| post-port26-033 | `theme_optional_roles` | 1 | a | `a strong divider is three times the hairline unless the theme authors its opacity`, `the gallery shows the xsmall rung, the inverse and underlined links, the plain checkbox and the outline` | UI.Divider is deleted; the facet-divider-strong tag on a native Frame replaces appearance = strong. Live: `port26-strong-divider-pane`. |
| post-port26-034 | `theme_optional_roles` | 1 | a | `strokes.utility draws the utility outline at its width, and 0 or unset draws none` | The native utility Button has no outline unless strokes.utility is more than 0. Live: `port26-utility-stroke`. |
| post-port26-035 | `theme_optional_roles` | 1 | a | `a pane is the raised fill with no corner and no edge` | The facet-pane tag replaces the surface word; there is one sheet builder. Live: `port26-strong-divider-pane`. |
| post-port26-036 | `theme_optional_roles` | 1 | a | `an inverse Button wears contentStrong lettered in surface, or the authored pair`, `the gallery shows the xsmall rung, the inverse and underlined links, the plain checkbox and the outline` | Live: `port26-inverse-paint`. |
| post-port26-037 | `toggle_presentations` | 1 | a | `a plain compact checkbox paints no wash, labels at its role and still toggles`, `the gallery shows the xsmall rung, the inverse and underlined links, the plain checkbox and the outline` | Activation fires the native Activated event; the 36 px row is its Size offset. |
| post-port26-038 | `toggle_presentations` | 1 | a | `a plain compact checkbox paints no wash, labels at its role and still toggles` |  |

### Lab audit

`main` added these cases after `7c364ca0`, up to `cb75b46b`. They cover the stack fill demand, the Menu submenu chevron, the Slider rung thumb and track floor, the ProgressView bar rungs and ring readout, the read-only Vote rung, the HUD paint probe, the Badge status mark, the ShortcutHint `capStroke` and `capGap` metrics, the StepIndicator rung marker, the GridRow chrome inset, the Notice plate carve and title, and one plate height for each rung. The family has 22 contracts and 30 main cases (a: 22, c: 8). A case in `needsLive` also needs a live Studio check. The candidate spec is `native_lab_audit_parity`.

| Contract | Main spec | Main cases | Class | Candidate cases | Note |
|---|---|---:|---|---|---|
| post-port27-001 | `fill_minimum` | 1 | c | - | The layout solver and its fill weights are deleted; native UIListLayout, UIFlexItem and AutomaticSize own a stack's size (see mech1-123). |
| post-port27-002 | `fill_minimum` | 1 | c | - | The layout solver and its fill weights are deleted; native TextWrapped with AutomaticSize owns the wrap (see mech1-123). |
| post-port27-003 | `fill_minimum` | 1 | c | - | The layout solver and its fill minima are deleted (see mech1-123). |
| post-port27-004 | `measure_memo` | 1 | c | - | The measure memo and its truncation verdict are deleted with the solver. |
| post-port27-005 | `menu` | 1 | a | `a submenu row shows its chevron beside a shortcut row, and the shortcut row shows none` | The native row is one Button with a trailingIcon, so every row form shows the chevron. The rectangle inside the row is native layout. |
| post-port27-006 | `value_controls` | 1 | a | `axis x: the track keeps one target of travel in a hugging cell` | A UISizeConstraint floors the Track at 44 px on both axes. The solved length is native. |
| post-port27-007 | `value_controls` | 1 | a | `axis y: the track keeps one target of travel in a hugging cell` | A UISizeConstraint floors the Track at 44 px on both axes. The solved length is native. |
| post-port27-008 | `value_controls` | 1 | a | `compact and large thumbs differ, and regular is the theme's thumb` | The native thumb is the 24 px knob changed by the rung's icon size less the regular icon size (compact 20, large 28), so regular stays the theme thumb. |
| post-port27-009 | `display_controls` | 1 | a | `a bar spends its rung on track thickness: small rungs thin, regular and large the theme track` |  |
| post-port27-010 | `display_controls` | 1 | a | `a large ring shows its value in the gauge` | A native ring shows its value at every rung: centred when the text bounds fit, else under the ring. It does not refuse a smaller rung. |
| post-port27-011 | `display_controls` | 1 | c | - | There is no ProgressView height option. The native thickness option also sets a ring's stroke, so a ring has nothing to refuse. |
| post-port27-012 | `display_controls` | 1 | a | `refuses a bar rung with a thickness` | The native bar takes thickness in place of height. The existing construction check refuses a diameter on a bar. |
| post-port27-013 | `vote` | 1 | a | `a readOnly vote keeps the interactive strip's rung height` |  |
| post-port27-014 | `hud_paint_probe` | 1 | c | - | The paint probe fixture is deleted (see apps-219). |
| post-port27-015 | `badge` | 1 | a | `the status mark has no page-colour ring and reads against the badge plate` | The native status plate is the neutral control plate, so the mark keeps its status colour, which differs from the plate in every tested package. The mark has no cutout. |
| post-port27-016 | `badge` | 1 | a | `an unplated utility badge draws no status mark` | A native utility badge draws no mark. The main case accepts no mark. |
| post-port27-017 | `shortcut_hint` | 1 | a | `the keycap stroke is a theme metric: Neutral the hairline, 0 draws none` | capStroke sets the .facet-shortcut-hint::UIStroke rule. The native hint draws a chord as one label, so capGap is accepted but has no gap to set. |
| post-port27-018 | `step_indicator` | 1 | a | `the rung sizes the step marker, and regular is the theme's medium icon` |  |
| post-port27-019 | `grid_row` | 1 | c | - | UI.Grid and UI.GridRow are deleted (see mech2-05). |
| post-port27-020 | `notice` | 1 | a | `an art theme's panel carve pads the standard plate; emphasis keeps the plain inset` | The standard plate's UIPadding is the larger of 8 px and the panel contentInsets. The case asserts the padding; the painted rectangles are live. The native title wraps, so a narrow plate does not cut it and it needs no disclosure. Live: `port27-notice-carve`. |
| post-port27-021 | `control_rung_heights` | 9 | a | `neutral: a Button, the segmented track and a checkbox land on one rung height`, `pixel_quest: a Button, the segmented track and a checkbox land on one rung height`, `fantasy_ornate: a Button, the segmented track and a checkbox land on one rung height`, `scifi_hud: a Button, the segmented track and a checkbox land on one rung height` | The case asserts the Button, segmented Picker and checkbox Toggle Size offsets in four packages. TextInput, the menu trigger and the art carve deltas that main pins are live. Live: `port27-rung-heights`. |
| post-port27-022 | `toggle_presentations` | 1 | c | - | The native Toggle has no content-sized width refusal. AutomaticSize sizes every form to its label. |

## Use the data

- `totals` has the class counts before and after the new tests.
- `contracts` has one record for each contract. A record has the main
  specs, the class, the cited candidate cases and the gap.
- `producers.rows` maps each main `full` producer to its candidate status.
- `bugs` has a failing-test description for each defect. `status` is
  `open` or `fixed`. A fixed defect names the case that shows the fix.
- `totals.uncitableCandidateCases` lists citations that are not suite case
  IDs, such as producers and groups of cases.

When you close a gap, add the candidate case ID to the contract and change
its class to `a`. When you retire a promise, change `api.md` first.
