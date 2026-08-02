# sponsor-framework-gaps — stage summary

**Gate:** `tools/gate.sh sponsor-framework-gaps` · **Date:** 2026-07-27/28 · **Suite:** 2075 → 2567 (+492) · **Game suite:** 2425 green, no game code touched.

**✅ CLOSED BY THE DIRECTOR 2026-07-28** after six same-day review rounds (SFH
pass, virtual-controller pass, ring/plate screenshots, pointer-held slot,
universality ruling, tap-to-pickup) — every finding fixed, pinned, and
live-verified; the full round log is in `review-packet.md`. The physical/human
rows (SFP-1..5 / SFH re-checks on hardware) remain the stage's honest pendings.

Roadmap Step 5: every reusable framework gap the RascalRally Sponsor experience needs, closed in LuauUI behind public API and proven in a Sponsor-shaped Studio gallery — no game policy absorbed, the shipped Sponsor Mode untouched.

## What shipped (ADR-0022)

- **Motion authority** `LuauUI.motion`: name-only motion classes (`container/object/reward/decay`), interruptible velocity-seeded springs, live-target chase with perceptual arrival (4 px), timelines with interrupt/skip that terminalize the playing beat, an injectable clock (one core transaction per frame, zero cost at rest), reduced-motion parity incl. the `informational` stepped-timer policy.
- **Per-node presentation channel** live on the adapter (transform offset/scale/rotation accumulating down the flat tree; declared-CanvasGroup fades) — which also fixed **SF-M9**, a pre-existing silent no-op of the keyboard keep-visible shift on device, and pinned fake/live handled-prop parity three ways.
- **Structural transitions**: mount-layer retire model (`When`/`ForEach`/surfaces; re-entry mid-exit reuses identity; 500 ms hard cap), vocabulary fade/slides/materialize/instant.
- **Toasts** `presenter.presentToast`: input-transparent presenter-private surface, pure scheduler (priority, cap 8, 3 visible, 1.5 s read floor, same-key supersede, capacity dismissals), RM keeps the full information surface.
- **Public drag/drop** `UI.draggable`/`UI.dropTarget` over one registry: shared promotion tokens (6 px pointer/14 px touch), rolling-window release velocity, detached terminal flights (session ends on the release frame; `land` fires at arrival), one `cancel` verb for all three cancel affordances, F7 modal-cancels-drag, ghost layer between toasts and modals, edge autoscroll to the ratified numbers with same-frame verdict re-resolve.
- **Unified collection**: `newVirtualList` windows + selects + reorders + accepts drops, focus-skip predicates with the active-interaction exemption, Readable rowHeight/viewportHeight.
- **Paint escapes** under audited authority: `tint` (role-blend | declared `direct`) with paint claims visible to defeat detection, `scaleMode`, `UI.stroke`, `zIndex` sibling override, fractional Anchor offsets + presentation-transform markers.
- **Semantic feedback** bus (activate/select/pickup/commit/land/reject/cancel/arrive/dismiss/supersede/celebrate — LuauUI plays nothing).
- **Async avatars**: bounded retry + session give-up, preload seam, silent presentable failure (opt-in mark only), dimmed treatment; live `rbxthumb://` transport proof.

## Live-found defects, all fixed and pinned this stage

1. **SF-M9** presentation channel dead on device (headless-green class) → per-node channel + parity pin.
2. **Scope double-dispose** of departed keyed rows (P5-F1, latent since Phase 0, surfaced by toasts) → scope_impl: early-disposed children skip the parent walk + deregister (fixes unbounded owned-list growth under churn too).
3. **Detector eats taps** (SF-D3 live half, found by a REAL injected click): `UIDragDetector` suppresses `.Activated` → registry answers "tap", renderer dispatches via the native-tap path.
4. AsyncImage failure mark contradicting SF-A1 (P5-F2) → silent by default, mark opt-in.
5. Plus P5-F3/F4/F5/F6 (SURFACE_LAYER reachability, cancel-verb unification, Readable viewportHeight, timeline mid-beat terminal).
6. **Toast body painted zero-width live** (hug HStack of fill children degenerates; headless-green class) → width `fill` on Body/Title/Detail + a headless paint-width pin. The follow-on "toasts invisible in captures" scare was NOT a paint defect: a toast lives ~4 s and the layer disposes itself when empty, faster than the MCP capture round-trip — the final capture drives sustained bursts and shoots with the local window capture (see `captures/manifest.json` note).
7. **Drag ghost rode exactly GuiInset pixels below the pointer** (director fix round 2026-07-28; headless-green class — insets are zero in test worlds, and the fake adapter models no root insets at all): the registry speaks WINDOW space while the ghost surface mounted `coreSafeContent`, double-counting the inset → ghost layer now mounts `edgeToEdge`; verified live to the pixel. Lesson: `docs/lessons/proxy-surfaces-must-speak-the-registry-coordinate-space.md`.

## Director fix round (2026-07-28, first SFH pass)

Suite 2536 → 2539, then → 2542 after the virtual-controller round (below); same-day fixes for every finding: ghost centered under the
pointer (`grabAnchor = "center"` default, `"preserve"` opt-out — the
RascalRally-ratified feel) with the inset fix above; presentation scale pivots
on the node's CENTER (adapter re-anchors while a motion scale is live — fixes
the reward pop growing from the top-left AND the ghost's pickup growth); the
RR-default commit is INSTANT with a decay-class wash on the landed row (Card B
alone keeps `flyToTarget`, which now aims rect CENTERS, killing the
slide-to-the-left); Toss rallies SlotA↔SlotB with mirrored seeds; the decay
wash strip is labeled; toasts ride raised plates inset from the edges with
body-size detail and a 2.5 s read floor; SFH-4/SFH-5 rewritten with exact
commands and a per-capture checklist. Live-verified at stamp 63225988-2522290;
three captures re-shot.

## Virtual-controller round (2026-07-28, director's second pass)

Suite 2539 → 2542. The director drove the armed flow with Studio's Virtual
Controller and found five real defects, all framework-side, all fixed same-day
and re-driven live through the running InputAction instances (engine pad→action
delivery was proven by the director's own presses in the telemetry log):
**auto focus groups were axis-blind** (every ungrouped run VERTICAL — "right"
across the hand's HStack couldn't reach Card B; groups are now layout-aware,
sharing the HStack/Grid derivation with the no-contribution path);
**B-cancel only existed on reorderable lists** (a drop-target list armed a card
the pad could not cancel); **A-commit used the stale aim** (the "returned to
the hand" report — activate now aims at the pressed row, and `beginSession`
emits `select` AFTER its opening hit-test so the arm presentation's aim
survives); **armed aim and the focus ring were two truths** (the presenter's
focused-observer now aims while armed, consumed intercepts sync the ring back,
and `armTo` spring-hops the ghost — RR's ghost-follows-focus); **rings under a
clip host draw inset** (the scroll edge ate the first row's ring); plus the
fixture's armed-ineligible DIM (the visible answer to "why did the arm skip
row 01"). Pins: the device-driven armed flow, cancel/re-arm, and horizontal
hand navigation (tests/sponsor_scenarios.spec.luau).

## Evidence

`acceptance-ledger.md` (every automatable row PASS_AUTOMATED; the physical/human remainder lives in `review-packet.md` as 5 physical + 5 human rows with exact procedures — the stage claim is AUTOMATION COMPLETE, release evidence pending those rows). Per-row records: `rows/*.json` + `rows/matrix/*.json` (five-view driver rows, all ok, injected input honestly labeled; VirtualInput re-probed non-delivering). 13 window-scoped PNG captures in `captures/` with pinned sha256s (`captures/manifest.json`), re-shot at the final source after a verifier caught the originals living only in the MCP transcript. Per-session preflights: `preflight-*.json`. Prior gates: `prior-gates.txt` (15/15, two stated deviations). Reviews: `ui-designer-spec.md` (+§10 dispositions), `ui-designer-review.md` (ACCEPTABLE WITH FINDINGS — every in-scope finding fixed or escalated in the responsibility ledger's escalation register), verifier verdicts in `verifier-*.json` with every MAJOR fixed same-day (gate-check repair, suite-floor ratchet 2075→2567, capture files, per-session preflights, the dense-motion bench scene, the PLAT-1 tap echo guard, presentation-aware drag hit rects).
