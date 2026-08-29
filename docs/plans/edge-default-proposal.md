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

**AMENDMENT 2026-08-29 (task EDGE2).** Director follow-up, verbatim: *"for
padding, i'm not sure we can just do this on mouse devices — we might need to
apply it for medium/large screens so that it applies on consoles and desktops
but not mobile. laptops could have touch, rog ally can have a mouse, etc. so
screen size is more useful."* This round measured the screen-size-gated
variant the same way EDGE measured the pointer-gated one (disposable
`mkpair` copy, patched renderer, `overflow_sweep` standalone) and re-measured
the pointer-gated variant fresh at the same pin for an honest, current
comparison. **The screen-size gate is promoted to the lead recommendation
below (§ "(ii′)"), on measured casualty parity plus two confirmed, real
device-shape wins the pointer gate misses — with one confirmed gap: it does
not reliably solve the director's own stated motivating case (a mouse- or
gamepad-equipped ROG Ally) any better than the pointer gate did, because
Facet's best available screen-size signal cannot yet tell a handheld apart
from a laptop.** Full detail:
`.superpowers/sdd/framework-gaps-phase2-followups/task-edge2-report.md` (task
EDGE2).

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

### (ii′) Screen-size-scoped default — AMENDED LEAD RECOMMENDATION (2026-08-29, task EDGE2)

Same mechanism as (ii) — `renderer.attach`'s existing floor-application
branch — but gated on `env:get("effectiveDisplaySize"):get() ~= "Small"`
(i.e. "Medium" or "Large": the director's own "medium/large screens"
wording) instead of `interactionClasses.pointer`. `effectiveDisplaySize` is
not a new fact: it is [ADR-0058](../adr/ADR-0058-physical-size-aware-ten-foot.md)'s
own touch-corroborated, already-shipped correction of the engine's raw
`displaySize`, already read the same way (`env:get(name):get()`) by
`client/host.luau`, `client/theme_controller.luau`, and
`adaptive.conditions` for the identical "should this session get
big-screen TREATMENT" question — reusing it here needs no new environment
plumbing, exactly as (ii) reused `interactionClasses.pointer`.

| screen-size-scoped floor | new failures vs. the unpatched baseline (0, current pin is clean) |
|---|---:|
| `edgeFloor = 2` (literal px) | **0** |
| `edgeFloor = "space.gutter"` | **1** — see "A shared, gate-independent regression" below |

**Measured fresh at the current pin (`PIN_FACET 1656fd7`)**, re-running the
same 63-surface `overflow_sweep` corpus, because the EDGE round's own
pre-existing `p2_cartwheel` drift has since been fixed (`task POP fix round
1`) — the corpus is clean at baseline now (96/96), a cleaner comparison base
than EDGE had.

**A shared, gate-independent regression, found this round.** At
`edgeFloor = "space.gutter"` (not at the literal `2`), BOTH the screen-size
gate and the pointer gate — re-measured side by side at the identical pin —
produce the exact same single new failure:
`p2_cartwheel`'s `HeroTiles/Tiles/TileGrid` zstack overflow at
`desktop-standard (1232x1067) @ +14`, `locale = xa`, now **30px against its
recorded 27px waiver ceiling**. This is corpus drift since EDGE's own
measurement (task SCROLL2's `fa7233a`, 2026-08-28, redistributed sibling
flex allocation in the same subtree), **not a defect of either gating
strategy** — confirmed by re-running the pointer-gate at this same pin and
getting the byte-identical finding. Flagged here as a real, small,
independent follow-up (bump the waiver or fix the tile) regardless of which
option ships.

**Two confirmed, measured wins over the pointer gate (ii)**, mounting
`tab_view` through the real presenter (same recipe as EDGE's desktop probe):

1. **A touch laptop in tablet mode** (`displaySize = "Medium"`,
   `preferredInput = "Touch"`, no mouse capability — a real Windows/ChromeOS
   2-in-1 with its keyboard detached) has `interactionClasses.pointer ==
   false` under (ii)'s own read of the same live `caps.mouse` fact, so the
   pointer gate leaves it at zero padding. The screen-size gate correctly
   floors it: measured directly at 1920x1080, a body-text row moves from
   `x=0`/`x=8` to `x=8`/`x=16` (container/leaf) under a `space.gutter` floor
   — the exact desktop-shaped protection the director asked for, on a device
   the pointer gate cannot see because it currently has no mouse plugged in.
2. **A phone with a Bluetooth mouse attached** (`displaySize = "Small"`,
   `capabilities.mouse = true`) has `interactionClasses.pointer == true`
   under (ii) — `pointer` is a raw capability read, not a screen-size fact —
   so the pointer gate would incorrectly hand a phone the desktop floor. The
   screen-size gate correctly excludes it (`effectiveDisplaySize` stays
   `"Small"` regardless of what peripherals are attached).

**One case that is a wash, not a win: real consoles.** The screen-size gate
does satisfy `effectiveDisplaySize == "Large"` for a real, no-touch, gamepad
console session (which (ii)'s pointer gate — by its own text, "leaving touch
and gamepad sessions at today's explicit zero" — never reaches at all), so
in predicate terms (ii′) is the only option of the three that even tries to
cover consoles. **Measured directly, this has zero visible effect**: at
`distanceProfile == "ten-foot"` (i.e. `effectiveDisplaySize == "Large"`),
`renderer.luau` already adds `effectiveOverscanInsets` (60/90px at 1080p)
to the content insets *before* the edge-floor step runs, and the floor step
itself is `math.max(existing, floorPx)` — so `math.max(90, 2-or-gutter) =
90` on every console-shaped viewport tested (mounting `tab_view` at
1920x1078/Large/Gamepad: a body-text row sits at `x=90`/`x=102` whether or
not the floor opt fires, because overscan already reserved far more than
either floor value). **Consoles were never actually at risk of riding the
edge**, independent of this proposal; reaching them is not a bug the
screen-size gate needs to fix, but it costs nothing.

**The open question this option does NOT settle: the ROG Ally.** The
director's own justification for asking for a screen-size gate was that a
mouse-equipped Ally should not get desktop treatment — measured directly,
`effectiveDisplaySize` **cannot deliver that with confidence today**, for a
concrete, code-level reason: [ADR-0058](../adr/ADR-0058-physical-size-aware-ten-foot.md)
deliberately corrects a touch-capable `"Large"`-reporting device only as far
as `"Medium"`, never to `"Small"` — landing an Ally in the **same bucket as
an ordinary laptop or desktop monitor**, by design (going further would
assert "this is definitely a phone-class device," a claim ADR-0058's own
text says a touch signal alone does not justify, because touch-capable
desktop kiosks exist too). Measured with the real `adaptive.effectiveDisplaySize`/
`interactionClasses` code, both gates land as follows for two plausible Ally
states (the choice between them is an *engine fact this round could not
verify* — ADR-0058 already flagged the real `ViewportDisplaySize` reading
for a physical Ally as device-owed and unmeasured):

| Ally session (worst case: engine reports raw `displaySize = "Large"`) | `effectiveDisplaySize` | gets the floor under (ii′) size-gate | gets the floor under (ii) pointer-gate |
|---|---|:-:|:-:|
| docked, mouse attached | `"Medium"` (corrected) | **yes** | **yes** |
| handheld, gamepad only, no mouse | `"Medium"` (corrected) | **yes** | no |

Neither gate excludes an Ally that the engine reports as `"Large"`; in the
handheld/gamepad-only sub-case the screen-size gate is *worse* than the
pointer gate for exactly the case the director named, because it is not
gated on mouse presence at all. **If the engine instead reports a physical
Ally as `"Small"`** (Roblox's own documented bucket for "most tablet/mobile/
handheld devices," and the more physically apt one) — a fact this round, like
ADR-0058 before it, could not verify without real hardware — the
screen-size gate would exclude an Ally in BOTH rows above regardless of
mouse, a clean, decisive win the pointer gate structurally cannot match.
**This is not this round's premise to assume either way; it needs the same
on-hardware `ViewportDisplaySize`/`TouchEnabled` reading ADR-0058 already
listed as device-owed**, now read as informing this decision too, not just
the ten-foot type-scale one.

### (iii) Status quo + per-app `edgeFloor` adoption in showcase/reference apps only

| | cost |
|---|---|
| Casualties | **0** (opt-in; nothing else moves) |
| Scope | Fixes only the surfaces someone remembers to touch — `tab_view` today, but every other current or future `automatic`-placement `TabView`/sidebar layout ships flush by default until someone notices |
| Root-cause fit | Partial — `tab_view`'s own zero-padding choice was made FOR MOBILE; a per-surface `edgeFloor` there still needs a desktop-only condition to avoid reopening the "eight pixels" mobile problem the file's own comment describes, which is the same input-class check option (ii) already centralizes |

## Recommendation

**AMENDED 2026-08-29 (task EDGE2): Option (ii′), the screen-size-scoped
variant, is now the lead recommendation** — gate the floor on
`env:get("effectiveDisplaySize"):get() ~= "Small"` rather than
`interactionClasses.pointer`, sized at `space.gutter`, applied wherever
`coreSafeContent`/`deviceSafeContent`/`bandSafeContent` already reserve
edges. It is measured at the same casualty cost as pointer-gated (ii) (zero
at the literal `2px` floor; one shared, gate-independent corpus-drift
regression at `space.gutter`, unrelated to which gate ships — see (ii′)
above), while additionally, measurably reaching two real device shapes (ii)
misses: a touch laptop with no mouse attached, and — correctly, in the
other direction — excluding a phone with a mouse attached that (ii) would
wrongly float. **It does not, however, more reliably deliver the director's
own stated motivating case (a mouse- or gamepad-equipped ROG Ally) than (ii)
did** — see (ii′)'s Ally table above. Both (ii) and (ii′) are recorded here
options for the director's word; this document does not silently pick one on
the Ally question, because doing so requires an engine fact (a real Ally's
`ViewportDisplaySize` reading) neither this round nor ADR-0058 could verify.

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

- `p2_cartwheel`'s own pre-existing, edge-floor-unrelated regression from the
  EDGE round (stale waiver/ledger rows, a real card-grid overlap) has since
  been fixed (`task POP fix round 1`) — the corpus is clean at baseline as of
  this amendment. A **new, small, unrelated** regression was found by THIS
  round instead (task SCROLL2's `fa7233a`, 2026-08-28, redistributed sibling
  flex allocation in the same `HeroTiles` subtree): a 27px locale waiver
  ceiling on `HeroTiles/Tiles/TileGrid` is now exceeded by 3px
  (`desktop-standard@+14`, `xa` locale) under EITHER gate at the
  `space.gutter` floor size — needs its own small fix or waiver bump before
  either (ii) or (ii′) ships at that floor size.
- **The Ally question is genuinely open, not a design choice left to the
  implementer** (correcting the prior version of this recommendation, which
  called the exact gate condition "a small design choice"). Whether
  `effectiveDisplaySize`/screen-size gating solves the director's own
  motivating case depends on an unverified engine fact — what a real
  ROG-Ally-class device's `GuiService.ViewportDisplaySize` actually reports
  — that [ADR-0058](../adr/ADR-0058-physical-size-aware-ten-foot.md) already
  listed as device-owed for the ten-foot type-scale question and this round
  found is equally load-bearing here. Until that reading exists, neither (ii)
  nor (ii′) can be said to definitively close the Ally case; the director's
  word is needed on whether to ship the measurably-better-for-laptops (ii′)
  now, wait for the hardware reading, or pursue a compound predicate (out of
  scope for a "screen size" gate as asked) that ANDs a size check with an
  Ally-specific exclusion once one exists.
