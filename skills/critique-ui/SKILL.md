---
name: critique-ui
description: Assess and improve how a Facet game interface looks, with captures, design rules and a fresh-context reviewer that scores it against a rubric. Use after building a screen and before repeating its layout, or when asked to review, critique or polish UI.
---

# Critique UI

Review the interface against its brief, intended users and visual direction.
An independent judgment can expose assumptions, but its scores do not replace
the owner's intent, input tests or player evidence.

## When

- When a new composition or substantial visual change needs deeper review.
- When asked to review, critique, assess or polish an interface.

## Quick review

For a focused change, review the affected states and representative supported
sizes. Scale the evidence to the change; there is no fixed time per screen.

1. In Play, in the Client, `return Facet.review.screen().text`. Investigate
   findings against the actual task and record justified exceptions.
2. Capture the changed state in context.
3. Check whether the user can find the needed facts, distinguish selection,
   predict the action and return. Check readability, fit and the requested
   visual direction. Text-led, quiet or full-screen designs can satisfy these.
4. Fix the most consequential problem, then capture and test the affected state
   again. A clean automated report cannot confirm a visual repair.

Use the full loop when independent review would add useful evidence.

## The loop

1. **Collect evidence.** With a shell and a Rojo project:

   ```sh
   lute run tools/facet critique --device desktop --device phone-portrait \
     --tap Shop --brief brief.txt --out artifacts/critique/r1
   ```

   With a saved screenshot and dump: `--capture shot.png --dump shot.json`.
   With Studio tools only, follow [Studio only](references/studio-only.md).
   The brief states the task, audience, supported contexts and intended visual
   direction. Include the owner's constraints, not the author's proposed fixes.

2. **Assess rule findings.** design.txt lists heuristic findings, including
   joined facts, number emphasis and missing visuals. A compact label, text
   table or restrained type scale can be appropriate. Fix observable problems;
   record false positives instead of restyling to satisfy the detector.

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

   Look at the side-by-side images. Check that the task improved and useful
   behavior survived. Investigate new findings; their count alone is not quality.

6. **Stop** when every screen passes, or after three rounds. Report the scores
   and the open fixes. Do not call a screen passed without a verdict.

## Rules

- The reviewer sees only the packet: captures, renders, design.txt, brief.
- One fresh reviewer per round. Do not reuse a reviewer that saw an earlier
  round; it anchors on its first view.
- Follow the owner's stated direction when a reviewer prefers another style.
  Ask only when a material design choice remains unresolved by the brief.
- Judge images, models, glyphs, text and numbers by how they serve the task.
  Do not require decoration, unique branding or a visual for every record.
- Captures do not prove motion, input or reachability. Test those separately.

## Calibrate the reviewer

A critic is useful only when it agrees with the game owner's eye. Keep labeled
cases and measure agreement with `lute run tools/facet critique cases` and
`lute run tools/facet critique score`. Keep cases used to revise the rubric
separate from unseen cases used to assess it. The score describes that sample,
not a universal measure of design quality.
