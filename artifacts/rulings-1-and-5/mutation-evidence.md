# Mutation evidence — rulings 1 and 5 (2026-08-14)

Every check added for the degrade cascade and the wrap rule, broken deliberately
and watched to redden a NAMED case, then restored. `mutate.py` beside this file
is the runnable harness: it patches one anchor, runs the named specs, restores
the file from a scratch backup, and reports the cases that turned red.

A check never seen to fail is decoration. Three of these did not bite on the
first run and are recorded with what was missing, because that is the finding:

* **M1** — the compact rung looked inert. Absorption takes only what the deficit
  asks for, so on a SINGLE shrinkable child the compact rung and the ellipsis
  rung reach the same width. A differential sweep over 1200 configurations found
  144 that differ, all with a SIBLING: at the compact rung `A` freezes at its
  compact form's width and the remainder redistributes, so `B` keeps its whole
  string; without the rung both slide into the ellipsis floor and `B` is cut.
  New case: "the compact rung SPARES A SIBLING".
* **M7** — the `availW` clamp fix had no witness at all. New case: "a FIXED-width
  label is clamped to ITS OWN box, and says so when it is cut".
* **M8** — "the rungs re-run from the original basis" is only observable through a
  `fill` sibling, which no case had. New case: "the cascade absorbs the deficit
  ONCE, so a `fill` sibling is handed nothing extra".

| # | mutation | file | a NAMED case that reddened |
|---|---|---|---|
| M1 | the compact rung stops lowering the floor | solver | the compact rung SPARES A SIBLING |
| M2 | the truncate rung stops lowering the floor | solver | rung 3: … it TRUNCATES, on one line, with the box intact; (a) THE CASCADE |
| M3 | the clip crop is removed | solver | what the cascade cannot absorb is CROPPED at the box |
| M4 | the clip is widened to every overflowing stack | solver | a stack that declared NO shrinkWeight is untouched |
| M5 | the wrap-rule gate is removed | solver | …one whose longest word does NOT fit is measured on ONE line |
| M6 | the zero-width guard is removed | solver | a ZERO-width box gives no verdict |
| M7 | the clamp reverts to the parent's offer | solver | a FIXED-width label is clamped to ITS OWN box |
| M8 | the rungs stack instead of re-running | solver | the cascade absorbs the deficit ONCE |
| M9 | ideographic breaks removed from minWidth | text_metrics | an ideographic run breaks between CHARACTERS; …a CJK line still WRAPS |
| M10 | emoji treated as breakable | text_metrics | an EMOJI cluster is NOT split |
| M11 | the wrap verdict never reaches the adapter | renderer | the SOLVER's verdict reaches the adapter; the ADAPTER makes the same call |
| M12 | the adapter ignores the solver's verdict | screen_target | the ADAPTER makes the same call, from the same string AND the solver's width verdict |

12 of 12 bite.
