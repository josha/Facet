# Large-text accessibility — acceptance ledger (roadmap Step 8.5)

**Stage:** `large-text-accessibility` (docs/plans/large-text-accessibility.md)
**Written:** 2026-08-03, BEFORE implementation (execution contract §2).
**Gate:** `tools/gate.sh large-text-accessibility` → `artifacts/large-text-accessibility/gate.json`

Status vocabulary (contract §2): `PASS_AUTOMATED`, `PASS_PHYSICAL`, `PASS_HUMAN`,
`FAIL_PRODUCT`, `FAIL_ENVIRONMENT`, `PENDING_PHYSICAL`, `PENDING_HUMAN`. A row
cannot pass through a different, easier row.

Baseline facts this ledger is written against (audited 2026-08-03, current source):

- `src/client/roblox_env.luau` maps the four `PreferredTextSize` values to
  guessed offsets `{ Medium=0, Large=6, Larger=10, Largest=14 }` and connects **no**
  change signal for the property.
- `src/client/text_premeasure.luau` measures words through `GetTextBoundsAsync`,
  which honors the live preference, while the solver has already added
  `preferredTextOffset` to the size it asks about — the documented double
  application (safe direction, but not exact-once).
- `src/client/text_calibration.luau` folds the preference into its per-font
  fraction when calibration runs under a non-Medium preference (fraction is
  bounds/size at size 100 — the offset rides the numerator only).
- The renderer already re-solves on `preferredTextOffset`/`typographyScale`/
  `themeMetrics` changes (src/render/renderer.luau env watch list), so live
  reflow-without-remount is wiring the adapter fact, not new machinery.
- `text_metrics.Metrics.truncated` exists; nothing reports it to a diagnostics
  surface, and no full-value affordance contract exists for truncated text.

| ID | User-visible behavior | Risk while lower tests stay green | Required evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| **LT-1** | The live adapter reads all four `PreferredTextSize` values and layout reserves the engine's real painted size — measured, not guessed, applied exactly once between measure and paint | Guessed offsets under-reserve (clip) or double-apply with engine-honoring bounds (waste, wrapped-early labels); paint and reservation drift by font/size | E2 probe + E1 seam tests + E3 integrated slice | Studio probe matrix (all four values × fonts × sizes: painted TextLabel bounds, GetTextBoundsAsync, GetTextSizeOffsetAsync, solver reservation); then suite | artifacts/large-text-accessibility/probe/preference-probe.json | PASS_AUTOMATED |
| **LT-2** | Changing the preference while a screen is mounted remeasures and reflows it without remount, and without losing control state, focus, input ownership, scroll position, or async resources | A change path that rebuilds the tree passes every static test; state loss only shows across the transition | E1 hot-swap tests + E3 live change probe | Headless hot Medium↔Largest with live focus/editing/scroll; Studio live-change probe | suite + artifacts/large-text-accessibility/studio/large-text.json | PASS_AUTOMATED |
| **LT-3** | First mount never waits on a yielding offset lookup; warm-up/failure keeps conservative documented geometry; when the measured answer lands, exactly one atomic re-solve applies it; the answer settling produces no further reflow | An async seam that blocks mount, applies twice, or oscillates passes tests that only look at the settled state | E1 + E3 | Failure/warm-up/stale-async fixtures (incl. the A->B->A double-step poisoning repro) | suite | PASS_AUTOMATED |
| **LT-4** | Headless tests keep an injectable preference seam; the live native path and the injected path have explicit, non-overlapping authority (never both applied) | Both seams active at once double-scales; neither active silently reverts to Medium | E1 | Authority tests over env facts (`preferredTextSize` multiplier vs live offset facts) | suite | PASS_AUTOMATED |
| **LT-5** | Theme fonts/weights/line heights/metrics, nine-slice chrome, ten-foot scaling, and the preference compose without clipping or double application | Each factor is tested alone; the composition drifts (e.g. ten-foot floor × preference applied to the same seam twice) | E1 + E3 | Composition tests at Fantasy Parchment + Studio Neutral, displaySize=Large × Largest | suite + studio row | PASS_AUTOMATED |
| **LT-6** | Public layouts and controls follow the overflow order: reflow first, containing-region scroll second, truncation only for bounded secondary/identity text; an action, instruction, status, error, result, or required fact never becomes an inaccessible ellipsis; permitted truncation exposes the full string through an affordance that works for every applicable input class | Truncation silently applied to essential text at Largest on compact widths while every control's own test passes at Medium | E1 | Overflow-policy tests per control/layout; full-value affordance contract tests | suite | PASS_AUTOMATED |
| **LT-7** | A mounted text node reports preference, font/role, natural+actual bounds, natural+visible line count, truncation/overflow state, chosen policy, and how the full value is reached; targeted checks catch sibling overlap, clipped essential text, sub-hit-floor controls after reflow, focus outside the scroll viewport, repeated post-settle reflow, and more moving-text surfaces than allowed; intentional overlays declare their relationship; diagnostics name node, contract, and likely fix | Diagnostics that exist but cannot fail (or fail on declared overlays) — the can't-ever-fail check class | E1 (+E3 for the dump surface live) | Verification-surface tests incl. negative controls (inject each violation → the check fires) | suite | PASS_AUTOMATED |
| **LT-8** | Every public control/layout and representative composed screens hold the guarantee at all four preferences, both reference themes, short+long locales, long unbroken names, mixed scripts, reduced motion | A sweep that only runs the defaults; long-locale/Largest interactions are where the defects live | E1 | Headless large-text matrix | suite (matrix cases) | PASS_AUTOMATED |
| **LT-9** | Compact phone portrait and landscape at Medium and Largest, the 667x375 Sponsor small-landscape at Largest, tablet/desktop catalog, and the ten-foot composition are correct through the real adapter — geometry/trace-paired captures, not screenshots alone | Emulated rows pass while the real adapter path (native paint, TextTruncate, safe areas) diverges from headless | E3 | studio-device-verification canonical rows + scenario surface. CAVEAT (honest split, recorded in the artifact): the compact-phone Largest rows are the INJECTED reservation axis (engine paints the session preference); real-paint agreement rides the production-place real-setting rows | artifacts/large-text-accessibility/studio/large-text.json + captures | PASS_AUTOMATED |
| **LT-10** | The real read-only player setting and its change notification are probed separately from injected fixture values; injected coverage is never claimed as the OS/player path | Injection-only evidence laundered as the real setting | E2/E3 (honest boundary; FAIL_ENVIRONMENT/PENDING where Studio cannot reach it) | Studio probe of the live setting path (`UserGameSettings`/settings UI); recorded outcome either way | probe artifact + studio row | PASS_AUTOMATED |
| **LT-11** | Sponsor View production fixtures — role selection, racer list/cards, race HUD/ticker/toasts/captions/countdown/omens, both roles' results, success/error/empty — stay readable, nonoverlapping, reachable, and usable at every preference, especially Largest on compact portrait/landscape; essential actions/facts visible or reachable in a predictable scroll path; touch targets usable; focus order/keep-visible/direct manipulation/state survive reflow; results `column`/`twoLane`/`threeLane` responds to measured content; permitted name/identity truncation exposes the full value consistently; reduced motion provides the same information without moving text | Game fixtures pass at Medium while Largest+compact collapses lanes, hides CTAs, or overlaps the gate strip | E1 + E3 | Game suite fixtures (luauui_sponsor_*.spec) + Studio Sponsor rows | game suite + studio rows + captures. CAVEAT: the sponsor compact-phone Studio rows were not emulated — compact geometry is the audited headless rows (390x844/844x390/667x375) + the physical pass; the driven Studio rows are native-viewport + exact 667x375 at the REAL Largest | PASS_AUTOMATED |
| **LT-12** | The Sponsor accessibility (§8) and localization (§9/S16.12) tables agree with the implemented policy; any historical truncation rule that hides an essential fact at large text is corrected, recorded, and tested — not preserved | Docs describe the old rule; tests pin the corrected one; nobody reconciles | E0 + E1 | Table-by-table reconciliation against implemented policy | UI_SPEC_sponsor_luauui.md diff + tests | PASS_AUTOMATED |
| **LT-13** | Rascal Rally consumer lockstep: every changed LuauUI contract audited against real game callers, game integration updated (no shims), game-side contract/integration tests updated, both Rojo mappings valid, game suite green, affected Studio canary run | A compatible-looking framework change that silently changes game text reservation; the game suite never re-run at the judged source | E1 + E3 | Consumer-impact ledger + live game suite run + canary | artifacts/large-text-accessibility/consumer-impact.md | PASS_AUTOMATED |
| **LT-14** | Step 9 performance-lab plan carries large-text/overflow workload rows: preference changes, long localized text, both themes, scroll/reflow churn, engaged reveal if shipped, teardown — with measurement queue/cache work, re-solves, per-frame writes, and active moving-label count as recorded quantities | Perf lab ships without the workloads and the cost of this stage is never measured | E0 | Step 9 plan diff | docs/plans update | PASS_AUTOMATED |
| **LT-15** | If an engaged reveal ships: reusable, engaged-only (focus/hover/deliberate open) after a quiet delay, reading-direction horizontal travel, pauses at ends, grapheme-correct, stops cleanly, static full-text alternative, reduced-motion disables travel, at most one moving surface per active presentation, no per-frame work for every clipped label. If not needed: a recorded decision | A marquee that runs unengaged, loops, or scales per-label frame work; or the decision made implicitly | E1 + E3 (or decision packet) | Reveal contract tests + Studio row, or decisions.md entry | suite/studio or decisions.md | PASS_AUTOMATED |
| **LT-16** | Both documentation sets are current: LuauUI api.md/guides for every public item this stage adds or changes; Sponsor parity/spec docs for the game-side policy | Docs drift; the fresh-author path breaks | E0 + drift checks | check_docs/check_surface_ledger + doc diffs | docs | PASS_AUTOMATED |
| **LT-P1** | A physical phone at the actual Largest preference, portrait and landscape, renders the public catalog and Sponsor View correctly through the retail client | Studio emulation structurally cannot prove the OS/player setting path, real touch, or device text rendering | E4 | Review build + checklist (review-packet.md) | named device result | PENDING_PHYSICAL |
| **LT-P2** | Subjective readability, hierarchy, and feel at large text meet the product bar | Automatable checks cannot judge readability | E5 | Review packet judgment rows | director result | PENDING_HUMAN |

## Decision packets

Recorded in `artifacts/large-text-accessibility/decisions.md` as LTN-*:

- LTN-1 — the exact authority seam chosen after the live probe (who owns the
  offset: engine bounds vs solver estimate vs paint), and why.
- LTN-2 — the engaged-reveal ship/no-ship decision.
- LTN-3 — corrected Sponsor truncation rules (old rule, why it hid an
  essential fact, new rule, and the recorded antecedent lines).
- LTN-4 — the full-value disclosure contract.
- LTN-5 — the matrix-found framework gaps and their fix shapes.
- LTN-7 — fresh-context review dispositions (what was fixed vs recorded).
