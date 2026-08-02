# A proxy surface must live in the coordinate space its driver speaks

**Date:** 2026-07-28 (director fix round, sponsor-framework-gaps)

## What happened

The director reported the drag ghost "in an odd offset position" under both
finger and mouse. Every headless drag test was green. Live measurement told the
whole story in two numbers: ghost center (229, **195**) against an aim point of
(229, **137**) — a vertical error of exactly 58 px, the CoreGui inset.

The drag registry speaks WINDOW space (its rects come from `screenRectOf`,
which includes the core inset). The presenter's ghost surface mounted with
`rootPolicy = "coreSafeContent"`, whose root frame already sits BELOW the
inset. Window-space numbers written into a root that starts at the inset get
the inset twice: the ghost rode exactly `GuiInset` pixels below the finger.

## The fix

The ghost surface attaches with `rootPolicy = "edgeToEdge"` — its root IS the
window origin, so registry window coordinates land 1:1
(`src/present/presenter.luau`, dragProxyHost). Verified live: ghost center ==
aim center to the pixel.

## The rules

1. **A surface driven by another system's coordinates must mount in THAT
   system's space** — or convert at the seam. Never let "both sides look like
   pixel numbers" hide two different origins.
2. **This defect class is invisible headless.** The test worlds set every inset
   to zero, so window space and root-local space coincide and nothing can
   disagree. The fake adapter models no root insets either (checked — no inset
   plumbing at all). Any coordinate-space seam between two mounted surfaces is
   therefore a LIVE-VERIFY row by construction; say so in the acceptance
   ledger instead of trusting a green suite.
3. **Diagnose space bugs with two absolute centers in one probe.** One
   `execute_luau` reading both rects in the same space beats any amount of
   staring at screenshots — the 58 px literally names the culprit.
4. Related recurrence: the toast-capture race bit AGAIN this round (a reset +
   single burst drains in ~5 s, slower than a "wait then shoot" round trip).
   The rule from `transient-ui-outlives-nothing-sustain-before-capturing.md`
   stands: sustain the state with a refill loop, shoot immediately, and never
   add a "let it settle" sleep you haven't checked against the state's
   lifetime.
