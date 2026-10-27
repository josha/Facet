# Critic calibration

The critique-ui skill gives a fresh reviewer a packet and a rubric. A reviewer
is useful only when it agrees with the game owner's eye. These cases measure
that agreement, so a change to the rubric, the brief or the model can be
compared with the last run.

## A case

Each folder under `cases/` is one screen:

```text
cases/<id>/
  case.json     the brief and the owner's label
  capture.jpg   the screenshot (PNG or JPEG; 1280 px wide is enough)
  dump.json     optional: the interface dump, for the rules and the blocks render
```

```json
{
  "schema": "facet-critic-case/1",
  "id": "shop-text-rows",
  "source": "where the capture came from",
  "labeler": "Josh, 2026-10-28",
  "capture": "capture.jpg",
  "dump": "dump.json",
  "device": "desktop",
  "brief": "The game, and the player's task and decision on this screen.",
  "label": {
    "verdict": "revise",
    "scores": { "lead": 2, "numbers": 1, "visuals": 1, "identity": 2, "economy": 2 },
    "must": ["item-without-visual", "numbers-buried"],
    "should": ["generic-identity"],
    "notes": "one or two sentences in your words"
  },
  "betterThan": "id-of-a-worse-version"
}
```

- `verdict` is `pass` or `revise`. Use `pass` only for a screen you would
  ship.
- `scores` use the rubric dimensions, 1 to 5. 3 is competent and forgettable.
- `must` lists the tags a reviewer must raise. `should` lists tags that are
  fair to raise. A tag in neither counts as an extra. Take tags from
  [the rubric](../../skills/critique-ui/references/rubric.md).
- `betterThan` names a case that shows the same screen worse. Pairs measure
  whether the reviewer ranks a revision above its original.
- The brief describes the game and the task, never the problems.

## Build the set

Aim for 30 cases first, then add as you find disagreements.

1. **Spread.** About a third clearly bland, a third mixed and a third that
   you would ship. A set of only bad screens cannot measure false alarms.
   Include Roblox games you admire, other engines' game UI and screens from
   your own games.
2. **Pairs.** For every fix you make with the critique loop, keep the before
   and the after as two cases and set `betterThan` on the after. Pairs are the
   most useful cases: they test the decision the loop makes.
3. **Devices.** Include portrait phone and console captures, not only
   desktop.
4. **Dumps.** When the capture is from your own place, save its dump with
   `lute run tools/facet preview --tap ...` (dumps land beside the
   screenshots). The rules and the blocks render need it.
5. **Label before you look at any reviewer output.** Write your label,
   then run the reviewer. Change a label later only when you decide that you
   were wrong, and say so in `notes`.
6. **Seed cases.** The cases marked `"labeler": "draft by Claude ..."` are
   drafts. Confirm each one or overwrite it, then set `labeler` to your name.

## Run the calibration

```sh
lute run tools/facet critique cases --cases eval/critic/cases --out artifacts/critic-cal/<run>
```

Give each packet in `artifacts/critic-cal/<run>/<id>/` to its own fresh
reviewer with [the critic brief](../../skills/critique-ui/references/critic-brief.md).
A reviewer must not see another packet, the labels or this folder. In Claude
Code, ask: "Run the critic calibration on artifacts/critic-cal/<run>: one
fresh agent per packet with the critic brief." Then:

```sh
lute run tools/facet critique score --cases eval/critic/cases --run artifacts/critic-cal/<run>
```

The score reports:

| Measure | Meaning | Aim |
|---|---|---|
| Verdict agreement | the reviewer's pass or revise matches yours | 90% or more |
| Must-fix recall | the share of your `must` tags it raised | 80% or more |
| Mean score error | the mean distance between its scores and yours | under 0.75 |
| Preferred pairs | the share of pairs where it scores the better case higher | 90% or more |
| Extras | tags it raised that you did not list | read them: some are your misses |

Read the per-case lines. A missed tag is either a rubric gap (change the
rubric), a vocabulary gap (two tags mean the same thing to the reviewer) or a
label error (fix the label). Run the calibration again after each change, and
keep the score line of each run in this file.

## Runs

| Date | Rubric | Cases | Verdict | Recall | Score error | Pairs | Notes |
|---|---|---|---|---|---|---|---|
| 2026-10-27 | first | 5 draft | 100% | 59% | 0.28 | n/a | The reviewer files joined text under `numbers-buried`, and it raised a missing commit on four screens that the draft labels missed. |
