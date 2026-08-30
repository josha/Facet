# A red check cannot report the next defect — and a count that does not decompose is one

**2026-08-15, O-22.** `check_flat_baseline` had been red for a day with **200
problems**. The ledger already knew the cause: `fb76787` had made `textWrapped` a
written prop on every text node, and the stored dump was never regenerated. The
obvious move was to characterize `textWrapped` and go green.

**199 is not 198.** One of the problems was not `textWrapped` at all:

```
06_tile_game|phone-portrait|nodes|/TileGame/Page/rack:
  rect changed '16,459 358x56' -> '16,459 353x56' (never allowed)
```

Bisected across the 167 commits since the last regenerate (8 worktree builds,
regenerating the dump at each): `02b9df1`, the column-major Grid refactor. Its own
message names the mechanism — measure summed the **unrounded** lane share while
arrange painted the **floored** one, so a grid offered a width that does not
divide evenly reported up to `lanes - 1` px more than it drew. Seven lanes in
358px with six 4px gaps: `(358−24)/7 = 47.71`, arranged at 47, last tile's right
edge at 353. The container had been claiming 358.

It is a **correction**, and the fix is right. Two things about it are the lesson.

## 1. The commit said "No baseline moved". The baseline moved.

That sentence was true of the test suite (5318 → 5334) and false of the flat
baseline, which moved by exactly one node. The author had no way to notice:
**`check_flat_baseline` was already red for an unrelated reason, so it could not
report this one.** A red check is not merely a missing signal — it is an
*actively silenced* one, and everything that lands while it is red arrives
unmeasured. The cost of leaving a checker red is not the row; it is every defect
the row would have caught in the meantime.

Corollary for the commit message habit this repo has: *"no baseline moved"* is a
claim about an instrument, and it should be made by running the instrument, not
by reasoning that nothing should have moved. Here the reasoning was sound and the
conclusion was wrong, because the change fixed a number the baseline had recorded
*wrongly*.

## 2. Decompose the count before you fix the cause you already know

The ledger's diagnosis was right and incomplete, which is the dangerous
combination: a fix aimed at it would have gone green and taken the rack with it.
The discipline that caught it costs one script:

> Group every difference by its *shape* — which keys were added, removed,
> changed — and count each shape. Then check the shapes sum to the number the
> check printed. **If there is a remainder, it is a finding.** Not "probably the
> same thing"; a finding, with a name.

Here the shapes were `added=textWrapped` × 198 and `rect` × 1, plus the
reproducibility line. The `1` is the whole reason this was worth doing.

The same script gave the closure its evidence for free: running the **pre-fix**
checker against the **regenerated** tree prints `199 problem(s)` = 198
`textWrapped` + 1 rack, which is the decomposition asserted by execution rather
than by a diff nobody re-ran.

## 3. "It is REGENERABLE" is a property of a file, not of a directory

Chasing the same question — *should this check compare against a frozen dump at
all?* — turned up that the frozen 0.6.0 baseline was **gitignored**, under
`artifacts/**/*.json`, whose comment justifies the rule with *"it is REGENERABLE
(the capture tools and the scenario rig are both in-tree)"*.

It is not. `_theme_baseline` renders **today's** source; the 0.6.0 dump is a
snapshot of a tree from three weeks earlier and there is no tool that can produce
it again. It was the only input to the byte-compatibility claim, six gate rows
read it, and it lived on one laptop.

When a blanket ignore rule states a reason, check the reason **per file**, not
per glob. The two dumps here sit two directories apart and differ on exactly that
property: one is a regenerable working artifact, the other is an irreplaceable
historical record.

## What this cost, and what it did not

Fixing the message on an absent input was worth doing (a Lune stack trace became
one named line). But the *alarming* half of the hypothesis — "a fresh clone would
silently pass" — was **false**: measured with each input moved aside, the exit
code was 1 both before and after. It is recorded here in that shape on purpose.
The instinct that found the real problem also produced a scarier story than the
facts supported, and the story was checked before it was written down.

See also: `tools/lune/check_flat_baseline.luau`'s header (the two instruments,
and why only one of them is a frozen dump). The full decomposition and the
mutation transcripts that produced this lesson are archived with that stage's
gate evidence rather than carried in the maintained tree.
