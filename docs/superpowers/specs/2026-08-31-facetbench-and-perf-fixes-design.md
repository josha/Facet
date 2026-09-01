# FacetBench + Three Facet Performance Fixes — Design

- **Date:** 2026-08-31
- **Status:** Approved in brainstorming; awaiting spec review
- **Owner ruling:** Comparison system is **public-facing** and **contributable** — outsiders can add frameworks and workloads, and we mine all results to optimize Facet.

## Goals

1. Build **FacetBench**: a public, contributable benchmark arena comparing Facet against Vide, Fusion, Blend, React-lua, and Flux under realistic game workloads (headless + live Studio).
2. Land three Facet performance fixes, each proven by a **demonstrator test** that fails before the fix (exposing the waste) and passes after:
   - F1: layout solver starts a global solve on every update;
   - F2: per-node reactive scope/allocation cost at every mount;
   - F3: keyed-collection (ForEach) reconciliation churn.
3. Every fix ships with before/after FacetBench numbers, a green Facet suite, RascalRally lockstep evidence, and a live Studio canary.

## Non-goals

- No Facet public-API changes. All three fixes are internal.
- No product/behavior changes to RascalRally.
- FacetBench does not judge developer ergonomics, only performance.
- No framework is benchmarked on workloads it cannot express (capability flags, not shims).

---

## Part 1 — FacetBench (the arena)

### Location and repo

`GameStudio/ui/FacetBench/` — a **sibling of Facet, outside Facet's repo**, initialized as its own git repository (public-ready). This keeps vendored rival frameworks outside Facet's DR-7 `check_no_fusion.py` scan roots (`src/ examples/ skills/ tests/ bench/ package/`) and outside `check_library_purity.py`. Facet's gates are untouched.

### Layout

```
FacetBench/
  frameworks/
    facet/        adapter.luau            (requires ../Facet/src; never vendored)
    vide/         vendor/ (v0.4.1, MIT)   + adapter.luau
    fusion/       vendor/ (v0.3-beta, MIT)+ adapter.luau
    blend/        vendor/ (Quenty 12.48.0 + Rx/Maid/Brio deps, MIT) + adapter.luau
    react/        vendor/ (jsdotlua 17.2.1, MIT) + adapter.luau
    flux/         vendor/ (tarekmahmouduix/Flux, styling layer) + adapter.luau
    _fixture/     toy framework with KNOWN cost — validates the runner itself
  workloads/
    battle_hud.luau
    war_room_inventory.luau
    killfeed_nameplates.luau
  runner/
    lune/         headless runner (fresh process per framework), schema, stats
    studio/       live runner ModuleScript + MCP drive scripts + rojo project
  results/        committed run artifacts (JSON) + generated chart page
  tools/          report/chart generation, schema check, adapter conformance check
  CONTRIBUTING.md README.md LICENSE (MIT) + per-vendor LICENSE files preserved
```

### Workload contract (framework-neutral)

A workload is **data plus a deterministic script**, written once, with no framework imports:

```luau
return {
  name = "battle_hud",
  requires = { "reactive" },              -- capability keys an adapter must declare
  sizes = { S = ..., M = ..., L = ... },  -- e.g. unit counts 100 / 400 / 1000
  build = function(size, rng) -> SceneSpec,  -- neutral tree: node kinds, props, lists
  script = function(size, rng) -> { Step }, -- seeded update steps: setState/addItem/
                                            -- removeItem/reorder/noop, with payloads
}
```

`SceneSpec` node kinds are a small closed set (`panel`, `label`, `image`, `bar`, `list`, ...) with neutral props. Steps are replayed identically for every framework. `rng` is a seeded PRNG owned by the runner; a workload never reads the clock or global state.

**Launch workloads**

1. **battle_hud** — isometric battle: N units × (health bar, 0–3 status icons, facing tag), floating damage numbers spawning/expiring every step, minimap blips, 4 squad panels. Stress: many small reactive updates per frame. Sizes 100/400/1000 units.
2. **war_room_inventory** — N items with icon/name/stats/rarity; script interleaves sort toggles, filter text narrowing, equip swaps, and loot inserts. Stress: keyed-list diffing. Sizes 150/500/1500 items.
3. **killfeed_nameplates** — a rolling kill feed (rows enter, expire) plus nameplates attaching/detaching as units spawn and die. Stress: mount/unmount churn. Sizes 50/200/600 concurrent elements.

### Adapter contract (per framework, idiomatic)

```luau
return {
  name = "vide", version = "0.4.1", license = "MIT",
  capabilities = { reactive = true, keyedList = true, headless = true, styling = true },
  mount   = function(sceneSpec, target) -> AdapterHandle,  -- target = Instance or nil (headless)
  applyStep = function(handle, step),   -- translate one neutral step into idiomatic updates
  unmount = function(handle),
}
```

- Each adapter translates the neutral spec into **that framework's idiomatic code** (Vide `indexes/values`, Fusion `ForPairs`, Blend `ObservableList`+Brio, React keys, Facet `ForEach`). Fairness is enforced socially, not mechanically: adapters are small, reviewable, and contributors may optimize their own framework's adapter — that is the point.
- A missing capability means the pair (framework, workload) is reported `"unsupported"`, never an error. Flux (a utility-styling layer, not a reactive framework) declares only `styling`, so it participates in mount-and-style measurements only.
- `tools/check_adapters.luau` runs a conformance suite: contract shape, determinism (two runs of the fixture spec produce identical trees), clean unmount (no leaked instances/connections).

### Runners and measurement

**Lune (headless, the everyday number).** One **fresh Lune process per (framework, workload, size)** so no framework inherits another's heap or GC state; at most **3 concurrent processes** (known trap: >3 lune runs die silently). Warmup then sampled measurement (reuse Facet bench constants as starting point: warmup 50, samples ≥ 1500 for stable p95). Metrics per pair: mount ms, per-step wall p50/p95/p99, unmount ms, heap net (`gcinfo` delta), collector swing. A CPU-yardstick scenario normalizes across machines (same technique as Facet's bench). Frameworks whose renderer needs real Instances headlessly use their documented headless path (Vide `lib.luau`, React noop renderer); a framework with no headless path (risk: Blend) reports `"live-only"` headlessly and is measured in Studio only.

**Studio (live, the truth number).** A runner ModuleScript executes the same (framework, workload, size) matrix against real Instances in a place, driven via Studio MCP; a rojo project serves FacetBench into the open blank place. Metrics: frame-time p50/p95 over the scripted run, GuiObject count, client memory, plus **microprofiler captures** for the public writeup. Standing traps honored: probe a commit marker in the served source before trusting any reading (stale-rojo trap), and publish-before-TestTrack rules from studio verification lessons.

**Results schema.** One JSON shape for both modes:

```json
{ "run": { "stamp": "...", "mode": "lune|studio", "host": "...", "device": "...", "seed": 1 },
  "rows": [ { "framework": "vide", "version": "0.4.1", "workload": "battle_hud",
              "size": "M", "status": "ok|unsupported|live-only|error",
              "metrics": { "mountMs": ..., "stepP50Ms": ..., "stepP95Ms": ...,
                           "stepP99Ms": ..., "unmountMs": ..., "heapNetKb": ...,
                           "gcSwingKb": ..., "frameP50Ms": ..., "frameP95Ms": ... } } ] }
```

`tools/report.luau` renders committed results into a chart page (single HTML file, no external deps). `tools/check_schema.luau` validates every committed artifact.

**Runner self-test.** `frameworks/_fixture/` is a toy framework whose per-step cost is constructed and known (e.g. a busy-loop calibrated against the yardstick). CI asserts the runner reproduces the fixture's expected ratios within tolerance. If the fixture drifts, the runner is broken — numbers from real frameworks are not trusted until it passes.

### Contribution model

`CONTRIBUTING.md` documents: adding a framework (= one folder: vendor + adapter + capabilities + license), adding a workload (= one neutral file, no framework imports), running the matrix, and submitting results (results PRs must include the schema-check and fixture-check outputs). The kohltastrophe/luau-reactivity-benchmark adapter-per-library pattern is prior art; FacetBench extends the idea from signal cores to full UI workloads.

---

## Part 2 — The three Facet fixes

Order: **arena first, baselines recorded, then fixes** — every fix gets a public before/after. Each fix is its own mission: demonstrator red → fix → demonstrator green, landed together so CI never holds a red test.

### F1 — Layout: clean frames must not solve

- **Today:** `render/renderer.luau:1675–1694` runs one root-level `solver.solve` per render cycle (`renderer.luau:1963`); incremental machinery skips clean subtrees *inside* the walk, but the walk always starts.
- **Fix:** (a) a frame with **zero dirty nodes and unchanged viewport/solve inputs performs no solve at all** — renderer reuses `lastResult`; (b) when dirt is contained, re-solve from the **nearest enclosing boundary whose offer/rect provably cannot change** (reusing the existing boundary analysis at `renderer.luau:3917`), not from the root.
- **Demonstrator D1** (`tests/` spec): mount a representative tree, render, change nothing, render again; assert via `controller.diagnostics()` that solve count for the clean frame is **0** and `work.arranged == 0`. Red today (a root solve starts every frame).
- **Risk note:** the solver memo needs a differential oracle (standing lesson); D1 pairs with an invariant spec asserting pixel-identical rects vs a forced full solve across the device matrix, including 320x640.

### F2 — Mount: per-node allocation cost

- **Today:** every node allocates `node.dirty = {}` at `mount.luau:622`; every reactive prop allocates observer callback closures (`mount.luau:254–683`); When/ForEach/ErrorBoundary each allocate child scopes + cleanup functions.
- **Fix:** (a) **lazy dirty state** — plain static nodes allocate no dirty table until first invalidation; (b) **shared observer dispatcher** — per-node observation routes through one dispatcher keyed by node, replacing per-prop closures; (c) audit `scope_impl.luau` child-scope creation so When/ForEach regions reuse a pooled cleanup shape. No public API change; disposal order and idempotency semantics preserved exactly (reverse-order disposal per `scope_impl.luau:104–129`).
- **Demonstrator D2:** mount N=500 static nodes and N=500 one-reactive-prop nodes; assert allocation budget per node (closure/table counts via instrumented counters, heap delta via gcinfo with GC quiesced) under thresholds set to post-fix design targets. Red today.

### F3 — ForEach: no-change updates must be near-free

- **Today:** `mount.luau:273–515` rebuilds the full `wanted` key map and `order` array on **every** update — `bp.props.key(item)` + `tostring` per item — even when the items are unchanged.
- **Fix:** (a) **identity/version fast path** — unchanged items input (same array identity or unchanged version stamp) skips reconciliation entirely; (b) **key string cache** — per-item key computed once while the item is identical (invalidated on item replacement); (c) diff touches only changed entries; pure moves keep their no-remount guarantee (`mount.luau:419`), retire/re-entry semantics (`mount.luau:359–369`) preserved.
- **Demonstrator D3:** mount ForEach with 500 items; apply a no-op update (identical items) then a single-append; assert `key()` call count is 0 for the no-op and ≤ small constant for the append, and that no itemScope is created/disposed for untouched rows. Red today (500 key() calls per update).

### Guardrails (all three fixes)

1. Full Facet suite green (`tools/test.sh`, then `tools/verify.sh` at the right gate level).
2. FacetBench before/after on all three workloads: target improvement on the fix's stressor, **no regression** elsewhere (existing bench regression factor 1.5 honored).
3. **RascalRally lockstep** (constitution): inspect affected callers, update/extend a game-side contract or integration test, run both projects' relevant tests, live Studio canary of an affected screen.
4. RED-TEAM (adversarial code review) at the end of the fix series.
5. Behavior invariants: layout results pixel-identical (F1), disposal semantics identical (F2), reconciliation semantics identical incl. retire/re-entry and duplicate-key errors (F3).

---

## Sequencing

| Phase | Deliverable | Gate |
|---|---|---|
| 1 | FacetBench skeleton: contracts, lune runner, fixture framework, Facet adapter, battle_hud headless | fixture self-test + Facet rows produced |
| 2 | Rival adapters (vide, fusion, react, blend, flux) — parallel subagent per framework | conformance suite green; unsupported/live-only rows honest |
| 3 | Remaining workloads + Studio runner + microprofiler capture path | full matrix runs both modes in blank place |
| 4 | **Baselines committed** + chart page + demonstrators D1–D3 written and shown red | baseline results.json in repo |
| 5 | F1, F2, F3 — one mission each, in that order | each: demonstrator green, suite green, bench no-regression, RR lockstep |
| 6 | Public polish: README, CONTRIBUTING, methodology writeup, updated charts | RED-TEAM pass; publishable |

**Model routing:** sonnet/opus subagents implement (one per framework adapter in phase 2; one per fix in phase 5, sequential); Fable orchestrates, reviews evidence, and runs Studio/MCP steps. Explore/research on haiku/sonnet.

## Risks

- **Blend headless**: Rx/Brio core is plain Luau but UI construction likely requires Instances → may be Studio-only. Accepted; reported honestly as `live-only`.
- **React-lua staleness** (17.2.1, ~2 yrs): benchmarked as-is; noted in methodology.
- **Fusion 0.3 headless not documented**: smoke-test before relying on it; fall back to live-only.
- **CloudStorage + rojo stale-serve**: every Studio reading gated on a commit-marker probe.
- **Lune concurrency**: hard cap 3 concurrent processes in the runner.
- **Public fairness disputes**: mitigated by tiny reviewable adapters, seeded determinism, fixture self-test, per-framework version pinning, and accepting adapter PRs from each community.

## Success criteria

1. One command runs the full headless matrix and writes schema-valid results; one MCP-driven flow does the same live.
2. D1–D3 demonstrably red at baseline (committed evidence), green after fixes.
3. Facet improves on its three stressor workloads with zero suite/bench/RR regressions.
4. A stranger can add a framework or workload from CONTRIBUTING.md alone.

## Addendum (2026-09-01, owner ruling): frame-cost target and scope extension

1. **Target:** steady-state per-step cost (frames-mode step p50 in the Studio matrix, and its Lune proxy) on stress workloads (battle_hud at EVERY size S/M/L, war_room_inventory, killfeed_nameplates) must land **well below 1 ms — stretch goal 0.5 ms**. Structurally this means per-step cost proportional to touched work, never to scene size.
2. **Scope extension:** fixes beyond F1–F3 discovered by profiling are IN SCOPE for Part 2. Each discovered fix follows the same discipline (red-first demonstrator or measured before/after, suite green, RR lockstep, no bench regression elsewhere).
3. **Honesty rule:** the target is aspirational; if after the campaign the number lands above it, the shipped result states the achieved figure and names the remaining bottleneck with evidence — the target is never met by weakening the workload or the instrument.
4. **Correction (D2):** "heap delta via gcinfo with GC quiesced" is not achievable under Lune (collectgarbage is count-only); D2 uses allocation counters/heap deltas without forced collection.

## Addendum 2 (2026-09-01): Part 2 revised by profiling evidence

The attribution campaign (FacetBench artifacts/profile/PROFILE_REPORT.md, 2026-09-01) supersedes Part 2's original F1–F3 hypothesis set:
- Original D1 (clean-frame solve) and D3 (ForEach no-op churn) are REFUTED at current HEAD: a zero-dirt refresh costs 0.000–0.002 ms and is O(1); `key()` is invoked 0 times on updateItem/setState/noop. No demonstrators or fixes ship for them.
- Original D2's cost is real but lives in steady-state per-step churn (3.4 KB per mounted node per step, flat across sizes), addressed by the revised fixes below rather than a mount-time fix.
- Revised fix set (each with a red-first counter-based demonstrator): **P1** cross-solve measure cache (solver measure pass has no reuse arm; a reuse solve still measures N, a 1-leaf-dirty solve measures 2N); **P2** copy-on-write rect map (replaySubtree re-inserts every skipped node into a fresh out-map — the superlinear term); **P3** cache the solver Node tree across solves (rebuilt every solve incl. one closure per node and theme-token re-resolution); **P4** drive the commit from the changed-rect set (six full-tree walks + N-entry loops to make ~4 writes); **P5** structural changes get boundary-rooted partial solves (only after P1+P2).
- Target restated per step class at size L (Lune proxy, Studio confirm): update/setState/noop ≤0.5 ms after P1–P4; add/remove/reorder ≤1 ms after P5, except list-shift writes which are irreducibly O(shifted) and are reported as such.
