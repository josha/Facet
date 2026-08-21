# Release-candidate finding ledger (RC-9)

Sources: `reviews/architecture.md` (ARCH-1..26), `reviews/reactive-runtime.md`
(RR-1..15), `reviews/roblox-platform.md` (PLAT-1..26),
`reviews/maintainability.md` (MAINT-1..41, 893 lines, on disk),
`input/ias-inventory.md` (INPUT-1..116, DF-1..9), `reviews/reuse.md`
(REUSE-1..125: 40 High / 55 Medium / 30 Low; 15 keep-separate with recorded
reasons), and the dead-code interim (recorded in the controller ledger).
Severity/confidence live in the source files; this ledger owns triage,
reproduction status, and disposition. Every Blocker/High is fixed and rerun in
a wave below or carries an explicit disposition with owner, risk, reason,
trigger.

## Reproductions performed before fixing (plan rule)

- ARCH-1/ARCH-2 — REPRODUCED by controller probe
  (`.superpowers/sdd/release-candidate-review/probe_arch1.luau`): row-factory
  throw with no boundary leaves the disposed row in `children`, the new row
  absent, ZERO dirty entries, and the error swallowed into `core:lastError()`
  (the caller's `set()` returns normally). The next good update rebuilds, so
  the corruption window ends at the next items change. Severity High
  confirmed; silent-swallow aspect added to the fix contract.
- MAINT-1 — verified by the auditor with `wc -c` (renderer 199,650 of 200,000)
  and by reading `check_source_size.py`'s single `>= CAP` branch.
- MAINT-3 — the auditor ran the scaffold end-to-end and hit the failure.
- PLAT-1/RR-6 — two independent reviewers converged on the same defect at the
  same lines; code read confirms the `false and X or nil` bind-time
  short-circuit. Device-only to OBSERVE, deterministic to prove headlessly by
  unit-testing the bind table construction.

## Wave assignment

| Wave | Contents | Status |
|---|---|---|
| R1 correctness (src/) | ARCH-1, ARCH-2, ARCH-3, RR-1, RR-2, RR-4, PLAT-1/RR-6, PLAT-2, PLAT-3, MAINT-6 + addendum: the two live divergence defects (VirtualList/VirtualGrid clamped-anchor blank-screen class; RR surfaces missing presenter.tick + the guide section that taught it) | DONE (review clean after fix round 1) |
| R2 safe maintenance (tools/tests/docs) | MAINT-1 (warning band + headroom analysis), MAINT-3, MAINT-4, MAINT-5, MAINT-7, MAINT-8b, MAINT-8c, MAINT-8d, ARCH-7, gate.luau empty-detail half of MAINT-2 | DONE (review clean after fix round 1) |
| R3 input authority | INPUT-90..93, INPUT-105, DF-1..4 (RR Priority/Sink scheme), DF-7, DF-9 + flag declarations, legacy-input drift check, allowlist | DISPATCHED |
| R4 haptics | press/release/select Custom defaults + expander mirror + same-instant collapse | DONE (review clean after 2 rounds; PENDING_DEVICE rows remain by design) |
| R5 naming + consolidation | ADR-0037 + tags + leaf modules + client host + world.luau + dead-code dispositions | DONE (review clean after fix round 1; 125-row reuse ledger structural) |
| Docs wave | ARCH-4, ARCH-5, ARCH-6, ARCH-9, ARCH-21, ARCH-22, PLAT-15, PLAT-16, PLAT-23, MAINT docs items + T12 catalog/product-language/comments | QUEUED |
| Perf wave | RR-5 (fresh-`{}` memo identity, 25 sites — measure first), RR-12, PLAT-20 + T15 requalification | HEADLESS HALF DONE (wave T15, `perf/requalification.md`). **RR-5**: the 25-site list was three consolidation waves stale and re-derived two ways to 38 sites (one of the 25 was `core:memo(` inside an error STRING). 4 FIXED with measurement, 2 CONTESTED (measured real, blocked by the `virtual_list.luau` / `table.luau` source-cap locks), 18 measured as noise, 14 unreachable by any scene — which is itself the finding, because no scene mounts a VirtualGrid or a RowActions tray. **RR-12**: measured, and a scene showed it — the one-observer notify fast path, `animation-interruption` −69%, `collection-mutation` −29%. **PLAT-20**: OPEN, unmeasurable headless (an Instance allocation with no `Instance` in the host); routed to the Studio capture rows. Studio + Android rows stay with the close-out. |

## Director device round (2026-08-17, physical phone, screenshots on file)

| ID | Observation | Diagnosis state | Route |
|---|---|---|---|
| DIR-1 | Demo-chip strip's left border clipped at the screen edge, light package, ~393px portrait | Bounded diagnosis delegated with the examples_gallery harness + per-package gutter regression | R1 item 39 |
| DIR-2 | Themed HUD plate TEXT overflows its plate (fantasy-ornate / fantasy-parchment) | Current tree is GREEN under the themed overflow sweep (46 surfaces x 9 viewports x package axis), so either the phone ran a stale published build or the effect is device-real (font rasterization) where the headless oracle is blind | Device retest on the CURRENT build (batched Studio/device session); if it reproduces, new sweep viewport + oracle work |
| DIR-3 | Themed HUD plates overcrowd/overlap each other and the topbar | Same as DIR-2 (same sweep owns plate partition) | Same as DIR-2 |
| DIR-4 | Column resize in landscape, rotate portrait → Rating column gone | CONFIRMED in code: resolveDim makes overrides absolute fixed px, no re-clamp on viewport shrink (table.luau:1180) | R1 item 38 (clamp contract decided) |
| DIR-5 | Portrait→landscape loses LEFT HUD content; URL-bar toggle restores | Model-level rotation is proven equal to a fresh mount by tests/hud_chrome_rotation.spec.luau (green), so the live symptom matches PLAT-3's stale-inset race in the real adapter (bogus insets published right after rotation; any later re-arrangement repairs) | PLAT-3 fix in R1 item 10 + rotation row in the batched device checklist |

The DIR wave closed clean (review + mutation-verified fix round); device confirmations ride the batched pass. DIR2 (expand live round): DIR2-1 empty pills FIXED (cover retired structurally), DIR2-3 X icon FIXED, plate width FIXED; DIR2-2 base-disappear cause removed + fence, OPEN pending the device click (owner: device packet). DIR3 (round 3): DIR3-1 transient-over-screen framework rule + DIR3-2 chrome shoulder access — in flight at close, review seat assigned (M2). The published-place question is resolved: the phone build may predate the 2026-08-15
ornate-overflow fixes (O-23/O-25). The batched session re-publishes the rebuilt
place and re-tests DIR-1/2/3/5 on device.

## Interim-pass and late-wave findings (2026-08-20)

- INT-1 (fixed, c247f1b): showcase demo host env — proxy-core delegation
  blindness; host-path spec now sweeps all 36 demos.
- INT-2 (fixed): the §5 scenario surface boots a silent no-op in the current
  showcase. NOT a scenario-host defect — a BOOT-ORDER one, present since the
  first commit: `init.client.luau` read `Facet_Showcase` and `return`ed 30,668
  characters above where it would have read `Facet_Scenario`, and
  `build_places.sh` bakes that attribute into the showcase place. Measured
  read-only in the open Edit session (showcase read at char 10,684, scenario at
  41,352, both attributes set, place stamped `5da7cba+dirty 2026-08-18`); the
  rename wave had briefly made the baked OLD-name attribute stop matching the
  branch, which is why the 2026-08-17 canary passed and the 08-18 rebuild ended
  it. Fix: `examples/gallery/client/boot_mode.luau` decides once, §5 selectors
  outrank the demo shell, and every unhonourable selector warns with its reason
  and stamps `Facet_ScenarioState`. `tests/gallery_boot_mode.spec.luau`, 18
  rows, 7 mutations bite.
- GAL-DD (open): with-animation + tab-view demos double-dispose at teardown
  (found by the host-path sweep; does not affect mount) — owner: next
  gallery-area writer round; risk: teardown counter corruption/throws.
- TOOL-XA (open, LOW): check_input_authority standalone exit 0 while printing
  selftest FAILED — gate rows compose it correctly; standalone callers cannot
  trust the exit code. Owner: T16 triage.

## Dispositions recorded so far (owner · risk · reason · trigger)

- MAINT-2 (gate-manifest restructure, 757 KB / 2,270 pins): the empty-failure-
  detail defect is fixed in R2; the structural redesign is ALREADY OWNED by the
  Step 14 plan's "Test and gate simplification" section (structured results,
  one coordinator, archived prose). Owner: Step 14. Risk while open: slow
  sweeps, weak failure localization. Trigger: distribution-readiness stage
  start. Doing it mid-Step-13 would rebuild the evidence system under the
  release review that depends on it.
- MAINT-1 renderer extraction beyond the warning band: R2 delivers the warning
  band, headroom records, and a seam analysis; an actual extraction happens
  ONLY if the analysis finds a one-way seam (the previous split's history shows
  growth returns to entangled blocks). Owner: this stage R2, else dispositioned
  to a dedicated refactor mission. Risk: a future edit crossing the cap is now
  LOUD (warning band) instead of silent. Trigger: warning-band alarm.
- ARCH-15/16 (`luau-*` public theme tag vocabulary): naming decision deferred
  to the R5/naming wave with the ADR-0037 work — renaming a public authoring
  vocabulary needs the same deprecation treatment as call shapes. Risk: brand
  incoherence only; no behavior. Trigger: R5.
- PLAT-10 (native StyleSheet default OFF) + the stale promotion tracker
  (dead-code interim): a PRODUCT flag decision, not a defect fix — the
  promotion-readiness artifact is refreshed in the docs wave and the default
  flip needs the owner's call at the Step 14 checkpoint. Owner: user.
  Risk: theme packages needing `nativeStyleSheets` fail on default targets
  (documented). Trigger: Step 14 owner checkpoint.
- Vendor bake-off artifacts (vendor/Fusion + fusion_adapter + imperative +
  historical gate): retire-or-document is a product/history decision — R5
  presents both costs; default recommendation: keep, with a one-paragraph
  signpost (they are provenance for ADR-0002's benchmark), because deleting a
  frozen bake-off makes its ADR unverifiable. Owner: controller at R5.

Every finding not named in a wave or disposition above is Medium/Low and is
triaged into the R5/docs/perf waves' briefs; the final whole-branch review
checks this ledger against the review files for silent drops.
