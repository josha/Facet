# The locale axis and 390x844 (O-19) — 2026-08-15

The overflow sweep varied display size, text preference and theme package, and
held the LOCALE at each surface's own English copy. O-19 recorded what that was
hiding: `p4_foyer`'s TopBar is clean in English at every preference at 390x844
and overflows by 33px at +10 / 58px at +14 under the shipping 1.4x `xa`
pseudo-locale. Both the axis and the viewport now exist.

## What landed

**The viewport.** `phone-390x844` joins `tests/lib/device_views.luau`, so both
always-on sweeps visit it (the file's own rule: a viewport only one of them
visits is a viewport where one of the two questions is never asked). It is not a
duplicate of the two narrow rows — it is *taller* than both while barely wider,
which is the shape that keeps a page fitting vertically while a chrome row runs
off the right edge.

**The axis.** A third pass in `tests/overflow_sweep.spec.luau`, by the only two
mechanisms the corpus has:

* a fixture exporting a flat `copy` table (17 scenarios) gets it put through the
  SHIPPING pseudo-localizer — the same seam and function `examples_gallery.spec`
  asserts against, so the expansion swept is the expansion pinned elsewhere;
* a reference proof takes `deps.locale = "xa"` at build, plus its own
  `steps.locale` where it has one (p3/p4/p5; p2 reads the fact alone).

**It is a second MOUNT, not a swing.** A fixture reads its copy when it builds,
so unlike the preference and the package this axis cannot ride an `env:set`. It
is therefore the only axis here with a per-cell mount cost, and the tier is
chosen for that: every viewport at +0 and at +14, no theme package.

**Reach is derived, not claimed.** A surface with no `copy` export and no locale
fact builds byte-identical text; mounting it again to discover that costs nine
mounts to learn nothing. Those surfaces are not offered the pass, and the
`REACH` case *prints* every one of them, deriving the answer from an English
text digest against the expanded one. Today: **21 of 59 swept surfaces have a
locale form.**

## What it surfaced

**31 findings on the first run — and 19 of them were noise the instrument itself
produced.** Those 19 came from surfaces the pass mounted but could not move (no
copy, no locale fact), so each was an English finding wearing a locale label.
Not offering the pass to those surfaces removed all 19. **The ledger is 12 rows**
(`LOCALE_WAIVERS`), each with a px ceiling, a smallest preference and the cells
it fires in, under the same four rules the English waiver list is under.

The genuinely new information, triaged under the same ruling as O-21 (fix what
hides text; waive what does not — `tools/lune/triage_overflow_waivers`):

| finding | what a player loses | disposition |
|---|---|---|
| `p4_foyer /Foyer/Root/TopBar` — **128px at +0** (English: 10px at +14) | the notice badge and the bell it sits on leave the screen; measured 19px off at +4 on a 359x718 phone | **owed** — the wrap was tried and measured WORSE (below) |
| `p2_cartwheel` cart section, 31px hstack + 27px overlap at +14 | a surface with **no English waiver at all** — the axis found it | recorded, owed |
| `card_rail /CardRail` page, 78px at +14 | the page runs past the fold | recorded, owed (same root cause as its English card-plate rows) |
| the other 9 | the same nodes the English list already carries, seen under expansion | recorded with their own ceilings |

**390x844 surfaced three more, all themed and all re-recorded rather than new
classes:** `05_word_game`'s keyboard keys and `06_tile_game`'s rack tiles report
their content box collapsing 3px and 2px *worse* than the widest cell the tier
had (Pixel Quest 29 → 32, Glossy Touch 37 → 39), and Pixel Quest's `barTrack`
inset collapses `time_curves`' two progress fills — a 2px sliver of a bar with no
copy in it, waived with that reason.

## The p4_foyer TopBar: a measured negative result

The obvious repair — `wrap = true`, which fixed six other rows this day — was
applied and **reverted, twice, on measurement**:

* the bar's `SearchSlot` declares `fill` on the main axis and a `layoutPriority`;
  a wrapping stack has neither a single line to fill nor a placement priority,
  and the solver files a finding for each. Dropping both (the slot hugs) clears
  those;
* but the wrapped bar is TALLER, and that pushed `/Foyer/Root` and `HomeBody`
  over on the short landscape rows — `HomeBody` went from a 16px waived overflow
  to **76px**, and `/Foyer/Root` overflowed where it had been clean.

So the repair trades one hidden badge for a worse page, and the row's own
in-file comment already names why the alternatives do not work (a text node's
shrink floor is its longest word, and the brand is the single word "Foyer").
What is left is a design call on the proof's chrome — drop the wordmark on a
compact phone, or give the bar a second form — which is a change to a reference
proof, not a sweep repair. Recorded here so the next agent inherits the
measurement rather than repeating it.

## Cost

The whole file went from ~14.2 s to **16.3 s** (median of three timed runs) with
390x844 *and* the locale pass added — +15 %, against a 79 s suite. The tier is
what buys that: two preferences instead of four, no theme cross product, and the
pass not offered to the 38 surfaces it could not move.

## Mutation evidence

| mutation | named case that reddened |
|---|---|
| `withPseudoCopy` made a no-op (the expansion never reaches the copy) | `REACH: the pass moved the copy it claims to…`, `every locale row still fires…`, and `scenario 'card_rail'` — 3 failed |
| the `p4_foyer /Foyer/Root/TopBar` locale row deleted | `proof 'p4_foyer': the solver reports NOTHING at any swept viewport…` |
| the 390x844 viewport removed from `device_views` | `every ledger row still fires — a stale row is a fixed defect, delete the line` (the two `time_curves` rows fire nowhere else) |

Unmutated: 68 cases green in the sweep, 5561/0 in the suite.
