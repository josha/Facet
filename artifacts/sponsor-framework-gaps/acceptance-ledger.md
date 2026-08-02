# Acceptance ledger — sponsor-framework-gaps (roadmap Step 5)

**Date created:** 2026-07-27 (BORN-RED: every row starts `PENDING`)
**Companion:** `responsibility-ledger.md` (ownership decisions), `docs/plans/luauui-consolidated-roadmap.md` §Step 5,
`docs/plans/agent-execution-contract.md` (status vocabulary, evidence ladder).
**Suite floor at stage start:** 2075 (`tools/test.sh 2075`). Ratchet up as work lands.

Status vocabulary: `PENDING` (born-red) → `PASS_AUTOMATED` / `PASS_PHYSICAL` / `PASS_HUMAN` /
`FAIL_PRODUCT` / `FAIL_ENVIRONMENT` / `PENDING_PHYSICAL` / `PENDING_HUMAN`.
A row cannot pass through a different, easier row. Captures pair with geometry/trace dumps.

## Motion authority

| ID | User-visible behavior | Risk | Required evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| SF-M1 | A value animated by a named motion class can be re-targeted any frame and continues from its current value **and velocity**; a seeded release velocity produces no visible seam; settle detection fires exactly once; idle motions cost zero per-frame work | A tween-shaped implementation hard-cuts velocity on interrupt while tests only check the end state | E1 deterministic solver tests (step-by-step positions under scripted clock) + E3 live slice | headless spec w/ injected clock; gallery `sponsor_motion` scenario steps | `tests/motion*.spec.luau` via `artifacts/test.json`; `rows/sf-m1.json` + capture | PASS_AUTOMATED |
| SF-M2 | A motion whose target is a live-read position chases the target while it moves (list reorder mid-flight); it never lands on a stale pixel | Target captured at launch looks right until the row moves | E1 (scripted target movement mid-flight) + E3 (fly-to-row while fixture reorders) | headless spec; `sponsor_drop` scenario step | test + `rows/sf-m2.json` + capture | PASS_AUTOMATED |
| SF-M3 | Arrival fires on the frame the object visually lands (perceptual radius against the live target), with settle as fallback when the target vanished; the semantic `land` event fires that frame | Settle-epsilon arrival trails perceived landing (~0.7 s in legacy); event fires late so game feedback desyncs | E1 (radius vs settle ordering under scripted clock) | headless spec | test | PASS_AUTOMATED |
| SF-M4 | A choreographed sequence (timeline of beats) runs on the framework clock, can be interrupted mid-beat, and resolves to a clean terminal state (skip = jump to end state, never half-painted); headless runs are deterministic via injected time | Sequences built on `task.delay` are untestable and un-interruptible; interruption leaves orphan state | E1 (interrupt at every beat boundary + mid-beat) + E3 (interrupted celebration fixture) | headless spec; `sponsor_celebration` scenario `interrupt` step | test + `rows/sf-m4.json` + capture | PASS_AUTOMATED |
| SF-M5 | Under reduced motion every motion contract substitutes an information-preserving equivalent (instant placement / short fade); nothing is silently dropped; informational timers still deplete | RM implemented as "skip the animation" deletes information | E1 (RM path emits same terminal states + same semantic events) + E3 (fixtures under `reducedMotion=true`) | headless spec; gallery scenarios with `setEnv reducedMotion` | test + `rows/sf-m5.json` + captures | PASS_AUTOMATED |
| SF-M6 | `When`/`ForEach` branches and presented surfaces can declare enter/exit transitions; an element re-entering mid-exit reverses smoothly; unmount completes only after exit (with a hard cap); RM = fade/instant | Exit transitions keep disposed scopes alive (leak) or block unmount forever | E1 (mount→unmount→remount races; scope disposal counts) + E3 (caption/toast fixture) | headless spec; `sponsor_toast` scenario | test + `rows/sf-m6.json` + capture | PASS_AUTOMATED |
| SF-M7 | Motion writes only presentation-channel properties; solver geometry and native-sheet paint authority are never violated; a style-authority audit passes while motion runs | Motion writing solver-owned or sheet-owned props reintroduces the defeated-paint bug class | E1 authority tests + E3 `GetStyled`/authority dump while animating | headless spec; scenario report authority section | test + `rows/sf-m7.json` | PASS_AUTOMATED |
| SF-M8 | Dense motion (≥20 concurrent springs + a running timeline) stays within the recorded frame budget in the perf scene; resting springs contribute zero | Per-frame allocation/connection churn melts weakest devices | E1 counters + Studio-emulated perf row (labeled regression evidence, not device proof) | bench scene + `perf_capture` scenario | `bench.json` delta + `rows/sf-m8.json` | PASS_AUTOMATED (headless + studio-emulated regression evidence; weakest-device numbers PENDING_PHYSICAL) |
| SF-M9 | **Found defect (2026-07-27 audit):** the presentation channel is a silent no-op on the live adapter — `presenter` keyboard keep-visible calls `setPresentationOffset` → `setProp(root,"transform",…)`, FakeTarget records it, `screen_target.setProp` has no `transform`/`transparency` branch, so the shift never lands on device. Fix: per-node presentation transform/transparency implemented live (Decision 2), keep-visible shift visibly moves the root in Studio, and a conformance check pins fake/live handled-prop parity so this class cannot recur | Headless-green/live-broken channel ships again; text fields hide behind the OS keyboard on phones | E1 conformance + E3 (Studio: field focused, occlusion fact set, root visibly shifted; geometry dump) | headless spec; `sponsor_toast`/text scenario step with `setEnv` keyboard rect | test + `rows/sf-m9.json` + capture | PASS_AUTOMATED (fixed this stage: per-node presentation channel live + fake/live parity pin; adapter path proven on-device by the ghost drive) |

## Collection substrate (racer-list shape)

| ID | User-visible behavior | Risk | Required evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| SF-L1 | One public list construct windows long content, supports single selection, row reorder, and acting as a drop surface simultaneously; rows keep mounted identity and focus across live order churn (250 ms re-sort while dragging) | Identity churn remounts rows mid-drag; selection/drop state silently resets; only-visible-rows assumptions break drop targeting on offscreen rows | E1 (window + identity + selection + drop under scripted churn) + E3 (live fixture with churn while dragging) | headless spec; `sponsor_list` scenario steps | test + `rows/sf-l1.json` + capture | PASS_AUTOMATED |
| SF-L2 | Dragging near a scroll edge arms after dwell (300 ms), ramps speed with penetration (100→500 px/s over 150 ms ease), keeps the row-under-pointer verdict fresh every frame while scrolling, clamps at canvas end while staying armed, and never arms on short content or a fast flick-through | Tick-based hover re-resolve lags ~2 rows at max speed; jitter resets dwell; short content shows a scroll affordance that can't scroll | E1 (scripted clock: dwell/ramp/clamp/reset rules) + E3 (drag-to-edge in fixture, verdict trace) | headless spec; `sponsor_drop` scenario autoscroll steps | test + `rows/sf-l2.json` + capture | PASS_AUTOMATED |
| SF-L3 | Rows can be declared unfocusable by live predicate (e.g., while a card is armed); navigation skips them; the currently-targeted row of an in-progress interaction never loses focusability mid-gesture; tap/inspect remains live in every state | Focus lands on an ineligible row; or the armed target is yanked from under the gesture when its own predicate flips | E1 focus-graph tests + E3 (gamepad-emulated navigation over mixed-eligibility fixture, labeled synthetic) | headless spec; `sponsor_list` scenario focus steps | test + `rows/sf-l3.json` | PASS_AUTOMATED |

## Drag/drop public contract

| ID | User-visible behavior | Risk | Required evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| SF-D1 | A blueprint can declare a draggable payload source and drop targets through public API; enter/leave fire exactly once per boundary; the predicted verdict is visible while hovering; drop resolves via the game-supplied legality predicate; cancel restores cleanly; works across containers (hand → list row) | Session policy hand-rolled per fixture; enter/leave double-fire under churn; legality read from visuals | E1 (session policy incl. retarget-under-scroll) + E3 (real drag via detector path, raw + semantic trace) | headless spec; `sponsor_drop` scenario | test + `rows/sf-d1.json` + capture | PASS_AUTOMATED |
| SF-D2 | Release velocity from a rolling 100 ms window seeds the settle motion (flick feels continuous); non-gestural cancels (keyboard/gamepad) take the same path with zero seed | Velocity computed from a single frame delta is noise; separate cancel path drifts in feel | E1 (scripted samples → expected velocity; zero-seed path) | headless spec | test | PASS_AUTOMATED |
| SF-D3 | Press-to-drag promotion uses shared per-input-class thresholds (mouse ≈6 px, touch ≈14 px); release under threshold is a tap (activate still fires); thresholds come from one token source | Divergent magic numbers per consumer; taps eaten on touch | E1 + E3 (VirtualInput pointer path: press-move-release under and over threshold) | headless spec; scenario input steps | test + `rows/sf-d3.json` | PASS_AUTOMATED |
| SF-D4 | Gamepad/keyboard reach the same drag outcomes via arm→navigate→commit/cancel through the same session and legality model (no second policy path); ineligible targets are skipped (SF-L3) | A parallel "gamepad mode" reimplements legality and drifts | E1 (same session object, both paradigms) + E3 (synthetic navigation, honestly labeled; physical gamepad stays pending) | headless spec; scenario steps | test + `rows/sf-d4.json` | PASS_AUTOMATED |
| SF-D5 | An illegal drop rejects: payload returns to origin under the motion contract (velocity-seeded when gestural), a semantic `reject` event fires once with the game-supplied reason code | Silent rejection ("the game ignored me"); double events under rapid retry | E1 + E3 (illegal drop in fixture; event trace + capture) | headless spec; `sponsor_drop` scenario | test + `rows/sf-d5.json` + capture | PASS_AUTOMATED |

## Paint / layering / markers

| ID | User-visible behavior | Risk | Required evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| SF-P1 | A node can bind a continuous color value (e.g., computed hue, energy lerp) on the binding channel with explicit authority separation from native-sheet paint; the authority audit stays clean | Reintroduces explicit-write-defeats-stylesheet; or silently dropped like old `Text.color` | E1 + E2 (authority) + E3 (hue-sweep fixture with `GetStyled` dump) | headless spec; `sponsor_list` row wash step | test + `rows/sf-p1.json` + capture | PASS_AUTOMATED |
| SF-P2 | Authored `Image` supports tint and scale-mode (fit/fill/crop/slice passthrough) with declared authority; avatar dim state renders | Tint fights native-sheet `ImageColor3` ownership | E1 + E3 (avatar dim in fixture) | headless spec; `sponsor_avatars` scenario | test + `rows/sf-p2.json` + capture | PASS_AUTOMATED |
| SF-P3 | `UI.stroke(bp, {…})` adds a reactive border to any box-like node; pulse via bound thickness/transparency works | Stroke instance leaks or double-materializes with theme chrome strokes | E1 (+ chrome-coexistence test) + E3 | headless spec; fixture step | test + `rows/sf-p3.json` | PASS_AUTOMATED |
| SF-P4 | A `zIndex` override lifts a node above tree order within its stacking scope (drag ghost above all; toast above list); order is deterministic and documented | Global z chaos / fights the shadow z model or native ZIndexBehavior | E1 (paint-order walk) + E3 (ghost-over-everything capture + instance dump) | headless spec; `sponsor_drop` ghost step | test + `rows/sf-p4.json` + capture | PASS_AUTOMATED |
| SF-P5 | Anchor children accept fractional (scale) offsets; a keyed marker overlay of ≥12 live markers tracks u,v signals without remounts | Fractional support only at mount; marker updates remount (dots blink) | E1 (identity across updates) + E3 (minimap-dots fixture, geometry dump) | headless spec; `sponsor_markers` scenario | test + `rows/sf-p5.json` + capture | PASS_AUTOMATED |

## Toast / transient presentation

| ID | User-visible behavior | Risk | Required evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| SF-T1 | `presentToast` shows an input-transparent, self-retiring surface above the base screen; it never steals focus or blocks gameplay input; it enters/exits under the transition contract | Toast layer eats clicks; focus jumps; stacking hides base modals | E1 (responder/focus untouched) + E3 (input passes through toast to control beneath; trace) | headless spec; `sponsor_toast` scenario | test + `rows/sf-t1.json` + capture | PASS_AUTOMATED |
| SF-T2 | Toast scheduling honors priority, a max-queue cap, per-toast minimum dwell (read floor), and same-subject supersede; bursts never stack unbounded | Spam bursts queue forever or truncate the currently-read toast | E1 (scripted burst schedules) | headless spec | test | PASS_AUTOMATED |
| SF-T3 | Under RM, toast/caption behavior preserves the full information surface (static/instant equivalents; nothing dropped) | RM silently drops queued toasts | E1 + E3 (RM axis on toast fixture) | headless spec; scenario `setEnv` | test + `rows/sf-t3.json` | PASS_AUTOMATED |

## Async images / avatars

| ID | User-visible behavior | Risk | Required evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| SF-A1 | AsyncImage failure is a silent, presentable state (placeholder persists; no spinner/broken glyph); a dim/disabled treatment is expressible via SF-P2 | Failure renders a hole or error glyph in production | E1 + E3 (failure fixture capture) | headless spec; `sponsor_avatars` scenario | test + `rows/sf-a1.json` + capture | PASS_AUTOMATED |
| SF-A2 | Bounded retry option (N retries, spacing) then permanent-for-session give-up; stale completions after release/churn never resurrect content (existing contract re-proven under list churn) | Retry loops forever; stale avatar pops into a recycled row | E1 (scripted transport failures + churn) | headless spec | test | PASS_AUTOMATED |
| SF-A3 | A preload seam warms a declared identity set so debuting badges skip the placeholder flash; unstarted work is skipped on release (logical-cancel contract) | Preload becomes an unbounded global sweep | E1 (provider-level) + E2 note | headless spec | test | PASS_AUTOMATED |
| SF-A4 | The Roblox transport path is proven live: real `rbxthumb://` success, a forced failure, and a stale-release in a visible session | Transport only ever proven headless; live behavior differs | E3 (Studio scenario with real content IDs) | `sponsor_avatars` scenario in Studio | `rows/sf-a4.json` + capture | PASS_AUTOMATED |

## World-anchored / billboard

| ID | User-visible behavior | Risk | Required evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| SF-W1 | An omen-shaped display-only billboard fixture mounts over a world part via `billboard_target`, live-updates a bound ring/label, honors RM, and tears down registry-neutral; scoping predicate (render vs record) is respected by the fixture | Billboard path drifts from screen path; teardown leaks adornee/instances | E3 (visible session: geometry/lifecycle dump + capture) + E1 for the pure scoping predicate | `sponsor_billboard` scenario | test + `rows/sf-w1.json` + capture | PASS_AUTOMATED |

## Semantic feedback

| ID | User-visible behavior | Risk | Required evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| SF-F1 | Controls, drag sessions, and motion arrivals emit named semantic events (`activate`, `select`, `commit`, `land`, `reject`, `dismiss`, `arrive`…) on their causal frames through one subscribe seam; LuauUI itself plays no sound/haptic; events carry enough context (source, reason code) for the game to map | Events fire off-frame (feedback feels detached) or double-fire; taxonomy sprawls per control | E1 (event-per-cause exactness incl. causal-frame assertions) + E3 (trace during fixture interactions) | headless spec; all Sponsor scenarios log events | test + `rows/sf-f1.json` | PASS_AUTOMATED |

## Lifecycle / cross-cutting

| ID | User-visible behavior | Risk | Required evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| SF-C1 | Every Sponsor scenario mounts→runs→resets→disposes registry-neutral (core/mount/provider counters return to baseline; no orphan instances/connections) over ≥20 cycles | Motion clocks/transition scopes/toast timers leak per cycle | E1 (cycle test over fixtures) + E3 (runner reset + telemetry counters) | headless spec; scenario `reset` steps | test + `rows/sf-c1.json` | PASS_AUTOMATED |
| SF-C2 | Sponsor fixtures stay correct under preferred-text axis (largest offset): no clipping, reserved bounds match paint | Dense rows clip at Largest | E3 (fixture under preferred-text env axis; geometry + capture) | scenario `setEnv` + report | `rows/sf-c2.json` + capture | PASS_AUTOMATED |
| SF-C3 | Five-view matrix rows pass on the Sponsor gallery (compact phone portrait/landscape, tablet, desktop, ten-foot): geometry, clipping, focus visibility, honest input labels | Layout correct only on the dev viewport | E3 via existing device driver; injected input labeled | `device_matrix.luau` rows over Sponsor scenarios | `rows/matrix/*.json` + captures | PASS_AUTOMATED |
| SF-C4 | Weakest-device performance: Studio-emulated perf row for the dense Sponsor scene recorded as regression evidence; physical low-end row explicitly pending | Emulated numbers passed off as device proof | E3 (labeled) + E4 pending | perf scenario + review packet | `rows/sf-c4.json`; review-packet row | PASS_AUTOMATED (labeled studio-emulated) / PENDING_PHYSICAL |

## Reviews and gates

| ID | Behavior | Required evidence | Artifact | Status |
|---|---|---|---|---|
| SF-R1 | ui-designer pre-implementation spec pass complete; in-scope findings resolved before build | specialist report + dispositions | `ui-designer-spec.md` | PASS_AUTOMATED (ui-designer-spec.md + §10 dispositions) |
| SF-R2 | ui-designer integrated review over paired fixture captures/traces across the matrix; repeated until no automatable/specialist gap remains | specialist report(s) + fix dispositions | `ui-designer-review.md` | PASS_AUTOMATED (ui-designer-review.md: ACCEPTABLE WITH FINDINGS; 16 findings — all in-scope fixed same day, 2 vocabulary items escalated as ESC-1, evidence top-ups run or FAIL_ENVIRONMENT-recorded) |
| SF-R3 | Fresh-context phase-gate verifier (+ architecture + platform verifiers; + reactive-runtime if controller/observer semantics changed) run on raw artifacts; every requirement-affecting finding fixed | verifier JSONs, `verdict` field programmatically checked | `verifier-*.json` | PASS_AUTOMATED (two-round loop: four fresh verifiers found 1 BLOCKER + 8 MAJOR across rounds — every one fixed and pinned same-day; round-2 verdicts in verifier-*.json; full disposition map in verifier-responses.md) |
| SF-R4 | Full suite green at ratcheted floor; game suite untouched; all prior gates re-run green | `tools/test.sh`, game `run-tests.sh`, `prior-gates.txt` | `test.json`, `prior-gates.txt` | PASS_AUTOMATED (suite 2523 at the ratcheted floor; game suite 2425; prior-gates.txt 15/15 with two stated deviations) |
| SF-R5 | Docs/ADR/parity updates: public API reference, `sponsor-view-parity.md` row statuses re-marked with evidence, ADR-0022 motion/drag/collection decisions, examples updated; stale roadmap claims (aspectRatio/Path2D "missing") corrected | doc diffs cited in gate | gate.json checks | PASS_AUTOMATED (api.md sections live; sponsor-view-parity re-marked with the 2026-07-27 re-audit; ADR-0022 finalized; docs gates green) |
| SF-R6 | Physical/human rows enumerated with exact closing procedures (touch drag feel, real gamepad drag, low-end perf, feel review) — explicitly pending, never substituted | review packet | `review-packet.md` | PENDING_PHYSICAL / PENDING_HUMAN |
