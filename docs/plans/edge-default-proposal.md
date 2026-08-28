# Edge-padding default — a costed proposal for the director's word

**Status: proposal only. No default is flipped by this document.** Companion
to [ADR-0055](../adr/ADR-0055-edge-floor.md) (the `edgeFloor` knob, shipped,
opt-in) and its own "What is deferred" section, which explicitly reserves
this exact question to the director. Full measurement detail, the 23-row
casualty re-verification, and the desktop repro:
`.superpowers/sdd/framework-gaps-phase2-followups/task-edge-report.md`
(task EDGE). Binding on any future flip: R15/ADR-0040 (a default-value change
needs its own ADR-0040 row, its own instrument, and the director's explicit
order — this document is the input to that decision, not the decision).

## The question

FIX-4 shipped `edgeFloor` (a per-call opt) and measured what a *universal*
default floor would break: 21 casualties at 1px, 23 at 2px, across the
95-surface corpus as it stood then. The director's own follow-up
(`padding.png`): desktop screens visibly ride the edge (a "tabs-nested"
sidebar flush against the screen, an unread badge touching the content card)
while mobile already looks fine. **Which screens actually break, are they
real breaks, and is there a default that fixes desktop without breaking
mobile?**

## What this round found

1. **Re-verifying FIX-4's 23 casualty rows honestly** (read source, judge
   what a player experiences, not just the geometry number) finds **16 are
   genuinely (a) TRULY BROKEN, 6 are (b) SHIFTED** (a small bleed into empty
   margin or a sub-2px change nothing collides with), and the one **(c)
   GIVE-WAY RUNG CROSSED** case FIX-4 flagged (`sponsor_drop`, a
   161→200px non-linear jump) reproduces identically. The corpus mostly held
   steady since FIX-4; two things drifted and are reported honestly: `probe`
   no longer breaks at the 1px floor (a real improvement, some landed round
   bought back about a pixel of room), and `p2_cartwheel` has an unrelated,
   pre-existing regression (its own waiver rows are stale even at **zero**
   edge floor) that inflates its casualty count for reasons that have
   nothing to do with edge padding — flagged as its own follow-up, not
   folded into this proposal's numbers.
2. **`padding.png`'s surface is `tab_view`** — the one showcase file with an
   "Inbox" badge. Its own source comment explains the zero-padding choice was
   made **for mobile** ("on a 320px-tall landscape carrying TWO [tab bars]
   the eight pixels are the difference between the page fitting and not").
   Measured directly at a real desktop viewport (1920x1080,
   `displaySize="Medium"`, `preferredInput="KeyboardAndMouse"`): the
   automatic-placement sidebar rail sits at **x=0**, flush against the
   physical screen edge, with the Inbox badge riding fixed 79px inside it —
   the same shape the screenshot shows, now with numbers.
3. **An input-class-scoped floor fixes it with zero measured casualties.**
   Scoping the shipped `edgeFloor` mechanism to
   `interactionClasses.pointer == true` (the same fact the renderer's own
   hover branch already reads) and re-running the full 63-surface corpus
   (51 scenarios + 7 examples + 5 proofs) at two floor sizes — a literal 2px,
   and `space.gutter` (the same metric `bandSafeContent` already floors
   with) — produces **zero new failures** in both runs: identical to the
   3 pre-existing, unrelated `p2_cartwheel` failures at plain baseline. The
   same desktop probe with a pointer-scoped `space.gutter` floor moves the
   sidebar from `x=0` to `x=8`.

## Options, costed

### (i) Universal small floor (1-2px), no scoping

| | cost |
|---|---|
| Casualties | **21 (1px) / 23 (2px)** — every row in the task-EDGE 23-row table needs a real fix (none is a plausible `edgeToEdge` opt-out; confirmed again this round, not just assumed from FIX-4) |
| Worst item | `sponsor_drop`'s give-way rung — a layout redesign, not a pixel tweak |
| Benefit reached | Desktop (the actual pain point) — but mobile pays the whole bill for a mobile-irrelevant fix |
| Fix itemization | See task-edge-report.md's verdict table, column "surface" — all 23 rows |

### (ii) Input-class-scoped default — RECOMMENDED

| | cost |
|---|---|
| Casualties | **0**, measured at two floor sizes (`2px` literal and `space.gutter`) against the full 63-surface corpus |
| Mechanism | `renderer.attach`'s existing floor-application branch, gated on `env:get("interactionClasses"):get().pointer == true` instead of an explicit opt; touch/gamepad sessions keep today's zero; an explicit `edgeFloor` (already shipped) or `rootPolicy = "edgeToEdge"` still overrides/exempts exactly as now |
| Size recommendation | `space.gutter` — an existing metric (no new theme vocabulary), already the value `bandSafeContent` floors with, rides the ten-foot ladder for free |
| Benefit reached | Exactly `padding.png`'s class (measured: `x=0` → `x=8` on the repro surface) with zero mobile disturbance (measured, not argued: the pointer/touch viewport sets never overlap in the corpus, and the empirical run confirms it) |

### (iii) Status quo + per-app `edgeFloor` adoption in showcase/reference apps only

| | cost |
|---|---|
| Casualties | **0** (opt-in; nothing else moves) |
| Scope | Fixes only the surfaces someone remembers to touch — `tab_view` today, but every other current or future `automatic`-placement `TabView`/sidebar layout ships flush by default until someone notices |
| Root-cause fit | Partial — `tab_view`'s own zero-padding choice was made FOR MOBILE; a per-surface `edgeFloor` there still needs a desktop-only condition to avoid reopening the "eight pixels" mobile problem the file's own comment describes, which is the same input-class check option (ii) already centralizes |

## Recommendation

**Option (ii).** Scope the floor to `interactionClasses.pointer == true`,
size it at `space.gutter`, apply it wherever `coreSafeContent`/
`deviceSafeContent`/`bandSafeContent` already reserve edges. It is the only
option measured at zero required casualty fixes while directly, numerically
resolving the director's screenshot, and it matches the director's own
FIX-4-era wording ("perhaps even default... but can be made to") as a
default rather than an opt-in, without option (i)'s 23-fix bill.

**This is not shipped here.** Per R15/ADR-0040 discipline, a default-value
change needs its own ADR-0040 table row, a pinned instrument (the same
pattern `check_gate_pins`/`public_shape.luau` already use for every other
documented default), and the director's explicit order before it lands. If
ordered, the consumer-lockstep list to re-walk first is RascalRally's own
11 non-spec `rootPolicy` call sites plus the one direct `Facet.renderer.attach`
call in `OmenState.luau` (FIX-4's corrected item-2 finding) — none of them
currently passes `edgeFloor`, but a DEFAULT change (unlike the opt-in knob)
reaches every one of them without an explicit call, so each needs a pass to
confirm the new floor composes cleanly with what it already reserves.

## What is still open

- `p2_cartwheel`'s own pre-existing, edge-floor-unrelated regression (stale
  waiver/ledger rows, a real card-grid overlap in the shipped Cartwheel
  reference app) needs its own round before its casualty count can be read
  cleanly under any future flip.
- The exact desktop breakpoint/condition (`interactionClasses.pointer` vs. a
  `displaySize`/viewport-width check) is a small design choice for whoever
  implements the flip; `pointer` was chosen for this measurement because the
  renderer already reads it elsewhere for the same "is this a mouse-shaped
  session" question, but a tablet with a connected mouse would also read
  `pointer == true` and gain the floor — worth a one-line confirmation in the
  flip round that this is the intended scope, not an accidental one.
