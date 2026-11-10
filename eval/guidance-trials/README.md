# Facet guidance trials

This set keeps the trials that changed the use-facet guidance and the library
on 9 and 10 November 2026. Each trial gave a fresh author one request and one
frozen kit, captured the result at three sizes and gave the captures to a
blind reviewer. The set includes the results that went against the candidate.

Use it to repeat a comparison, to calibrate a reviewer, or to choose a task
that the guidance has not seen. It is development evidence. It is not a
benchmark and it does not give a success rate.

## Read the records

- [Protocol](protocol.md): how to run an author, capture, review blind and
  run a repair round.
- [Tasks](tasks.json): the four requests that were used and their exposure,
  and unseen requests for the next test.
- [Kits](kits.json): each frozen kit, its hash and what it added.
- [Runs](runs.json): each author run, its kit, stage, script and cost.
- [Reviews](reviews.json): each blind review, its builds, scores and ranking.
- `previews/`: 480-pixel captures, named `<run>_<size>[_<state>].jpg`. They
  are for browsing. Small text and painted edges need the original capture.

The builds are disabled LocalScripts in the "ui tests" place. The original
captures, the authors' art and source, the kits and the review keys are in
the studio's experiment folder `artifacts/facet-guidance-ab-20261109`. They
are not in this repository.

## Results

Scores are 1 to 5 from one blind reviewer. One run stands behind each row.

### First pass, current guidance against a candidate

| Task | Current | Candidate | Identity | Craft | Lead | Desktop | Portrait | Landscape | Reviewer ships |
|---|---|---|---|---|---|---|---|---|---|
| Honey | `honey-1` | v3 `honey-4` | 4 to 4 | 4 to 3 | 4 to 3 | 3 to 3 | 2 to 4 | 1 to 2 | v3 |
| Blackjack | `blackjack-1` | v3 `blackjack-3` | 4 to 3 | 3 to 3 | 4 to 3 | 4 to 3 | 2 to 4 | 2 to 3 | v3 |
| Blackjack | `blackjack-1` | v3.1 `blackjack-4` | 3 to 4 | 3 to 3 | 4 to 4 | 3 to 3 | 2 to 4 | 2 to 2 | v3.1 |
| Drawing | `draw-1` | v3.1 `draw-2` | 3 to 4 | 4 to 2 | 4 to 3 | 3 to 3 | 4 to 2 | 3 to 2 | current |
| Blackjack | `blackjack-1` | v3.2 `blackjack-5` | 2 to 4 | 2 to 3 | 3 to 3 | 3 to 3 | 2 to 4 | 2 to 3 | v3.2 |

In the first phase, a reviewer ranked candidate v1 (`honey-2`) first of three
honey builds and picked current guidance on blackjack and on mail. The two
mail builds shared the same layout faults, which were library gaps.

### What one review round adds

| Build | Stage | Identity | Craft | Lead | Desktop | Portrait | Landscape |
|---|---|---|---|---|---|---|---|
| `blackjack-1` | current, first pass | 2 | 2 | 3 | 3 | 2 | 2 |
| `blackjack-5` | v3.2, first pass | 3 | 3 | 3 | 3 | 4 | 3 |
| `blackjack-7` | v3.2, repair round 1 | 3 | 3 | 4 | 3 | 4 | 3 |
| `blackjack-8` | v3.2, repair round 2 | 4 | 3 | 3 | 4 | 3 | 4 |
| `draw-1` | current, first pass | 3 | 3 | 4 | 4 | 4 | 2 |
| `draw-3` | v3.3, first pass | 4 | 2 | 3 | 3 | 2 | 3 |
| `draw-4` | v3.3, repair round 1 | 4 | 4 | 4 | 4 | 4 | 4 |

One reviewer scored the four blackjack builds together, and another scored
the three drawing builds together. Each reviewer ranked the last repaired
build first. On drawing, current guidance ranked above the v3.3 first pass.

### A first pass after the lessons of a repair round

v3.4 states, as general causes, what the v3.3 drawing first pass missed and
its repair round fixed. One reviewer scored four drawing builds together.

| Build | Stage | Identity | Craft | Lead | Desktop | Portrait | Landscape |
|---|---|---|---|---|---|---|---|
| `draw-1` | current, first pass | 3 | 4 | 4 | 4 | 4 | 3 |
| `draw-3` | v3.3, first pass | 3 | 2 | 3 | 3 | 2 | 2 |
| `draw-4` | v3.3, repair round 1 | 4 | 3 | 4 | 4 | 3 | 4 |
| `draw-5` | v3.4, first pass | 4 | 3 | 3 | 4 | 3 | 2 |

Ranked: `draw-1`, `draw-4`, `draw-5`, `draw-3`. The v3.4 first pass did not
repeat the faults of the v3.3 first pass. It stayed below the repaired build
and below current guidance, mainly on the short wide screen. Drawing was
development material for v3.4, so this is not an independent test.

## What the results say

- Every build from v3 on uses Facet for layout, images, text and controls,
  with a ground that reaches the glass. Game builds from current guidance are
  almost all native: `draw-1` has 49 native constructors and no Facet stack.
- A first pass from v3.x is not reliably better finished than a first pass
  from current guidance. It has more character and more loose ends.
- One independent review round is the largest gain that was measured. A
  repaired build ranked above current guidance in two reviews and second, on
  equal points, in the third.
- No build reached craft 5. An image model did not raise craft.
- A v3.x first pass cost 19 to 31 minutes and 284K to 392K tokens. Current
  guidance cost 27 to 31 minutes and 412K to 442K. A repair round cost about
  as much as a first pass.

## Limits

- One run stands behind each cell. A reviewer's score for the same build
  moved by one point, and once by two, between reviews. Of the three reviews
  that held three or more drawing builds, `draw-1` ranked first in two and
  second in one.
- All four used tasks informed the guidance. No result here is an
  independent test of the final kit. Use a task from the `unseen` list.
- The authors could not start a reviewer. The harness ran each repair round.
  An author that runs its own review loop has not been measured.
- The reviews judged captures. They did not test input, focus, a gamepad or
  state after rotation.
- Captures were taken at three sizes. A tablet and a console were checked by
  some authors and not by the reviews.
- The cost of several runs was not recorded for each run; [runs](runs.json)
  says where.

## Library gaps that the authors reported

Each gap cost an author time. They are not fixed by this set.

- No drawing surface or pointer capture construct. Each drawing build reads
  raw input for the canvas.
- `UI.Path` takes fixed `width` and `height` only, has no round caps and
  stops at 100 points. Its point format is not documented.
- `UI.Text { textSize = function }` fails to build. A bound size needs the
  native `TextSize`.
- `UI.Image { width = "fill", aspectRatio }` collapses in a stack that hugs
  its height.
- A stack does not draw `Rotation` on its direct children and gives no
  warning.
- `UI.Timer` rejects `tint`.
- Stepper `min` and `max` are read once. `Sheet.placement` and the Avatar
  `background` are not reactive.
- The Button `shortcut` format is not documented.
- `UI.environment()` has no safe-area insets.
- A sliced image can lose rows at some scale and height pairs. This is
  engine behavior.
- `Facet.review` reads rectangles. It does not find a label on the
  transparent margin of an image, and `covered-text` can name an image whose
  paint does not reach the text.
