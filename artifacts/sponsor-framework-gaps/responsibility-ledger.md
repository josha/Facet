# Sponsor framework gaps — responsibility ledger

**Date:** 2026-07-27
**Stage:** roadmap Step 5 (`docs/plans/luauui-consolidated-roadmap.md` §Step 5), gate `sponsor-framework-gaps`
**Rule:** every Sponsor-motivated need is assigned exactly one owner before coding. LuauUI
owns reusable mechanism; RascalRally owns policy/content. No Sponsor fixture may carry a
local workaround for a framework-owned row. A need that turns out to require a material
unresolved architecture choice is escalated, not hidden.

Audit basis: fresh 2026-07-27 re-audit of `docs/reference/sponsor-view-parity.md` rows
against `src/` at v0.7.0 (suite 2075 green). Many 2026-07-22 rows are already closed:
native ScrollView (A1), Path2D ring/needle (A4/B3), aspectRatio (B6), reactive style
props (A6), adaptive layout (A7), preferred-text single application (A10), four-edge
safe areas (R23), touch-gesture normalize/arbiter, UIDragDetector adapter,
`newDragSession`, AsyncImage + PreloadAsync transport, selection bridge, teardown
soundness, rich-skinning v2. Those need no new ownership decision; the table covers
what remains.

## LuauUI-owned (mechanism) — closed by this stage

| # | Need (Sponsor evidence) | Owner decision | Closing acceptance rows |
|---|---|---|---|
| RL-1 | Interruptible spring motion with named classes, velocity seeding, settle/arrival events (`UI_SPEC_sponsor_motion.md`; legacy `Shared.Spring`, `SponsorMotion`) | LuauUI motion authority: solver-safe value animation, class registry, injectable clock. Class *table contents* ship as framework defaults; a game may register its own classes. | SF-M1..M3, SF-M7, SF-M8 |
| RL-2 | Choreographed/timed sequences + interruption (celebration beats, countdowns; 50× `task.delay` in legacy) | LuauUI timeline/ticker with injectable time; interruption/skip semantics are framework contracts. The *content* of any authored sequence stays game-side. | SF-M4 |
| RL-3 | Reduced-motion equivalents that preserve information (motion spec invariant; M12 R1) | LuauUI: RM substitution (instant/fade) is part of every motion/transition/toast contract; "RM information surface ≥ animated path" is a framework invariant. | SF-M5, SF-T3 |
| RL-4 | Structural enter/exit transitions (captions, toasts, GO! scrim, results choreography) | LuauUI: `When`/`ForEach`/present surfaces gain transition contracts (interruptible, RM-aware). | SF-M6 |
| RL-5 | Live-target flights (card fly-home/commit chasing a moving row) | LuauUI: motion targets accept a live-readable position re-read per frame; arrival = perceptual radius + settle fallback, emitting a causal event. | SF-M2, SF-M3 |
| RL-6 | One list that windows + selects + reorders + accepts drops with stable identity under live churn (racer list) | LuauUI unified collection substrate (fold reorder/select/drop into the virtualized construct). | SF-L1, SF-L3 |
| RL-7 | Drag-to-edge autoscroll (band/dwell/ramp/speed; per-frame hover re-resolve) | LuauUI: autoscroll is a scroll-host + drag-session mechanism with framework defaults and tunable options; numeric defaults follow the ratified spec ranges. | SF-L2 |
| RL-8 | Cross-container drag/drop as public API (payload, legality, enter/leave, predicted verdict, cancel, snap-back) | LuauUI: `draggable`/drop-target blueprint contract over `newDragSession` + `UIDragDetector`/Grip. Legality *rules* (which drop is legal and why) stay game predicates supplied through the seam. | SF-D1, SF-D5 |
| RL-9 | Release-velocity tracking and handoff; zero-seed for non-gestural cancels | LuauUI velocity tracker (rolling window) feeding motion; same path for all input schemes. | SF-D2 |
| RL-10 | Press→drag promotion thresholds per input class (6 px mouse / 14 px touch; tap preserved under threshold) | LuauUI shared interaction tokens (no per-consumer magic numbers). | SF-D3 |
| RL-11 | Non-pointer drag alternative (gamepad/keyboard arm→navigate→commit through the same session/legality model) | LuauUI: every verb reaches every input scheme; the alternative paradigm is a framework contract, not per-game code. | SF-D4 |
| RL-12 | Continuous per-node color (sponsor hue, energy wash) that a closed selector set cannot express | LuauUI: authority-separated continuous color binding on the binding channel; finite-state color stays native-sheet-owned (already shipped). | SF-P1 |
| RL-13 | Image tint + scale mode on the authored surface (avatar dim, icon tint) | LuauUI `Image` props with declared authority vs native sheet. | SF-P2 |
| RL-14 | Author-facing stroke/border modifier (row stroke pulse, ring stroke) | LuauUI `UI.stroke` modifier, reactive. | SF-P3 |
| RL-15 | Paint-order override (drag ghost above all, toast above list) | LuauUI `zIndex` override honored by the deterministic paint walk. | SF-P4 |
| RL-16 | Fractional-of-parent positioning + keyed live marker overlay (minimap dots/name tags) | LuauUI: Anchor scale offsets + marker composition from existing keyed `ForEach`. Projection *math* (world→u,v) stays game code. | SF-K1, SF-K2 |
| RL-17 | Transient toast/banner surface (toast strip, lower-third captions, ribbons) | LuauUI `presentToast`: input-transparent, self-retiring, stacked, priority + queue cap + min-dwell + supersede. Copy/priority *values* per message are game data. | SF-T1..T3 |
| RL-18 | Semantic interaction feedback events (haptic/sound beats fire on causal frames) | LuauUI emits named semantic events (activate, select, commit, land, reject, dismiss…) from controls/motion/drag; it never plays a sound or haptic. | SF-F1 |
| RL-19 | Async avatar completeness: dim state, bounded retry, preload-imminent-set, silent presentable failure | LuauUI resource/AsyncImage options (mechanism + defaults); retry counts/timing chosen per call site. | SF-A1..A4 |
| RL-20 | World-anchored omen surface lifecycle (display-only billboard over a kart) | LuauUI: existing `billboard_target` verified with a Sponsor-shaped display-only fixture (mount/update/RM/teardown). Pointer capture into billboards stays out of scope (ADR-0009 riders). | SF-W1 |
| RL-21 | Dynamic focus-skip (ineligible rows skipped while a card is armed; the armed card's own target never loses focus mid-interaction) | LuauUI focus graph: per-node focusable predicate with an active-interaction exemption. Which rows are ineligible is game state. | SF-L3 |
| RL-22 | Teardown/churn cleanliness of all the above under repeated mount/reset | LuauUI (registry-neutral disposal is a framework invariant). | SF-C1 |

## RascalRally-owned (policy/content) — proven expressible by fixtures, not absorbed

| # | Need | Why it stays game-side | Fixture proof |
|---|---|---|---|
| RG-1 | Row-state 4-tier precedence (transient verdict > terminal > contextual > default), tier meanings, channel treatments | Tier semantics/meanings are game rules. LuauUI already expresses the mechanism (memos + app-state tags + reactive style props + SF-P1 + RL-21). | Sponsor list fixture drives all four tiers through public API only |
| RG-2 | Legality rules and block-reason codes → glyph + toast copy | Authority/fairness + copy. The seam (predicate in, verdict + reason code out; keyed toast in) is framework; the table contents are game. | legal/illegal drop fixture uses a fixture-local reason table |
| RG-3 | Family hues, sponsor palette, "badge=WHO / color=WHAT" invariants | Creative identity. Framework supplies tokens/roles + continuous color seam. | fixtures use neutral Studio tokens + one continuous-hue demo value |
| RG-4 | Haptic/sound asset choice, mix, timing policy; particle/confetti content | Content + device policy. Framework only emits SF-F1 events. | fixture logs emitted events; plays nothing |
| RG-5 | Camera work, world→minimap projection math, kart poses | World simulation. Framework consumes projected fractions (SF-K2). | marker fixture feeds synthetic u,v signals |
| RG-6 | Copy/localization resolution | Game localization system. `env.locale` consumer work is a recorded rider, not Step 5 scope. | fixtures accept resolved strings |
| RG-7 | Optimistic provisional-record pattern (pending pill, server overwrite, rejection reap) | Game use of the existing replication mutation lifecycle; no new framework construct needed. | (Step 6 concern; noted for the parity matrix) |
| RG-8 | Sprite-sheet ring rendering variant | A game presentation optimization; the reusable ring is `UI.Path` (shipped). Framework adds nothing. | ring fixture uses `UI.Path` |
| RG-9 | Momentum projection for flick-commit | Deliberately rejected by the ratified motion spec for dense moving targets; positional resolve chosen. Velocity handoff (RL-9) still ships; a projection helper is NOT built this stage (YAGNI until a consumer exists). | recorded as an intentional non-goal |

## Escalation register

Any need that cannot be closed under the ownership above without a material
unresolved architecture choice is added here with a decision packet instead of a
workaround.

**ESC-1 (2026-07-27, from ui-designer review R2-F6 residual + fix-round decision
packet): interactive-state roles are missing from the AUTHORED surface/content
vocabulary.** Three treatments in the designer's §4.2 state table are honestly
inexpressible through public authoring today: `controlSelected` as an authored
surface (the theme ROLE exists; the `Box.surface` enum does not carry it),
selected content stepping to `contentStrong`, and a disabled-opacity treatment
for ineligible-but-inspectable rows (`enabled=false` is wrong — those rows must
still activate to explain themselves). Working alternatives shipped this stage:
the unified list's native `selected` tag paints controls correctly, and verdict
washes ride `tint` role-blends. The gap is a THEME-VOCABULARY extension (schema +
sheet rules + all nine reference packages), not a Sponsor fixture need — routed
to Step 5.5/6 with the recommendation: extend `surface`/`role` with the
interactive-state entries rather than widening `tint` into a state channel
(the tint schema's own rule: a closed-set state is never a continuous color).

**ESC-2 (2026-07-27, platform verifier PLAT-4 residual): authored
`onPointerDown/Move/Up` handlers and the presenter's zone-A test still receive
layout-space rects (`rectOf`) while drag hit-tests now use presentation-aware
`screenRectOf`.** A slider dragged DURING a live enter/exit slide would compute
against the solved rect, offset by the slide. Deliberate this stage (changing
`rectOf`'s meaning under existing consumers was out of bounds); no current
consumer drags mid-slide. Decision owed: hand pointer-zone callbacks
`screenRectOf`, with the existing-consumer sweep that requires. Round-2 platform
review enumerated the full consumer set: authored `onPointerDown/Move/Up`
handlers, the presenter's zone-A test, AND the presenter's `syncGeometry` feed
that Slider's track math reads (api.md's slider wording overstates until this
closes — P2-1).

> **PARTIALLY CLOSED 2026-07-29 — forced by a device report, not by the decision
> packet.** iPhone 15 Pro, gallery example 02 under Pixel Quest: "when I go to edit
> mode and pick up a row, it doesn't always appear under my finger — the picked up
> chip moves up as I scroll down." The deferral weighed only the PRESENTATION half
> of the shift ("no current consumer drags mid-slide") and missed the SCROLL half,
> which a SHIPPED example lives in: example 02 makes the page the scroller and the
> Table a block, so the table root's solved rect is canvas-space while `pos` is
> window-space, and on touch the same gesture that drags the ≡ handle also pans the
> page. Measured drift = the page's scroll offset exactly, on the ghost chip, the
> drop line AND the committed slot.
>
> Landed: `renderer` now hands authored `onPointerDown/Move/Up` the `screenRectOf`
> lookup (the consumer sweep the entry asked for — Table's resize math is
> difference-only and Rating's star math wanted window space already), and Table's
> reorder drag re-reads its root/body rects on every move and on the drop instead of
> snapshotting them at pickup (a live lookup in the wrong space would still have
> drifted, and a right-space rect read once would still have gone stale). Proof:
> three new rows in `tests/table_input.spec.luau` §5, both halves mutation-checked
> independently; suite 2571 -> 2574.
>
> STILL OPEN: the presenter's zone-A outside-tap test and the
> `syncGeometry`/`onGeometry` feed that Slider's track math reads both still take
> solved rects. api.md's "Two rect reads" section now states that residual instead
> of overstating (P2-1 downgraded, not closed). Physical-device re-drive of example
> 02 is owed — the Studio session available at fix time reported a 1x1 viewport
> (FAIL_ENVIRONMENT, `studio-viewport-1x1-instrument-trap`).

## Riders carried (recorded, not Step 5 scope)

- `preferredTextOffset` placeholder values sweep (`src/client/roblox_env.luau:98-100`).
- `topbarInset` and `env.locale` have zero consumers (silent gaps; flag to director).
- XP-S4 notched-device pixel re-drive; NS-P1/P2 + XP-P1..P4 physical rows.
- Gallery runner `reset()` leak fix has no automated regression (Studio-dependent).
- VirtualList variable row heights (deferred §17 gate) — Step 5 keeps fixed heights.
