# Five rulings needed to finish round 3 (2026-08-13)

Everything in the round-3 ledger that could be closed from a desk is closed or in
flight. These five cannot be: each is a **product decision**, not a repair, and
guessing one would be inventing policy. Each is stated with the measurement, the
options, and a recommendation.

---

## 1. A shrinkable label can land outside its box (ledger #6)

**Measured.** Three `shrinkWeight=1` texts in a 120px box solve to
`x0 w120 / x120 w120 / x240 w100` — two land *wholly outside* the box.
`absorbTier` absorbs at most `Σ(basis − floor)`; any residual deficit is simply
not absorbed, and nothing clips.

The shrink pass is best-effort **and its own diagnostic says so** — this is
documented behaviour, not a silent bug.

| option | consequence |
|---|---|
| **A. Clip at the box** (recommended) | Content never paints outside its parent. Text is cut off instead — visible, but bounded and debuggable. |
| B. Keep best-effort, make it loud | A solver finding fires whenever residual deficit remains, so it shows up in the sweeps instead of on a device. Nothing moves; the defect becomes visible rather than fixed. |

**Recommendation: A.** "Paints outside its parent" is the failure class this
framework has fixed four separate times; a fifth spelling of it should not be
policy.

---

## 2. `shrinkWeight` flips the `ViewThatFits` winner (ledger #7)

**Measured, and it invalidates a round-2 claim.** Round 2 §2.4 says
`ViewThatFits` "picks its candidate before any of this and is therefore
unaffected". PASS 1.5 (the measure-side shrink, landed a day later) made that
false. Swept 150→420px: adding `shrinkWeight=1` to a candidate's children flips
the chosen candidate at **10 of 28 widths (290–380px)**, because the candidate
now *reports* a shrunk extent and `fitsW` becomes true.

| option | consequence |
|---|---|
| **A. `ViewThatFits` measures candidates UNSHRUNK** (recommended) | "Does this fit?" means "does it fit at its natural size". A candidate is chosen for what it is, then shrunk if the chosen one still needs it. Predictable; matches what the name says. |
| B. Keep shrink-aware fitting, document it | More candidates "fit", so the picker prefers richer layouts at narrow widths. Defensible, but it means `fits` silently means "fits after squeezing" and a designer cannot predict the winner. |

**Recommendation: A**, plus correcting the round-2 §2.4 sentence either way — it
is currently false on disk.

---

## 3. A BLOCK table publishes a scroll path it has no host for (ledger #10)

**Confirmed.** `table.luau:2869-2871` returns `…/Main/Body` unconditionally with
no `scrolls` check. The crash half is already fixed. The *design* half is live in
the shipped playlist example: open a swipe tray, scroll the page, and **the tray
rides along still open**, because "any scroll closes the tray" is bound to a node
that never scrolls.

| option | consequence |
|---|---|
| **A. Publish nothing when the table does not scroll** (recommended) | The tray-closing rule binds to the real scrolling ancestor, so a page scroll closes the tray as users expect. |
| B. Leave it | A tray stays open across a page scroll in every BLOCK table. Currently shipping. |

**Recommendation: A.** B is the reported symptom.

---

## 4. The row-actions menu is not clamped to the viewport (ledger #12)

**Confirmed, unchanged.** A trigger at y=508 on a 600px viewport puts the menu at
y=556..629 — 29px past the bottom edge.

| option | consequence |
|---|---|
| **A. Flip the menu above the trigger when it would overflow** (recommended) | Standard platform behaviour; the menu is always fully on screen. |
| B. Clamp it to the edge | Simpler, but the menu can then cover its own trigger. |

**Recommendation: A**, since the anchor geometry needed is already computed.

---

## 5. The "Edit item" wrap rule (ledger #13)

`renderer.luau:452` is unchanged. The doc's own root-cause analysis gives the
honest rule: **wrapping is right only when the phrase's longest word fits the
drawable width.** Today the check is coarser than that, so a phrase can be
allowed to wrap into a column too narrow for one of its words, and that word
overflows.

| option | consequence |
|---|---|
| **A. Adopt the longest-word rule** (recommended) | Matches the analysis already written; a phrase wraps only when wrapping can actually succeed. |
| B. Leave it | Occasional overflow on narrow columns with long words — worst in German/Finnish pseudo-loc, where this project already has a standing 1.4× expansion rule. |

**Recommendation: A**, and it interacts with the localization rule the studio
already binds itself to.

---

## Also worth a decision, not blocking

**Should `row_actions.luau` and `screen_target.luau` be split?** They are 219,701
and 229,860 characters. The old reason to split — a 200k sync cap — turned out to
be false (`docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md`: both
load into Studio intact; the cap is on *writing* `Source` from code). The
remaining reason is maintainability: `row_actions.luau` has a documented history
of repeat defects, several of them found this session. That is a real reason, but
it is a refactor to schedule deliberately, not an emergency.
