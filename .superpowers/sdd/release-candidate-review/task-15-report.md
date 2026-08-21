# Wave T15 — report

**Status: COMPLETE for the headless/build half. Two CONTESTED items, both with
measurements and named blockers.** No Studio capture taken, no push, no subagents.

Base `d8aa27e` (suite 6808) / Rascal Rally `fccf29d` (3449).
Evidence: `artifacts/release-candidate-review/perf/requalification.md` and
`artifacts/release-candidate-review/perf/capture-plan.md`.

---

## Per-item outcomes

**1. Lab refresh + verification — DONE.** `check_perf_place.py` PASS (rebuilt from
source; 17 required instances, 5 version markers, publish-safe). **The checked-in
`.rbxl` was three days stale** — 2,538,179 bytes built 08-18 against 2,721,018 on
rebuild — so any capture taken from it in that window was of a place that did not
match the repository. All **17** workloads select, mount, run every declared pass,
reset, and reproduce their seed digest headlessly; `dense-scroll-native` refuses to
mount by design (a host seam) and says so by name. The registry-vs-runner contract
spec is green. Each release wave the brief flagged was checked against the runtime
rather than assumed.

**2. Headless perf suite — PASS.** 20 scenes × 5 profiles, every budget and the
one-way frame ceiling held. **The Controls indirection is proved ≤ noise**: the hop
in isolation is +0.000004 ms, and namespace-vs-legacy across three runs is −0.04% /
+1.93% / +1.17% — it changes sign. Construction-only, never per frame. No
optimization.

**3. RR-5 / RR-12 — measured, then fixed only where measured.**
- RR-5's 25-site list was three consolidation waves stale. Re-derived two ways
  (static literal scan + a runtime instrument counting VALUE-equal recomputes) to
  **38 sites**; one of the original 25 was `core:memo(` quoted inside an error
  STRING and is not a memo.
- Arm B (value-eq everywhere) moves the adapter op log **by zero writes across all
  twenty scenes** — the renderer already diffs — so the cost had to be read at the
  SOLVE layer, where it is real.
- RR-12: measured first (per-flush allocation and time), then optimized because a
  scene showed it — the one-observer `notify` fast path.
- PLAT-20: OPEN and untouched. It is an Instance allocation; headless has no
  `Instance`, so no headless instrument can see it. Routed to the Studio rows.

**4. Counters current — DONE.** The lab had two separately written counter
literals that had drifted both ways: the renderer's structural counters were on the
live read and not the capture row, and the **haptics counters were in neither** —
readable on screen during a capture and absent from the artifact that capture
produced. One `liveCounters()` now serves both; haptics became a table (the overlay
string is derived from it), and the text-premeasure queue was added. Theme-swap
counters audited and already current. Held by a BY-SET comparison plus a
named-counter case; both mutations bite.

**5. Capture readiness — DONE, and it found a live defect.**
`tools/microprofiler_aggregate.py` filtered scopes on a hard-coded `Facet/`, and
**every dump this project owns predates the rename and carries `LuauUI/*`** — so
the default invocation printed an empty table for the entire corpus, which reads as
"the framework did no work". Fixed (both prefixes, the legacy one announced, an
explicit sentence when nothing matches) and given a `--selftest` that synthesises a
dump carrying one scope of each prefix; two mutations bite. Scope-label balance
re-verified (15 cases). **The guide had lost three workloads** — "the fourteen" vs
seventeen declared, the three missing being the NAMED LEVERS aimed at the top cost
in every device capture ever taken; corrected and mechanised in three directions,
three mutations bite. `capture-plan.md` written: 13 ordered rows with settings,
warm-up, window, expected counters, and the two rows this wave changed marked as
owing a re-capture.

**6. Evidence — DONE.** `perf/requalification.md` (8 sections, 6 concerns). RC-22
moves from bare PENDING to a run string covering the headless half only, ending in
the explicit sentence that the Studio and Android rows stay with the close-out. The
findings ledger's Perf-wave row moves QUEUED → the same honest split.

**7. Memory workstream — MEASURED; the one seam that pays is CONTESTED.** Table
below. The instrument for the Studio half shipped (module-load marks). The lazy
structure did not ship, for one reason stated in full in §7 of the artifact.

---

## The memory table — headline

Live Lua heap retained after `require`, one subset per process, 9 repeats, median.

| subset | KB | vs root |
|---|---|---|
| **`require(Facet)`** | **2 797** | — |
| root minus the 19 composite controls | 1 966 | **−831 KB (−29.7%)** ← whole saving |
| …+ `ProgressView` only | 1 998 | −799 (−28.6%) |
| …+ the three Rascal Rally builds | 2 247 | **−550 KB (−19.7%)** ← biggest realistic subset |
| …+ `Table` only | 2 291 | −506 (−18.1%) |

**Every other candidate the brief named is noise**, measured as a marginal on top of
that floor: `themes/package` 0 KB (already pulled transitively), the drag/gesture
family 13, `replication/adapters` 11, `controls/path_shapes` 7, `input/spatial`
inside the ±15 KB band, `sensory_profile` 23 standalone. `themes/snapshot` (299 KB)
cannot be deferred at all — `env/environment` requires it. `blueprint_schema`
(536 KB) is a hot path, which the brief's own rule excludes.

**Why it did not ship.** The mechanism is proved at runtime:
`type M = typeof(require("@self/controls/table"))` costs **0 KB and does not load
the module** while keeping `M.Spec` as a type, so all 19 typed signatures survive a
deferred require and only `src/init.luau` changes — **no locked or off-limits file
is involved**. But there is **no Luau analyzer anywhere in this toolchain and no
gate row typechecks**, so the change's entire justification ("the typed signatures
survive") is a claim no instrument here can falsify. Shipping that at
release-candidate stage is the class this repo refuses. One analyzer gate row
unblocks a one-file, 831 KB change, and `Facet.preload()` ships beside it.

---

## RR-5 disposition counts (38 sites)

| disposition | n |
|---|---|
| **FIXED, measured** | **4** |
| **CONTESTED — measured real, blocked by a source-cap lock** | **2** |
| NOISE — exercised, moved no scene | 18 |
| UNMEASURED — no scene or workload reaches them | 14 |
| NOT A SITE (`core:memo(` inside an error string) | 1 |

- Fixed: `virtual_window.luau` `canvasDim`; `virtual_grid.luau` `canvasDim`,
  `extentDim`, `virtualSlot`. Eq is `rect.sameFlatValue`, the framework's existing
  flat-record equality (already the renderer's `sameGeometryValue` and the selection
  indicator's `sameGeometry`). Both fixes red-first via churn-counter specs.
- Contested: `virtual_list.luau:3234` (`rowExtentDim`; moves `variable-extents`
  246→223 solves — the file is 7,813 chars from the write cap and its ledger row
  says the hosted-block extraction must PRECEDE the next change of any size) and
  `table.luau:1968` (`canvasHeight`; moves `table-unified` 38→28 — `table.luau` was
  OFF-LIMITS to this wave and its own trigger has fired). Both are the same
  construct as the two that were fixed and each is one argument long.

**Measured effect of what shipped:** `lab-collection-churn` 41 solves → 1 over 40
churn iterations, all 40 producing zero rect and zero prop writes; lab
`variable-extents` 294→246, `edit-locality` 131→83 (partial 53→29),
`collection-churn` 30→25; VirtualGrid 57 measure-dirties → 0 on a no-op off-window
edit. Scene p95 `lab-collection-churn` 1.50 ms → 0.14 ms.

**RR-12 effect:** `animation-interruption` 0.347→0.106 ms (−69%),
`collection-mutation` 1.214→0.864 (−29%), `hud-binding-storm` 0.220→0.206 (−6%),
five interleaved samples a side.

---

## Commits (framework `main`, not pushed)

| sha | subject |
|---|---|
| `1bde05e` | the review said twenty-five memos re-dirty the tree; four of them actually do |
| `3256ce8` | the flush's biggest allocation was a sorted list of one |
| `fc83c3c` | the counter you could read on screen was the one the capture did not carry |
| `205de01` | three marks, and only the bootstrap can take the first one |
| `29dc917` | the summary tool read every device capture we own as an empty table |
| `b9c7c8b` | the numbers, and the five instruments that produced them |

Rascal Rally: **no commit, by design.** This is a compatible internal change; the
consumer suite is green at 3449 against the changed Facet source and the standing
`facet_public_surface_currency` contract is green. Measured on the SHIPPED sponsor
racer list (24 rows, six 250 ms republishes, the production `Controls.VirtualList`
path): the solve count is +7 with and without the RR-5 fix — that list's every-tick
republish carries real content changes, so the fix is behaviour-neutral there
rather than a win, and a game-side test asserting "no change" would have been a
check that proves nothing.

---

## Tails

```
./run-tests.sh                                 6821 passed      (base 6808; +13 new cases)
RascalRally ./run-tests.sh                     3449 passed      (unchanged)
tools/perf.sh          perf: PASS (100 runs, 20 scenes) [artifacts/phase-4/perf.json]
check_perf_place       PASS — 17 required instances, 5 version markers, publish-safe
check_perf_scenes      7 production scenes alive at floorAndroid
check_perf_metrics     100 headless records carry all 7 metric rows; 0 device rows
check_perf_budgets     20 scene budgets; 3 device budgets declared and unmeasured
check_perf_captures    PASS — 18 rows admissible, classes={'studio': 18}, 0 device rows
check_perf_gate_evidence scopes/headless-linkage/falsifiable/perf-gate/budgets — all PASS
profile_scopes spec    15 passed (balance on every exit path)
microprofiler_aggregate --selftest  PASS — container, header, 3 records, 1 layout record, both prefixes
public surface         BYTE-IDENTICAL to artifacts/release-candidate-review/public-surface.txt
check_boundary         PASS (155 src files, 413 consumer files)
check_registration     PASS (38 controls, 99 exports, 255 specs)
check_source_size      PASS — 6 modules in the band, all with ledger rows
```

---

## Concerns

1. **A whole control family is outside the measurement surface.** No bench scene
   and no lab workload mounts a `VirtualGrid` or a `RowActions` tray. That is
   exactly why four real RR-5 sites in `virtual_grid.luau` measured zero — nothing
   ran them — and why the grid fix had to be proved by a spec instead of a scene.
   The row-actions half is still unmeasured.
2. **Two measured RR-5 sites are blocked by source-cap locks**, and they are the
   same one-argument construct as the two that shipped. `virtual_list.luau` owes its
   hosted-block extraction; `table.luau` was off-limits.
3. **The public type surface has no mechanical guard at all** — no analyzer, no
   gate row. It blocked an 831 KB memory win here and will block the next claim
   that rests on a type.
4. **The built place carries no comparable build stamp.** It was three days stale
   and only a rebuild revealed it. `Facet_SourceStamp` is already READ by the
   capture facts; nothing WRITES it at build time.
5. **No MicroProfiler dump is in the repository.** `--selftest` closes the decoder
   half; "does a real client still emit this shape" can only be answered by a real
   dump, and every one lives outside the tree. `.gitignore`'s existing
   irreproducible-evidence exception would cover one.
6. **`screen-lifecycle-churn` is not a usable trend signal on this host** — it swung
   1.23→3.57 ms across provably identical arms. A first, non-interleaved reading of
   it looked like a clean +1.3 ms regression from the RR-5 fix and was noise.
7. **Another agent was working in this tree concurrently.** All six commits went
   through `tools/commit_isolated.py` with named paths; each commit's file list was
   verified afterwards and none carries the other agent's work. I stopped using
   `git stash` for A/B arms after one shared-index run hung, and used file copies
   instead.
