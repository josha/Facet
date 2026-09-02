# Facet Wicked Fast — game-UI stress workloads + the all-dirty campaign — Design

Goal text: `docs/plans/2026-09-02-facet-wicked-fast-goal.md` (method + traps in
`docs/plans/2026-09-02-facet-wicked-fast-reference.md`). Previous campaign closed at Facet
`4d9e3aac` / FacetBench `f38add27`; its after-picture is the **"before"** of this one
(`FacetBench/docs/studio-runs/2026-09-02-after-campaign.md`). Charter with the booked levers:
`docs/superpowers/plans/2026-08-31-facetbench-plan2-3-notes.md`.

Operating assumption stated up front (goal §operating rules): the owner is not watching, so
this spec is not gated on an approval reply; every step below is reversible (own commits via
`tools/commit_isolated.py`, no force-push, no public API change without the owner).

## Goals

1. **Measure the class Facet has never been measured on**: 50–250 world-anchored nameplates whose
   screen position changes every frame ("all-dirty"), plus a per-frame structural-churn layer
   (floating damage numbers). facet vs vide (the speed target) in Lune (facet + `_fixture`) and
   Studio loop + frames (all six frameworks), honestly.
2. **Make Facet materially faster on that class** with the profile choosing the mechanism, and
   attack the last O(N) walks: an empty solve still costs 0.969 ms at L (`memoPlan` rebuilt per
   solve = 0.959 ms of it), `structuralSync` walks the whole tree on every structural step, the
   commit's sibling scan is O(siblings) per dirty node.
3. **Fix the booked user-visible warm-up bug**: `propSigCache` recycles instances wearing style
   props they never declared (RED-TEAM finding 3, HIGH).

## Non-goals

- No public API or behavior change (a zero-diff in `controller.stats().rectWrites` per step and
  an identical live GuiObject census are the mechanical proof, exactly as last campaign).
- No shim in a rival adapter. A rival that cannot express a positioned layer idiomatically
  declares the capability missing and the row reads "unsupported".
- No wall-time assertions in any spec (Luau VM is bimodal; counters only).
- L7 list-shift windowing (a product decision) stays booked. L6 (the engine's own layout cost)
  is measured and reported, not attacked, unless a Facet-side tree change falls out of O3.

---

## Part 1 — Arena extension (FacetBench)

### 1.1 Scene DSL: a position primitive

The DSL has stacks (`panel` + `direction`) and nothing that places a child at an (x, y). Three
additions, all framework-neutral:

**`canvas` node kind.** A container whose direct children are free-positioned. Same shape as
`panel` minus `direction`, plus optional numeric `width`/`height` props (px). Children may be
any kind incl. `list`.

**`x` / `y` props** (px from the canvas's top-left, integers). Legal ONLY on a direct child of
a `canvas`, or on the `template` root of a `list` whose parent is a `canvas`. Values are the
usual `PropValue` (literal, `{ref}` state, `{item}` field). `scene.validate` rejects `x`/`y`
anywhere else and rejects a `canvas` child that lacks both (a child with no position is a stack
author's mistake, not a canvas idiom).

**`updateItems` step** — one frame of moves in one step:
```
{ kind = "updateItems", listState = "plates", updates = { { key = "p1", fields = { x = 412, y = 96 } }, … } }
```
Semantics = the listed `updateItem`s applied together, then ONE reconciliation. Every key must
be live (validated by the two-pass simulation, same as `updateItem`). Adapter contract: apply
every field write, then reconcile once per step the way the framework does it — facet: N signal
sets + one `controller.refresh()`; vide/fusion/blend: N synchronous source writes (that IS their
idiom; no fake batching); react: one `setState` carrying the merged item table; `_fixture`:
burns its cost model once per touched field.

**Capability `positioned`.** Declared by facet, vide, fusion, react, blend, `_fixture`. flux
already lacks `reactive`/`keyedList` and stays unsupported by the existing mechanism.

### 1.2 Adapter mapping (idiomatic, per framework)

| framework | `canvas` | positioned child |
|---|---|---|
| facet | `UI.Anchor{ width?, height? }` (`docs/reference/api.md` "Anchor") | `anchor = "topLeft"`, `offsetX`/`offsetY` = resolved scalar; item-bound → the per-item signal the adapter already keeps in `ctx.itemSignals` |
| vide | `Frame` (no `UIListLayout`), `Size = UDim2.fromOffset(w,h)` when given | `Position = function() return UDim2.fromOffset(x(), y()) end` — a bound prop function, vide's own reactive spelling |
| fusion | `New "Frame"` | `Position = Computed(function(use) return UDim2.fromOffset(use(x), use(y)) end)` |
| react | `createElement("Frame")` | `Position = UDim2.fromOffset(x, y)` from props; a move re-renders the item element |
| blend | `Blend.New "Frame"` | `Position = Blend.Computed(x, y, fromOffset)` |
| _fixture | container burn | per-node burn; `updateItems` burns per touched field |

The `SNAP_PROPS`/behavioral-bite snapshot gains `x`/`y` so a do-nothing adapter still bites.

### 1.3 `nameplates` workload (the flagship, all-dirty class)

- `requires = { "reactive", "keyedList", "positioned" }`, sizes **S=50, M=120, L=250** plates.
- Scene: root `canvas` 1280×720 → `list "plates"` whose template is
  `panel(vertical){ panel(horizontal){ label name, label level }, bar hp, bar cast }` — 6 nodes
  per plate (L ≈ 1,500 nodes + root). `x`/`y`/`hp`/`cast`/`level`/`name` are item fields.
- Model: plates sit at seeded world points on a 200×200 plane at unit heights; a pinhole camera
  at fixed height orbits (yaw += 0.02 rad/tick) and bobs (pitch sine). Projection per tick →
  `x,y = floor(...)` clamped to the canvas (a plate behind the camera is clamped to the edge, not
  removed — removal is the range-churn's job, not the projector's). Every plate moves every tick.
- Script, 600 steps = 30 blocks × 20 slots. Per block: **14 `tick`** (`updateItems` x,y for ALL
  live plates + cast width for the ~20 % of plates flagged as casters), 2 `updateItem` hp (wave
  on a seeded plate), 1 threat flip (`updateItem` level text `"60"` ↔ `"!! 60"` — a paint-only
  role flip has no DSL spelling, and a text change is the harder, honest choice), 2 range churn
  (killfeed's stash-and-re-add discipline: live count stays within `[floor, total]`, the stash is
  returned by script end so the array is cycle-safe over two passes), 1 `noop`.
- With 70 % of slots being `tick`, the matrix `stepP50Ms` IS the all-dirty number; the profile
  harnesses (`tools/profile/attr`, extended for `updateItems`) give the per-class split.
- `tests/nameplates.spec.luau`: determinism (same seed → same script), `scene.validate` +
  `validateSteps` pass, pinned counts per size (steps 600, tick 420, churn 60, live-plate floor
  and cap), every `tick` touches every live plate, projection stays inside the canvas, and the
  two-pass cycle invariant. Registered in `workloads/registry.luau` and `tests/run.luau`.

### 1.4 `damage_fountain` workload (per-frame structural churn in a positioned layer)

The class nameplates cannot see: add/remove EVERY frame in a free-position layer, where a stack
would charge O(shifted) but an anchor should charge O(1) — isolates L4 (`structuralSync` whole-tree
walks) from the list-shift floor.

- `requires` as above; sizes **S=30, M=80, L=200** live numbers (lifetime 40 steps, 3 spawns per
  spawn slot ⇒ steady state ≈ size). Template: `label` (1 node, `text`,`x`,`y`).
- Script 600 steps, repeating 3-slot triplet: `addItem` ×k (fresh keys at seeded x,y), `updateItems`
  (every live number `y -= 4`, "rise"), `removeItem` ×k oldest. Steps stay single-kind so the
  per-class cost is legible; frames-mode in Studio gives the combined per-frame bill. FIFO drained
  to empty by step 600 (battle_hud's discipline) so cycling is safe.
- Spec mirrors 1.3's shape (determinism, validation, pinned counts, drain-to-empty).

### 1.5 Runners, results, chart

- Lune matrix: `lune run runner/lune/run_matrix --workloads nameplates,damage_fountain` for facet +
  `_fixture` (rivals are live-only). ABBA pairs against the campaign-before checkout for the Facet
  rows (A/B/A/B, 750 samples, drift gate ≤10 %).
- Studio: `runner/studio/DRIVING.md` unchanged (marker, rojo build, `FireAllClients`, scrape).
  Loop + frames at S/M/L for all six.
- `tools/check.sh` green (stylua, `tests/run`, `check_adapters`, `check_runner`, `check_schema`,
  `check_baselines`, `check_bare_loops`, rojo build). Results envelopes committed under `results/`
  with the campaign-before envelopes kept; `results/chart.html` regenerated via `lune run tools/chart`.
- `tools/profile/attr` + `probe` learn `updateItems` and the `canvas` kind (L8: a moved seam
  re-runs its harnesses, not assumes them).

---

## Part 2 — Facet fixes

**Profile first.** Step 0 of Part 2 is the attribution of a nameplates `tick` at L and a
`damage_fountain` `addItem`/`removeItem` at L (`docs/profiling/2026-09-02-nameplates-attribution.md`
in FacetBench). The order below is the *expected* order from the campaign's numbers; the profile
re-ranks it, and a lever the profile says is <5 % of the step is dropped, not built.

Candidates (each states the mechanism, its red counter, and its oracle):

**O1 — `memoPlan` becomes a cross-solve store.** `measure_facts.luau:409` rebuilds a per-solve
plan memo (`ctx.memoPlans`, `solver.luau:3722`) for every node — the 0.959 ms "measure nothing"
floor. A plan is a pure function of the node's size inputs, kind and children; hold it on the
P3 node-store entry, invalidated where `layout_node.build` rebuilds the node (a rebuilt node is a
new table, so a table-keyed store self-invalidates — VERIFY this in the demonstrator, do not
assume it). Red counter: a new `work.planBuilds` that reads N on a 0-dirty solve and must read 0.
Oracle: rects + measured sizes byte-equal to a forced full solve across the device matrix.

**O2 — split `dirtyContains` into measure/arrange halves.** The closure builder
(`renderer.luau:2877-2893`) adds every prefix for both classes so an arrange-only change
(offsetX/offsetY — the whole nameplates class) re-measures its ancestors and re-enters arrange at
the root (L2: 1.000 ms to arrange three nodes). Adopt gate (`solver.luau:1801`) reads the measure
half; the arrange skip's third arm re-derives from `prev.offerW/offerH`. Red counter:
`work.measured` on an offset-only step must be 0 and `work.arranged` must be O(dirty), not O(N).
Oracle as O1. Prop-dirt audit (`tests/layout_prop_dirt.spec.luau`) extended so a prop that
touches measure can never be classified arrange-only by the split.

**O3 — moved-not-resized translate.** An Anchor child whose offer and measured size are unchanged
and only its (x, y) moved: translate its subtree's rects (rect map is COW — P2 — so this is a
delta write per descendant, no re-entry), and let `rect_pass` write only the moved descendants.
Red counter: `work.arranged` for a plate move = plate root only; `rectWrites` = subtree size
(unchanged — the writes are real). Oracle as above.

**O4 — commit walks under a translate.** Of the eight commit walks, the ones that depend only on
size/visibility/text (textScale, padding, textVerdicts, visible) must not visit a translated
subtree; hitRects and scrollRegions must. Red counter: `lastCommitVisits` on a tick bounded by
(plates × hit-bearing nodes), not nodes.

**O5 — L3 dirty-child index** on the list node so the commit's sibling scan (`probeEntry`,
`commit_walks.luau:351`) is O(dirty children), not O(siblings).

**O6 — L4 `structuralSync` incremental** (`ssLivePaths`/`ssZOrder`, `renderer.luau:2388/2409`):
maintain per-parent, update from the structural delta instead of re-walking the tree. This is
the `damage_fountain` lever. Red counter: a new `work.ssVisited` reading O(delta).

**W1 — `propSigCache` warm-up fix.** `renderer.luau:885-903` keys the signature on the props
table with strong keys and `mount.luau:637` mutates `node.props[k]` in place, so a nil↔non-nil
key-set change is never seen and a recycled instance keeps a style prop it never declared.
Fix: the signature is recomputed when the key SET changes (a cheap key-count + presence check on
the write path, or invalidation at the mutation site — the demonstrator decides which is
cheaper). Red: a spec that mounts A with `shadow`, recycles into B without, and asserts B's
instance carries no `UIShadow`; plus the RED-TEAM repro reconstructed from the report's
description (the report is not on disk).

### Per-fix discipline (every one, no exceptions)

1. Solver headroom is 861 chars: **extract a live seam first** — `chosenCandidate`
   (`solver.luau:814`) goes first, then whatever the fix needs; the source-cap ledger row updated
   with a trigger that is actually in the file.
2. Red-first counter demonstrator (extend `work.*` / `stats()`; never wall-time).
3. Differential oracle vs a forced full solve across the device matrix incl. 320×640.
4. Prop→dirty-class audit extended when a class boundary moves.
5. Gates: `tools/test.sh` full; `tools/verify.sh affected --jobs 1` FOREGROUND;
   `python3 tools/check_source_size.py`; `stylua --check src tests tools bench examples`.
6. RascalRally lockstep: a game-side contract/integration test named for the fix (`games/RascalRally/
   code/tests/facet_*.spec.luau`), `games/RascalRally/code/run-tests.sh` green.
7. Fresh-context adversarial review (subagent, the fix's diff + demonstrator), findings fixed
   before the commit. Commits via `tools/commit_isolated.py`.
8. FacetBench ABBA re-measure after each landed fix; the number goes in the running ledger.

### Closing

RED-TEAM (code-reviewer agent) over the whole diff; RascalRally milestone Studio canary (marker
discipline; 60 fps sustained, quarantine nil); Lune + Studio matrices re-driven; before/after doc
`FacetBench/docs/studio-runs/2026-09-02-wicked-fast.md` with per-class numbers vs targets
(≤0.5 ms update / ≤1 ms structural at L) — a miss stated with its bottleneck and next lever;
`results/chart.html` regenerated; charter notes updated; memory + `tasks/lessons.md` on any
correction.

## Risks

- **O2/O3 correctness**: an arrange-only change that secretly feeds measure (fractional offsets
  resolve against the anchor's inner extent; a child that overflows may change the anchor's
  content size). The prop-dirt audit + oracle at 320×640 are the defence; an overflow-sized anchor
  is a required oracle fixture.
- **O1 memo identity**: if `layout_node.build` reuses the node table for a rebuilt node, a
  table-keyed plan store serves a stale plan. The demonstrator must include a "child added under
  a reused node" case.
- **Source cap**: every solver-side lever costs chars; extraction before feature is mandatory.
- **Measurement**: CrashPlan/background load; only ABBA pairs count; `_fixture` must read 1.00x.

## Success criteria

- `nameplates` + `damage_fountain` rows for all six frameworks in Studio (loop + frames, S/M/L),
  facet + `_fixture` in Lune; 0 errors; `_fixture` 1.00x ± drift.
- Facet `tick` at L materially faster than the before-arm; per-class numbers stated against the
  targets, honestly.
- Full gate green in both repos; RR suite green + clean canary; no public API change.
- W1 fixed with a red-then-green spec.
