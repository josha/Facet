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

## Review a design target

When a separate concept guides an expressive game, review it before translation.
For new open art direction, review the alternatives together in one round.
Check that their composition, type and rendering approach differ where the
game's visual constraints leave room, then judge each against the same task
and appropriate finish. Do not select a winner solely because
it is the easiest to implement. If all are generic, request revision of the set.
For a focused native study suited to an established, quiet or explicitly
minimal brief, the first Studio screen can supply both the direction and the
runtime evidence; it does not need a duplicate concept round.
Use the loop below for a separate concept with a packet labeled
`design target`: the original brief, prototype images, inspected references
and the states the design proposes. Static representative data is sufficient.
Do not require a runtime dump or input proof at this stage. Judge visual
quality, readability, composition and state treatment; mark runtime and input
as unverified. Resolve visual `must` fixes before implementation.

Use the next fresh round on the first representative Studio screen, before
functional routes and repeated layouts. Label the packet `runtime translation`
and include the target beside the actual capture at a similar viewing size.
Show the choice, action and opened control where the task has them. Include
selection with focus on that item, selection after focus moves to a peer,
pressed paint, and any changing feedback before and after acceptance. Do not
infer these combinations from separate idle images. For multi-device work,
include a wide view and the declared minimum supported narrow and short layouts
in this early packet. Use the [minimum-viewport procedure](../use-facet/references/compact-compositions.md#verify-the-minimum-viewport).
Require recorded camera, safe-area and task-body dimensions with scaling;
a preset name alone does not establish coverage. Keep a separate notched case
when it imposes different constraints. For phones supporting both orientations, require portrait
and landscape evidence; neither proves the other. Check actual target sizes
and text, not the device's nominal resolution. View enlarged phone captures at their recorded camera width
for readability, and use the full-resolution image for painted-edge inspection.
Static task data is
sufficient; these must be real controls with live labels. Judge whether their
visible shapes, type and state treatment carry the target's direction.
Successful image loading and a matching palette do not establish that.
Name the most important quality lost in translation, if any, even when the
runtime looks coherent on its own. Check the author's preservation claims
against the images; correct behavior does not offset missing visual craft.
Accept a deliberate runtime font substitution when it preserves hierarchy and
readability. Still judge the craft of the composition, subject and interactive
surfaces within the chosen visual language.
List the image paths actually viewed. Identify missing required state or
viewport captures in the verdict; a visual score for the supplied images
does not clear that missing evidence.
Resolve visual `must` fixes and inspect the repair before extending the game.

Review the completed task with its actual states, sizes and input evidence.
Keep the loop's three-round limit across target, runtime translation and final
task; changing the packet label does not start a new review budget. If no
fresh round remains, use a separate self-review and report that limit.

## The loop

1. **Collect evidence.** With a shell and a Rojo project:

   ```sh
   lute run tools/facet critique --tap Shop --brief brief.txt --out artifacts/critique/r1
   ```

   With a saved screenshot and dump: `--capture shot.png --dump shot.json`.
   The default sweep includes small and notched phones in both orientations.
   Use explicit `--device` flags for a focused review; report that narrower
   coverage and add the product's minimum cases when the presets do not cover it.
   With Studio tools only, follow [Studio only](references/studio-only.md).
   The brief states the task, audience, supported contexts and intended visual
   direction. Include the owner's constraints, not the author's proposed fixes.
   Include the original request. When references informed the direction or the
   requested comparison, include those images or links. The reviewer must view
   their pixels before judging that gap; a search result does not show them.
   References calibrate craft and clarity. They are not templates to copy.
   Include the visual study when one guided the implementation. Label it as
   a design target so the reviewer can compare it with the actual capture.
   When prior work is available and a new identity is intended, include a small
   comparison of recent interfaces. Judge repeated composition and typography,
   not only changed colors or artwork. Shared styling within an established
   product is appropriate. In a blind author evaluation, keep this comparison
   in the reviewer packet; do not give prior solutions to the author.
   Include the states needed to judge the task. For a choice, show selection
   and focus together. For changing feedback, show before and after the action
   so the reviewer can judge readability and placement. A single idle capture
   cannot establish those properties.

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
   for stats, records, ranks and progress. Check the control contract before
   implementing a proposed visual change. Fix the observed problem; the
   critic's proposed move is not an API requirement or evidence that the
   existing control's behavior must be replaced.

5. **Compare.** Build the next packet into a new folder, then:

   ```sh
   lute run tools/facet critique compare artifacts/critique/r1 artifacts/critique/r2
   ```

   Look at the side-by-side images. Check that the task improved and useful
   behavior survived. Investigate new findings; their count alone is not quality.
   Reassess the whole composition against the brief and visual target. Adding
   each suggested ornament does not prove that a generic composition improved.

6. **Stop fresh review rounds** when every screen passes, or after three rounds.
   This limit ends independent scoring, not repair work. Fix known `must`
   defects, then capture and test the affected states again. Report unresolved
   blockers and do not describe that result as finished. Report the scores and
   open fixes; do not claim a fresh pass without a verdict on the final capture.

## Rules

- The reviewer sees only the packet: captures, renders, design.txt, brief.
- Include visual references when they informed the direction or requested
  comparison. A deliberate native or text-led direction does not need an image
  hunt to qualify for critique. Keep the author's self-assessment and proposed
  fixes out of the packet.
- One fresh reviewer per round. Do not reuse a reviewer that saw an earlier
  round; it anchors on its first view.
- Follow the owner's stated direction when a reviewer prefers another style.
  Ask only when a material design choice remains unresolved by the brief.
- Judge images, models, glyphs, text and numbers by how they serve the task.
  Do not require decoration, unique branding or a visual for every record.
- Captures do not prove motion, input or reachability. Test those separately.
- Report visual quality and device/input coverage separately. Missing minimum
  viewport or input evidence cannot be cleared by high aesthetic scores.

## Calibrate the reviewer

A critic is useful only when it agrees with the game owner's eye. Keep labeled
cases and measure agreement with `lute run tools/facet critique cases` and
`lute run tools/facet critique score`. Keep cases used to revise the rubric
separate from unseen cases used to assess it. The score describes that sample,
not a universal measure of design quality.
