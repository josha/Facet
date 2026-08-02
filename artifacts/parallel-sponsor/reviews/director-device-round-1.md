# Director device round 1 — real iPhone pass (2026-07-31, verbatim)

Evidence: `IMG_3548.jpeg` (repo root) + `selection.mov` (frames extracted).
These are REAL-TOUCH findings — several live exactly in the recorded
injection blind spot (in-scroll-host activation), which is why the automated
rows could not catch them.

| # | Director's words | Pixel/diagnostic reading |
|---|---|---|
| DB-1 | "avatar icon is missing from a played card like we had in legacy mode" | Gate pills render lock/ring WITHOUT the author badge (video frames: every pill badge-less). Legacy pill = author badge at the left cap + ring. Restore the badge per §4.2 (`play` = badge + ring; `locked` = lock, badge drops) |
| DB-2 | "when doing the FTU, no dots hinting to pick up the card and drop it on flash (in legacy, we did work to handle alignment and edge cases like if flash was below the scroll view)" | The M26 FTUE pull line never renders — OWN-D22's owed "target fact" was never wired. Wire it with legacy's alignment + below-scroll edge handling (SponsorFtue's pull-line target resolution; cite) |
| DB-3 | "there is a random blue stripe to the left of the racer (bolt in this photo) and on the bottom right empty card slot. That should not be there. See IMG_3548.jpeg" | THREE elements: (a) the watched-row leading MARKER bar (F4's form) — DIRECTOR OVERRULES: remove it (watched carries plate level only); (b) the blue OUTLINE on Bolt = the FOCUS RING showing under REAL TOUCH — must never paint on a touch session (framework input-class suppression bug on device); (c) the empty slot's bottom blue stripe = the refill-fill bar painting as a stray accent stripe — match legacy's empty-slot refill form |
| DB-4 | "Tapping to pick up/drop a card doesn't work. I can tap to pick up card, but when I tap on racer, the racer highlights green,…card just sits there. No drop onto the racer." | CROWN BUG: real-touch tap-commit does not fire. The verdict paints (green = legal) so the tap reaches the row; the commit routing (armed session + row tap → play) never runs on the real touch path. Trace the device tap flow end to end (armOnTap session + dropTarget tap arbitration vs the list's selection); the headless drivers pass, so the divergence is in the REAL input path |
| DB-5 | "I had a card picked up, round ended, and the next round started with it picked up but not usable, and cards in deck didn't reset. The card should dismiss at the end of the race and the deck should reset between rounds." | Round-boundary lifecycle: the armed/held session must CANCEL at the racing→grace/results edge and the hand must re-derive from the fresh round's attributes. PlayFlow session + hand state leak across rounds |
| DB-6 | "I raced first, at the end on finish screen picked sponsor, and the finish screen changed. It shouldn't change." | The results VARIANT must LATCH to the role held during the displayed round; picking the next role changes ONLY the CTA labels/emphasis (per DV5-2's server-confirmed-role rule). Currently the whole screen re-renders to the sponsor variant on role confirm |
| DB-7 | "if you look at selection.mov, you'll see a bad drop sequence… a blue outline within a yellow highlight… weird transition where the yellow fades into the blue outline and fades out. Please match the coloring and highlighting we had in legacy mode… The racer should not have an outline ring at all." | Video frame: Flash's row = yellow/olive wash + blue outline + blue marker bar simultaneously — channel soup. Match LEGACY's drag/aim/drop paint exactly (row wash toward the verdict/family hue per SponsorGesture:976 at legacy's alpha; NO outline ring on racers, ever — this also retires the verdict stroke form on rows). One channel, one meaning |
| (obs) | — | Video frame also shows the "You're cooking!" caption overprinting the masthead Lap chip in portrait — caption band vs topbar layering; fix with the round |

Real-device verification note: fixes prove headless + Studio, but DB-3(b),
DB-4 and DB-7 close only on the director's next device pass — say so in the
round report.

---

## Disposition (2026-07-31, UI engineer)

All seven **FIXED with tests + mutations**; the observation too. Ledger rows
OWN-D49…OWN-D58, spec amendments A22 (row paint / watched / focus ring) and A23
(the author badge). Suites: game 2801 → 2818, LuauUI 2743 → 2752, both green;
stylua clean; 11/11 legacy checksums unchanged.

**DB-4's real-path divergence, named:** the presenter's ADR-0013 input auto-wiring
was a ONE-SHOT walk at `present()` time. The Sponsor HUD's whole interactive tree
lives inside `HudRegion` (`isSponsor and phase ~= "results"`), and
`init.client.luau` constructs the presenter at CLIENT STARTUP — while the player is
still a racer — so the racer list contributed nothing at all: no `handleActivate`
(the tap-commit), no `handleCancel`, no focus groups, no `bindController`. A tap on
a row still moved focus (that is unconditional), the focus observer re-aimed the
armed session, the row painted its legal verdict — and then nothing dispatched.
Every headless row passed because every rig seats the sponsor BEFORE constructing
the presenter. Fixed in the framework (`presenter.refresh()` re-discovers
contributions from the live tree, exactly as it already re-derived the focus map),
and the drivers made honest (`adapter.touchTap` models the real three-part order).

**Device re-check owed:** DB-4, DB-3(b), DB-7 (native routing, the touch input
class, and a moving image are all outside what any harness here can prove), plus a
look at DB-1's badge and DB-2's dots at device scale. See the review packet §6b.
