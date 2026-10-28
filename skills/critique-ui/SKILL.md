---
name: critique-ui
description: Assess and improve how a Facet game interface looks, with captures, design rules and a fresh-context reviewer that scores it against a rubric. Use after building a screen and before repeating its layout, or when asked to review, critique or polish UI.
---

# Critique UI

An author grades its own screen too kindly. This skill gets an independent
judgment, then turns it into concrete changes.

## When

- After the first complete task works, before you copy its layout to other
  destinations.
- After a visual change, to confirm it helped.
- When asked to review, critique, assess or polish an interface.

## In a timed build

When the whole game must ship in minutes, run this quick pass on each main
screen as soon as it works, before building the next one. It takes about two
minutes a screen.

1. In Play, in the Client, `return Facet.review.screen().text`. Fix every
   medium or high finding, or name the reason it is deliberate.
2. Capture once wide and once in portrait.
3. Answer in one line each: What leads? Is the current choice marked? Does
   every option of each choice show? Is anything stacked one per row in a wide
   space? Is any plate mostly empty, or any page content on one side? Does the
   world show around pages, and do HUD readouts sit on panels? Which three
   theme cues show here? Could this capture belong to an unrelated game?
4. Fix the worst answer, then move on.

Run the full loop below when time remains, starting with the screen the player
sees most.

## The loop

1. **Collect evidence.** With a shell and a Rojo project:

   ```sh
   lute run tools/facet critique --device desktop --device phone-portrait \
     --tap Shop --brief brief.txt --out artifacts/critique/r1
   ```

   With a saved screenshot and dump: `--capture shot.png --dump shot.json`.
   With Studio tools only, follow [Studio only](references/studio-only.md).
   The brief is two or three lines: the game, the player's task and decision.

2. **Fix true rule findings first.** design.txt lists rule findings with fixes:
   facts joined in one text, numbers without emphasis, items without a visual,
   competing leads. They are cheap to fix. Skip a finding only when the choice
   is deliberate, and say why.

3. **Get a fresh judgment.** Start a separate agent with
   [the critic brief](references/critic-brief.md) and the packet path only. Do
   not tell it your intent or your fixes. It writes `verdict.json` by
   [the rubric](references/rubric.md). Without a separate agent, do the
   separate pass in [Studio only](references/studio-only.md#get-the-judgment).

4. **Act on the verdict.** Apply the top one to three `must` fixes. Keep what
   the verdict lists under `keep`. For each fix, use the matching use-facet
   recipe: [information display](../use-facet/references/information-display.md)
   for stats, records, ranks and progress.

5. **Compare.** Build the next packet into a new folder, then:

   ```sh
   lute run tools/facet critique compare artifacts/critique/r1 artifacts/critique/r2
   ```

   Look at the side-by-side images. A fix that adds findings or loses a `keep`
   item is not done.

6. **Stop** when every screen passes, or after three rounds. Report the scores
   and the open fixes. Do not call a screen passed without a verdict.

## Rules

- The reviewer sees only the packet: captures, renders, design.txt, brief.
- One fresh reviewer per round. Do not reuse a reviewer that saw an earlier
  round; it anchors on its first view.
- A taste conflict between the verdict and the game owner's stated direction
  goes to the owner. Follow the owner.
- Every item, record and stat carries a visual by default: its image or model,
  else a theme glyph, emblem, swatch, pips or bar. Text-only needs a reason.
- Captures do not prove motion, input or reachability. Test those separately.

## Calibrate the reviewer

A critic is useful only when it agrees with the game owner's eye. Keep labeled
cases and measure agreement with `lute run tools/facet critique cases` and
`lute run tools/facet critique score`. The Facet repository explains the case
format in `eval/critic/README.md`.
