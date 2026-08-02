# UI-Designer INTEGRATED review — sponsor-framework-gaps (roadmap Step 5, SF-R2)

Status: **DELIVERED for SF-R2** · Author: UI Designer specialist · 2026-07-27
Reviewed against: `ui-designer-spec.md` (incl. the lead's §10 dispositions — the contract),
`acceptance-ledger.md`, `rows/*.json` + `rows/matrix/*.json` (live evidence),
`examples/gallery/scenarios/sponsor_*.luau` (the eight fixtures as built).

Numbering: findings here are **R2-F#** (the spec's own §9 findings were F1–F14 and are
already dispositioned; the implementation phase's fixes were P5-F#). Severity scale:
MAJOR (needs a disposition or a fix before Step 5 closes clean) / MINOR (dispositionable
as accept-with-amendment or a small follow-up). Class per the dispatch: **(a)** design/spec
issue, **(b)** LuauUI mechanism/bug, **(c)** fixture-composition issue.

Already known, deliberately **not** re-reported: the step-inline synchronous readback lag
(navigate sweep, `inputPassthrough` press delta — both re-proven frame-spaced); VirtualInput
non-delivery this session (injected input honestly labeled `mcp-injected`); interactive
toasts and momentum projection as recorded non-goals (spec F14, confirmed).

---

## 1. What landed well (so the findings read in proportion)

The mechanisms are the good kind of boring. Judged against my own tables:

- **Motion classes** — all four (`container`/`object`/`reward`/`decay`) live as the only
  currency; interrupt-continues-from-value-and-velocity proven (`interruptToggle` inside one
  settle, no restart pop); velocity seeding goes through the public tracker
  (`newDragVelocity`), so the number that seeds the flight is framework-computed; the decay
  attack-is-a-cut re-hit does not ratchet. **Arrival by perceptual radius on the causal
  frame** is real (`how=radius`, the 0.717 s settle-trailing reproduced numerically as the
  counter-example). Resting springs cost zero; 41 concurrent motions = one transaction per
  frame.
- **The F6 mid-beat-terminal ruling as landed is right**: interrupt terminalizes the
  *playing* beat too, on the interrupt frame (`midbeat:interrupted terminal=true`), which is
  the only reading under which "skip = jump to end state, never half-painted" is true —
  the alternative (remaining beats only) leaves the mid-flight box as free motion. I
  endorse this as the contract wording for §1.6.
- **Cancel unification** matches my §5.5 table exactly: freeRelease / overSource / action
  each emit exactly one `cancel` with a distinct `how`; `reject` stays reserved for a
  refusal *with a target* carrying the game's reason code; the modal-cancels-drag rule (F7)
  is proven end-to-end with `how=modalPresented`. This is the shape I asked for.
- **Toast scheduling** honors the read floor against priority (F2 as dispositioned),
  caps the queue at 8 with `dismiss(reason=capacity)` traced (F3 as dispositioned), and
  the RM burst displays the full information surface over time — nothing silently dropped.
- **RM parity incl. the stepped informational policy** (F10): the billboard ring kept
  depleting under RM with quantized writes to the same terminus, and the RM axes that ran
  emitted the same trace/terminal states as the animated paths.
- **The marker overlay** is the strongest single row: 6660 updates, zero remounts, and the
  u,v∈{0,1}² corner check passed on **centres** with dx=dy=0 — the fixture even avoided the
  half-marker-adrift measurement trap I would have flagged.
- The derived row height (theme snapshot + live text facts + `lineLimit 2`, F13 as
  dispositioned) is the fixed-px-heights lesson operating as designed, and SF-M9
  (headless-green/live-broken presentation channel) was exactly the defect class my I-3/I-1
  invariants exist to catch — found, fixed, and parity-pinned this stage.

The eight-scenario structure survived contact: every §8 scenario exists, carries the steps
my tables named, and the row artifacts answer "which frame" rather than "roughly when."

---

## 2. Dispositions requested

### R2-F1 — Supersede: one causal moment is emitting two event shapes. **MAJOR · class (a) ruling + (b) one-line change** *(the dispatched taxonomy question — ruled here)*

The live trace shows the presenter emitting `dismiss(reason=supersede)` on replacement
while the closed taxonomy (and the fixture's counter) also carries a distinct `supersede`
event. **Ruling: the `supersede` event is the contract.** Rationale: one meaning per
event — `dismiss` means *the surface retired from display* (timeout, manual, capacity —
a game maps it to a whoosh-out); a same-subject replacement is *the message updated where
it stands*, and a game that plays a dismissal sound on it has been lied to. Emitting both
also double-fires the causal frame, which SF-F1's own acceptance forbids. Requested:
replacement emits exactly one `supersede` (context: subject key, predecessor id, successor
id); `dismiss(reason=supersede)` is removed from the emitting path; `dismiss` reasons
remain `timeout | manual | capacity`. (`capacity` stays a `dismiss` per the F3
disposition — a queued toast that never showed still *retired*, and changing that now
would churn game mappings for no player-visible gain.)

### R2-F2 — Supersede-as-replacement vs my §3.2 "content swaps in place" (P3 deviation 4). **MINOR · class (a) — ACCEPT with conditions**

The landed behavior replaces the same-key toast rather than mutating content inside one
mounted node. Acceptable — the design intent behind "in place" was *no exit/enter churn
and no positional jump*, not a specific mutation mechanism — **on three conditions**, which
I ask be pinned by assertion: (1) the swap is same-slot (successor occupies the
predecessor's position, no re-stack shuffle); (2) same-frame (no frame in which neither is
present — no blink); (3) no enter/exit transition plays on either side of the swap. The
successor starting a fresh read floor is correct (new content earns a new read). §3.2 to
be amended to "replacement presents in place (same slot, same frame, no transition
churn)". Visual continuity on device rides the PENDING_HUMAN row H5 below.

### R2-F3 — The feedback bus accepts ad-hoc event types; the first fixtures already sprawled. **MAJOR · class (b)**

`pres.emitFeedback({ type = "celebrate", … })` appears in two fixtures (motion pop,
celebration done) and `feedback:celebrate` is cited in sf-f1.json as ordinary evidence —
but **`celebrate` is not in the closed v1 taxonomy**, and taxonomy sprawl was the named
risk on SF-F1. The seam currently enforces nothing, so the "contract amendment with a
gate" rule is only a doc sentence. Requested disposition, either: (i) consumer-emitted
custom events are legal but **must be namespaced/marked** (e.g. `custom:` prefix or a
`custom = true` field) so a game's sound map can mechanically separate contract events from
app events, and the fixtures rename `celebrate` accordingly; or (ii) strict-authoring like
motion classes (unknown type = error; `feedback.register(name)` for extensions). I
recommend (i) — the bus doubling as an app event channel is useful, and the loud marker
preserves the closed set's meaning. Related, accepted as-is but should be documented: a
fixture-created `clock:chase` publishes its own `arrive` via the callback (the framework
seams — controls, sessions, commit flights — auto-emit; raw motion tools do not). That
split is defensible; write it down in the SF-F1 doc so causal-frame responsibility is
explicit at the seam boundary.

### R2-F4 — The §5.5 non-pointer *presentation* was not built; only the session mechanics were. **MAJOR · class (c), with a possible (b) helper**

`sponsor_drop` proves arm→navigate→commit/cancel through one session object (SF-D4's
acceptance), but the §5.5 table's presentation column is absent from the fixture: the
armed source shows **no armed state** (spec: `controlSelected` fill + `accent` 2 px
stroke), **focus does not move into the target collection on arm** (spec: initial target =
first eligible row), and **focus-returns-to-source on cancel** is not driven. As landed, a
gamepad player who arms a card gets a proxy but no source-state change and must navigate
into the list unaided — a silent state at fixture level (I-9). Requested: the fixture
completes the arm presentation and the focus handoff (if "arm → focus first eligible
target" needs a framework helper on the registry, that is a small (b) addition worth
making once rather than per-game), and the H2 physical-gamepad row verifies it. Until
then the SF-D4 row's PASS should carry a "mechanics-only; presentation pending" note.

### R2-F5 — Evidence scope quietly narrower than the spec's §8 conventions; the ledger rows read wider than what ran. **MAJOR · class (c)**

Recorded honestly in sf-c3.json ("bounded evidence, no silent cap") — good — but the
narrowing leaves **spec-named WRONGs unverified** while SF-C2/SF-C3 sit at PASS_AUTOMATED:

- Matrix ran **only `sponsor_drop`** (spec: all scenarios × five views). Unverified
  spec-table WRONGs: toast breach of the top safe area on notched compact portrait; toast
  stacking gap on ten-foot; avatar fallback-initial overflow at largest text on compact
  portrait (the initial scales inside a fixed 44 px circle — this one is genuinely at
  risk); dim-treatment legibility on ten-foot; celebration no-overlap-after-interrupt
  across viewports; marker corner-exactness on other aspect ratios (numerically proven at
  one live viewport only).
- The RM axis is evidenced for motion, drop, toast, billboard — but **not for
  celebration** (informational beats keep order + events — a spec-table row),
  **avatars** (instant fades), **markers** (positions still track), or **list**.
- SF-C2 largest-offset ran on `sponsor_list` only.

Requested: either (i) a bounded top-up — matrix rows for `sponsor_toast` (notched
portrait + ten-foot) and `sponsor_avatars` (compact portrait at largest offset), plus
headless RM cases for celebration/markers (cheap E1s) — or (ii) re-scope the SF-C2/C3 row
text in the ledger to what ran and move the rest to explicit pending entries in the
review packet. Silent option: none. I recommend (i) for the two matrix rows (both are
real player-visible risks) and (ii) for the remainder.

### R2-F6 — Interactive-state fills landed on elevation surfaces; the §4.2 state table is not expressible as specced. **MAJOR · class (b) (or (a) amendment)**

Both list fixtures paint the §4.2 states with what the authored surface vocabulary has,
not what the spec says: legal-verdict and selected fills use **`raised`** (an elevation
role) instead of `controlHover`/`controlSelected`; the ineligible state is `base` fill +
`secondary` text role with **no disabled-opacity treatment** (spec: surface at raised
transparency + disabled content opacity); selected content does not move to
`contentStrong` (the fixture comment is explicit: "'secondary' is the only authored text
role there is"). Multi-channel redundancy still holds (stroke + edge bar + glyph), so
players are not misled — but the elevation channel is now carrying interaction state,
which is exactly the one-meaning-per-channel erosion I-5 exists to stop, and §4.2 is the
reference table every game list will copy. Requested disposition: **(preferred)** extend
the authored surface/content vocabulary for composed rows with the interactive-state roles
(`controlHover`, `controlSelected`, a disabled/dim treatment, `contentStrong`) so the
theme — not each fixture — owns those paints; **or** amend §4.2 to the achievable Studio
Neutral mapping and record that the interactive roles are Button-only this stage. Either
way the fixtures and the table must agree before games inherit the pattern.

### R2-F7 — The unified list's window height is a build-time pixel; rotation goes stale. **MAJOR · class (b)**

Spec §8.3 declares the list `fill=1`; the construct takes a plain px `viewportHeight`, so
both list fixtures derive it from the viewport **at build** and the report honestly flags
`viewportHeightDerivedAtBuild = true` ("a viewport change needs a reset to re-derive").
The matrix passed because every row rebuilds — but a live phone rotation or split-screen
resize mid-session leaves the window height wrong. This is the fixed-px-vs-live-facts
defect class (the same lesson that produced the derived row height) one level up.
Requested: a follow-up row for a fill/Readable viewport height on `newVirtualList` (or an
explicit documented contract that a hosting screen remounts the list on size-class
change, with the presenter doing so automatically). Not a Step-5 blocker if documented,
but it must not close silently.

### R2-F8 — Autoscroll chevron: shows at a clamped end, hard-cuts between states, sized off-spec. **MAJOR for (i), MINOR for (ii)/(iii) · class (c), with a (b) assist**

(i) My §4.5 affordance table: hidden "whenever that edge is at its canvas end (no
affordance for a scroll that can't happen)". The fixture's `alphaFor` keys only off
band/state; since clamp-at-end deliberately **stays armed** (correct for the scroll
mechanism), the chevron keeps pulsing at 100 % against an edge that cannot move — the
honest-affordance rule inverted at exactly the moment it matters. Fix is fixture-side if
the autoscroll state exposes at-end (`scrollTop` vs range is readable); if it doesn't, add
`atCanvasEnd` to the published state (small (b)). (ii) The 120 ms fades between
hidden/armed/active are hard cuts as landed. (iii) The chevron uses `iconSizes.medium`;
spec says the small icon size [20–28 px]. Neutral-channel discipline (never
`accent`/`danger`) is honored — good.

### R2-F9 — Landscape hand column landed trailing; spec said leading. **MINOR · class (a) — recommend ACCEPT as amendment**

The engineer's rationale is written in the fixture and it is a good one: portrait
(list, hand) and landscape (list | hand) are **one child order**, and a structural swap
would remount both halves. Trailing also serves the right thumb on landscape phones.
Requested: amend §8.4 to "landscape = trailing hand column," and record the
child-order-stability constraint as a reusable doctrine note (it will shape every future
adaptive layout) — plus a backlog question for the framework: keyed child reorder without
remount, so a future design *can* choose leading.

### R2-F10 — Toast option naming and the unexercised `edge`. **MINOR · class (a)/(c)**

The supersede key landed as `key`; my §3.1 contract says `subject`. Either rename or
amend — but pick now, before Step 6 games write against it (I mildly prefer `subject`;
`key` collides mentally with collection row keys). Separately, `edge = "bottom"` is never
exercised by any fixture or cited test; one headless scheduler/geometry case would close
it (bottom-edge stacking grows upward from the safe-area inset).

### R2-F11 — Over-source release fires the hand's `onDrop` *and* `cancel(how=overSource)`. **MINOR · class (b) — document the split**

Both happened on one gesture (returned=1 alongside the cancel trace). The shape is
defensible — the bus event is the semantic verb (cancel), the target callback is the
mechanical landing the consumer uses to restore the card — but undocumented it invites a
game to handle "returned to hand" twice (a place sound in `onDrop` plus a whoosh on
`cancel`). Requested: the drag contract doc states that a source-container drop resolves
the session as `cancel(how=overSource)`, that the container's `onDrop` still runs for
restoration, and that feedback mapping should key on the bus only. Also document which
`how` values are framework-reserved (`freeRelease`, `overSource`, `action`,
`modalPresented`) vs the open consumer-supplied reason strings sharing the channel.

### R2-F12 — The 40→44 px compact-portrait band switch has no evidence. **MINOR · class (c)**

sf-d1 records 40 px bands at the landscape drive; the §8.4 matrix WRONG ("band heights not
switching 40→44 on compact portrait") was never checked because autoscroll never ran on
the portrait row. One headless E1 (autoscroll options resolved under a compact-portrait
env) closes it — or, if the mechanism doesn't exist, this upgrades to a small (b).

### R2-F13 — Literal px values in fixtures (rule-3 sweep). **MINOR · class (c)**

Instances: `minColumnWidth` 96/104/56/104, selected edge bar `px = 4` (spec says space
step `xs`), wash bar `px = 6`, billboard `RING = 160` + canvas 320×220 + thicknesses 4/10,
`FLY_FROM = -160`, viewport-derive clamps (220/160/460; 0.5/160/420), metric-missing
fallbacks `56`. Requested disposition: classify each as **demo data** (scripted travel
distances, canvas sizes — acceptable, add a `-- demo value` label) vs **design values**
(the edge bar and grid minimums should be metrics/space steps). None are player-misleading
under Studio Neutral; the point is that games copy fixtures verbatim.

### R2-F14 — Fixtures use option values outside my declared tunable ranges. **MINOR · class (a) — clarify the rule**

Burst toasts run duration 1.2 s / readFloor 0.4 s / readFloor 0 (ranges: duration
[2.5–8], readFloor [1–3]) as compressed test schedules, and the framework accepted them
silently. Correct behavior, wrong ambiguity: the ranges are **gate-time governance for
framework defaults and game tuning, not runtime clamps** — a fixture scripting outside
them for deterministic evidence is legal. Requested: one sentence to that effect in the
option-table docs so the next reviewer doesn't file this as a defect (or decide clamping
is wanted, which I do not recommend).

### R2-F15 — `decorative = true` timeline beats: unexercised, possibly unimplemented. **MINOR · class (b)/(c)**

§1.6's RM rule lets a beat be dropped under RM *only* when marked `decorative = true`;
no fixture or cited test exercises the flag, and celebration's RM axis didn't run
(see R2-F5). Requested: engineering confirms the flag exists with one headless case
(decorative beat dropped under RM; unmarked beat kept with its event), or the contract
line is moved to a recorded deferral rather than standing as an untested promise.

### R2-F16 — Small fidelity nits, one bundle. **MINOR · class (c)**

(1) The celebration fixture's `interruptMidBeat` comment still calls the
playing-beat-terminal question open — the F6 ruling landed and the row proves it; update
the comment so the source doesn't contradict the contract. (2) Billboard icon slot is a
bare accent disc; spec says a theme icon or fallback glyph in `onAccent` sits on it.
(3) Non-tracked markers use surface `control`; §8.7 says the neutral `contentSecondary`
channel. (4) `RewardChip` surface is `control`; spec sketch said `controlSelected`
(collapses into R2-F6's vocabulary question). (5) The illegal-verdict fallback glyph is
`"/"` — legible intent is "blocked"; a `×` (or the theme's blocked icon when present)
reads better at caption sizes. None change behavior; all change what games copy.

---

## 3. Rows that need human eyes or physical hardware (for the review packet)

These are the only claims I cannot close from source + row evidence, listed with their
closing procedure. Everything else above is automatable.

| ID | Row | Procedure | Status |
|---|---|---|---|
| H1 | Touch drag feel on a physical phone | Real finger: promotion at 14 px (no eaten taps at 13 px of jitter), pickup scale read, velocity-seeded return on a real flick, hand "put it back" affordance discoverable without prompting | PENDING_PHYSICAL |
| H2 | Real gamepad arm→navigate→commit | After R2-F4 lands: arm shows on the source, focus enters the list at the first eligible row, skips read correctly at speed, cancel returns focus to the source; hand↔list group crossing does not trap | PENDING_PHYSICAL |
| H3 | Weakest-device perf (SF-M8/SF-C4) | Already ledgered PENDING_PHYSICAL; add the F6-dispositioned reorder-under-motion sample to the device run | PENDING_PHYSICAL |
| H4 | Motion feel review | Human capture/live pass over the motion + celebration labs: materialize scale (0.96), reward overshoot (the only bounce), decay wash, arrival-vs-perceived-landing; retunes stay inside the ±30 % window (spec rule 2) | PENDING_HUMAN |
| H5 | Toast feel + supersede continuity | Watch a supersede replacement for any blink/jump (pairs with R2-F2's conditions); burst readability at 3-visible; whether 4 s / 1.5 s floor feel right (spec F1's rider: these are designer-chosen, not ratified) | PENDING_HUMAN |
| H6 | Notched-device safe areas | Toast stack under a real notch (top edge) and the portrait hand strip vs the home indicator — the emulated matrix device (S22 Ultra) does not exercise a notch/home-indicator inset pair; a notched emulated row is an acceptable interim, physical closes it | PENDING_PHYSICAL (interim: notched matrix row) |
| H7 | Ten-foot at distance | From ~3 m: focus-ring strengthening on the drop lab, chevron visibility, billboard caption legibility (observational per §8.8's matrix note, per disposition F12) | PENDING_HUMAN |

---

## 4. Verdict

The Step-5 mechanisms — motion classes with true interruption and radius arrival, the
timeline's terminal discipline, the unified cancel, toast scheduling, the marker overlay,
stepped RM — landed faithful to the contract and in several places (marker centres, the
mid-beat ruling, derived row heights) better than the spec's own sketch. The findings
cluster in three places: one taxonomy ruling to take (R2-F1/R2-F3), one vocabulary gap
that makes the reference state table unbuildable as written (R2-F6), and a set of honest
but narrower-than-spec evidence scopes (R2-F5) plus fixture-presentation gaps (R2-F4,
R2-F8) that must not close silently. Nothing observed misleads a player today under
Studio Neutral; several things would mislead the next game team that copies these
fixtures as the pattern library.

**VERDICT: ACCEPTABLE WITH FINDINGS**
