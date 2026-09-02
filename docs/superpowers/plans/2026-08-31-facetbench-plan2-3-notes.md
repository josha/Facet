# FacetBench — Plan 2 complete; Plan 3 perf campaign complete (updated 2026-09-02)

## ✅ Plan 3 perf campaign CLOSED at Facet `8a82e3d5` (from `4b460f0c`, 16 commits)

P1 cross-solve measure reuse arm, P2 copy-on-write rect map, P3 cross-solve node store, P4 commit
driven from the changed set, P5 boundary-rooted structural solves. Judged at FacetBench `dc9d39e`;
full receipts in **`GameStudio/ui/FacetBench/docs/studio-runs/2026-09-02-after-campaign.md`**
(envelopes `results/lune-2026-09-02-{4b460f0c-before,8a82e3d5-after}.json` and
`results/studio-2026-09-02-1cc47a2-after.json`).

**Result.** ABBA-paired headless Lune (A/B/A/B, 750 samples/round, pooled): **8.9–16.1x faster at
every workload and size** — `battle_hud` L 42.667 → 2.644 ms, `war_room` L 51.519 → 3.872,
`killfeed` L 8.289 → 3.206. Live: `battle_hud` L frames **51.31 → 16.59 ms/frame** (~19 fps → a
solid 60) on an identical 4,150-GuiObject census. Allocation 3.4 → 0.22 KB per mounted node per
step; p95/p50 GC tail 3.1x → 1.5x. `_fixture` (the harness's own cost model, never touches Facet)
reports 1.00x — the negative control that says the arena did not move. The engine's own
`UpdateUILayouts + Layout` stayed at ~4.1 ms/frame: the campaign changed Luau, not the tree.

**Targets: `noop` MET, every other class MISSED** (spec Addendum 2, honesty rule applied). Update /
setState at L: 0.64 ms on a 904-node scene (1.3x over the 0.5 ms target) and 2.5–3.7 ms on 5–7k
nodes (5–7x over). Add / remove: 1.07–8.76 ms against 1 ms. The two list-shift classes are reported
as the O(shifted) floor they are (war_room `reorder` 7,335 rects at 7.0 µs each).

**Why, in one fact.** *Every remaining stage that costs anything is still O(N) in the mounted tree.*
`tools/profile/probe` at L: a solve that measures **nothing** and arranges **nothing** still costs
**0.969 ms** — 0.19 µs/node of pure traversal, 42 % of a real 1-leaf solve. ≤0.5 ms at 5,109 nodes
needs 0.098 µs/node, so the gap is not a constant-factor problem.

**No behavior changed and the evidence says so mechanically:** `controller.stats().rectWrites` is
identical at both arms for every step class of every workload, and the live GuiObject census is
identical row for row.

### Booked levers (next campaign's scope, in measured order)
1. **L1 — the skip walk must not descend into a skipped subtree** (`layout/solver.luau`,
   `replaySubtree` + the measure reuse arm). −0.96 ms of 2.49 at L. **Keystone**; nothing else gets
   the update class under 1 ms.
2. **L2 — arrange must not re-enter at the root.** 1.000 ms to arrange *three* nodes (vs 0.001 ms
   with nothing dirty): the dirty closure always contains the root and distributing a vstack
   descends into every child. −1.0 ms of 2.49 at L. Independent of L1.
3. **L3 — the commit's sibling scan.** 8 pruned walks × ~1,100 siblings = 0.609 ms at
   `lastCommitVisits ≈ 64`; fix is a dirty-child index on the list node. −0.5 ms of 2.49 at L.
4. **L4 — `structuralSync`'s whole-tree walks (F6, never taken).** 2.389 ms of a 5.802 ms `addItem`
   at L — the largest single term in a structural step. `ssLivePaths` + `ssZOrder`
   (`render/renderer.luau:2388`, `:2409`). LOW risk, independent: the cheapest unclaimed win.
5. **L5 — re-enable the P4 prune on chrome/path-bearing surfaces.** Now measured, not argued:
   `tools/profile/chrome` puts the two shut gates (`commit_walks.luau:803`, `:967`) at **+22 %/step**
   and `lastCommitVisits` 64 → ~1,100. Strategy: a chrome-path list and a path-node list maintained
   on the full walks, instead of latching off for the surface's life. Hits most RascalRally screens
   (any `ProgressView` ring or dismissible plate trips it).
6. **L6 — the tree handed to the engine is now worth as much as the Luau.** `UpdateUILayouts +
   Layout` = 4.10 ms/frame, ~40 % of a `battle_hud` L frame's real work. The before capture
   deprioritised this; **that ranking has inverted.**
7. **L7 — the list-shift floor needs windowing, not micro-optimisation.** 4.5–8.4 µs per moved rect
   on 3,460–7,335 rects. A product decision about long lists, not a solver bug.
8. **L8 — the promoted harnesses are seam-coupled.** P3 moved `toLayoutNode` → `layout_node.build`
   and `tools/profile/probe` died in `unpack` on it (fixed at FacetBench `1cc47a2`, both names now
   wrapped). A campaign that moves a seam must re-run them, not assume them.

### Standing measurement truths from the checkpoint
- **The ABBA pair is the only trustworthy cross-checkout number on this machine.** Background load
  ran 2.0–3.6 (1-min) with CrashPlan paused, and CrashPlan came back mid-Studio-drive at a mean 18 %
  of a core. Interleaving A/B/A/B absorbed it: round-to-round disagreement ≤3.6 % on every facet row.
- **Round 1 of each arm drifted, round 2 did not** — the machine was still settling. Every
  drift-failed row's *value* agreed with its clean counterpart to 2.2 %: the drift gate rejects the
  reading of the yardstick, not the measurement.
- **`_fixture` is the control that makes the claim falsifiable**, in both runtimes: 1.00x on Lune,
  0.96–1.01x across two Studio sessions a day apart under totally different load.
- **The loop-mode script-timeout ceiling at L is gone.** Every facet/L loop row now runs at the full
  250/25; the before drive needed 60/10 because a 43 ms step × 275 exceeded Roblox's ~10 s limit.
- **`attr` costs ~0.1–0.3 ms/step** — 2–3 % of a 43 ms step but 7 % of a 2.6 ms one. State it when
  quoting per-class numbers post-campaign.

---

## Plan 2 record (unchanged)

Plan 1 complete at `6addcde`. **Plan 2 complete at `0895eea`** (23 commits): registry rename (dual-runtime requires), war_room_inventory + killfeed_nameplates workloads, four vendored rivals (vide 0.4.1, fusion v0.3-beta, react-lua 17.2.1, blend quenty ×28 pkgs) + flux fetch-only (no upstream license; removal-on-objection policy in CONTRIBUTING), five live-only adapters (source-verified; reviews caught 3 crash-class + 1 fairness-class defects pre-live), Studio runner (mirrored rojo place, shared measurement core, lazy target provider, host-alive + surface guards, script-scrubbed vendor clones, console protocol + scrape), FIRST LIVE MATRIX (42 rows, 0 errors: results/studio-2026-09-01-c0c0803.json + docs/studio-runs/), bare-loop hazard lint (2 vendor hazards named), frameworks table + live-framework guide.

**Headline as it stood BEFORE the perf campaign** (superseded by the section above; kept because the delta is the story): frames-mode battle_hud S facet 4.40ms vs vide 0.0225ms (~195x); at L facet 44.0ms/frame vs vide 16.7, engine layout only 4.12ms of facet's 44 → the bill is Luau-side layout solving. This is the before-picture for F1–F3.

## Plan 3 opening chores (small)
- Live-only behavioral bite (~10 lines): runCombo snapshots after mount and asserts change in beforeUnmount (both outside measured windows) — closes the do-nothing-adapter gap for live adapters; then upgrade CONTRIBUTING's "review obligation" wording to name the mechanical gate.
- run.device in the envelope (schema + studio_scrape + run_matrix).
- sortedOrder tiebreak on key in war_room_inventory (table.sort tie order is runtime-defined; breaks same-seed-same-script across runtimes).
- acceptChild empty-object test; blend closure scanner dot/dash name classes; scene._lastListStates → return value; evidence doc line ~35 "0.1%"→"0.07%".

## Plan 3 main scope (original + review bookings)
- Baselines (Lune + Studio) committed with drift gating: reject rows whose yardstickDriftPct exceeds a threshold (Lune); for Studio either a survivable yardstick or write-time *Norm gating (drift ran 0.07%→105% in-engine).
- **M and L full-matrix sweep** — every committed cross-framework number is size S, where frameP*Ms is budget-bound (~16.7ms) and cannot discriminate; L is where frames mode becomes a measurement (only one combo driven there so far).
- Chart page from results/ (natural S<M<L order is already in the envelope sort).
- Demonstrators D1–D3 shown red; Facet fixes F1–F3 in the Facet repo (RR lockstep + device canary per constitution; RED-TEAM at end).
- SPEC CORRECTION (D2): "heap delta via gcinfo with GC quiesced" impossible — Lune collectgarbage is count-only; D2 needs allocation counters instead.
- Consider: cross-adapter comparable digest (list lengths/key order/bound scalars) — snapshots are per-adapter-shaped, so a framework doing less work is only catchable per-adapter today.
- CI workflow (check.sh on PRs) when the repo goes public; heapNetKb read-phase offset note.

## Standing traps for Plan 3 drives
- Studio yardstick unusable (drift to 105%) — never trust *Norm in studio envelopes.
- Empty places kill characters (~7s fall) and respawn WIPES PlayerGui mid-measurement → CharacterAutoLoads=false + assertHostAlive (both shipped; keep them).
- Lune `warn` writes to STDOUT (matrix decodes last line only); Studio HttpService blocked in this channel (console-dump + checksum is the transport).
- Marker discipline before trusting any Studio reading; execute_luau VM cannot string-require and has its own module instances (guards don't span VMs).
- Live "proven to bite" claims ship their raw dump fragment (DRIVING.md evidence rule).

## Plan 3 / campaign CLOSED (2026-09-02, Facet 4d9e3aac)

T10 final gate: RR live canary CLEAN (60fps sustained, quarantine nil, partials firing at pinned counts; two round-boundary diagnostics proven pre-existing via A/B). RED-TEAM: 10 findings — 9 fixed+verified (incl. the campaign-introduced stamp/flag coupling; diagnostics double-replay 605→1/frame; setMeasured epoch now a geometry fact; 4 attach opts documented + mechanised pin; two fresh extractions boundary_report + geometry_facts after the ledger's named seams proved STALE-TRIGGERED). verify.sh full: PASS 0 red (archived manifest row repaired via documented CASE_ID_REPAIRS after P4's case rename).

**Bookings for the next campaign / maintenance:**
- **propSigCache (RED-TEAM finding 3, HIGH, pre-existing Step-9-era):** recycled instances wear style props they never declared (props-table-keyed signature cache never invalidated on nil↔non-nil writes; repro in the RED-TEAM report). User-visible with recycling on. STRONG first-task candidate.
- verify.sh hygiene trio: git-ls-files untracked blind spot (false PASS class); producer race at --jobs>1; check_perf_captures output as hashed evidence (non-idempotent verdicts). Plus: repair_graph --dry-run backlog (11 stale receipt pins, 3 retirements, 1 add, 1 dropped pin, 4 pending); suite-cache fingerprint includes untracked .DS_Store (spurious misses); place builds non-byte-stable (14-file churn per full run).
- Source-cap ledger: AUDIT ALL ROWS for stale triggers (two named seams had already left their files). Solver headroom 861 — next solver change takes chosenCandidate (solver.luau:814) first.
- markFlip (P4): conservative, never fired in 3,000-frame soaks — retire or keep, needs live proof either way. stats() fields beyond attach opts undocumented in api.md. RR 878375e emitLegacyScripts:false double-boots rojo-BUILT places (game-side bug, canary report has evidence).
