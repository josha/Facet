---
name: critique-ui
description: Assess and improve how a Facet game interface looks, with captures, design rules and a fresh-context reviewer that scores it against a rubric. Use after building a screen and before repeating its layout, or when asked to review, critique or polish UI.
---

# Critique UI

Review the interface against its brief, intended users and visual direction.
An independent judgment can expose assumptions, but its scores do not replace
the owner's intent, input tests or player evidence.

For a UI review, identify supplied game art separately from authored UI art
in the packet. The world behind a HUD and the game subjects inside previews
remain context owned by the game-building agent. Judge how the interface
presents them; do not require Facet to generate them or credit their detail
alone as UI craft. A whole-screen UI concept does not make its incidental
world imagery a Facet implementation requirement.

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

Use these rounds when a separate concept image guides an expressive game.

1. **Target round.** Before translation, review the alternatives together.
   The packet, labeled `design target`, holds the original brief, the concept
   images, any references and the states that the concepts propose. Judge
   visual quality, readability, composition and state treatment. Runtime and
   input stay unverified. If every alternative is generic, ask for a revised
   set. Do not select a winner because it is the easiest to build.
2. **Translation round.** Review the first Studio screen before other routes
   are built. The packet, labeled `runtime translation`, holds the target and
   its role (agent-chosen concept, user specification, directional sketch or
   inspiration), a capture at the target's aspect ratio at the same viewing
   size, and captures at the smallest supported phone in each orientation.
   Show the choice, the action and an opened control as real controls with
   live labels: selected with focus, selected with focus on a peer, pressed,
   and feedback before and after acceptance.
   Judge fidelity to the target separately from general quality. Name the most
   important quality lost in translation even when the runtime looks coherent
   on its own. A coherent screen with a materially different composition or
   finish needs revision. Loaded images and a matching palette do not show
   that shapes, type and state treatment survived. Accept a font substitution
   that keeps hierarchy and readability.
3. **Final round.** Review the completed task with its actual states and sizes.

A quiet, established or explicitly minimal design has no separate concept. Its
first Studio screen is both the target and the runtime evidence.

The loop's three-round limit covers these rounds together. In the verdict,
list the images viewed and name any missing state or size; a score for the
supplied images does not cover a missing one.

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
   Agent-found inspiration calibrates craft and clarity. A selected concept
   constrains the implementation; a user-provided reference is a visual
   specification unless the user explicitly gives it a narrower role.
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
