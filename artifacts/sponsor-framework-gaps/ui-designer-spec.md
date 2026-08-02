# UI-Designer pre-implementation spec — sponsor-framework-gaps (roadmap Step 5)

Status: **DELIVERED for SF-R1** · Author: UI Designer specialist · 2026-07-27
Binding inputs: `responsibility-ledger.md` (ownership — binding), `acceptance-ledger.md`
(SF-* rows this spec makes buildable), `GameStudio/specialists/UI_DESIGNER.md`
(role charter, "Designing for LuauUI"), `GameStudio/specialists/APPLE_UI_MOTION_SKILL.md`
(motion doctrine, generalized here), and the four ratified RascalRally specs
(`UI_SPEC_sponsor_motion.md`, `UI_SPEC_racerlist_autoscroll.md`,
`UI_SPEC_chaos_row_states.md`, `UI_SPEC_avatar_badges.md`) — consumed **only** as the
source of framework default numbers and interaction shapes, never as game policy.

**Reading rules for this document (binding on the build):**

1. Every name in this spec is a public LuauUI concept. Where the concept does not
   exist yet it is marked **NEW CONTRACT** — that is the deliverable of Step 5, and no
   fixture may substitute a local workaround for it (responsibility-ledger rule).
2. Every number is a **framework default with a tunable range** `[lo–hi]`. Defaults
   sourced from a ratified RascalRally spec are cited `(ratified: <spec> §n)`. Tuning
   inside the range does not re-gate; leaving the range does.
3. Colors are token roles from the active style (fixtures run under **Studio
   Neutral**): `surface`, `surfaceStrong`, `content`, `contentStrong`,
   `contentSecondary`, `accent`, `onAccent`, `danger`, `onDanger`, `control`,
   `controlHover`, `controlPressed`, `controlSelected`, `hairline`. Space steps
   `xs–xl`; type ramp `caption`/`label`/`body`/`heading`/`title`; radii
   `control`/`panel`/`pill`; shadows `raised`/`overlay`; motion tokens
   `fast` (0.12 s) / `normal` (0.2 s). A literal px or hex in a fixture is a defect
   except where this spec explicitly declares the value a **new framework default**
   (those live in the framework's token/option tables, not in fixture code).
4. Input is named as **actions** — Activate / Cancel / Navigate / Adjust — never keys.
5. Fixture content is placeholder-neutral: `"Row 01"…"Row 20"`, `"Card A/B/C"`,
   glyph-free shapes, Studio Neutral hues only. No RascalRally copy, no
   family-hue meanings, no sounds, no game rules. One deliberately continuous hue
   demo value exists (§6.1) because SF-P1 requires proving continuous color; it is
   labeled a demo value, not an identity system.

## 0. Invariants (declared up front; every section composes with these)

- **I-1 Interruptible always.** Anything mid-motion accepts a new target on any frame
  and continues from its current value **and velocity**. No input lockouts during
  transitions; no "wait for the animation" guards anywhere in a contract.
- **I-2 Overshoot is earned.** Exactly one motion class (`reward`, §1.1) is
  under-damped. Liveliness everywhere else comes from inherited gesture velocity,
  never from decorative bounce.
- **I-3 Flights chase live targets.** A motion target may be a live-readable that is
  re-read every frame. Capturing a pixel at launch is a contract violation, not a
  tuning choice.
- **I-4 Reduced motion = information parity.** This is an invariant, not a
  preference. Every motion, transition, toast, and timer contract carries a named RM
  equivalent that preserves the full information surface, terminal states, and
  semantic events. "Skip the animation" that deletes information is a defect
  (SF-M5, SF-T3).
- **I-5 One meaning per visual channel; color is never the sole signal.** Every state
  set in this spec is multi-channel (fill + stroke/form + glyph/position + text).
  The autoscroll affordance uses only the **neutral channel**
  (`contentSecondary`) — verdict channels (`accent` = legal, `danger` = illegal)
  never leak onto it.
- **I-6 Presentation state never replicates.** Focus, hover, scroll, animation
  progress, drag sessions, and toast queues are client-local. Fixtures drive them
  with local signals only.
- **I-7 Every verb reaches every input scheme.** Pointer drag ⇔ touch drag ⇔
  non-pointer arm→navigate→commit are one session and one legality model (SF-D4).
  A cancel affordance exists on every scheme (§5.5).
- **I-8 Accessibility floors.** 44 px effective target floor on every interactive
  element (display-class-resolved); the 4.5:1 contrast gate runs at token compile;
  each fixture states its text-scaling reflow behavior (§8, per scenario); markers
  and rings that fall below floors are declared **non-interactive** (§6.4).
- **I-9 No silent states.** Every rejection, failure, and ineligibility has an
  on-screen expression at the point of action: illegal drops present a verdict and a
  reject return; failed avatars present a complete fallback; ineligible rows read
  dimmed *and* stay inspectable.

---

## 1. Motion vocabulary (SF-M1, SF-M2, SF-M3, SF-M5, SF-M7, SF-M8)

### 1.1 Named motion classes — **NEW CONTRACT** `LuauUI.motion`

A **motion class** is a named pair `{ dampingRatio, response }` in a framework
registry. The four built-ins generalize the ratified RascalRally set
(ratified: sponsor_motion §1) under framework-neutral names:

| Class | ζ (damping) | Response | Owns (the shape, not the game meaning) |
|---|---|---|---|
| `"container"` | 1.0 | 0.35 s | Large surfaces materializing/minimizing: panels, sheets, split-view regions. Pairs with a proportional scrim/fade companion. |
| `"object"` | 1.0 | 0.28 s | Small manipulable objects: drag proxies, flights between slots, pickup scale, chips. Critically damped so a gentle set-down never bounces, while a seeded toss visibly carries. |
| `"reward"` | 0.7 | 0.18 s | The one earned-overshoot class: arrival pops, celebration accents. Non-gestural by definition (I-2). |
| `"decay"` | 1.0 | 0.5 s | Scalar feedback decays: energy washes, affordance fades, attention that must die out on its own. Attack is a cut (set instantly), decay is the spring. |

- All four are **tunable ±30 % without re-gating** (ratified: sponsor_motion §1).
- A game may **register additional classes** (`motion.register(name, {ζ, response})`);
  the registry is strict-authoring: an unknown class name at build time is an error
  with a did-you-mean, never a silent fallback.
- **A raw `{ζ, response}` literal at a call site is refused.** Classes are the only
  currency (the sponsor spec's Invariant 3, promoted to a framework rule).

**What the designer declares vs what the framework decides:**

| Designer declares | Framework decides |
|---|---|
| The class name per animated value | Solver math, integration, dt clamping/substepping |
| The target (static value or live-readable, §1.3) | Per-frame re-read scheduling, idle sleep (resting spring = zero per-frame cost, SF-M8) |
| The velocity seed source (a tracker handle, or none) | Velocity blending on re-target (never hard-cut) |
| Arrival semantics wanted (`arrive` event, radius override) | Arrival detection (radius vs settle fallback, §1.4), exactly-once firing |
| The RM equivalent *form* when the default is wrong (§1.5) | RM substitution mechanics, event/terminal-state parity |
| Nothing about clocks | Injectable clock; headless determinism (SF-M1/M4 evidence) |

### 1.2 Interruption and velocity handoff

- `retarget(value)` on any frame continues from current position **and** current
  velocity (SF-M1). There is no "restart" verb.
- A gestural release seeds the motion with the release velocity from the shared
  **velocity tracker** (**NEW CONTRACT**, §5.3): a rolling ~100 ms / ~5-sample
  window yielding px/s (ratified: sponsor_motion §1). Non-gestural starts
  (Cancel action, timeline beats) seed **zero** — same path, zero seed (SF-D2).
- 2D motion is two independent scalar springs (X, Y); the contract exposes a paired
  form so consumers never hand-compose axes wrong.

### 1.3 Live-target chase

- A motion target may be `function() -> number` (or a Signal) **re-read every
  frame** (SF-M2, I-3). Intended for flights toward list rows that re-sort
  mid-flight, slots that re-layout, and focus that moves.
- If the live target leaves the visible region of its scroll host, the chased value
  **clamps to the host's viewport rect** (generalized from ratified:
  sponsor_motion §4) — the flight visibly parks at the edge nearest the true target
  rather than exiting the clip.
- If the live target **vanishes** (row unmounted), the motion falls back to the last
  read value and resolves by settle (§1.4). The consumer receives the arrival event
  with `targetLost = true` context so it can present the honest outcome (I-9).

### 1.4 Arrival — the perceptual radius

- **Arrival fires on the frame the moving value enters the perceptual radius of the
  live target: default 4 px [2–8]** (framework default; ratified feel work found
  settle-epsilon arrival trails perceived landing by ~0.7 s — SF-M3 risk column).
- Settle (position within solver epsilon AND velocity ≈ 0) is the **fallback**, used
  when the target vanished or the radius never trips (a chase that never catches a
  fast mover ends at settle-on-last-read).
- The semantic `arrive` event (§7) fires **exactly once, on the causal frame**, with
  `{ how = "radius" | "settle", targetLost }`.

### 1.5 Reduced-motion equivalents (SF-M5; I-4)

Per class, the framework substitutes; the designer may override the *form* per
declaration but can never opt out of parity:

| Class | RM default |
|---|---|
| `container` | Cross-fade `fast` [0.1–0.2 s]; no scale, no slide. |
| `object` | **Instant placement** at the terminal value + fade `fast` at the destination (a returning object visibly re-fills its origin slot — "it came back" stays explicit). |
| `reward` | Instant placement, no overshoot (ζ forced to 1.0 territory = no spring at all). |
| `decay` | The scalar sets instantly and **clears at decay-end as a step** — the information (hit happened, when it ended) is preserved; nothing pulses. |

- **Informational timers still deplete under RM** — continuously-depleting displays
  (rings, bars) adopt the **`stepped` RM policy** (**NEW CONTRACT**): value updates
  quantize to a coarse step (default 250 ms [100–500]) instead of sweeping
  per-frame; the display still reaches its terminal state at the same wall-clock
  moment (generalized from ratified: chaos_row_states §4 reduced-motion).
- RM paths emit the **same semantic events and terminal states** as the animated
  paths — this is the E1 evidence shape for SF-M5.

### 1.6 Timeline / choreographed sequences (SF-M4) — **NEW CONTRACT** `motion.timeline`

- A timeline is an ordered list of **beats**; each beat declares a duration (motion
  token or seconds) or a motion-class-driven value, and a terminal state.
- Runs on the injectable framework clock (headless-deterministic).
- **Interrupt** at any frame → the timeline resolves every remaining beat to its
  terminal state on that frame ("skip = jump to end state, never half-painted").
- **Skip** is the same operation invoked deliberately (a player action may bind to
  it — e.g. Activate on a celebration surface).
- Beat boundaries are the causal frames for that beat's semantic events; interrupt
  fires each remaining beat's terminal event once, in order, on the interrupt frame.
- RM: beats with informational content collapse to their stepped/instant equivalents
  but **keep their relative order and their events**; purely decorative beats may be
  dropped only if they carry zero information (the designer marks a beat
  `decorative = true` to permit this — unmarked beats are never dropped).
- Authored beat *content* (what a celebration says/shows) stays game-side (RL-2);
  the fixture (§8.2) uses neutral placeholder beats.

### 1.7 Authority (SF-M7)

Motion writes **presentation-channel** properties only (position/scale offsets,
transparency, the continuous-paint binding channel of §6.1). It never writes
solver-owned geometry or native-sheet-owned finite-state paint. The existing
authority audit must stay clean while motion runs — this is a hard acceptance
criterion, not guidance.

### 1.8 Density floor (SF-M8)

≥20 concurrent springs + one running timeline stay inside the recorded perf-scene
budget; a settled spring costs zero per-frame work (no connection churn, no
allocation). The fixture hook is §8.1's `stress` step; the number lives in the
bench scene, not in this spec.

---

## 2. Structural transitions (SF-M6) — **NEW CONTRACT** `transition` on `When` / `ForEach` rows / presented surfaces

### 2.1 The vocabulary

A structural region or presented surface may declare:

```
transition = {
  enter = <form>,        -- "fade" | "slide" | "materialize" | "instant"
  exit  = <form>?,       -- default: the symmetric reverse of enter (I-1/Apple §7)
  duration = <motion token>?,  -- "fast" | "normal"; default "normal"
}
```

| Form | Enter | Exit (symmetric default) |
|---|---|---|
| `fade` | transparency 1 → 0 over the token duration | 0 → 1, same duration |
| `slide` | from the nearest declared edge (`from = "top"|"bottom"|"leading"|"trailing"`, required with this form); travel = the surface's own extent + safe-area inset; driven by `container` class | back out the same edge (I-1: "if it disappears one way, it emerges from where it came") |
| `materialize` | scale 0.96 → 1.0 (**[0.94–0.98]**, ratified: sponsor_motion §2/§8) on the surface's presentation scale + fade, together, `container` class | mirror: scale to 0.96 + fade out |
| `instant` | hard place | hard remove |

- **Asymmetric exits are legal but must be declared** (`exit = "instant"`), for the
  "the world owns the next frame" boundary (ratified: sponsor_motion §8's deliberate
  asymmetry). Undeclared asymmetry does not exist.
- **Re-enter mid-exit reverses smoothly** from the current value and velocity
  (SF-M6): the same spring re-targets; there is no finish-then-reopen.
- **Unmount completes only after exit, with a hard cap: 500 ms [250–1000]**
  (framework default — SF-M6's leak guard). At the cap the node hard-unmounts and
  the scope disposes; disposal counts are the E1 evidence.
- `ForEach` rows: enter/exit apply per keyed row (a departing row exits in place;
  siblings re-arrange under the collection's reorder motion, §4.4 — two different
  contracts, deliberately).
- RM: `slide` and `materialize` become `fade` at `fast`; `fade` stays; `instant`
  stays. Exit caps unchanged.

### 2.2 What the designer declares vs the framework decides

Designer: the form, edge, duration token, and any asymmetric exit. Framework:
interruption/reversal mechanics, scope lifetime, cap enforcement, RM substitution,
event parity.

---

## 3. Toast / transient surface (SF-T1, SF-T2, SF-T3) — **NEW CONTRACT** `presenter.presentToast`

### 3.1 Contract shape

```
presenter.presentToast(blueprint, {
  edge = "top" | "bottom",        -- default "top"
  priority = <number>,            -- default 0; higher runs first in the queue
  duration = <seconds>,           -- default 4 [2.5–8]
  readFloor = <seconds>,          -- default 1.5 [1–3]
  subject = <string>?,            -- supersede key (same-subject replacement)
}) -> handle { dismiss() }
```

### 3.2 Behavior (all framework-owned; copy/priority *values* are game data — RL-17)

- **Position policy:** toasts stack from the declared safe-area edge inward, gap
  `s`, newest nearest the edge; max width = min(90 % of the screen's content width,
  the `regular` breakpoint width); centered horizontally. Each toast is a
  `surfaceStrong` Box, radius `panel`, shadow `overlay`, padding `m`, content
  `body`/`contentStrong` per the fixture's tree.
- **Max simultaneous visible: 3 [1–4].** Excess waits in the queue.
- **Queue cap: 8 [4–16]**, priority-ordered, FIFO within a priority. At cap, the
  lowest-priority queued (never a showing) toast is dropped — and the drop emits a
  `dismiss` event with `reason = "capacity"` so nothing vanishes untraceably (I-9).
- **Read floor:** a showing toast is immune to replacement/supersession until its
  `readFloor` elapses; priority orders the *queue* but never truncates a showing
  toast's floor.
- **Supersede:** a new toast with the same `subject` replaces its queued
  predecessor immediately, or replaces a showing one the moment its read floor is
  met (content swaps in place — no exit/enter churn for a same-subject update).
- **Input transparency:** the toast layer never takes focus, never joins any
  navigation group, and passes all input through to the surfaces beneath (SF-T1).
  Toasts are display-only in Step 5; an *interactive* toast is an explicit non-goal
  (recorded §9-F14).
- **Enter/exit:** the §2 transition contract — default `slide` from its edge +
  fade, `normal`; exit symmetric. Retirement = duration elapsed or `dismiss()`.
- **Layering:** above the base screen, **below** the drag-proxy layer and modals
  (§6.3's documented order).
- **RM (SF-T3): static append/instant swap.** Enter/exit become instant; stacking,
  queue, read floor, durations, supersede, and every queued toast's eventual display
  are **unchanged** — nothing is dropped that the animated path would have shown.

---

## 4. Unified collection — the racer-list shape (SF-L1, SF-L2, SF-L3)

### 4.1 The construct — **NEW CONTRACT**: `newVirtualList` gains unified options

One public construct (the existing `newVirtualList`, extended — RL-6: fold into the
virtualized construct, not a second list) that simultaneously:

- **windows** long content (visible-rows-only build, fixed row heights this stage —
  the variable-height rider stays deferred);
- **selects** (single selection this stage; `selected` Signal in, `select` events
  out);
- **reorders** (order is *owner state*: the list renders the order it is handed and
  animates the difference, §4.4; an interactive reorder emits a request — the
  mutation lifecycle applies, pending never means success);
- **accepts drops** (each row is a drop target in the §5 session; targets stay
  valid for off-screen rows via the session's retarget-under-scroll path);
- keeps **mounted identity and focus** across live order churn (a 250 ms re-sort
  while dragging must not remount rows, reset selection, blink images, or move
  focus — SF-L1).

### 4.2 Row visual state sets (multi-channel, never color-only — I-5)

Neutral Studio treatments; precedence top-first (generalized shape of the ratified
precedence — transient verdict > terminal > contextual > default — whose *meanings*
stay game-side, RG-1):

| State | Fill | Stroke (§6.2) | Content | Extra channel |
|---|---|---|---|---|
| **Drop verdict: legal** (hovered by a legal payload) | `controlHover` | `accent`, 2 px | unchanged | leading verdict glyph slot shows the affirmative glyph (theme icon; fallback glyph if none) |
| **Drop verdict: illegal** | `control` | `danger`, 2 px | unchanged | verdict glyph slot shows the blocked glyph; row does NOT dim (the verdict is about the payload, not the row) |
| **Ineligible** (live predicate false, §4.3) | `surface` at raised transparency (the theme's disabled treatment) | none | `contentSecondary`, disabled opacity | still Activate-inspectable (I-9) |
| **Selected** | `controlSelected` | `hairline` | `contentStrong` | leading `accent` edge bar, `xs` wide (form channel, not hue-only) |
| **Focused** | (state-independent) theme `chrome.focus` ring; ten-foot strengthening applies | | | |
| **Default** | `control` | none | `content` name, `contentSecondary` secondary | |

Verdict > ineligible > selected > default for the paint channels they share; focus
composes over all of them and never recolors content.

### 4.3 Focus-skip with the active-interaction exemption (SF-L3)

- **NEW CONTRACT:** per-row `focusable = <live predicate>` on the collection (and
  generally per-node on the focus graph). Navigation skips false rows; wrap/edge
  rules are unchanged.
- **Exemption (binding):** the row that is the **current target of an in-progress
  interaction** (drag hover target, non-pointer armed target) never loses
  focusability mid-interaction, even if its own predicate flips false — the flip
  takes effect when the interaction ends (generalized from ratified:
  chaos_row_states §1.2's "sacred" rule). An illegal commit on such a row rejects
  (§5.4) rather than the row vanishing from under the gesture.
- Ineligible rows remain pointer/touch-tappable in every state: Activate on an
  ineligible row is the game's "explain why" hook (fixture: flips an inspection
  label). Skipped-for-navigation never means dead-to-inspection.

### 4.4 Live churn — what may move, what must not blink (SF-L1)

- **May move:** row *positions*, under the collection's declared
  `reorderMotion = <motion class> | "instant"` (default `"object"`; RM instant).
  Rows slide to their new slots; they never cross-fade.
- **Must never blink:** mounted row identity (no unmount/remount on re-sort),
  async images inside rows (no placeholder flash on move — SF-A2's churn clause),
  selection state, focus position, the in-progress drag's hover verdict, scroll
  offset (beyond what reorder math requires).
- The drop session's target rects **retarget on the same frame** as any
  reorder/scroll so hover verdicts never trail (§5.2, SF-L2's per-frame re-resolve
  generalized).

### 4.5 Drag-to-edge autoscroll (SF-L2) — **NEW CONTRACT**: scroll-host + drag-session mechanism

Framework defaults (ratified: racerlist_autoscroll, cited by §):

- **Bands:** two full-width bands at the scroll viewport's top/bottom edges; height
  **40 px** (44 px when the size class is compact portrait) **[32–52]** (§1).
  Membership = the **pointer point**, never the proxy bounds (§1 — band and drop
  verdict must share one coordinate).
- **Dwell:** 300 ms **[250–400]** continuous presence in one band before scrolling
  starts; timer resets on leaving both bands or crossing bands; in-band jitter never
  resets (§2).
- **Speed:** linear in penetration depth, `v(p) = 100 + 400·p` px/s —
  `V_MIN = 100 [80–140]`, `V_MAX = 500 [400–650]` (§3).
- **Ramp:** effective velocity eases 0 → v(p) over **150 ms** ease-out at arm; ~80 ms
  ease-out to 0 on disarm (§3, §4).
- **Clamp:** hard clamp at canvas ends, no bounce, stays armed (§4).
- **Hover re-resolve every frame while scrolling** — the row-under-pointer verdict
  updates in the same frame as each scroll step (§4; SF-L2's correctness core).
- **Never arms:** on short content (no scrollable range → bands inert, no
  affordance — honest affordances only) or on a fast flick-through (dwell
  guarantees this without a special case) (§5).
- **Input schemes:** pointer and touch take the full mechanism; **non-pointer has no
  autoscroll path** — focus-follows-navigation already scrolls the host (§7).

**Affordance states (the neutral-channel rule, I-5):** one chevron glyph pinned
centered to the active edge, `contentSecondary` tint, size = the theme's small icon
size **[20–28 px]**, above rows / below the drag proxy:

| State | Presentation |
|---|---|
| **hidden** | default; also whenever that edge is at its canvas end (no affordance for a scroll that can't happen) |
| **armed** (dwell counting) | 40 % opacity, static |
| **active** (scrolling) | 100 % opacity + gentle opacity pulse at 0.8 Hz |

Fades 120 ms between states; RM: pulse becomes static 100 %, the scroll motion
itself stays (it is the function, not decoration). The chevron never uses `accent`
or `danger` — those are verdict channels.

---

## 5. Drag interaction states (SF-D1…SF-D5)

### 5.1 The public seam — **NEW CONTRACT**: `draggable` / drop-target blueprint contract

A blueprint declares a **payload source** (`draggable = { payload, proxy? }`) and
**drop targets** (`dropTarget = { accepts = <game predicate>, onDrop }`), wired by
the framework over the existing `newDragSession` policy core + the native detector
path (RL-8). Legality *rules* arrive only through `accepts` / the verdict seam —
the framework never invents legality (RG-2). Enter/leave fire exactly once per
boundary; the predicted verdict is live while hovering; sessions go inert on every
terminal (drop / cancel / reject).

### 5.2 Press → promotion (SF-D3) — **NEW CONTRACT**: shared interaction tokens

- Promotion thresholds live in **one framework token table**, per input class:
  **pointer 6 px [4–8]; touch 14 px [10–18]** (ratified thresholds, cited as
  framework defaults). No consumer carries its own number.
- Below threshold, release = **tap**: Activate fires normally (taps are never
  eaten). At threshold, the press promotes to a drag session, the `pickup` event
  fires, and the proxy appears (§5.3).
- During an active session over a scroll host, target rects re-resolve every frame
  (session retarget; pairs with §4.5's re-resolve rule).

### 5.3 Proxy (ghost) presentation

- The proxy is the `draggable`'s declared `proxy` blueprint (default: a snapshot
  composite of the source — a `surfaceStrong` Box, radius `control`, shadow
  `overlay`, carrying the source's content).
- **Layer:** the proxy renders on the **drag-proxy layer** — above the base screen,
  lifted nodes, and toasts; below modals (§6.3). Within a fixture that means
  "above all" in the working sense of SF-P4.
- **Pickup scale:** 1.0 → **1.15 [1.1–1.2]** via `object` class on the proxy's
  presentation scale (ratified: sponsor_motion §3c). Grab–release–grab reverses
  smoothly through the same spring.
- **Tracking is hard 1:1** with the pointer — no spring lag on the finger, ever.
  The velocity tracker (§1.2) records the rolling window during tracking.
- RM: pickup scale is instant; tracking unchanged (tracking is the function).

### 5.4 Drop, reject, snap-back (SF-D1, SF-D5)

- **Legal drop:** session resolves via `accepts`; the `commit` event fires with the
  target id; proxy disposal/hand-off is the consumer's declared choice:
  `onCommitProxy = "destroy" | "flyToTarget"` (fly = `object`-class flight chasing
  the live target, `land` on arrival — §1.3/§1.4).
- **Illegal drop (reject):** payload proxy returns to its origin under the `object`
  class, **velocity-seeded when gestural** (the toss visibly carries home), zero
  seed otherwise; the semantic `reject` event fires **exactly once** with the
  game-supplied reason code; the origin slot visibly re-fills (I-9: the optimistic
  change visibly reverts). Rapid retry never double-fires.
- **Cancel:** same return flight, zero seed; `cancel` event with reason.
- A modal presenting mid-drag **cancels the active session** (focus trap and drag
  cannot coexist; documented, deterministic).

### 5.5 Non-pointer path — arm → navigate → commit (SF-D4)

One session, one legality model, second paradigm (I-7):

| Phase | Action | Presentation |
|---|---|---|
| **Arm** | Activate on the source | Source enters **armed**: `controlSelected` fill + `accent` 2 px stroke + the proxy appears and **travels from the source to the focused target** (`object` class, zero seed, chasing focus — ratified shape: sponsor_motion §3d). Focus moves into the target collection (initial target = first eligible row). |
| **Navigate** | Navigate | Focus moves between **eligible** targets only (§4.3 skip rules; the armed exemption protects the current target). The proxy chases the focused row live; the hovered verdict presents exactly as pointer hover (§4.2). Ineligible rows read dimmed + skipped; they are never focus-landable while armed. |
| **Commit** | Activate on a target | Same session `drop` path; legal = `commit`, illegal = `reject` + return (a row the exemption kept focusable can reject — never silently). |
| **Cancel** | Cancel | Disarm; proxy returns to source (zero seed); focus returns to the source. |

- **Focus-ring language:** the ring is the theme's `chrome.focus` treatment,
  unchanged and always visible on the current target (ten-foot strengthening
  applies). The *armed* state is carried by the source's armed presentation and the
  proxy's existence — never by restyling the focus ring (one meaning per channel).
- **Cancel affordances per scheme (I-7):** non-pointer = the Cancel action; pointer
  = release outside every target (free-area release is a cancel, presented as the
  return flight) or the Cancel action mid-drag; touch = release outside every
  target, **plus** the source slot itself always reads as a legal "put it back"
  target while dragging (an explicit, visible cancel affordance — touch has no
  Cancel key).

---

## 6. Paint extensions (SF-P1…SF-P5) and avatars (SF-A1…SF-A4)

### 6.1 Continuous color — **NEW CONTRACT**: binding-channel paint with declared authority

Two legitimate uses of continuous color, and only these (everything finite stays on
tokens/tags/native-sheet states — the shipped path):

1. **Value blends** (`blend`): a scalar binding `t ∈ [0,1]` blending **between two
   token roles** — e.g. `control → accent` driven by an energy value that a `decay`
   spring owns. Re-themable, contrast-checkable at both endpoints, the preferred
   form. This is the "energy wash" shape.
2. **Data-supplied identity color** (`direct`): an `{r,g,b}` Signal whose value IS
   game data (an identity hue). Exempt from theming by declaration; the authority
   audit records the node's paint as binding-owned; the design rule (I-5) still
   applies — identity hue may never be the *sole* carrier of any meaning.

Authority separation is explicit: a node's continuous channel is declared at build
(`paint = { channel = "fill" | "stroke" | "imageTint", ... }`); the native sheet
never fights it, the audit stays clean while it animates (SF-P1, SF-M7), and a node
without the declaration cannot be written continuously at all.

**Design rule (binding):** if the value driving a color is a member of a closed set
(hover/selected/disabled/verdict/phase), it is a **state**, and states use tokens
and tags — reaching for the continuous channel to express a state is a defect.

### 6.2 Stroke modifier — **NEW CONTRACT** `UI.stroke(bp, { role?, thickness?, transparency? })`

- Adds a reactive border to any box-like node: `role` = color token (default
  `hairline`), `thickness` px or metric name (default the theme's hairline stroke),
  `transparency` bindable (pulse via bound thickness/transparency is the intended
  idiom — SF-P3).
- Coexists with theme chrome strokes deterministically: the authored stroke is a
  distinct instance/slot from theme chrome; it never double-materializes with a
  panel's own stroke and never leaks on unmount (the chrome-coexistence test in the
  ledger row).
- Verdict strokes in this spec (§4.2) are 2 px; hairline is 1 px; both from
  theme metrics, cited here for the fixtures' expected captures.

### 6.3 Paint-order override — **NEW CONTRACT** `UI.zIndex(bp, n)` + the documented layer order

- Within its **stacking scope**, a node with `zIndex > 0` paints above all
  zero-index siblings; ties resolve by tree order; shadows keep their mandatory
  negative-z position below their node. Deterministic, headlessly walkable.
- The **documented global order** (bottom → top):
  1. base screen tree (with per-scope `zIndex` lifts inside it),
  2. toast layer (§3),
  3. drag-proxy layer (§5.3),
  4. modal scrim + modal (its own scope, its own lifts),
  5. nothing above a modal.
- Rationale recorded: the proxy tracks the finger — no transient may occlude it;
  modals cancel drags (§5.4), so the proxy never fights a modal.

### 6.4 Marker overlay — the minimap-dot shape (SF-P5; RL-16)

- **NEW CONTRACT:** `Anchor` children accept **fractional (scale) offsets**; a
  keyed `ForEach` of anchored children is the marker overlay idiom. Offset updates
  are arrange-only (no re-measure, no remount) — ≥12 live markers tracking u,v
  Signals update without blinking.
- **Visual minimums:** a marker is ≥ 8 px [6–12] at its smallest; markers are
  **declared non-interactive** (they fall below the 44 px floor by design — display
  only; a game needing tappable markers must present a separate, floored control).
  This declaration is part of the contract, not a per-fixture waiver.
- **Channel rule:** marker identity in the neutral fixture = shape + one
  `accent`-role highlight for the "tracked" marker (never hue-only, I-5). Game hue
  identity would ride §6.1 `direct` — proven by one demo marker, labeled as such.
- Projection math (world → u,v) is game code; fixtures feed synthetic signals
  (RG-5).

### 6.5 Image tint and scale mode (SF-P2)

- **NEW CONTRACT:** authored `Image` gains `tint` (token role, or a §6.1 binding)
  and `scaleMode = "fit" | "fill" | "crop" | "slice"` with declared authority vs the
  native sheet (no ownership fight with theme image rules).
- The **avatar dim treatment** is the reference consumer: dim = image toward 35 %
  transparency [25–45] + companion rim stroke transparency +0.35 (ratified:
  avatar_badges §1.3 "Dimmed"), expressed entirely through SF-P2 + §6.2 — no bespoke
  paint.

### 6.6 Async avatars (SF-A1…SF-A4; RL-19)

- **Loading:** placeholder = a complete presentable composite (fallback initial on
  `surfaceStrong` circle — the *shape*; content is game-side). Never a spinner.
- **Ready:** content fades in **0.15 s [0.1–0.25]** (ratified: avatar_badges §1.3);
  RM instant.
- **Failure is silent and presentable (I-9, SF-A1):** the placeholder persists; no
  broken-image glyph, no error state visible to the player, ever. "Silent" means
  visually — the provider state still reports `failed` for instrumentation.
- **Bounded retry:** default **3 retries, 1 s apart [counts/spacing per call
  site]** (ratified defaults), then permanent-for-session give-up.
- **Stale completions never resurrect** after release/churn (existing contract,
  re-proven under list churn — a recycled row never pops a stale face).
- **Preload seam (SF-A3):** a declared identity set warms before its debut moment;
  released-before-started work is skipped (logical cancel). Never an unbounded
  sweep.

---

## 7. Semantic feedback events (SF-F1) — **NEW CONTRACT**: one subscribe seam

- Controls, drag sessions, motion arrivals, toasts, and timelines emit **named
  semantic events on their causal frames** through one subscription seam. LuauUI
  plays no sound and no haptic — games map events to assets (RG-4).
- **Closed initial taxonomy (v1):** `activate`, `select`, `adjust`, `pickup`,
  `commit`, `reject`, `cancel`, `arrive` (generic motion arrival, §1.4), `land`
  (a drag/commit payload reaching its target — the arrival that means "delivered"),
  `dismiss` (toast/modal retirement, with reason), `supersede` (same-subject toast
  replacement). Growing this set is a contract amendment with a gate, never an
  ad-hoc addition (taxonomy sprawl is the named risk).
- Every event carries `{ source, kind, reason? , context }` sufficient for a game
  to map it without reading visuals.
- Causal-frame exactness is acceptance: the event fires on the frame the thing
  became true (the arrival frame, the commit frame, the reject frame) — never on a
  timer after it, never twice.

---

## 8. The fixture set — the Sponsor-shaped gallery scenarios

**Set chosen: the eight scenarios as dispatched — no merges.** Rationale: each
scenario's deterministic steps map 1:1 onto ledger rows with distinct evidence
drivers; merging (e.g. celebration into motion) would couple SF-M4's
interrupt-at-every-beat evidence to SF-M1's solver steps and make failed captures
ambiguous. `sponsor_markers` and `sponsor_billboard` stay separate because one
proves the screen-space Anchor overlay and the other the world-anchored render
target — different adapters, different failure modes.

**Shared conventions (all scenarios):**

- Scenario files follow the existing gallery contract: `{ title, ledgerRows,
  build(ctx) -> { screen, present, steps } }`; steps are state/action drivers (the
  runner never counterfeits hardware input; injected input is honestly labeled).
- Every scenario: mounts under Studio Neutral; runs `reset` clean over ≥20 cycles
  (SF-C1); takes the `setEnv reducedMotion` axis (SF-M5/T3) and the preferred-text
  axis at largest offset (SF-C2 — stated reflow behavior per scenario below); logs
  all §7 events to the scenario trace (SF-F1's E3).
- Size classes: `compact` (< 600) / `regular` (< 1000) / `wide`, ten-foot capped at
  `regular`. Layout branches are stated as intents on one tree — never per-device
  copies.
- **Five-view matrix (SF-C3), all scenarios:** compact-phone-portrait,
  compact-phone-landscape, tablet-landscape, desktop-standard, console-ten-foot.
  Generic WRONG for every row: clipped content, overlapping siblings, a focus ring
  off-screen or invisible, a target under the 44 px floor, text truncated where
  this spec says it reflows, or an input labeled as physical that was injected.
  Per-scenario WRONGs below.

### 8.1 `sponsor_motion` (SF-M1, SF-M2, SF-M3, SF-M5, SF-M7, SF-M8)

**Purpose:** the motion-class lab — every class visible, interruptible, seedable.

**Hierarchy:**

```
Screen (safe-area root, gap "m", padding "m")
└─ VStack
   ├─ Text "Motion lab" (heading)
   ├─ ZStack fill=1                      -- the stage
   │  ├─ Box id=StageSurface (surface)
   │  ├─ Box id=SlotA (control, radius control, size from theme control metrics)   -- top-leading via ZStack align
   │  ├─ Box id=SlotB (control, radius control)                                    -- bottom-trailing
   │  ├─ Box id=Puck  (accent, radius pill)  -- the flying object (object class)
   │  ├─ Box id=Panel (surfaceStrong, radius panel, shadow overlay)                -- the container-class surface, When-mounted
   │  └─ Box id=RewardChip (controlSelected, radius control)                       -- reward-pop subject
   ├─ Box id=WashRow (control, radius control, padding "s")                        -- decay subject: fill = blend(control→accent, t=energy)
   └─ HStack (gap "s")  -- controls
      ├─ Button "Panel"  (Activate: toggle Panel)     ├─ Button "Fly" ├─ Button "Toss"
      ├─ Button "Pop"    ├─ Button "Hit"              └─ Button "Stress"
```

**Layout intent:** compact portrait = stage above, controls wrap into two rows;
compact landscape = controls as a trailing column; regular/wide = one control row.
Ten-foot = regular density, focus strengthening visible on the buttons.

**Focus order:** the control buttons, left→right (top row first), one navigation
group. Cancel = no-op (nothing to dismiss). Initial selection: "Panel".

**Steps and what each shows:**

| Step | Shows |
|---|---|
| `openPanel` / `closePanel` | Panel materialize/mirror under `container` (§2 materialize form on a When). |
| `interruptToggle` | open→close→open inside one settle: reverses from current scale+velocity — WRONG: any restart pop or finish-then-reopen. |
| `flyToSlot` | Puck flight A→B, `object`, zero seed; `arrive` event on the radius frame (trace) — WRONG: event trailing visible landing. |
| `retargetMidFlight` | SlotB moves (scripted) mid-flight; puck chases the live rect (SF-M2) — WRONG: landing on the stale pixel. |
| `seedVelocityFly` | scripted release-velocity seed; the flight visibly carries — WRONG: a hard-cut zero-velocity start. |
| `rewardPop` | RewardChip `reward` pop — the only overshoot in the lab. |
| `hitDecay` ×2 fast | WashRow energy sets to 1 instantly, decays; a re-hit mid-decay re-sets without ratchet — WRONG: second hit dimmer than the first. |
| `stress` | ≥20 puck clones + a running timeline for the perf row (SF-M8 bench hook). |
| (env) `reducedMotion` | every step re-run: instant/fade equivalents, same trace events, same terminal states (SF-M5). |

**Preferred-text:** heading and button labels reflow (buttons grow, wrap to more
rows on compact); the stage never shrinks below its slots' floor — stage yields
height via fill weight.

**Matrix WRONG (specific):** Panel's materialize origin drifting off its resting
rect on any viewport; Puck clipped by the stage on compact landscape.

### 8.2 `sponsor_celebration` (SF-M4)

**Purpose:** the timeline contract — interruption at every boundary and mid-beat.

**Hierarchy:** Screen → VStack: Text "Sequence lab" (heading); ZStack stage with
four Beat Boxes (`control`, radius `control`) in a row (HStack inside the stage),
each with a caption Text (`caption`); HStack controls: Buttons "Run", "Interrupt",
"Skip", "Replay".

A neutral 4-beat timeline: beat 1 = Box A materializes; beat 2 = Box B flies in
(`object`); beat 3 = Box C `reward` pop; beat 4 = a `decay` wash across the stage.
Beats emit trace events at their boundaries.

**Focus order:** the four control buttons, one group. Activate on the stage while
running = Skip (the player-facing skip verb, §1.6).

**Steps:** `run` (clean sequence, deterministic under the injected clock);
`interruptAtBoundary` (scripted at each of the three boundaries — three
sub-invocations); `interruptMidBeat` (mid-beat-2: everything resolves to terminal
on that frame — WRONG: any half-flown box or half-faded wash persisting);
`skipToEnd`; `replay` (terminal → clean restart, no orphan state); env RM
(informational beats keep order + events; the wash steps).

**Preferred-text:** captions wrap to two lines; beat boxes grow with their captions
(automatic content sizing), stage scrolls never clips.

**Matrix WRONG:** any beat box overlapping another after `interruptMidBeat` on any
viewport (the half-painted state the contract forbids).

### 8.3 `sponsor_list` (SF-L1, SF-L3, SF-P1, SF-P3)

**Purpose:** the unified collection under churn, with continuous wash and stroke
pulse.

**Hierarchy:**

```
Screen (padding "m", gap "s")
└─ VStack
   ├─ Text "Collection lab" (heading)
   ├─ HStack (gap "s")
   │  ├─ Button "Churn" (toggle 250 ms re-sort)      └─ Button "Eligibility" (toggle the predicate pattern)
   ├─ unified newVirtualList fill=1                   -- 20 rows, keys "row-01".."row-20"
   │  └─ row = HStack (padding "s", gap "s"):
   │       Box swatch (controlSelected, radius pill, small)   -- identity form slot
   │       VStack: Text name (body) / Text detail (caption, contentSecondary)
   │       Spacer
   │       Box verdictGlyphSlot (icon-size)                    -- §4.2 verdict glyph
   │       Box washOverlay = blend(control→accent, t=rowEnergy)  -- SF-P1 (fill channel)
   └─ Text id=InspectLine (caption, contentSecondary)          -- "explain why" output
```

Row heights are theme-derived (target floor + padding) — the fixture declares no px
height. Selection single; `reorderMotion = "object"`.

**State sets:** exactly §4.2's table. Stroke pulse (SF-P3): a step drives one row's
`UI.stroke` transparency on a bound `decay` value — WRONG: stroke instance leaking
after the step or doubling with theme chrome.

**Focus order:** controls group above; the list is its own navigation group
(vertical axis); Navigate skips ineligible rows per §4.3; initial selection = first
row. Cancel = leave the list group (back to controls).

**Steps:** `select` (selection presents multi-channel); `startChurn`/`stopChurn`
(250 ms re-sort; identity/selection/focus/images survive — WRONG: any blink,
remount counter increment, or focus jump); `mixedEligibility` (predicate pattern:
every 3rd row ineligible; synthetic Navigate sweep shows skips, honestly labeled);
`exemption` (arm a §5.5 interaction on a row, flip its predicate false mid-arm; the
row keeps focus until disarm — WRONG: focus yanked mid-interaction); `washSweep`
(SF-P1 hue-sweep with `GetStyled` authority dump — WRONG: audit flagging the wash
channel); `strokePulse`; `inspectIneligible` (Activate on a dim row updates
InspectLine — I-9 proof).

**Preferred-text:** names reflow within rows (detail line wraps to a second line;
rows grow — fixed-height windowing still holds because heights derive from the
same text facts; if largest-offset growth exceeds the derived height, the detail
line is declared `lineLimit`-capped at 2 and ellipsizes — stated, not silent).

**Matrix WRONG:** verdict glyph slot clipped on compact portrait; skip behavior
differing between synthetic Navigate on desktop-standard and console-ten-foot rows.

### 8.4 `sponsor_drop` (SF-D1…SF-D5, SF-L2, SF-P4, SF-M2)

**Purpose:** the whole drag story — promotion, proxy, verdicts, reject, autoscroll,
non-pointer path, ghost layering.

**Hierarchy:** the §8.3 collection (12 rows, taller stage) **plus** a hand strip:

```
   ├─ (the unified list, fill=1, as §8.3 minus wash/pulse extras)
   └─ HStack id=Hand (gap "s", padding "s", surfaceStrong, radius panel)
        ├─ Box id=CardA (draggable; control, radius control, ≥44 target)
        ├─ Box id=CardB (draggable)
        └─ Box id=CardC (draggable)
```

**Layout intent:** compact portrait = hand docked bottom (thumb zone); compact
landscape = hand as a leading column; regular/wide = hand bottom with wider
gutters; ten-foot = regular density. Reflow, never squeeze: portrait is a
different stack order, not a scaled landscape.

**Legality seam (fixture-local *data*, framework mechanism):** a fixture reason
table — even rows accept CardA/B, odd rows reject CardC, etc. — supplied through
`accepts` with reason codes `"demo-blocked-1"`… (RG-2's seam proof; the table
content is placeholder).

**Focus order:** Hand group (horizontal) ↔ list group (vertical); initial
selection CardA. Non-pointer flow per §5.5; Cancel per §5.5's table.

**Steps:**

| Step | Shows |
|---|---|
| `pressUnderThreshold` | VirtualInput press-move(<6 px pointer / <14 px touch)-release → Activate fires, no session (SF-D3) — WRONG: eaten tap. |
| `promoteAndHover` | over-threshold promotion; `pickup` event; proxy at 1.15 with `overlay` shadow above **everything** incl. a summoned toast (SF-P4 capture + instance dump). |
| `legalDrop` | verdict presents `accent` multi-channel while hovering; `commit` on the causal frame; `onCommitProxy = "flyToTarget"` chases the live row (SF-M2 tie-in). |
| `illegalDrop` | `danger` verdict while hovering; on release: velocity-seeded return, exactly one `reject` with the fixture reason code; origin slot visibly re-fills (SF-D5) — WRONG: double event under rapid retry, or a zero-velocity hard-cut return. |
| `autoscrollDrive` | scripted drag into each band: dwell 300 ms → ramp → speed tracks penetration → clamp at end, still armed; chevron hidden/armed/active states; per-frame verdict trace while scrolling (SF-L2) — WRONG: verdict trailing ≥1 row at max speed; chevron shown on short content (`shortContent` sub-step swaps in a 4-row list). |
| `churnWhileDragging` | 250 ms re-sort mid-drag: hover verdict retargets same-frame; the hovered row keeps the exemption (SF-L1/L3). |
| `nonPointerFlow` | arm→navigate→commit and arm→navigate→cancel through the same session (trace proves one session object; synthetic navigation, honestly labeled; physical gamepad stays pending) (SF-D4). |
| `cancelPaths` | pointer free-area release; touch release-over-source; Cancel action — all three land the same `cancel` trace shape (I-7). |
| (env) RM | proxy pickup instant, return flights instant+fade, verdicts/events unchanged. |

**Preferred-text:** card labels use `compactLabel` forms when the hand tightens;
the hand strip grows in height before it ever clips a label.

**Matrix WRONG:** hand strip under the safe-area/home-indicator on
compact-phone-portrait; band heights not switching 40→44 on compact portrait;
proxy under any toast in the layering capture.

### 8.5 `sponsor_toast` (SF-T1, SF-T2, SF-T3, SF-M6)

**Purpose:** the transient surface and the structural-transition contract.

**Hierarchy:** Screen → VStack: Text "Toast lab" (heading); Button id=Beneath
("Press me") centered in a fill ZStack; HStack controls: Buttons "One", "Burst",
"Priority", "Supersede". Toast content blueprint: HStack (padding "m"): Box glyph
slot · VStack: Text title (`body`, `contentStrong`) / Text detail (`caption`,
`contentSecondary`).

**Focus order:** Beneath + the four controls, one group. Toasts never enter it
(SF-T1). Cancel = no-op.

**Steps:** `showOne` (enter = slide-from-top + fade under §2; retire at duration);
`inputPassthrough` (VirtualInput click **through** an active toast's rect onto
Beneath — Activate fires; focus trace untouched) — WRONG: the toast eating the
click or focus moving; `burst` (8 queued: max 3 visible, priority order, cap
drops lowest-priority queued with a `dismiss(capacity)` trace); `priorityMidFloor`
(high-priority arrival during a showing toast's read floor: queue reorders, the
showing toast finishes its floor — WRONG: truncation); `supersede` (same-subject
replaces in place, `supersede` trace, no exit/enter churn); `exitInterrupt`
(re-present the same subject mid-exit: reverses smoothly — SF-M6's re-enter);
`unmountCap` (scripted stuck exit hits the 500 ms cap; scope disposal counters
return to baseline); env RM (static append/instant swap; the full burst still
displays over time — nothing dropped, SF-T3).

**Preferred-text:** toast text wraps; a toast grows in height, never widens past
max width, never truncates the title.

**Matrix WRONG:** toasts breaching the top safe area on notched compact rows;
stacking gap collapsing on ten-foot.

### 8.6 `sponsor_avatars` (SF-A1…SF-A4, SF-P2)

**Purpose:** the async-image lifecycle and the tint/scale-mode contract.

**Hierarchy:** Screen → VStack: Text "Avatar lab" (heading); Grid (or wrapped
HStacks) of 8 avatar composites — each a ZStack: fallback circle (Box
`surfaceStrong`, radius `pill`) + Text initial (`label`) + AsyncImage (crop scale
mode) + rim via `UI.stroke` (`hairline`); HStack controls: Buttons "Load", "Fail",
"Churn", "Preload", "Dim".

**Focus order:** the control buttons only (avatars are display); one group.

**Steps:** `load` (staggered ready: 0.15 s fade-ins; RM instant); `fail` (forced
transport failure on half the set: placeholder persists, **no visible failure
mark** — WRONG: any spinner/broken glyph/hole; provider state shows `failed` in
the trace only); `retrySchedule` (scripted clock: 3 retries 1 s apart then
permanent give-up — trace); `churnStale` (release + remount rows while fetches
resolve: stale completions never paint — WRONG: a face popping into a recycled
slot); `preload` (declared set warms; debuting composite skips the placeholder
flash); `dim` (SF-P2 tint/transparency treatment + rim shift per §6.5/§6.6);
`liveTransport` (Studio-only: real `rbxthumb://` success + forced failure +
stale-release — SF-A4's E3).

**Preferred-text:** the initial scales with the type ramp inside the circle; grid
wraps to fewer columns rather than shrinking circles below the face floor
(≈28 px legibility floor, ratified: avatar_badges §1.1, cited as the display
minimum for face content).

**Matrix WRONG:** fallback initial overflowing its circle at largest text on
compact portrait; dim treatment illegible on ten-foot.

### 8.7 `sponsor_markers` (SF-P5)

**Purpose:** the keyed marker overlay on fractional Anchor offsets.

**Hierarchy:** Screen → VStack: Text "Marker lab" (heading); ZStack fill=1: Box
map surface (`surfaceStrong`, radius `panel`) + Anchor overlay → keyed ForEach of
12 markers (Box, radius `pill`, ≥8 px, `contentSecondary`; marker #1 = the
"tracked" demo: `accent` + a distinct shape (square) — shape+hue, never hue-only;
marker #12 = the §6.1 `direct` continuous-hue demo, labeled); HStack controls:
Buttons "Orbit", "Burst", "AddRemove".

**Focus order:** controls only; markers are declared non-interactive (§6.4).

**Steps:** `startOrbit` (synthetic u,v signals orbit all 12 at 60 Hz-equivalent
scripted updates; identity check: zero remounts across 1000 updates — WRONG: any
dot blink or mount-counter increment); `burst` (all 12 jump simultaneously —
arrange-only writes in the trace); `addRemove` (markers 13/14 enter, 3/4 exit via
keyed ForEach with `fade` transitions; survivors untouched); env RM (marker motion
is data, not decoration — positions still track; enter/exit fades become instant).

**Preferred-text:** heading reflows; the map surface yields no marker geometry to
text (markers are viewport-fractional).

**Matrix WRONG:** fractional positions drifting off the map box on any aspect
ratio (u,v = 0.0/1.0 corners must sit exactly on the surface's corners);
markers scaling with viewport (they must stay physical-ish sizes via theme
metrics, not grow with the map).

### 8.8 `sponsor_billboard` (SF-W1)

**Purpose:** the display-only world-anchored omen shape over `billboard_target`.

**Hierarchy (billboard root):** ZStack: `UI.Path` ring (role `accent`; a second
arc bound to a depleting fraction) + Box icon slot (theme icon or fallback glyph,
`onAccent` on an `accent` circle) + Text caption (`caption`) beneath. Mounted over
a fixture world part via `billboard_target`. Display-only: no focusables, no
pointer capture (ADR-0009 riders stay out of scope).

**Screen-side controls (companion screen mount):** Buttons "Mount", "Deplete",
"Move", "Teardown".

**Steps:** `mount` (billboard appears over the anchor; geometry/lifecycle dump);
`deplete` (the arc empties on a scripted clock; under RM the `stepped` policy
applies and the ring reaches empty at the same wall-clock moment — §1.5);
`movePart` (the world anchor moves; the billboard tracks — engine-owned, verified
visible); `scopePredicate` (the render-vs-record scoping predicate respected —
E1 for the pure predicate); `teardown` (registry-neutral: adornee/instances gone,
counters at baseline — WRONG: any orphan after 20 mount/teardown cycles).

**Preferred-text:** the caption scales; the ring/icon composite does not (angular
size in-world is engine policy; the fixture states the caption is the only
text-scaling participant).

**Matrix note:** billboard content renders in world space — the five-view rows
verify the *companion screen* normally and capture the billboard for visibility
only; ten-foot legibility of billboard text is recorded as observational, not a
geometry gate.

---

## 9. Findings & risks for the lead (dispositions requested)

- **F1 — Toast timing numbers have no ratified source.** Duration 4 s [2.5–8],
  read floor 1.5 s [1–3], max visible 3, queue cap 8 are designer-set defaults
  (§3.2); the ratified game specs cover toast *geometry* only. I recommend
  accepting them as framework defaults and letting Step 6 game integration tune —
  but they should be called out at the gate as new numbers, not inherited ones.
- **F2 — Priority vs read floor is under-specified in SF-T2.** I ruled: priority
  orders the queue and **never truncates a showing toast's read floor** (§3.2).
  If the lead wants urgent-preempt semantics (a priority tier that does truncate),
  that is a contract addition — flag now, not mid-build.
- **F3 — Capacity drops needed an event.** SF-T2 allows dropping queued toasts at
  the cap; silently dropping violates I-9 at the instrumentation level. I added
  `dismiss(reason="capacity")` to the taxonomy (§3.2, §7). Confirm the taxonomy
  addition.
- **F4 — `arrive` vs `land` needed disambiguation.** The ledger lists both without
  defining the split. I defined: `arrive` = generic motion arrival (SF-M3);
  `land` = a drag/commit payload delivered to its target (§7). If engineering
  prefers one event with context, that is acceptable — but the causal frames must
  not merge.
- **F5 — Armed-target removal is unspecified.** SF-L3 protects the armed target's
  *focusability*, but no row says what happens when the armed/hovered row is
  **removed** (unmounted) mid-interaction. I ruled (§1.3, §4.3): targeting ends
  with a `leave`, the verdict clears, the session continues with no hovered
  target, and a flight in progress resolves by settle with `targetLost = true`.
  Needs a nod — it touches SF-L1's churn evidence.
- **F6 — Reorder animation is a new default.** SF-L1 never says whether re-sorted
  rows *animate* to their new slots. I specced `reorderMotion` defaulting to the
  `object` class with RM/`"instant"` opt-out (§4.4). This has a perf cost on
  weakest devices (20 rows × 2 springs, transient) — the SF-C4 perf row should
  include a churn-while-animating sample, which the ledger's dense-motion row
  (SF-M8) does not currently name.
- **F7 — Modal-cancels-drag is a new documented rule** (§5.4, §6.3). No SF row
  covers a modal presenting mid-drag; leaving it undefined would leak into Step 6
  as an incident. Cheap to build now; confirm.
- **F8 — The exit-cap number (500 ms) and arrival radius (4 px) are framework
  defaults I am asserting** (§2.1, §1.4). The radius traces to the dispatch's
  ratified list; the cap does not — it is sized at ~2× the slowest class's
  perceptual settle. Both live in option tables, both tunable.
- **F9 — Markers are declared non-interactive by contract** (§6.4). If any future
  consumer wants tappable markers, the 44 px floor collides with 8 px dots; the
  contract-level declaration prevents a fixture from quietly waiving the floor.
  Confirm this is the intended resolution rather than a floored marker variant.
- **F10 — The stepped-RM policy for informational timers is a new named contract**
  (§1.5). SF-M5's "informational timers still deplete" needs a *mechanism*; I
  generalized the game's 250 ms tier. It must apply to `UI.Path` arc bindings
  (billboard §8.8) too, which touches the path leaf's update path — engineering
  should size that before committing.
- **F11 — Continuous-color `direct` form weakens theming by design** (§6.1).
  Identity hues from game data cannot be role-blends. The authority audit records
  it, but the contrast gate cannot check a runtime hue against its backdrop — the
  design rule (identity hue never the sole carrier, I-5) is the only guard.
  Recommend the API name make the exemption loud (e.g. `directUnthemed`) so a
  reviewer can grep for every use.
- **F12 — SF-C3's "focus visibility" on `sponsor_billboard` is vacuous** (§8.8 —
  display-only, no focusables). The matrix row for that scenario should assert
  the companion screen's focus story and record billboard checks as visibility
  captures; otherwise a checker may mark a trivially-green focus row as evidence.
- **F13 — VirtualList fixed heights vs preferred-text growth** (§8.3): rows derive
  height from theme metrics + text facts (per the fixed-px-heights lesson), but
  the Step 5 windowing contract is *fixed heights*. At the largest text offset the
  derived height grows uniformly — legal — but a per-row wrap difference would
  not be. I capped the detail line (`lineLimit` 2) to keep uniformity; if the
  engineers find largest-offset uniform growth breaks the windowing math, that is
  an escalation, not a quiet clamp.
- **F14 — Interactive toasts are an explicit non-goal** this stage (§3.2), as is
  momentum projection (RG-9, reconfirmed — velocity handoff ships, projection does
  not). Recording both so their absence in fixtures reads as decided, not missed.

---

## 10. Lead dispositions (Fable, 2026-07-27) — all 14 findings resolved before implementation

| Finding | Disposition |
|---|---|
| F1 toast timing defaults | **ACCEPTED** as framework defaults (duration 4 s, read floor 1.5 s, 3 visible, queue cap 8), every one an overridable option. They are designer-chosen, not ratified; the human feel gate may retune them — recorded in the review packet. |
| F2 read floor never truncated by priority | **ACCEPTED** — matches the ratified M12 read-floor mechanism. Encoded in the pure toast scheduler tests. |
| F3 capacity drop emits `dismiss` with reason `capacity` | **ACCEPTED** — taxonomy addition to SF-F1; games can observe drops. |
| F4 `arrive` vs `land` | **ACCEPTED** as disambiguated: `arrive` = any chase reaching its live target (motion event); `land` = a drag/commit payload reaching its resolved drop (session event). SF-F1 wording covers both; tests assert each fires from its own seam. |
| F5 armed-target removal | **ACCEPTED** — removal of the targeted row ends targeting with exactly-once `leave`, clears the predicted verdict, and any in-flight motion resolves by settle fallback (`targetLost`). Added to the drag-session contract (P4). |
| F6 `reorderMotion` default (`object`) + perf sample | **ACCEPTED**; the SF-M8 perf scene adds a reorder-under-motion sample. |
| F7 modal presented mid-drag cancels the session | **ACCEPTED** — the presenter emits a cancellation the session honors; proxy and focus trap never coexist. P3/P4 interface rule. |
| F8 exit hard cap 500 ms | **ACCEPTED** as a flat, non-overridable cap: no exit transition may defer disposal beyond 500 ms. |
| F9 markers non-interactive | **ACCEPTED** by contract — marker layers are display-only; interaction belongs to list rows/other surfaces (matches legacy dots; avoids the 44 px floor collision). |
| F10 stepped RM for informational timers | **ACCEPTED**, sized: implemented in the motion clock as an `informational` motion kind — under reduced motion its output quantizes to 250 ms ticks with the same wall-clock terminus; Path/bar leaves change nothing (they just receive fewer writes). |
| F11 loud name for direct hue | **ACCEPTED, amended shape**: one `tint` prop with two value forms — role-blend `{ role, blend }` (themable, preferred) and `{ direct = {r,g,b} | "#hex" }` (declared theming-exempt escape). The loud word lives in the value form; closed-set states may never use the continuous channel (doc + lint rule). |
| F12 billboard focus-visibility vacuous | **ACCEPTED** — the billboard matrix rows assert geometry/lifecycle only; focus-visibility assertions are marked not-applicable, not silently passed. |
| F13 fixed-height windowing vs largest text | **ACCEPTED** — fixture rows cap detail lines via `Text.lineLimit`; list row height may derive from the effective theme-metrics snapshot but stays uniform per list. If largest-offset growth still breaks windowing, that is an escalation row, not a clamp. |
| F14 non-goals reconfirmed | **CONFIRMED** — no interactive toasts, no momentum projection this stage. |
