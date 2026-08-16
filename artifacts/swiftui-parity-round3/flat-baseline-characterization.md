# O-22 — the neutral flat baseline, characterized (2026-08-15)

`lune run tools/lune/check_flat_baseline` exited 1 with **200 problems**. This is the
decomposition, the dump-versus-invariant call, the fix, and the mutation evidence that the
check still bites afterwards.

Everything below was run in this working tree by the agent that wrote it; every number is
from a transcript it holds. Tier: **headless Lune only** — a regression signal, not a Studio
claim and not a device claim. Nothing here needs one: the instrument under repair is itself
a headless dump comparison, and the two things it measures (a prop key's presence and one
container's reported width) are facts about the solve, not about paint on a screen. The
Studio and device tiers stay owed exactly where they already were (O-3).

---

## 1. The decomposition — 200 = 1 + 198 + 1, and the last one is the finding

The check runs **two** instruments and reports their problems in one list, which is why the
count needs splitting before it means anything:

| # | Instrument | Problems | What it is |
|---|---|---|---|
| 1 | reproducibility pin (stored dump vs a fresh regenerate) | **1** | the stored artifact was stale — a chore, not an accusation |
| 2 | compatibility claim (fresh vs the frozen 0.6.0 baseline) | **199** | 198 × `textWrapped`, and **1 rect** |

### 198 × `textWrapped=false` — the known prop

From **`fb76787`** (director ruling 5, the wrap rule) — which is **O-13's own closure**, so one
owed row's fix re-broke another. The solver publishes `textFacts.wraps`
(`src/layout/solver.luau:1184-1205`) and `applyTextVerdicts` writes it at the paint seam
(`src/render/renderer.luau:1739-1751`).

Measured across the whole regenerated dump (24 renders, 8 fixtures × 3 viewports):

- **312** nodes carry a `textWrapped` key. **312 of 312 are `false`.** Not one is `true`.
- Of those 312, **198** also exist in the frozen 0.6.0 baseline and are not otherwise
  characterized — which is the 198.
- The nodes that **do** wrap carry **no key at all**: `02_playlist_table`'s `/Playlist/Page/Hint`
  wraps to two lines on the phone (rect `16,105 330x34`, two 17px lines) and has no
  `textWrapped`; its one-word `Title` beside it has `textWrapped=false`.

That asymmetry is not an accident, and it turned out to be the load-bearing fact for the fix.
The seam is minimal-write and `nil` means *never written*, which is the adapter's own default
(wrap on whitespace) — so a wrappable node costs **zero** writes and `false` is the only value
a fresh node can carry.

### 1 rect — `06_tile_game` `/TileGame/Page/rack`, `358x56` → `353x56`, phone only

This is the remainder, and it is **not** `textWrapped`. It was found by decomposing rather
than counting: 199 ≠ 198.

Root cause, bisected rather than reasoned — 8 worktree builds over the 167 commits between
`bd623e1` (where the rack is 358) and `HEAD`, regenerating the dump at each and reading the
rack's rect:

```
bd623e1  358x56     fc8e34a  358x56     421e5f0  358x56     110242a  358x56
67b1166  358x56  ->  02b9df1  353x56  <- first bad     66feca6  353x56   3c67718  353x56
```

**`02b9df1`** — the column-major `UI.Grid` refactor. Its own message names the mechanism:

> measure summed the UNROUNDED lane share while arrange painted the floored one, so a grid
> offered a width that did not divide evenly reported up to `lanes - 1` px more than it drew.

The rack is 7 uniform lanes in 358px with six 4px gaps: `(358 − 24) / 7 = 47.71`, arranged at
47. The last tile's right edge has always been at 353; the container claimed 358. **The 5px is
that over-report to the pixel** (≤ `lanes − 1` = 6).

**Nothing moved on screen.** All seven tiles are byte-identical at all three viewports —
phone `x = 16/67/118/169/220/271/322`, `47x56` each; desktop and tablet racks unmoved at 416,
because 416 divides evenly into 7 lanes of 56 and there was no remainder to lose. So this is
the measure side coming into agreement with a paint that never changed.

**The finding worth naming:** `02b9df1`'s message says *"No baseline moved (5318 -> 5334, +16
new)"*. That is true of the test suite and false of the flat baseline, which moved by one
node — and this check was the only instrument in the repo that said so. It could not say so
out loud at the time because it was already red for an unrelated reason, which is the general
cost of leaving a checker red: **a red check cannot report the next defect.**

---

## 2. The call: dump, or invariant?

**Both — picked per fact.** The question turned out to be answerable only after separating the
two instruments the file runs, because they are not the same kind of thing:

1. **The reproducibility pin** (`CURRENT` must byte-equal a fresh regenerate) **carries no
   claim.** Its only job is that the artifact a reader may cite is current — which is what
   ADR-0032's migration step 1 needs when it names *"the flat baseline is unchanged"* as its
   proof. It is *supposed* to go red on every legitimate change to the render. **It cannot be
   expressed as an invariant**, because "is this file current" has no rule to compare against.
   Keep it, and read its red as a chore.

2. **The compatibility claim** (`BASELINE_3_5`, frozen at 0.6.0) is where a difference means
   something — and this file **already contained the rule form** before it had a name.
   `ALLOWED_ADDED_PROPS` compares a *property* against a *rule* ("this key may newly appear,
   for this reason") rather than against a stored value, which is why the two seam-level
   corrections that preceded this one — `textSize` (2026-07-25) and `textFont` (2026-08-02) —
   each cost **one entry** instead of hundreds. `textWrapped` is the third member of exactly
   that family and takes exactly that form.

So the honest answer to *"will the next legitimate prop re-break this row?"* is **no, and it
already didn't twice** — the mechanism that survives a new prop has been in this file for
three weeks. What re-broke O-22 was not the absence of an invariant; it was that **nobody ran
the check** while shipping `fb76787`.

**What is NOT being done, and has now been declined three times:** moving `BASELINE_3_5`
itself. That would make every future difference agree with whatever the tree does. The
regenerate here is of the *reproducibility* artifact only.

### The one thing that had to change: a rule with no value was too weak

`ALLOWED_ADDED_PROPS` said only *"this key may appear"* — any value, forever, on every node.
For `textSize`/`textFont` that is unavoidable (their whole content is that each node resolved
to its *own* role). For `textWrapped` **the value is the invariant**: a `true` in this dump
means the renderer paid a write to restore the engine default — the zero-write contract
broken, on hundreds of nodes, silently.

So entries gained an optional `value`, and `textWrapped` is pinned to `"false"`. An entry with
no `value` behaves exactly as before; an entry with one forgives that value and nothing else.

**This is strictly tighter than the mechanism it extends**, and §4's control proves the
difference is real rather than rhetorical.

---

## 3. The fix

| Change | File |
|---|---|
| `ALLOWED_ADDED_PROPS` entries may pin a `value`; `textWrapped` added, pinned to `false`, with the zero-write contract stated | `tools/lune/check_flat_baseline.luau` |
| `ALLOWED_RECT_DRIFT` entries may name one exact `path` instead of a `prefix`; the rack added as an exact path | `tools/lune/check_flat_baseline.luau` |
| Header: the two instruments, and why only one of them is a frozen dump | `tools/lune/check_flat_baseline.luau` |
| An absent stored input is a named problem, not a Lune stack trace | `tools/lune/check_flat_baseline.luau` |
| The frozen 0.6.0 baseline is now **tracked** (see §5) | `.gitignore` |
| Regenerated + re-characterized; the stale sha pin replaced and the staleness recorded | `artifacts/rich-skinning-v2/rows/neutral-render-dump.json`, `artifacts/rich-skinning-v2/rs-a1-image-is-element.json` |

The rack is an **exact path** and not a prefix deliberately: a prefix would have waived the
seven tiles under it too, spending their rect coverage to buy nothing, when the fact being
forgiven is about the container alone. §4's M2 is the proof that it did not.

Result:

```
check_flat_baseline: PASS (1461 flat nodes byte-compared against
artifacts/theme-packages-and-skinning/final-neutral-dump.json; 9 characterized prop deltas,
5 characterized new nodes, 3 characterized added prop keys, 9 characterized rect-drift
scope(s), 2 characterized class substitution(s); no other rect/hit/class change)
  uniform vertical shifts forgiven: 02_playlist_table|desktop /Playlist/Page/Restore +25px;
  ... /Playlist/Page/Tracks +25px; phone-portrait +42px; tablet +25px
```

---

## 4. Mutation evidence — the check still bites

Both mutations were made in **source**, so they flow through the regenerate the check does
itself; both were reverted and the green re-confirmed (`git diff` clean on both files).

### M1 — break the minimal-write contract the new value pin exists for

`src/render/renderer.luau:1746`, `if (if previous == nil then true else previous) ~= wraps`
→ `if previous ~= wraps`. This is not an arbitrary perturbation: it is precisely the
regression the pin protects against — the seam stops treating `nil` as the engine default and
starts writing `textWrapped=true` on every wrappable node.

```
check_flat_baseline: FAIL [UI-STYLE-001] — 436 problem(s)
435 of them name textWrapped=true, e.g.
  05_word_game|tablet|nodes|/Wordle/page/col/board/tile5_5/ch: props changed
    '…textSize=20' -> '…textSize=20;textWrapped=true' and is not characterized
```

**435 named cases.** ✅ bites.

### M1-control — the same mutation, with the `value` pin removed

The counterfactual that decides whether the pin is load-bearing or decorative. With
`value = "false"` deleted (so the entry behaves exactly like the `textSize`/`textFont` ones)
and M1 still live:

```
check_flat_baseline: FAIL [UI-STYLE-001] — 1 problem(s):
  - the stored dump … is not reproducible from the current tree — regenerate it …
```

**Zero compatibility findings.** The 435-node regression is completely invisible; the only
survivor is the reproducibility chore, which a regenerate would silence — and the check would
then be green *with the defect shipped*. That is the "a check that compares nothing" shape,
reproduced on purpose. The pin is load-bearing.

### M2 — prove the exact-path rack waiver does not leak to its children

`examples/gallery/examples/06_tile_game.luau`, the rack's `gap = "xs"` → `"s"`. This moves the
container's width (waived) **and** every tile inside it (must not be).

```
check_flat_baseline: FAIL [UI-STYLE-001] — 20 problem(s)
19 name a rack CHILD, e.g.
  06_tile_game|desktop|nodes|/TileGame/Page/rack/rt7: rect changed
    '376,440 56x56' -> '400,440 56x56' (never allowed)
0 name /TileGame/Page/rack itself (correctly waived)
```

**19 named cases, and the container correctly silent.** ✅ bites, at exactly the intended
width.

### Null results — recorded, not hidden

None this round: both mutations reddened, and the control behaved as predicted. The *absence*
of a null result is itself worth stating, because this project has published two this week and
their value comes from being reported when they happen rather than from being rare.

---

## 5. A second finding, from trying to answer "is a frozen dump the right instrument"

**The frozen 0.6.0 baseline was not in version control.** `artifacts/**/*.json` is gitignored,
and the rule's own comment justifies itself with *"it is REGENERABLE (the capture tools and the
scenario rig are both in-tree)"*.

`artifacts/theme-packages-and-skinning/final-neutral-dump.json` **is not regenerable.** It is a
frozen snapshot of a tree from 2026-07; `_theme_baseline` renders *today's* source. It is the
only input to R9's byte-compatibility claim, it is read by six gate rows, and until today it
existed on exactly one laptop. A clone could not run the check at all, and lost the claim with
the machine.

Measured, not assumed — with each input moved aside in turn:

| Input absent | Before | After |
|---|---|---|
| `CURRENT` (regenerable) | `No such file or directory (os error 2)` + Lune stack, **exit 1** | one named line + the exact regenerate command, exit 1 |
| `BASELINE_3_5` (frozen) | same stack, **exit 1** | *"NOT regenerable … restore it from git rather than re-rendering one"*, exit 1 |

**What this did NOT turn out to be:** the exit code was 1 in both cases before the change, so
no gate row ever passed on a missing input. The defect was the message, not the verdict — and
that distinction is recorded because the first hypothesis (a silent pass on a fresh clone) was
the more alarming one and it was **false**. It was checked before it was written down.

Fix: one narrow negation in `.gitignore` with its reason inline (409 KB, once), and the
sibling regenerable dump stays ignored on purpose.
