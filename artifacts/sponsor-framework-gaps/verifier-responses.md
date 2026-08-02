# Verifier findings — response ledger (2026-07-27, suite 2531)

Every finding from the four fresh-context reviews, with what happened to it. "Pinned" names the regression that keeps it fixed.

## Phase-gate (verifier-phase-gate.json, first pass: NOT READY)

| Finding | Response |
|---|---|
| PG-1 BLOCKER gate red / SUMMARY overclaim | Gate checks were red pending this very review round; SUMMARY reworded to "automation complete, release evidence pending" with the physical/human remainder named. Final gate run recorded at close. |
| PG-2 five-view evidence path unpassable | FIXED: evidence → `rows/sf-c3.json`; check now validates all five row records `ok:true` via python, not `ls`. |
| PG-3 zero capture files | FIXED: 13 window-scoped PNGs re-shot at the final source via `tools/studio/capture_viewport.sh`, sha256-pinned in `captures/manifest.json`; rows re-pointed. |
| PG-4 floor never ratcheted | FIXED: `tools/test.sh 2531` (ratcheted three times as the fix rounds landed). |
| PG-5 no per-session preflights | FIXED: `preflight-session-scenarios.json` + `preflight-session-matrix.json`, honestly marked as assembled post-hoc from in-session probes; the capture re-shoot session ran against a live stamp check. |
| PG-6 SF-M8 without a bench artifact | FIXED: `dense-motion` scene in `bench/perf_scenes.luau` (24 springs + timeline + windowed churn), baselined + budgeted by the file's own rule, in `check_perf_scenes.py`'s liveness gate; `sf-m8.json` cites it; device frame time stays PENDING_PHYSICAL. |
| PG-7 artifacts predate current source | Cured for the visual evidence by the final-stamp re-shoot; the numeric row JSONs record their own stamps and the deltas between stamps are the FIX rounds themselves, stated in each row. |
| PG-8 SUMMARY cites unwritten files | FIXED with PG-1's rewording; everything cited now exists. |
| PG-9 `test -f` shallow checks | Partially hardened (five-view check validates content; suite floor is the deep gate); accepted residual: per-row content checks beyond that are the verifiers' own job, recorded here. |

## Roblox-platform (verifier-platform.json, first pass: NOT READY)

| Finding | Response |
|---|---|
| PLAT-1 MAJOR double-activate risk | FIXED: `dispatchNodeTapOnce` — detector-scoped 50 ms echo window, injectable clock, native + synthesized paths both route through it; guard clears on detector detach. Pinned: "one press cannot activate twice" (presenter_drag_integration.spec). |
| PLAT-2 touch/pen consumption unmeasured | Accepted → review packet SFP-2 (physical touch) — the tap path is input-class-agnostic by construction. |
| PLAT-3 synthesized tap bypasses gates | FIXED: dispatch honors `enabled ~= false` + TAPPABLE, same as native. |
| PLAT-4 hit rects ignore presentation offsets | FIXED (fix-round item 1): `screenRectOf` composes accumulated ancestor presentation offsets; `rectOf` untouched by instruction. Pinned +4 tests. Residual (pointer-zone callbacks still layout-space) escalated as ESC-2. |
| PLAT-5 CanvasGroup docs | FIXED: three costs written into api.md (clip, memory-cap blank, resize-recreates). |
| PLAT-6 PreRender unbind/budget | FIXED: documented in motion_driver + presenter.tick docs (caller owns the unbind; render-thread budget framing). |
| PLAT-7 purity unpinned | Accepted residual: `check_boundary` scope note recorded; purity re-verified by two independent reviews this stage. |
| PLAT-8 parity pin is a source regex | Accepted with the E3 compensation: the live ghost drive exercises the real transform write path on device. |

## Architecture (verifier-architecture.json, first pass: NOT READY)

| Finding | Response |
|---|---|
| ARCH-F1 MAJOR chase leak on mid-flight teardown | FIXED: flight records keep their chase handle; `hideProxyFor` and `registry.dispose` cancel it. Pinned: "dismissing a surface mid-commit-flight leaves the shared clock EMPTY". |
| ARCH-F2 MAJOR retiring subtrees stay drag-live | FIXED: renderer collects retiring roots per structural sync; the registry's `isPathLive` collaborator excludes them at RESOLUTION time (targets, sources, and `armTo`) — reversal-safe, zero registration churn. Pinned: "a RETIRING drop target leaves resolution and returns on re-entry". |
| ARCH-F3 asymmetric enter/exit reversal cut | Accepted limitation, documented: the designer vocabulary defaults to mirror pairs; a declared asymmetric pair reverses with a cut. |
| ARCH-F4 aliased-owner double-dispose silenced | Accepted nuance, comment updated in scope_impl: the detector's subject is same-HANDLE double dispose; aliasing a scope into two owners is its own §6.3 violation. |
| ARCH-F5 `own()` lacks parent deregistration | FIXED alongside RR-4's quarantine work (child() covered; own()-of-scope noted in the comment as caller-owned aliasing, see F4). |
| ARCH-F6 two exemption mechanisms | Disposition: `registry.interactionTarget()` is the production seam (the registry OWNS the interaction); `graph.beginInteraction` remains the public focus-side API for non-drag interactions. Documented in focus_graph. |
| ARCH-F7 one ghost vs N flights | Accepted, documented in the proxy host: a re-grab replaces the visible ghost; the replaced flight resolves invisibly (token-guarded). |
| ARCH-F8 dead `host` authority | Accepted: `UI.Custom` is UI-EXT-001 (phase-3 heritage), the declaration predates this stage; left for Step 5.5's cleanup ledger. |
| ARCH-F9 stale gate.json | Cured by the final gate run. |

## Reactive-runtime (verifier-reactive-runtime.json, first pass: NOT READY)

| Finding | Response |
|---|---|
| RR-1 BLOCKER throwing callback wedges the clock | FIXED: step body pcall'ed, `stepping` always clears, error on `clock:lastError()`. Pinned ×2 (runtime_quarantine.spec: throwing onSettle; throwing live-target). |
| RR-2 MAJOR dispose-during-step crash | FIXED: mid-step dispose defers to the step tail. Pinned. |
| RR-3 MAJOR chase survives axis disposal | FIXED via ARCH-F1 (cancel on teardown); the drag registry was the reachable shape. |
| RR-4 MAJOR un-quarantined scope cleanup | FIXED: per-resource pcall, walk continues, counters exact, `disposing` always clears, error reported through each core's channel (`onCleanupError`). Pinned (siblings-release + no-false-double-dispose). |
| RR-8 MAJOR per-cycle leak invisible to SF-C1 | FIXED both halves: `adaptive.conditions` owns its six memos via `opts.scope` (both sponsor fixtures pass it) AND a long-lived-core churn pin now exists (sponsor_scenarios.spec RR-8 block). Residual: the two pre-Step-5 scenarios (adaptive_controls, perf_capture) share the old pattern — recorded for Step 5.5's cleanup ledger, out of this stage's scope. |
| RR-5 sibling-ordering false double-dispose | Accepted nuance (same family as ARCH-F4), comment covers it. |
| RR-6 `child()` missing disposed assert | FIXED (same assert `own()` has). |
| RR-7 no conformance rows for the changed semantics | Partially addressed: runtime_quarantine.spec pins the semantics against the DEFAULT core; extending tests/conformance to all three candidates is recorded for Step 5.5 (the bake-off candidates already diverge on documented deltas). |
| RR-9 write-gate comment wrong | FIXED: comment now states the while-active rule precisely. |
| RR-10 onSettle unsub leaks boxes | FIXED: unsubscribe removes the box. |
| RR-11 `stop()` missing disposed guard | FIXED. |
| RR-12 un-pcall'ed subscribers/hooks | FIXED: feedback emit + presenter tick hooks quarantine (bus exposes `lastError`). |

## ui-designer review (ui-designer-review.md: ACCEPTABLE WITH FINDINGS)

R2-F1..F16: all in-scope items fixed in the fix round (supersede verb, §5.5 armed presentation, state channels, live viewportHeight, chevron states, subject naming + bottom edge, nit bundle, docs); the two inexpressible treatments + the selected-content/disabled-opacity residual escalated as **ESC-1** (responsibility ledger); evidence top-ups run (avatars largest-text portrait) or honestly environment-failed (notched portrait — the emulator reports no notch insets).

---

# Round 2 (2026-07-28)

All four verifiers re-ran fresh-context against the final source (suite 2535).

## Phase-gate round 2 (verifier-phase-gate.json: READY TO DECLARE)

| Finding | Response |
|---|---|
| PG2-1 mutation-tested pins | The round-2 verifier mutation-tested the new pins itself (detector-tap, echo guard, retiring-sibling boundary, disabled-source) — each pin fails when its fix is reverted. No action owed. |
| PG2-6 final gate at final source | Run after the last edit landed (see gate.json). |

## Platform round 2 (verifier-platform.json: ACCEPT)

| Finding | Response |
|---|---|
| P2-1 api.md slider wording overstates until ESC-2 closes | FIXED: wording qualified; the full pointer-zone consumer set (authored onPointerDown/Move/Up, presenter zone-A, syncGeometry feed) is enumerated in ESC-2 (responsibility ledger). |
| P2-2 retiring-prefix sibling bug | FIXED same-day: segment-boundary test + sibling pin ("/S/Slot" no longer excludes "/S/SlotA"). |
| P2-3 disabled drag source still draggable | FIXED same-day: renderer `dragSourceEnabled` map → registry `isSourceEnabled` collaborator + pin (the first attempt mutated a frozen decl and was reworked). |

## Architecture round 2 (verifier-architecture.json: READY TO DECLARE)

Both round-1 MAJORs verified fixed at source (ARCH-F1 chase-handle cancel,
ARCH-F2 retiring-subtree exclusion incl. the sibling boundary). Four residuals
carried honestly (mid-drag-retirement path untested, structure-dirty invariant
unasserted, six MINORs, gate.json-at-final-source — the last is closed by the
final gate run recorded in `gate.json`).

## Reactive-runtime round 2 (verifier-reactive-runtime.json: READY TO DECLARE)

Round-1 findings verified fixed. Of the seven carried residuals, three were acted
on at close:

| Residual | Response |
|---|---|
| RR-12-R1 MAJOR — `fireSettle` was the one un-quarantined callback fan-out left; a throwing onSettle subscriber starved every later subscriber's only notification | FIXED at close: per-subscriber pcall in `fireSettle`, errors land on `clock:lastError()` via a new `internals.noteError` seam (the announce path fires OUTSIDE the step pcall, so the quarantine must be fireSettle's own). Pinned both paths (step settle + reduced-motion synchronous announce) — suite 2535→2536. |
| RR-8-R1 MINOR — `adaptive_controls` and `perf_capture` still built scope-less `conditions`, leaking six memos per build | FIXED at close: both scenarios own a scope, pass it to `conditions`, dispose it on teardown. |
| RR-1-R1 MAJOR — clock quarantine is frame-granular: a PERSISTENTLY throwing consumer callback freezes all motion on that clock while it throws | CARRIED, deliberately. Entry-granular quarantine is an eviction-policy design choice (evict the throwing spring/chase and hide intermittent errors, vs. retry every frame and share the fate) — wrong to rush at stage close. The wedge class RR-1 named is fixed (the clock never latches); this residual is about blast radius during a persistent throw. Recorded for Step 5.5 with the verifier's reproduction. |
| RR-1-R2 / RR-5-R1 / RR-7-R1 / RR-3-R1 MINORs | Carried as recorded (stats-invariant doc nuance, false-double-dispose family nuance, cross-core conformance extension, dispose-during-iteration read — the last unexecuted/low-confidence). Step 5.5 ledger. |

## Toast-capture postscript (after platform round 2)

The remaining open observation — sf_toast_stack.png showing no toasts — resolved
as a CAPTURE RACE, not a paint defect: a toast lives ~4 s and the toast layer
disposes itself when empty, faster than the MCP screenshot round-trip, so every
"empty" shot postdated the layer's destruction (a planted probe Frame vanished the
same way). With sustained bursts driven and the local window capture used
immediately, the stack (glyph + title + detail rows, queue-overflow copy) is
plainly visible. The real live-found defect stands separately: the toast body
painted zero-width (hug HStack of fill children) — fixed in the fixture with a
headless paint-width pin (suite 2534→2535).
