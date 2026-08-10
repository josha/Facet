# Acceptance ledger — swiftui-reference-app-validation

Written before implementation (execution contract §2), 2026-08-08. Every row starts
`PENDING`; a row closes only on a tool-observed artifact from the judged source.
Evidence levels are the contract's E0–E5. A row cannot pass through an easier row:
a headless focus test does not close a Studio input row, a capture without paired
geometry/state closes nothing, and no fixture may impersonate an Apple host-OS
surface.

Proof names (original, clean-room):

| Proof | Interprets | Working name |
|---|---|---|
| P1 | Backyard Birds (garden/collection) | **Glade** |
| P2 | Food Truck (operations dashboard) | **Cartwheel** |
| P3 | Fruta (catalog + compact entry) | **Sipworks** |
| P4 | Roblox app home (discovery feed) | **Foyer** |
| P5 | Roblox app avatar editor | **Wardrobe** |

## Stage-level rows

| ID | User-visible behavior | Risk while lower tests stay green | Required evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| **RA-1** | Reference sources inspected at stage start; dates + behavior recorded; IP boundary held (original names/copy/data/assets everywhere) | Inventories written from memory, or reference identity leaking into the repo | E0 | source fetch + repo audit grep | sources.md, sources/features-*.md | PASS_AUTOMATED (source-inspection-and-ip-boundary check green: dates, baselines, clean-room grep) |
| **RA-2** | Capability ledger classifies every reference feature (available / composable / framework gap / Roblox-service adaptation / no host equivalent) with citations | Rows invented from the stale 0.5.0 parity doc instead of current source/evidence | E0→E3 | ledger written against current api.md + live proofs | capability-ledger.md | PASS_AUTOMATED (capability-ledger check green: five sections, five classifications, no-percentage rule) |
| **RA-3** | Responsibility ledger: LuauUI vs proof-owned vs host-OS per proof; production Roblox service mapped; no local workaround, raw GuiObject, key listener, parallel focus/layout, or device-name branch in any proof | A proof quietly re-implements framework behavior | E1 + audit | ownership audit + drift checks over proof source | responsibility-ledger.md | PASS_AUTOMATED (responsibility-ledger check green: forbidden-list grep + drift scan enforce it) |
| **RA-4** | Each proof mounts from a self-contained build with deterministic fake services; no network, no real purchase, no player-data write | Proof only runs inside the dev gallery with hand-assembled state | E3 | place/scenario build + fresh mount | places.json | PASS_AUTOMATED (places-and-builds green: five places rebuilt from final source, bytes+digest stamped) |
| **RA-5** | Full library suite green at close (stage-start floor 3556, closing floor 3833); prior gates unregressed | This stage's changes regress an earlier gate silently | E1 | tools/test.sh + tools/prior_gates.sh | artifacts/test.json, prior-gates.txt | PASS_AUTOMATED (suite 3833 exit 0 at close; full prior_gates.sh sweep regenerated at judged source — 16 PASS + eight named (gate,check) reds all diagnosed in prior-gates-analysis.md: seven are tools/bench.sh instrument variance with bench PASSING standalone at this source, one is Step 10\'s own pre-existing canary declaration) |
| **RA-6** | Rascal Rally consumer synchronized for any LuauUI contract/behavior change (or compatibility evidence recorded) | Framework fix lands without its production consumer | E1/E3 | game suite + canary when visible behavior changed | consumer-impact.md | PASS_AUTOMATED (RR suite 3094 exit 0 re-run at final judged source; consumer-impact.md carries the per-change analysis and honest non-claims) |
| **RA-7** | Every reusable defect the proofs exposed is fixed in LuauUI with API/tests/docs/live proof; large subsystems become follow-on proposals | Fixes hidden inside proof code | E1+E3 | framework diff + tests + Studio slice | framework-fixes.md | PASS_AUTOMATED (six bounded fixes with failing-first/mutation-proved tests + live proof; two follow-on proposals with live evidence — framework-fixes.md) |
| **RA-8** | swiftui-parity.md + authoring docs explain what Roblox reproduces and what has no host equivalent; drift checks green | Docs claim parity the ledger does not support | E0 | check_docs / drift tools | docs.json | PASS_AUTOMATED (docs-updated green: parity §12 incl. late-stage additions, check_docs + check_registration green) |
| **RA-9** | Fresh-context phase-gate, architecture, and Roblox-platform reviews run on raw artifacts; requirement findings fixed and rerun | Implementer self-approval | E5(review) | verifier subagents | reviews/README.md | PASS_AUTOMATED (three fresh-context reviews on raw artifacts: 0 BLOCKER; two reviews independently converged on the same two vacuous gate greps, all 8 MAJORs fixed same-day with mutation proof, dispositions in reviews/README.md) |

## Per-proof loop rows (each = the complete representative loop, played)

| ID | Loop that must be observed end to end | Required evidence | Artifact | Status |
|---|---|---|---|---|
| **RA-P1** | Glade: overview of collection sites with visibly draining supplies → open a site's detail → refill water and food (levels visibly restore and resume draining) → browse visitor detail → open the store shelf → complete a purchase-shaped upgrade on the fake service (feature visibly unlocks; balance-shaped fact updates) → interruption/failure state → reset | E1 loop states + E3 played slice with traces/captures | proofs/garden.json | PASS_AUTOMATED+E3 (loop pinned headless 73 cases incl. matrix pin; live rows/axes clean; corpse-fix A/B live) |
| **RA-P2** | Cartwheel: adaptive split navigation (sidebar collapses on compact) → dashboard with recent-orders panel using a custom diagonal thumbnail arrangement + charts (bar/line/donut-shaped from Path/Grid) → open an order → advance its status → order-prep countdown timer runs, completes, and survives navigation → charts reflect the change → reset | E1 + E3 as above | proofs/dashboard.json | PASS_AUTOMATED+E3 (62 pins; live 5 rows + keyboard + full loop + axes all settled-0) |
| **RA-P3** | Sipworks: browse catalog → search with live filtering → favorite/unfavorite (persists across navigation in-session) → item detail with ingredient/nutrition-shaped disclosure → order flow on fake service → rewards balance accrues with redemption at threshold → recipes section gated behind purchase-shaped unlock → locale swap to an expansion pseudo-locale reflows without clipping → compact entry flow reuses the same components | E1 + E3 as above | proofs/catalog.json | PASS_AUTOMATED+E3 (63 pins; live 5 rows + keyboard + full loop + axes settled-0 incl. compact entry) |
| **RA-P4** | Foyer: nav rail + tab pair → friends carousel (horizontal scroll) → sectioned feed: responsive card grid (columns follow width), horizontal continue-shelf, ad disclosure, ratings → search collapses to icon on compact → open a tile's detail-shaped surface → refresh/reset; feed state, focus, and scroll survive reflow | E1 + E3 as above | proofs/discovery-home.json | PASS_AUTOMATED+E3 (17 pins; five rows + keyboard trace re-collected 2026-08-09 at final source: 0 diagnostics everywhere, notices modal opened by traversal, search collapses to icon at compact; axes all 0 incl. four preferred-text values under parchment) |
| **RA-P5** | Wardrobe: category tabs filter an item grid (thumbnail, creator, verified badge, price) → select try-equips onto the live preview pane (ViewportFrame-backed) → undo/redo walk the equip history → currency pill updates on purchase-shaped confirm (with rejection path) → segmented top control switches sections → compact arrangement stacks preview over catalog; equip state survives rotation/theme swap | E1 + E3 + E2 for the ViewportFrame seam | proofs/avatar-editor.json | PASS_AUTOMATED+E3+E2 (13 pins + Stage seam; five rows + keyboard + orbit/equip/theme re-collected 2026-08-09 at final source; both live defect shapes this stage fixed are settled 0; ten-foot unfit declared) |

## Matrix and axes rows

| ID | Behavior | Required evidence | Artifact | Status |
|---|---|---|---|---|
| **RA-M1** | Every proof loop across its applicable five view rows (compact phone portrait, phone landscape, tablet landscape, desktop, console ten-foot), presets resolved at runtime, geometry/focus asserted before captures | E3 | studio/device-matrix.json | PASS_AUTOMATED (all five proofs x five rows ok at final source; studio/device-matrix.json + per-row archives; wardrobe/foyer re-collected post-lock, cartwheel/sipworks phone rows re-collected with Touch boot fact) |
| **RA-M2** | VirtualInput keyboard + pointer traces on live geometry for each proof's primary path; raw event paired with semantic action and visible state change; unavailable paths recorded FAIL_ENVIRONMENT | E3 | studio/device-matrix.json | PASS_AUTOMATED (keyboard raw->semantic pairing closed per proof incl. the disabled-control negative control and the CoreGui-Tab refusal, both recorded; pointer trace on glade; unavailable classes recorded honestly in boundaryNotes) |
| **RA-M3** | Public theme-package swap (Studio Neutral ⇄ Fantasy Parchment) on each mounted proof: same semantic tree, focus + mount identity preserved, no source edit | E3 | studio/fixture-axes.json | PASS_AUTOMATED (fantasy_parchment swapped on every mounted proof via the public step: 0 diagnostics settled, mount identity preserved, no source edit; the swap axis itself surfaced and then verified two framework fixes) |
| **RA-M4** | Preferred text all four values headlessly + Largest on compact phone rows live: no overlap, essential text reachable, focus/scroll survive | E1 + E3 | studio/fixture-axes.json | PASS_AUTOMATED (0/4/10/14 live on foyer under parchment + headless sweeps pinned; wardrobe pref14 under parchment+xa 0) |
| **RA-M5** | Reduced motion: same information, no travel; localization expansion (≥1.4×) reflows without clipping | E1 + E3 | studio/fixture-axes.json | PASS_AUTOMATED (reduced motion 0 on every proof; xa >=1.4x expansion reflows clean everywhere — and caught the Picked-plate defect that was fixed same-day, finding 21) |

**Captures note (phase-gate review m-5):** live captures cited by name in this
stage's artifacts (e.g. `glade-parchment-postfix`, `wardrobe-parchment-stage-fixed`)
are Studio MCP session captures reviewed at run time; they are NOT archived as
image files on disk. The archived evidence per row is the paired
geometry/env/focus/state JSON in `studio/`, which is what the gate checks
consume. Rows close on that pairing, never on a capture alone.

## Honestly-pending rows

| ID | Behavior | Status |
|---|---|---|
| **RA-X1** | Physical touch (incl. real mobile OS keyboard) on each proof's compact arrangement | PENDING_PHYSICAL |
| **RA-X2** | Real gamepad delivery / console behavior for ten-foot rows | PENDING_PHYSICAL |
| **RA-X3** | "Each proof reads as a designed product" — subjective quality judgment | PENDING_HUMAN |
