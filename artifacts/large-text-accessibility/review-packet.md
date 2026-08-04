# Large-text accessibility — review packet (LT-P1 physical / LT-P2 human)

**Stage:** large-text-accessibility (Step 8.5) · **Prepared:** 2026-08-03
**Status:** LT-P1 `PENDING_PHYSICAL`, LT-P2 `PENDING_HUMAN` until the passes below run.

Everything automatable is closed by the gate; these two rows are the honest
remainder that only a real device and a human judgment can close. The user has
a phone available — the pass is designed to take ~10 minutes.

## What is being judged

1. **LT-P1 (physical):** the real OS/player text-size path on real hardware —
   the Roblox app's actual `Largest` preference, real touch, real screen — for
   the public gallery surface and the production Sponsor View, portrait AND
   landscape.
2. **LT-P2 (human):** subjective readability at large text: hierarchy holds,
   nothing feels cramped or clipped, the disclosure plate reads as an answer
   (not a pop-up ad), reflowed layouts still look designed rather than survived.

## Phone pass — procedure (LT-P1)

Prereqs: the Rascal Rally place published to the test universe (the usual
publish flow; DO NOT publish from a dirty working tree — publish after this
stage's changes are synced), phone logged into the test account.

1. On the phone: Roblox app → in-experience or app Settings → **Text size →
   Largest**. (The in-experience Escape menu carries the same stepper the
   Studio probe drove.)
2. Join the Rascal Rally place. Hold the phone **portrait**.
3. Pre-start card: both role CTAs fully readable — the secondary CTA must read
   "Sponsor a Race" complete, never "Sponsor a…" (this exact truncation was the
   live defect at Largest; its fix is in this stage).
4. Pick **Sponsor a Race**. Walk the surfaces in order, portrait first, then
   rotate landscape and repeat: role pick → director table (racer list: long
   names ellipsize inside their own cells; position numerals NEVER truncate;
   rows don't overlap) → watch a racer (watched card) → cards in hand (captions)
   → race HUD (ticker, toasts, captions, countdown, lap text — all complete) →
   results (both roles if time allows: CTAs full, countdown full, coin totals
   full, standings names ellipsized-with-a-reason only).
5. **Long-press a truncated racer name** → the full-name plate appears while
   held, leaves on release. (Touch long-press is unprovable in Studio; this is
   its only real test.)
6. Mid-session: open the menu, step Text size **Largest → Medium** → the UI
   reflows in place without losing your spot; step back to Largest.
7. Note ANYTHING that is clipped, overlapping, unreachable, or unreadable, with
   surface + orientation. Screenshots welcome.
8. Set the phone's preference back to your own value when done.

## Desktop micro-pass (5 seconds, closes the raw-hover row)

In any Studio Play session of the gallery place with the `preferred_text`
scenario: move the real mouse over the truncated "Bartholomew…" line and rest
~half a second → the full-name plate must appear; move away → it leaves.
(Studio cannot synthesize mouse MOVEMENT, so this row needs one human hover.)

## Recording results

Reply with pass/fail per numbered item (or "all good"). Results land in
acceptance.md (LT-P1 → PASS_PHYSICAL with device name, LT-P2 → PASS_HUMAN) and
this packet gets the transcript. Any failure becomes a FAIL_PRODUCT row fixed
before the stage closes.

## Director judgment rows (surfaced by the sweep; each measured and asserted,
none silently fixed)

While judging LT-P2, four product calls are open — a look at each on the phone
pass is enough:

1. **Map name-tag plate** (Larger/Largest): the name paints ~11px taller than
   the ratified 72×18 plate. The name stays reachable (long-press disclosure).
   Grow the plate, or accept the overhang?
2. **667×375 results above Large**: no declared arrangement fits (the poorest
   column wants 268px in a 233px box); the surface shows its declared column
   fallback. Should another region be allowed to scroll or drop at raised
   preferences (§S16.5 currently declares exactly one scroll region)?
3. **The recap's one-line REDUCED form** still ellipsizes on the two narrow
   sponsor rows (raising it collapses the arrangement entirely — worse).
   Acceptable, or re-rank the recap's lane?
4. **Racer row on 667×375** wants 17px more than its lane at EVERY preference
   (pre-existing, not a large-text defect). Fix in a follow-up?

## Rollback / exit

Nothing in this pass changes state beyond the phone's own text-size setting
(step 8 restores it). Leave the experience normally.
