# Critique rubric

Judge the screens as a player of this game would see them. Use the capture for
the whole impression, the squint render for what leads, and the blocks render
for layout. Use design.txt as evidence, not as the verdict: a rule can find a
deliberate choice and miss a real problem.
Judge the requested visual direction, including restrained, familiar or
text-led designs. Do not penalize an appropriate design for lacking an example's
art, large numerals, borders, exposed world or screen structure.
Calibrate finish to the game's world, tone, audience and art style. A cozy
game can earn high scores with colorful rounded forms; a pixel game with
precise pixel craft; an adult-oriented world with detailed or strongly
stylized treatment. Judge execution within the appropriate language.
Realism, texture density and geometric complexity do not raise scores by
themselves. Age alone does not require realism or a dark palette. An elaborate
UI that clashes with the game can fail identity despite its technical detail.

## Answer these for each screen

1. **First look.** In one second, what does the eye land on? Is it the most
   important thing for the player's decision on this screen?
2. **Lead.** Does emphasis help the user's task? A title can lead orientation;
   equal-weight rows can support comparison. Identify actual competing demands.
3. **Numbers.** Are relevant values, units and relationships readable and easy
   to compare at the intended density? Large numerals, aligned table cells and
   compact sentences are possible treatments, not requirements.
4. **Visuals and finish.** Does the representation help recognition or
   understanding, and does its craft meet the requested finish? A recognizable
   genre is not proof of finished visual design. For an expressive game, inspect
   the actual subject rendering, typography, surfaces, edges and state details.
   Does this look ready for players, or like a colored wireframe? A coherent
   palette on basic placeholder shapes is still a prototype. A named material
   must be visible; do not credit a plain fill as cloth, wood or metal. Compare
   the level of craft with the references without requesting their exact style.
   A deliberate graphic or text-led game can be finished through strong shape,
   type and composition; texture and illustration are not universal requirements.
   Images, models, glyphs, charts and text remain alternatives. Do not request
   a visual where it adds no information or useful character.
5. **Identity.** Does the screen fit the brief and established visual language?
   Name the visible type, shape, material, imagery or feedback choices that
   express this product. For a game, does the treatment support its world and
   intended feeling, or does it still look like an unrelated neutral starter
   with a new title and accent? Flag generic styling when it misses that
   direction. For an expressive game, compare the capture with relevant shipped
   screens: does the subject have presence, do interactive surfaces share its
   visual language, and does the result belong to the action? A hero picture
   above ordinary cards is weak evidence of a complete identity. Do not award
   a pass merely because you can name a font, accent and illustration.
   For an identity score of 4 or more on an expressive game, name the visible
   evidence in the choices and action as well as the subject in `keep`.
   Reusing the illustration's colors on generic buttons is not sufficient.
   When a new identity is intended and recent work is supplied, compare the
   whole composition, type hierarchy, framing and shape language. A recurring
   subject panel beside the same card stack can remain generic despite new
   props and colors. Name the similarity and why it weakens this brief; do not
   penalize intentional consistency within one product. Coherence alone does
   not establish distinction or finished craft.
   Judge the complete composition again after each repair; adding the requested
   props does not automatically resolve a weak visual language.
   A professional mail app, Studio tool or explicitly minimal game
   can succeed with quiet, familiar styling. Novelty and decoration alone do
   not improve the score.
6. **Economy.** What can go without losing the decision: repeated facts, a
   wall of zeros, boxes inside boxes, an introduction above the choice?
7. **Space.** Does the space go to the subject and the decision, or is content
   stranded in a corner of a large plate? In reserved status space, inspect
   the balance above and below a short label group. Center it when that fits
   the composition; do not require centered paragraphs or dense reading rows.
8. **Commitment.** Is the action distinct from navigation and next to the facts
   it depends on? Compare before and after feedback: does the action stay in
   place within the same task, with a clear meaning and readable status? Flag
   a button displaced by a new status message as a `must` fix. A deliberate
   transition to a different page can use a different composition.

Apply these questions to the real captures at each supported form factor.
Do not credit an identity described in notes but absent from the screen.
Assess an original treatment suited to the brief. Use references to compare
craft, clarity and coherence, not similarity to their layout, assets or branding.
Familiar genre arrangements and standard controls are valid; copied surface
details do not establish a product's own direction.
When the brief asks for a compelling game UI, identity needs positive visual
evidence at that standard. Readability and correct controls are necessary but
do not answer that question. Record the largest gap from the visual references
and a concrete repair; do not soften the judgment because the UI is functional.
When a reference comparison is part of the brief or direction, use relevant
game screens. If their pixels were unavailable, report that comparison as
unverified; do not imply that it passed. Without an external target, judge
visible craft and suitability against the brief; do not require an image
hunt for a deliberate native or text-led style.
Missing glyphs, unloaded art and construction placeholders are defects, not
style choices. A desktop pass does not excuse a phone landscape view that
shows only the header or hides the action. Record input evidence separately:
a screenshot cannot prove selection, activation, text entry or return behavior.
For a packet labeled `design target`, judge the proposed visual states and
record runtime, device and input behavior as unverified. Do not treat a visual
pass on that prototype as a release verdict for the implementation.
When a design-target packet contains alternatives, assess each and compare
their visual range within the game's art constraints. Preserve required style
traits, such as pixel rendering, while varying the decisions left open.
Palette swaps on the same structure need revision before
implementation. Recommend a direction only if its craft and task clarity
meet the brief; a least-bad candidate is not a pass.
When a runtime packet includes a design target, compare their defining
qualities at the same viewing size. Check subject separation, control
silhouettes, edges, type hierarchy and state emphasis where they carry the
direction. Name the largest visible loss even when the artwork loads and the
palette matches. Allow changes that improve correctness, readability or fit;
matching the concept's pixels is not the goal.

Inspect essential labels over art in the actual selected and focused states,
including both states together. Read them at the intended viewing size, without
zooming in to compensate. Check small presentations and different image crops.
If image detail obscures a label or state mark, record a `must` fix with the
`low-contrast` tag and a `revise` verdict, regardless of the other scores.
A clean bounds report and attractive artwork do not override this defect.
If the needed state capture is missing, record missing evidence rather than
assuming it is readable. A quiet surface needs no extra decoration.
In the combined selected and focused state, check the space between the focus
treatment and the selection mark. A ring crossing a check, badge or label is
a `must` fix even when both remain identifiable. Include strokes, halos and
curved edges in this visual check; separate element bounds can still collide
in their visible paint.

Recheck identity after readability and fit repairs. A repair that replaces the
game's material and type hierarchy with an unrelated utility panel can fix
contrast while creating a visual regression. Judge both outcomes in the new
capture; an appropriate quiet tool can retain its plain surfaces.

For runtime device fit, require the declared minimum safe viewport in each
supported orientation, with measured dimensions and scale. A larger phone
capture cannot clear a missing smaller one. Inspect opened dialogs and changed
feedback as well as entry. Clipped essential text, action paint or focus
outlines are `must` fixes with a `revise` verdict even when the button center
is visible or clickable. A scroll container alone is not reachability proof;
require evidence of revealing and activating the target. Record missing
minimum captures, input routes or rotation-and-return evidence separately
from the scores for supplied images. Do not call device fit complete until
those gaps are closed on the final source.

## Scores

Score each dimension 1 to 5 against the task and requested experience.
5 means an especially strong result; 4 means the capture clearly meets the
brief, with positive visible evidence; 3 means a noticeable gap remains even
if the controls work; 2 means a major failure; 1 means the task is obstructed.
For an expressive game, a functional but generic treatment does not earn
identity 4. A recognizable but schematic treatment does not earn visuals 4.
For visuals 4 or more, name the visible evidence of finished craft in `keep`,
as well as recognition. A gold outline, genre color or readable symbol alone
does not establish it. For a quiet tool or text-led game, clarity, typography, composition
and restrained feedback can provide that evidence. Give evidence for each
requested fix. When a dimension has no relevant content, record that in `keep`
and use 4; do not invent a need for numbers or art to increase the score.

| Dimension | Covers questions |
|---|---|
| `lead` | 1, 2, 8 |
| `numbers` | 3 |
| `visuals` | 4 |
| `identity` | 5 |
| `economy` | 6, 7 |

The verdict is `pass` only when every score is 4 or more. Otherwise it is
`revise`. This is the critique tool's review convention, not proof of usability
or a universal release threshold. Report missing evidence separately.

## Fixes

Give at most five fixes for each screen, most important first. Each fix names
the element, the problem a player would notice, and one concrete move in Facet
terms (a text role, a layout relationship, a visual, a removal). A move such as
"make it pop" or "improve hierarchy" is not a fix. Mark a fix `must` when the
screen fails a question without it; otherwise `should`. Tag each fix with one
of these tags:

`lead-unclear`, `competing-leads`, `numbers-buried`, `joined-facts`,
`item-without-visual`, `stat-without-visual`, `progress-as-text`,
`generic-identity`, `boxed-everything`, `stranded-space`, `zero-wall`,
`commit-unclear`, `low-contrast`, `crowded`, `repeated-facts`.

Tags classify an observed problem; their names do not impose design rules.
For example, `item-without-visual` needs evidence that recognition suffers,
and `joined-facts` needs evidence that the combined text impairs reading.

Also name what works and must stay (`keep`), so a revision does not lose it.

## verdict.json

```json
{
  "schema": "facet-critique/1",
  "screens": [
    {
      "id": "desktop-seed-shop",
      "firstLook": "The 40 px headline, not the seeds or their prices.",
      "scores": { "lead": 2, "numbers": 1, "visuals": 1, "identity": 2, "economy": 3 },
      "verdict": "revise",
      "fixes": [
        {
          "rank": 1,
          "level": "must",
          "tag": "item-without-visual",
          "element": "each seed row",
          "problem": "Five identical text rows; the player reads every name to find the sunflower.",
          "move": "Give each seed packet its image at 64 px beside the name; remove the row plates."
        }
      ],
      "keep": ["Back and Close placement"]
    }
  ]
}
```

Use the screen ids from PACKET.md. Write only this file. Do not edit the game.
