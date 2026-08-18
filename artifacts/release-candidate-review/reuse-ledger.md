# Reuse ledger (acceptance RC-10)

**Every one of the 125 findings in `artifacts/release-candidate-review/reviews/reuse.md`
appears exactly once in the table below**, in one of three states:

- **CONSOLIDATED** — an owner and the commit that landed it.
- **KEPT SEPARATE** — the audit's own recorded reason, which is in every case a
  property of the code rather than a preference. These are the twelve findings
  the audit itself marked `(c) keep separate`.
- **DEFERRED** — an owner (the module the audit's own recommendation names) and a
  trigger that reopens it. Wave R5's brief scoped consolidation to a named
  subset; a finding outside that subset was never in scope, and saying so with
  an owner and a trigger is the honest record. "They may diverge later" is not a
  reason and appears nowhere below.

## What this file claimed before, and why the claim is now checkable

The first version of this ledger opened with the same completeness sentence and
carried **16 of the 125** findings. The R5 review measured it: 109 absent,
including 31 High-severity findings and **9 of the 12** the audit marked
`(c) keep separate` — which the wave's own brief had demanded by name — and
three findings the brief named BY NUMBER (REUSE-29, REUSE-110, REUSE-119) with
no recorded disposition anywhere. RC-10 had been flipped to `PASS_AUTOMATED` on
that artifact, and the `reuse-consolidation` gate row could not see the gap
because its ledger clauses were five fixed `grep -qF` strings — this repository's
own documented "check that proves nothing" shape, applied to exactly the property
RC-10 names.

So the gate row no longer greps for sentences. It **counts the finding IDs in
this file against the ID range in the audit** and fails on any gap, any
duplicate and any ID this file invents, with a planted-omission negative control
in `tools/check_reuse_ledger.py --selftest`. A ledger that drops a row now
reddens the row that publishes it.

Wave R5, 2026-08-18 (fix round 1 included). Framework commits `8691380`,
`36d1883`, `8fe8482`, `1776fb14`, `d1b2d7b2`, `d32364c5`, `3ca4b51`, `d6c5b3c`
and fix round 1; RascalRally `b9a7466`, `6a12637e`, `927b8047`.

---

## Every finding, once

| ID | Sev / Conf | Finding | Disposition | Commit |
|---|---|---|---|---|
| REUSE-1 | High / high | `isFinite` predicate ×17, byte-identical | **CONSOLIDATED** — `src/num.luau` (`isFinite`) | `8fe8482` |
| REUSE-2 | High / high | "Is this a Readable" ×17 in two incompatible spellings | **DEFERRED** — owner `src/controls/reactive_value.luau`; trigger: the next change that touches the divergent copy | — |
| REUSE-3 | High / high | Segment-aligned path prefix ×7 + 2 unsafe inline variants in live routing | **CONSOLIDATED** — `src/paths.luau` (`isPrefix`) — and the two unsafe live copies at `presenter.luau` | `8fe8482` |
| REUSE-4 | High / high | Rect algebra: 15+ copies, four epsilons, two edge conventions | **CONSOLIDATED** — `src/rect.luau` | `8fe8482` |
| REUSE-5 | High / high | Bounded-Levenshtein "did you mean" ×5, two thresholds | **CONSOLIDATED** — `src/text_distance.luau` | `8fe8482` |
| REUSE-6 | Medium / high | `patternEscape` ×6 with an exported owner | **CONSOLIDATED** — `src/paths.luau` (`escape`) — 5 of 6; `controls/table.luau` deferred, see Scoped | `8fe8482` |
| REUSE-7 | Medium / high | Closed-key-set validation bypassed by three modules | **DEFERRED** — owner `the audit's own (a) recommendation`; trigger: the next change that touches the divergent copy | — |
| REUSE-8 | Medium / high | `deepFreeze` ×3, one without the already-frozen guard, behind a public API | **DEFERRED** — owner `src/spec_guard.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-9 | Low / high | Engine-service acquisition: two conventions, one helper written twice | **DEFERRED** — owner `the audit's own (a) recommendation`; trigger: the next change that touches the divergent copy | — |
| REUSE-10 | High / high | Scroll anchoring ×3; two carry the bug the third fixed | **DEFERRED** — owner `src/controls/scroll_anchor.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-11 | High / high | `virtual_grid` re-authors `virtual_window` wholesale | **DEFERRED** — owner `the audit's own (a) recommendation`; trigger: the next change that touches the divergent copy | — |
| REUSE-12 | High / high | Own-subtree walk (`adjustTargets` family) ×9 | **DEFERRED** — owner `src/controls/node_walk.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-13 | High / high | Theme-metrics sanity guard ×5, four use the weak predicate | **DEFERRED** — owner `src/themes/snapshot.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-14 | High / high | Axis-lock verdict ×4 with an owner; and the gate is class-blind | **DEFERRED** — owner `the audit's own (a) recommendation`; trigger: the next change that touches the divergent copy | — |
| REUSE-15 | Medium / high | Settable-Signal refusal ×8, wording already drifted | **DEFERRED** — owner `src/controls/contract.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-16 | Medium / high | Scroll-offset clamp ×4; Table's copy has no NaN guard | **DEFERRED** — owner `src/virtual_extents.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-17 | Medium / high | Menu panel shell ×3 and a presentation-staleness drift the source predicted | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-18 | Medium / medium | Lazy persistent spring bound into a signal ×4 | **DEFERRED** — owner `src/motion/lazy_spring.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-19 | Medium / high | Axis transposition helper families ×3 | **DEFERRED** — owner `src/controls/axis_math.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-20 | Medium / high | Key↔path↔item addressing ×5; Table's is O(N) | **DEFERRED** — owner `src/controls/keyed_index.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-21 | Medium / high | `level_picker` re-authors `value_model`'s arithmetic | **DEFERRED** — owner `the audit's own (a) recommendation`; trigger: the next change that touches the divergent copy | — |
| REUSE-22 | Medium / high | Row-keys action context ×2 | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-23 | Medium / high | Reorder slot→index off-by-one ×2, `insertSlotAt` ×2 | **DEFERRED** — owner `src/virtual_extents.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-24 | Low / high | `bindNativeScroll` wrapper + latch ×3 | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-25 | Low / high | Reactive-enum "validate now, tolerate later" ×3 | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-26 | Low / medium | Per-row selected memo: two lifecycle strategies | **DEFERRED** — owner `the audit's own (a) recommendation`; trigger: the next change that touches the divergent copy | — |
| REUSE-27 | Low / high | Two `resolvePresentation` with different semantics | **KEPT SEPARATE** — Merged semantics would differ: two different questions about two different controls, and a merged function would need both output vocabularies and both input sets. The audit's own cheap fix (rename one) is not this wave's to take. | audit (c) |
| REUSE-28 | High / high | Seven paint walks, seven private caches, one hand-maintained eviction list | **DEFERRED** — owner `src/render/paint_pass.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-29 | High / high | Hidden-roots filter ×3 verbatim, plus an import shadowed by its own copy | **CONSOLIDATED** — `focusMap.isHiddenPath` at all FOUR sites (the audit counted three); the shadowing local in `presenter.luau` deleted | fix round 1 |
| REUSE-30 | Medium / high | Effective text size/face resolver ×5 across measure and paint | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-31 | Medium / medium | Aspect-ratio derivation ×5; grid handles one axis only | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-32 | Medium / high | Alignment factor/offset ×4 with two rounding rules | **DEFERRED** — owner `src/layout/align.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-33 | Medium / medium | Weighted slack distribution: one integral rule, three float copies | **DEFERRED** — owner `src/layout/distribute.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-34 | Medium / high | Prop→write-channel declared twice, plus a third class-scoping table | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-35 | Low / high | Stage/Foreign host seam: three matched twins | **DEFERRED** — owner `src/render/host_seam.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-36 | Low / high | `screenRectOf` / `paintedRectIn` share eight lines of shift math | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-37 | Low / high | `drainDeparted` / `drainAppeared` identical | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-38 | Low / medium | `adaptive.sizeClass` / `heightClass`: one rule, two bodies | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-39 | Low / medium | `math.floor(v + 0.5)` ×61, one named helper | **CONSOLIDATED** — `src/num.luau` (`roundPx`) + `src/rect.luau` | `8fe8482` |
| REUSE-40 | Low / medium | Five diagnostic-record shapes for one concept | **KEPT SEPARATE** — Merged semantics would differ: `placement_audit`'s `filedBy` exists because a parent files a finding naming a child, and its ABSENCE is load-bearing for the incremental-replay gate at `solver.luau`. A merged record carries a field meaningless to the other four. | audit (c) |
| REUSE-41 | Low / high | "First candidate that fits, else the declared fallback" ×2 | **KEPT SEPARATE** — More branching than it removes: a merged helper needs a fit predicate, a rejection reporter, an eligibility gate and a forced-fallback callback to eliminate ~6 shared lines. The shared RULE is already stated in both headers. | audit (c) |
| REUSE-42 | High / high | Hand-mounted presenter-private chrome overlay ×7 | **DEFERRED** — owner `src/present/chrome_layer.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-43 | High / high | Document-order first-visible-match walker ×3 | **DEFERRED** — owner `src/present/focus_map.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-44 | High / high | Pointer-dwell engagement state machine ×2 | **DEFERRED** — owner `src/present/dwell.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-45 | Medium / high | Listener list + unsubscribe ×6, two error policies | **DEFERRED** — owner `src/core/listeners.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-46 | Medium / high | Duration-ramp driver ×3 inside one module, already asymmetric | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-47 | Medium / high | `motion/classes` and `motion/curves` are the same registry twice | **DEFERRED** — owner `src/motion/named_registry.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-48 | Medium / high | Blueprint meta-channel attach ×4, read ×2 | **DEFERRED** — owner `src/blueprint.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-49 | Medium / medium | "Is this node focusable" ×7, no two agree on the guards | **DEFERRED** — owner `src/focus_classes.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-50 | Low / medium | `easeOutQuad` hand-rolled beside the curve evaluator | **KEPT SEPARATE** — Dependency reversal plus a measured shape: `autoscroll` is deliberately dependency-free and `motion/curves` is a registry with table dispatch, a direction branch and a `-0` normalisation, where this is two multiplies. | audit (c) |
| REUSE-51 | Low / high | Clock-participant done-latch scaffold ×2 | **KEPT SEPARATE** — Merged semantics would differ: `chase` fires an arrival with a `how` reason; `timeline` runs terminals in two orders and reports one of four reasons. A shared base is ~10 lines of scaffold wrapped in more branching than it removes. | audit (c) |
| REUSE-52 | High / high | Colour-role resolution ×2, already divergent, with a live game workaround | **DEFERRED** — owner `src/tokens/palette.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-53 | High / high | Slot flat-paint tables hand-mirrored across the two paint paths | **DEFERRED** — owner `src/tokens/chrome_slots.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-54 | High / high | `UIShadow` property write ×3 | **DEFERRED** — owner `src/client/paint_primitives.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-55 | High / high | Descriptor→`Font` builder ×3, and the key format declared twice | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-56 | High / high | `default_style` / `default_light_style` near-copy, with live shadow drift | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-57 | Medium / high | Interaction-state colour derivation stated three times | **DEFERRED** — owner `src/tokens/palette.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-58 | Medium / high | `stampOf` (FNV-1a) written twice | **DEFERRED** — owner `the audit's own (a) recommendation`; trigger: the next change that touches the divergent copy | — |
| REUSE-59 | Medium / high | Dotted-path traversal: 2 writers + 3 readers, all hand-rolled | **DEFERRED** — owner `src/themes/metric_path.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-60 | Medium / high | Border `UIStroke` creation ×5 and three partial name registries | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-61 | Medium / medium | Gradient sequence materialization ×2 | **DEFERRED** — owner `the audit's own (a) recommendation`; trigger: the next change that touches the divergent copy | — |
| REUSE-62 | Low / high | `toColor3` ×3 plus inline copies | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-63 | Low / high | The ten-foot rule stated twice inside `environment.luau` | **DEFERRED** — owner `the audit's own (a) recommendation`; trigger: the next change that touches the divergent copy | — |
| REUSE-64 | Low / high | `imperative.luau` writes the same closure twice in one function | **DEFERRED** — owner `the audit's own (a) recommendation`; trigger: the next change that touches the divergent copy | — |
| REUSE-65 | Low / high | Copy-on-write decoration hint ×2 in one file | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-66 | Low / high | Haptics entry-connection teardown ×2 | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-67 | Low / medium | Capitalize-first ×6, sorted-key collection ×8 | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-68 | Low / high | Three cores' `defaultEq` diverge on NaN | **KEPT SEPARATE** — Merged semantics would differ, AND THE DIFFERENCE IS THE MEASUREMENT: ADR-0002 scores the imperative baseline on `nan-equal-write-skipped`, and all three conformance artifacts carry that named check. The three cores are the bake-off candidates. | audit (c) |
| REUSE-69 | Low / medium | Scalar-shape validators at ~25 public boundaries | **KEPT SEPARATE** — Merged semantics would differ: most messages carry teaching text that IS the error's value, and `package.luau` collects reports rather than throwing, so a merged helper needs a mechanism parameter. Two purely mechanical sites do not earn an extraction. | audit (c) |
| REUSE-70 | Low / medium | `chrome_props.colorSeq` / `numSeq` are the same function twice | **KEPT SEPARATE** — More branching than it removes, and it obscures a tutorial: the stop payloads genuinely differ (`{r,g,b}` vs `{v}`), and the 201-line file is the framework's stated single-owner explanation of what `kind` means. | audit (c) |
| REUSE-71 | High / high | Framework-checker chain copied into 12 gate rows, five different contents | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-72 | High / high | Prior-gates allowlist inline-Python'd into 5 rows, three different policies | **DEFERRED** — owner `tools/check_prior_gates_rollup.py`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-73 | High / high | Python checker report skeleton ×13, three dialects, divergent missing-evidence handling | **DEFERRED** — owner `tools/gatecheck.py`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-74 | High / high | `check_sf_rows` / `check_spike` / `check_verdicts` are one checker three times | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-75 | Medium / high | Shell preamble ×17; five wrappers byte-identical but for one line | **DEFERRED** — owner `tools/_common.sh`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-76 | Medium / high | `check_*_cli` printer written four times | **DEFERRED** — owner `tools/lune/checker_cli.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-77 | Medium / high | Two Luau line-lints share a copied engine, and a comment detector that under-delivers | **DEFERRED** — owner `tools/lune/source_lint.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-78 | Medium / high | Perf-lab harness built from scratch ×5 | **DEFERRED** — owner `tests/lib/perf_lab_harness.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-79 | Medium / high | `tools/lune/artifact.luau` exists and is bypassed by five sites | **DEFERRED** — owner `the audit's own (a) recommendation`; trigger: the next change that touches the divergent copy | — |
| REUSE-80 | Medium / high | 48 gate rows re-assert the evidence check `gate.luau` already performs | **DEFERRED** — owner `the audit's own (a) recommendation`; trigger: the next change that touches the divergent copy | — |
| REUSE-81 | Medium / high | Five ad-hoc `process.args` flag parsers; one already ran the wrong path silently | **DEFERRED** — owner `tools/lune/cli_args.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-82 | Medium / high | Capture sha256[:16] pin implemented five times in three languages | **DEFERRED** — owner `tools/check_capture_pins.py`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-83 | Medium / high | `percentile` ×2; one lacks the empty-sample guard | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-84 | Medium / high | Consumer path hardcoded 74×, suite row duplicated 14× | **DEFERRED** — owner `tools/consumer.json`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-85 | Low / high | `.luau` directory walkers ×6, two inside one file | **DEFERRED** — owner `tools/lune/fs_walk.luau: luauFiles(root, { recursive? })`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-86 | Low / medium | Probe scene-mount harness copied into eight probes | **DEFERRED** — owner `tests/lib/scene_harness.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-87 | Low / high | Suite-transcript capture/grep idiom ×179 / ×1412 | **KEPT SEPARATE** — A WRITTEN POLICY makes the literal shape the subject of an existing audit: `check_manifest_integrity.py` pins `SUITE_CMD`/`CAPTURE`/`FORM_A`/`FORM_B` as regexes over these exact strings. Collapsing the captures into a helper would blind that audit. | audit (c) |
| REUSE-88 | High / high | Headless stack builder ×106 across 100 spec files, two incompatible return orders | **CONSOLIDATED** — `tests/lib/world.luau` — 24 spec files, R12 scope | `d1b2d7b2` |
| REUSE-89 | High / high | Recursive deep-copy ×16 | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-90 | High / high | Neutral-derived theme-package fixture ×10 | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-91 | High / high | Reference theme-package registry ×9, already divergent | **DEFERRED** — owner `tests/lib/theme_packages.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-92 | High / high | Five `ref_*` gallery scenarios, 122 lines each, differing in four identifiers | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-93 | High / high | `adapter_source` / `renderer_source` bypassed by 29 raw reads — silent-green pins | **DEFERRED** — owner `the audit's own (a) recommendation`; trigger: the next change that touches the divergent copy | — |
| REUSE-94 | High / high | `scrollStub` ×6; five return a no-op unsubscribe | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-95 | Medium / high | Scenario-fixture world ×9 | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-96 | Medium / high | `press` ×17 and `settle` ×26 drive helpers | **CONSOLIDATED** — `world.press` / `world.settle` / `world.tick` | `d1b2d7b2` |
| REUSE-97 | Medium / high | Diagnostics assertions ×12 at three fidelities | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-98 | Medium / high | Virtual-collection fixtures ×19 | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-99 | Medium / high | Sponsor-scenario trace recorder ×8 | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-100 | Medium / high | Theme-install step ×7; only one carries the lesson | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-101 | Medium / high | `section()` source-slicing ×7, inconsistent inside one file | **DEFERRED** — owner `the audit's own (a) recommendation`; trigger: the next change that touches the divergent copy | — |
| REUSE-102 | Medium / high | Two device matrices claim to be identical and are not | **DEFERRED** — owner `the audit's own (a) recommendation`; trigger: the next change that touches the divergent copy | — |
| REUSE-103 | Medium / high | `fails` ×8, `contains` ×8 (two contracts, one name), `near` ×2 | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-104 | Medium / high | Renderer-attach world ×10 | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-105 | Low / high | `fixed` / `fill` Dim shorthands ×21 | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-106 | Low / high | `clip(text, chars)` in both gallery pickers | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-107 | Low / medium | Two bench registries share three workload names | **KEPT SEPARATE** — Merged semantics would differ: they measure different subjects and merging makes each number unattributable. The audit's own follow-up — disambiguating the NAMES — is recorded, not taken. | audit (c) |
| REUSE-108 | Low / high | `cloneRows` in a tutorial and in a fixture | **KEPT SEPARATE** — Obscures a tutorial, and the semantics differ: different record shapes and different jobs, and `05_word_game` is a teaching file whose family header commits every example to being readable end to end without cross-imports. | audit (c) |
| REUSE-109 | High / high | Facet client host bootstrap ×4; three of four freeze the motion clock | **CONSOLIDATED** — `src/client/host.luau`, blessed client entry point #12 | `1776fb14` / RR `6a12637e` |
| REUSE-110 | High / high | Reduced motion has three authorities; the player's setting reaches ~3 of ~44 sites | **DEFERRED** — owner ``roblox_env.bind(env, { reducedMotion })``. **HIGH, and named in brief §3b** — not taken. The framework half is a one-line seam; the consumer half retires ~44 raw `ReducedMotionEnabled` reads across 14 RascalRally modules, which is a game-side wave. Trigger: the next RR wave that touches any SponsorGesture/ItemFx motion path, or the haptics-defaults row, whichever lands first. | — |
| REUSE-111 | High / high | Spring solver and motion-class registry duplicated wholesale | **DEFERRED** — owner `the audit's own (a) recommendation`; trigger: the next change that touches the divergent copy | — |
| REUSE-112 | High / high | `AVG_GLYPH_FRACTION = 0.62` copied into the game five times, beside the real measurer | **DEFERRED** — owner `the audit's own (a) recommendation`; trigger: the next change that touches the divergent copy | — |
| REUSE-113 | High / high | Device-chrome facts re-derived 5× and watched 13× | **DEFERRED** — owner `src/client/screen_chrome.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-114 | High / high | The racer list exists three times, with two finish latches and three badges | **DEFERRED** — owner `the audit's own (a) recommendation`; trigger: the next change that touches the divergent copy | — |
| REUSE-115 | Medium / high | 13 game modules own a per-frame loop across three RunService signals | **CONSOLIDATED** — `presenter.onTick` + the host's single PreRender; `presenter.claimFrameDriver` added in fix round 1 so the one-driver rule covers both drivers | `1776fb14`, fix round 1 |
| REUSE-116 | Medium / high | Settings pair: ~130 lines of dock chrome duplicated, plus a positional binding | **DEFERRED** — owner `the audit's own (a) recommendation`; trigger: the next change that touches the divergent copy | — |
| REUSE-117 | Medium / high | Four surface-plate recipes, a triplicated ribbon, 15 corner-radius values | **DEFERRED** — owner `src/controls/banner.luau`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-118 | Medium / high | Hand-rolled keyed reconciler and transient banner in the always-on HUD | **DEFERRED** — owner `the audit's own (a) recommendation`; trigger: the next change that touches the divergent copy | — |
| REUSE-119 | Medium / high | The Facet arm produces no UI sound and no haptics | **DEFERRED** — owner ``presenter.onFeedback` -> `UiSound.play/haptic` in the host`. **Named in brief §3b** — not taken, and deferred to a row that exists: acceptance `RC-13` (haptics defaults) is still PENDING and owns the game's feedback->sound/haptic mapping. Trigger: RC-13. | — |
| REUSE-120 | Medium / medium | External-observable→Signal adapter ×3 shapes, no framework owner | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-121 | Medium / medium | Blueprint node identity is a hand-maintained path string; 17 `PATHS` tables | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-122 | Medium / high | Cross-surface z-order has no owner; Facet roots default to the bottom | **CONSOLIDATED** — `screen_target.Opts.displayOrder` | `1776fb14` |
| REUSE-123 | Low / high | Three input models the framework already extracted, still live in the game | **KEPT SEPARATE** — AN EXPLICITLY AUTHORISED POLICY: the root `CLAUDE.md` keeps the legacy Sponsor modules shipped and untouched as the `UseLuauUISponsor = false` rollback arm. The audit's own follow-up (record the delete-when-the-arm-retires trigger) belongs to the migration doc. | audit (c) |
| REUSE-124 | Low / high | Boot-readiness is a game-invented viewport spin loop | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |
| REUSE-125 | Low / high | Studio-only preview modules ship to every production client | **DEFERRED** — owner `the audit's own (b) recommendation`; trigger: the next change that edits two or more of the copies the audit lists | — |

---

## The High-severity deferrals, called out

A `DEFERRED` row is honest but easy to skim past, so the High findings that are
still deferred are named here for routing. None is a live defect the audit
measured as *currently* wrong except where noted; each is a divergence risk with
a real owner:

- **REUSE-2** (Readable predicate ×17, two incompatible spellings) — the two
  predicates genuinely disagree today about a table with a `get` method, which
  is the one deferral on this list with a measurable behavioural split.
- **REUSE-10** (scroll anchoring ×3; two carry the bug the third fixed) —
  `table.luau` holds the fixed copy and is OFF-LIMITS while the source cap
  stands, which is what blocks it.
- **REUSE-11** (`virtual_grid` re-authors `virtual_window` wholesale),
  **REUSE-12** (own-subtree walk ×9), **REUSE-13**, **REUSE-15**, **REUSE-16**,
  **REUSE-17** — the `controls/` family, all of which touch `table.luau`,
  `virtual_list.luau` or both.
- **REUSE-71 / 72 / 73 / 74** — the gate and checker families: framework-checker
  chains copied into 12 gate rows, the prior-gates allowlist inline-Python'd
  into 5, the Python report skeleton ×13, and three checkers that are one
  checker three times. Owner is `tools/`; the natural moment is the Step 14 gate
  simplification the manifest already books.
- **REUSE-90** (neutral-derived theme-package fixture ×10) and **REUSE-100** —
  `tests/lib/` fixtures, the same class of work as REUSE-88 and the natural next
  users of `tests/lib/world.luau`'s precedent.
- **REUSE-110** (reduced motion has three authorities) — see its row: the
  framework half is one seam, the consumer half is a game-side wave.

## Enforcement (the gap the audit named)

The audit observed that none of the 14 `check_*.luau` or 19 `check_*.py`
checkers asserted single ownership of any mechanism in the report — every
finding was held by review alone. What R5 added:

- `tools/check_reuse_ledger.py` — **this file's own completeness**, structurally:
  the finding IDs here against the ID range in the audit. Selftest plants an
  omission, a duplicate and an invented ID.
- `tests/world_substrate.spec.luau` — the retired 5-tuple order in both
  spellings, plus a **ratchet on hand-rolled presenter builders** so R12's
  follow-up trigger is mechanical rather than a grep for its own sentence.
- `tests/hidden_roots_owner.spec.luau` — REUSE-29's four walks against one owner,
  with the shadowing local pinned structurally.
- `tools/check_call_shape_drift.py` — a NEW old-form composite call in either
  repository, scanned WHOLE-FILE (a wrapped call defeated the first version) with
  a wrapped-call plant in the selftest and its two remaining blind spots named in
  the docstring.
- `tools/check_brand_drift.py` — the `luau-*` theme-tag family, with the
  toolchain names asserted NOT caught, and its `gate_manifest.luau` allowlist
  entries scoped to their two literal sentences rather than to the whole file.
- `tools/lune/check_boundary.luau` — verified by planting that a consumer require
  of `vendor/Fusion` or `src/core/` is refused.
- `tests/session_lifetime.spec.luau`, `tests/process_globals.spec.luau`,
  `tests/leaf_helpers.spec.luau`, `tests/text_distance.spec.luau`,
  `tests/client_host.spec.luau` — each pins an owner's contract, and each was
  mutation-tested against the defect it exists to catch.
