# FacetBench — Plan 2 complete; carried items for Plan 3 (updated 2026-09-01)

Plan 1 complete at `6addcde`. **Plan 2 complete at `0895eea`** (23 commits): registry rename (dual-runtime requires), war_room_inventory + killfeed_nameplates workloads, four vendored rivals (vide 0.4.1, fusion v0.3-beta, react-lua 17.2.1, blend quenty ×28 pkgs) + flux fetch-only (no upstream license; removal-on-objection policy in CONTRIBUTING), five live-only adapters (source-verified; reviews caught 3 crash-class + 1 fairness-class defects pre-live), Studio runner (mirrored rojo place, shared measurement core, lazy target provider, host-alive + surface guards, script-scrubbed vendor clones, console protocol + scrape), FIRST LIVE MATRIX (42 rows, 0 errors: results/studio-2026-09-01-c0c0803.json + docs/studio-runs/), bare-loop hazard lint (2 vendor hazards named), frameworks table + live-framework guide.

**Headline (public-facing, with the loop-mode caveat now disclosed in the evidence doc):** frames-mode battle_hud S facet 4.40ms vs vide 0.0225ms (~195x); at L facet 44.0ms/frame vs vide 16.7, engine layout only 4.12ms of facet's 44 → the bill is Luau-side layout solving. This is the before-picture for F1–F3.

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
