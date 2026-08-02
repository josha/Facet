# UI Designer — integrated review, ROUND 1 (parallel Sponsor on LuauUI)

**Date** 2026-07-30 · **Reviewer** UI Designer role · **Scope** L1 entry/lifecycle, L2 table/list/map/poses, L3 cards.
**Method** every capture in `rows/REVIEW-PAIRS.md` opened and read as pixels (plus crops at 2–4× of the gate
slot, the stray ring, the tablet rows, the armed ghost and the dock); geometry/traces read from the three
`rows/PS-*.md` files. Verdicts come from the pixels; where a trace is the only evidence I say so.
**Files I could not read:** none. **Extra files opened** (not in the index, used as corroboration):
`PS-L2-rolepick-modal.png`, `PS-T5-rowstates-luauui-max-portrait.png`, `PS-T1-luauui-min-iphone16-landscape.png`.

**Instrument limits I did not re-litigate:** injected clicks not reaching buttons inside the virtual list's
scroll host; `ButtonB`/`ButtonY` refusal; arbitrary-point outside-tap. Live commit/drag/toast/fly-home stay owed
to the physical pass.

---

## 1. Per-pair verdicts

| Pair | Verdict | Criteria applied | What I saw in the pixels |
|---|---|---|---|
| Table max, **phone portrait** | **MISSES** | C2 hierarchy, C7 state, C9 readability | Structure is right (map top / list below, 1st read = list). But Bolt P2's `locked` gate slot paints as a **toggle-switch silhouette** — a wide empty pill track with a red ring + **gold** padlock parked at its left end, ring overhanging the pill's left cap (F3). Map tags read cleanly where legacy's collide. No hand dock present (F6). |
| Table max, **phone landscape** | **MISSES (blocker)** | C8 spatial consistency, C7 | Split, row order and density all correct and legible. A **bare family-hued ring floats unattached** in empty plate space ~200 px below the last row, at the gate-strip x-band, with no pill and no lock — the same widget that renders in-row in portrait (F1). Selected row wears a heavy accent stroke ring (F4). |
| Table max, **tablet** | **PARTIAL — not state-matched** | C2, evidence integrity | Geometry good: map left, 8 rows, generous targets. But legacy is `Lap 3/3` racing with a live shield pill on Wrenchy while LuauUI is 7-of-8 **finished** — the pair cannot support a state comparison, only geometry (F6). The **selected row escapes the finished recede**: Wrenchy's name is near-white and its swatch full-strength while every other flagged row is `contentSecondary` and muted (F2). |
| Table max, **desktop 1080** | **MEETS** | C2, C9 | Same three-band read as legacy; finished rows recede in both; row pitch within a few px of legacy. Labels pre-glyph-fix (known gap). No stray ring at this size. |
| Table max, **TV 1080 (44 dpi)** | **BEATS** | C10 platform-native, §8 ten-foot | LuauUI row type is ~1.35× its own desktop size; **legacy's TV type is byte-identical to its desktop type** (no ten-foot bump at all). LuauUI's plate is also inset well inside the frame where legacy runs near-full-bleed — better title-safe. Focus/selection ring gives the ten-foot anchor legacy lacks. |
| Follow/min, **phone portrait** | **MISSES** | C9 readability, C2 | The **minimap has no surface**: a pale trace and dots painted straight onto the live sky, near-zero contrast, and it merges with the CoreGui player-list chip in the same corner (F5). Watched card is left-aligned with a smaller, lighter name than legacy's centred bold `heading`; the ‹ › affordances are hairline glyphs on an over-wide plate (F7). Capture is pre-glyph-fix. |
| Follow/min, **phone landscape** (LuauUI = raw pane) | **MISSES** | C9, C2 | Post-fix pane confirms both above at the fixed build: plateless minimap on sky; "Wrenchy Penguin / P1" left-aligned with ~10 px chevrons. Legacy's card is centred, bold, with full-size chevrons on their own plates — legacy wins the 2nd read of the pose. Correctly no name tags on the minimap in this pose (matches legacy). |
| **Armed card + aim affordances** | **MISSES (blocker)** | C5 directness, C2, invariants 1/13 | Source slot correctly empties (framework `dragHeld`) — the one thing this pair proves outright. But the **held card paints as a blank rounded rectangle** on the aimed row: no icon, no caption, nothing (F1b). The two remaining hand cards render **white « and »** glyphs instead of the card art and **carry no family hue** — legacy's purple Headwind / gold Tailwind are unmistakable at a glance, LuauUI's are two identical grey tiles distinguished only by a truncated word (F3b). Ghost sits on the aim row, not at the ratified staging spot (F9). |
| Sponsor results, phone landscape (legacy only) | n/a — **bar recorded** | C2, R3 | Bar to beat, not copy: the bank chip is half-covered by the CTA band, the Skip chip is occluded by the CoreGui player list, and a **parked sponsor is told "8th!"** — the driver's placement slam where §S16 asks for a round-story hero line. |
| Sponsor results, phone portrait (legacy only) | n/a — **bar recorded** | C2 | Bands read correctly top-to-bottom; CTAs use the **row** candidate in compact where §6 predicts the column. Same "8th!" hero and same Skip occlusion. |
| *(extra)* Role-pick modal, LuauUI | **MEETS** | C1 task clarity | Two verbs, primary accent-filled and dominant, correct first-timer copy on both, no dismiss affordance. Scrim is real and measured (sky `74,133,208` → `53,81,109`). No focus ring painted in a pointer session — correct per C10, and it proves the ring on the racer rows is *selection*, not focus. |
| *(extra)* Row states, greyscale | **BEATS/MEETS** | never-colour-only | Finished rows read by **flag form + recede + latched position** with zero hue. Real, and better expressed than legacy's. |

---

## 2. Findings (most severe first)

**F1 — BLOCKER · framework-mechanism (triage) · `PS-T1-luauui-max-iphone16-landscape.png`**
A gate ring paints **detached from its row**, floating on empty table plate, unclipped by the list viewport.
The same widget renders in-row in portrait, and its x sits in the gate-strip band while its y is ~200 px below
any row — a rect solved in one space and consumed in another (the `screenRectOf`/pointer-rect family). The ONE
countdown form appearing unattached is the most broken-looking thing in the build. **Fix direction:** the ring
must be a child of the slot's ZStack, positioned in the row's own space and clipped by the list host; assert in
a fixture that no ring node's rect falls outside its row's rect at both axes.

**F1b — BLOCKER · game-composition (framework seam) · `PS-C1-armed-hand-luauui.png`**
The armed ghost has **no face**. Hypothesis with a named seam: OWN-D12 binds the card face's emptiness to
`registry.heldSource`, and the drag proxy re-renders that same subtree, so the proxy empties itself.
**Fix direction:** the proxy renders the payload's face unconditionally; the emptiness predicate applies to the
*dock slot node only* (`heldSource == slot AND node is not the proxy`). A held card with no face fails C5 and
invariant 13 outright.

**F2 — MAJOR · game-composition · tablet + armed + `PS-T5` captures**
**Selection overrides GENERAL-INACTIVE.** A finished, out-of-the-race row that happens to be the watched racer
paints the *brightest* name and a full-strength swatch while every other finished row recedes. §4.1's precedence
is `drag-hover verdict > GENERAL-INACTIVE > RELATIVE-INACTIVE > ACTIVE`; selection is not in that ladder and may
never lift a recede. Cross-checked three ways: Flash bright-orange when selected+finished vs muted when
finished-only; Bolt muted in `PS-T5` vs bright while racing. **Fix:** the recede composes over selection.

**F3 — MAJOR · game-composition · portrait max crop**
The `locked` gate slot **reads as an interactive toggle switch**: a pill ~2.5× as wide as its content with the
ring+glyph parked at the left end and empty track to the right (painted at a size nobody measured for it), and
it carries **two hues in one composite** — a red ring around a **gold** padlock. §S5 tints both from
`familyRole(family)`; gold is the reserved `sponsorTell` meaning. **Fix:** size the pill to its live content,
apply the family tint to the glyph (check the icon isn't a coloured asset defeating `blend = 1`), keep the ring
inside the pill's cap.
**F3b — MAJOR · game-composition ·** the hand's card faces are white `«` / `»` glyphs with no family tint and no
card art; help vs hinder is unreadable at a glance in the mode's primary verb. **Fix:** wire the card icon set
and the family tint before the gate; a chevron placeholder is not shippable next to legacy's purple/gold pair.

**F4 — MAJOR · design-spec (mine) + composition · every LuauUI max capture**
The watched row's paint is an **accent stroke ring** — the exact form the spec assigns to focus (§4.1 focused)
and to the drop verdict (§8: "the drop verdict carries stroke weight as well as hue"). One meaning per channel
(invariant 4) is broken before a card is even held. My spec never named a *watched* treatment; Q3 approved the
meaning without approving the form. **Fix + amendment (A3).**

**F5 — MAJOR · design-spec (mine) + composition · both follow-pose captures**
The **minimap has no plate** in the minimized pose. §S6 declares the canvas as `Path` + markers with no surface;
maximized borrows the table plate, minimized has nothing, so the trace lands on live sky at ~1.2:1 contrast and
dissolves into the CoreGui chip. Legacy's dark bounded panel is the bar. **Fix + amendment (A1).** It also
removes the only visual cue that the canvas is the restore target.

**F6 — MAJOR · evidence integrity · `REVIEW-PAIRS.md`**
Two claims in the index do not hold. (i) **Every LuauUI max capture predates L3** (13:0x vs the card layer's
20:1x): there is no paired device evidence of the hand dock anywhere in this round — only the raw-pane armed
shot. The empty band at the bottom of all five LuauUI plates is the dock's reserved space, not a layout defect,
but it is also not proof of anything. (ii) The **tablet pair is not state-matched** (legacy racing vs LuauUI
finished), so "same states held by the shared rig" is not true of that row. Every pair must carry the layer set
and rig state live at capture time.

**F7 — MAJOR · design-spec (mine) + composition · follow pose**
The watched-racer card loses the 2nd read: name **left-aligned** in a full-width plate with a large dead gap,
`heading` resolving smaller and lighter than legacy's, and cycle chevrons rendered as ~10 px glyphs inside their
target boxes. §S4 never stated alignment or a glyph floor. **Fix + amendment (A2).**

**F8 — MAJOR · design-spec (mine) · §7 M5 vs §11 D-2**
My own spec contradicts itself: §7 M5 says the tap-armed ghost chases "the held/aim spot" and re-targets on a
focus move; §11 D-2 records the ratified behaviour as one **fixed staging spot above the dock**, deliberately not
riding the aimed row. The build followed M5 (F9 below is the symptom, not a build error). **Ruled in §4.**

**F9 — MINOR · game-composition ·** the armed ghost parks on the aimed row and overlaps its name. Follows from
F8's ruling: move it to the staging spot; the row carries the aim.

**F10 — MINOR · game-composition ·** hand dock is left-aligned in its band where legacy centres it, and the
emptied (held) slot **loses its corner radius** — a square-cornered well beside two rounded ones.

**F11 — MINOR · process ·** the dev banner sits in the chip-row band and **occludes the SizeToggle** in all five
max captures. Move it (bottom-left, or behind a key) before round 2 or it will keep masking a §4.5 control.

### What the build got right and the spec should now record
- **Ten-foot type bump delivered** where legacy has none, with a more title-safe inset (record as an intentional
  difference that *beats* the baseline — `PS-T1-luauui-max-androidtv1080.png`).
- **Map name tags legible and non-colliding** where legacy's stack into an unreadable pile at every size.
- **Finished state is form-first** (flag + recede + latched position), greyscale-proven.
- **Framework `dragHeld` empties the source slot** with no hand-rolled state — exactly the parallel-plan intent.
- **Role-pick**: per-flag copy, dominant primary, no dismissal path, measured scrim, no focus ring for pointer.
- Per-row plates with hairlines separate rows better than legacy's continuous panel at tablet/TV densities.

### Spec amendments I will make (no director ruling needed)
A1 §S6 — the minimap form declares `surface = "raised"` + panel radius; the whole canvas stays the restore target.
A2 §S4 — `WatchedText` centres between the arrows; cycle glyphs resolve at `label` inside the target box.
A3 §4.1 — add a **watched** row treatment: `controlSelected` plate + a leading marker, **never** an accent stroke
ring; and state explicitly that watched/focus/hover never lift a GENERAL-INACTIVE recede.
A4 §7 M5 — corrected to the fixed staging spot, aligning with §11 D-2; invariant 9 (chase live targets) applies to
the **commit** flight only.
A5 §S7 — hand dock centres in its band; an emptied slot keeps `radii.control`.
A6 §4.2 — the `locked`/`play` pill sizes to live content; every glyph in a gate slot carries **one** family hue.

---

## 3. Rulings on the five queued questions

**R1 — Split-axis keying: adopt (a), key on `sizeClass`.** Recorded as an intentional difference, desktop-window
only. §6 keys row height, ticker, chip row and CTAs on the class; a second breakpoint vocabulary for one property
is how invariants rot. (b) also reads a *solved* rect back into a condition — the same read-back class that
produced F1. Revisit only if the director judges a tall desktop window a real configuration; if so, express it as
a declared environment condition, never a geometry read-back.

**R2 — CoreGui player list: disable it while the Sponsor HUD is presented** (`SetCoreGuiEnabled(PlayerList,false)`
on enter, restore on teardown), applied to **both** presenters so the comparison stays honest. This is a game
policy change and I am asking for it because the pixels show it occluding three load-bearing things, not one:
the racer list's top-right (P1's numeral), the **minimap** in the follow pose, and the **Skip chip** in legacy
results. The alternative — reserving the top-right as a no-content band in both poses — costs the minimap corner
and is worse. Escalate to the director only if there is a social reason to keep the roster visible to a sponsor.

**R3 — `disconnected` row state: KEEP**, as a recorded intentional difference, on three conditions: it renders in
the existing vocabulary (GENERAL-INACTIVE recede + a form glyph, **no new hue**), it sits at the
GENERAL-INACTIVE rung of §4.1's precedence, and it stays inspectable (explains itself on attempt). It closes a
real "no silent states" hole legacy leaves — a dropped racer's row otherwise reads ACTIVE and eats a card.

**R4 — Q1 CONFIRMED as built:** Cancel is a **no-op** on the role modal via `cancelPolicy = "none"`. The
framework mechanism the recommendation was contingent on now exists, so option (a) stands and (b) is withdrawn.
Rider: PS-G5 must still prove B does nothing on a physical pad.
**Q3 CONFIRMED with an amendment:** selection **means the watched racer** (durable, survives a re-sort, reads as
"chosen"). The *paint* is amended per A3 — selection may not borrow the focus/verdict stroke channel and may not
lift a receded row (F2, F4).

**R5 — OWN-D13, design side: flash + refill + toast IS the ratified revert for a SERVER rejection. No framework
verb required.** §4.6's "flies home to its slot" was written for the live-session paths (illegal drop, cancel)
where a ghost exists under the player's hand. A server `blocked` arrives after the gesture is over: there is no
object on screen to fly, and inventing one would animate a card the player never sees leave. What invariant 11
requires is that the optimistic change **visibly reverts at the point of action**, and four channels already do
that. Two conditions: (i) the slot's re-fill must be a visible *arrival* (`reward` class on the slot), not a
silent swap, so "it came back" is legible; (ii) the reject flash, the refill and the toast must land on the same
frame so cause and effect read as one event. I will split §4.6 into client-cancel (flight) and server-rejection
(flash + refill + toast) accordingly.

---

## 4. What round 2 must include

**Surfaces:** L4 (chip row + shared midline against the platform cluster — carry the M11 notch lesson; objective
chip incl. *absent in grace/results/pre-start*; ticker with the Q2 compact strip; caption/ribbon priority; toasts
with the read floor; start countdown placement in both poses). L5 (omen billboard scoping + ring, minimap omen
agreement). L6 (results **both roles × both orientations**; band model with the CelebrationSlot holding its
reserved height; `ViewThatFits` CTA reflow; skip always reachable). For L6, beat the legacy bar rather than copy
it: legacy's bank chip collides with the CTA band in landscape, its Skip sits under the CoreGui list, and it
shows a parked sponsor the **driver's** "8th!" slam instead of a round-story hero line (§S16).

**Re-captures I need, all post-fix, state-matched, with the live layer set stamped on each pair:**
1. All five max views **with the hand dock present** — this round has zero paired device evidence of S7.
2. Phone portrait + landscape, both poses, after the minimap plate (A1) and the watched card (A2) land.
3. A held-card frame showing **RELATIVE-INACTIVE + held-blocked slash** on at least two rows, and a
   **finished + watched** row proving the F2 precedence fix.
4. A gate slot in `play` (badge + depleting ring) and in `locked`, at compact **and** wide — F1 and F3 are only
   judgeable with a live record held.
5. The armed ghost **with a face**, at the staging spot (F1b, F8/F9).
6. A rejected play frame: origin-slot flash + refill + one keyed toast on one frame (R5's conditions).
7. Tablet/desktop/TV re-shot post-glyph-fix, on the same rig state as their legacy twins.
