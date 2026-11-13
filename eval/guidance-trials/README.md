# Facet guidance trials

This set keeps the trials that changed the use-facet guidance and the library
on 9 and 10 November 2026, and the trial of the theme flow on 12 November. Each trial gave a fresh author one request and one
frozen kit, captured the result at three sizes and gave the captures to a
blind reviewer. The set includes the results that went against the candidate.

Use it to repeat a comparison, to calibrate a reviewer, or to choose a task
that the guidance has not seen. It is development evidence. It is not a
benchmark and it does not give a success rate.

## Read the records

- [Protocol](protocol.md): how to run an author, capture, review blind and
  run a repair round.
- [Tasks](tasks.json): the six requests that were used and their exposure,
  and unseen requests for the next test.
- [Kits](kits.json): each frozen kit, its hash and what it added.
- [Runs](runs.json): each author run, its kit, stage, script and cost.
- [Reviews](reviews.json): each blind review, its builds, scores and ranking.
- `previews/`: 480-pixel captures, named `<run>_<size>[_<state>].jpg`. They
  are for browsing. Small text and painted edges need the original capture.

The builds are disabled LocalScripts in the "ui tests" place. The original
captures, the authors' art and source, the kits and the review keys are in
the studio's experiment folders `artifacts/facet-guidance-ab-20261109` and
`artifacts/facet-guidance-opus-20261112`. They are not in this repository.

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

### A stack ground for labels on art, on an unseen task

v3.5 is the guidance of the package after the review read the paint of an
image. v3.6 adds the stack `ground`, which pads the content of a stack to the
paint of its art. Both authors built the quest board, an unseen task, on the
same library. One reviewer scored the two builds together.

| Build | Kit | Identity | Craft | Lead | Desktop | Portrait | Landscape |
|---|---|---|---|---|---|---|---|
| `quest-1` | v3.5 | 4 | 4 | 3 | 4 | 3 | 3 |
| `quest-2` | v3.6 | 4 | 3 | 3 | 4 | 2 | 1 |

Ranked: `quest-1`, `quest-2`. The reviewer would ship neither. The v3.6
author made the art of the sign, the notices and the panels the ground of
their stacks, and no label left the paint of its art. It lost on the phone
layout, on seams in sliced art and on a seal over the footer of a notice.
The v3.5 build had a stamp over the progress count in the reader on the
phone in portrait: a column with a width in pixels was wider than its fill
slot. The review reported that fault; the author did not run the review in
that state. One run stands behind each arm, so the result does not separate
the kits.

### The theme flow, on two development tasks

v4 is the guidance of 12 November 2026: a card in quantities, a concept, the
card corrected to the concept's measures, `finish` as values, and the theme
sheet compared with the concept by measure. One fresh Opus-medium author
built each task with an image model (12 images allowed). One reviewer scored
each task's builds together. The earlier builds had no image model, except
that `blackjack-8` is the second repair round of `blackjack-5`.

| Build | Kit | Identity | Craft | Lead | Desktop | Portrait | Landscape |
|---|---|---|---|---|---|---|---|
| `honey-1` | current | 3 | 3 | 2 | 3 | 1 | 1 |
| `honey-4` | v3 | 3 | 2 | 3 | 3 | 3 | 1 |
| `honey-5` | v4 | 4 | 4 | 4 | 4 | 3 | 4 |
| `blackjack-5` | v3.2 | 4 | 3 | 3 | 3 | 4 | 4 |
| `blackjack-8` | v3.2, repair round 2 | 4 | 4 | 3 | 4 | 3 | 3 |
| `blackjack-9` | v4 | 3 | 3 | 3 | 3 | 2 | 2 |

Honey ranked `honey-5` first by a wide margin. Blackjack ranked
`blackjack-9` last. Both v4 authors followed the flow: each wrote sizes on
its card, corrected them to the concept, started the edge at 3 or 4 px and
kept it, and added edges to its actions after the theme sheet. The honey
author kept the place of its concept, a stall with a canopy, a counter and
jars as buttons. The blackjack author chose the flatter of its two concepts,
because a curved rail would not survive a phone, and the reviewer read the
result as a template. It also lost on cards with one pip and a letter for
a court card, and on a result plate that leaves the screen in portrait,
which `Facet.review` did not report. The flow raised the strength of the
theme in both builds. It did not decide how much of a place the build keeps
or how finished its objects are. Both tasks are development material, and
one run stands behind each cell.

### The place and the objects, on an unseen task

v4.1 added two things to v4 after the blackjack result: choose the
composition with the most of the place in it, and list the objects of the
concept with the parts that a player expects on each. Both authors built
the pet care screen, an unseen task, on the same library, with 7 images
each. One reviewer scored the two builds together.

| Build | Kit | Identity | Craft | Lead | Desktop | Portrait | Landscape |
|---|---|---|---|---|---|---|---|
| `pet-1` | v4 | 4 | 4 | 4 | 4 | 4 | 3 |
| `pet-2` | v4.1 | 3 | 3 | 3 | 3 | 2 | 2 |

Ranked: `pet-1`, `pet-2`. The reviewer would ship neither as it is and
called `pet-1` close. The v4 author painted a room at dusk and made the
needs jars and the actions toy blocks. The v4.1 author drew a flat den, and
the reviewer read it as a stock template: the additions did not show in the
build. They were removed from the guidance. The pair is the first result
for the theme flow on a task that the guidance had not seen, and v4 scored
4 on five of six axes there. One run stands behind each arm, so the result
does not separate the kits.

### One order and a finish that follows the hierarchy, on an unseen task

v5 states one order for the work, keeps the strong edge for the plate that
leads, and names equal bright borders on nested controls as a fault. Both
authors built the fishing HUD, an unseen task, on the same library, with
no image generator; each drew its art with a script. One reviewer scored
the two builds together, in two states at three sizes.

| Build | Kit | Identity | Craft | Lead | Desktop | Portrait | Landscape |
|---|---|---|---|---|---|---|---|
| `fish-1` | v4 | 4 | 3 | 3 | 4 | 3 | 3 |
| `fish-2` | v5 | 3 | 4 | 3 | 4 | 4 | 3 |

Ranked: `fish-2`, `fish-1`, one point apart. The reviewer would ship
neither. The v4 author built a lagoon and a dock and drew a brass dial; the
reviewer saw four boxes with one border weight that compete, and a dial
that sits on the character on both phone forms. The v5 author compared the
edge of the controls with the edge of the plates on the theme sheet and
left the controls without one; the reviewer called its portrait the
cleanest of the two. The v5 author built no world, so the baseplate shows
behind the HUD, and its tension arc is thinner than the distance numeral
beside it. Lead is 3 for both. One run stands behind each arm, and one
point is inside the movement of a reviewer between reviews, so the pair
does not separate the kits. It shows no loss from the change.

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
- The first four used tasks informed the guidance. The quest board did not,
  and it has one run for each arm.
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
- `finish.edge` draws on panels and Sheets and not on controls. Both v4
  authors found the Button and Stepper tags by reading instances and wrote
  stroke rules. Those strokes draw outside the layout box, so with a hard
  shadow they used up the gap between a stepper and the action under it.
- `Facet.review` has no finding for a plate that leaves the screen, or for
  two controls whose edges or shadows touch.
- The type roles do not step down on a phone. One author scaled every text
  with a bound `TextSize`.
- A stack `ground` with `paintRect` came up at 44 by 44 pixels twice, on a
  fresh Play and after a change of device, until its art had a `Size`.
- `UI.Image` raises an error when a bound width or height is negative in the
  first frames.
- Nothing moves the selection when a change of phase disables the control
  that has it.
- `UI.Flash` paints a rectangle on a shaped plate.
- The Stepper has no size option for its count.
- `sliceCenter` reads as a list of four numbers in the reference and needs
  the named fields `x0`, `y0`, `x1` and `y1`.
- Roblox stops `TextSize` at 100, so a type role above it does nothing; a
  larger name needs a `UIScale`. The guidance does not say so.
- `cut-at-edge` reports a text or a control. A plate that the edge of the
  screen cuts, with its text still on the screen, has no finding.
- The reveal mark of a corner region sits on a `top` region on a narrow
  screen: the `top` zone centres on the full width. Both fishing authors
  wrote a second layout for portrait, and the review reported nothing.
- A Text takes no bound `textSize`, and `textSize` with `textRole` needs a
  `fit` table. A size between two roles has no direct form.
- A `nil` in the positional children of a constructor drops the children
  after it, with no error.
- The radius of a `pathShapes` arc is a share of half the box. The node
  does not say so.
- `shortcutHint` on a `bare` Button draws its glyph over the label.
- That a Button can be held (`onPointerDown` and `onPointerUp`) is only in
  `Button.disclose`.
- An injected `ButtonR2` did not fire an InputAction in Studio for either
  author, so the gamepad route of a held action was not proven.
