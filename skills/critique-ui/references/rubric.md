# Critique rubric

Judge the screens as a player of this game would see them. Use the capture for
the whole impression, the squint render for what leads, and the blocks render
for layout. Use design.txt as evidence, not as the verdict: a rule can find a
deliberate choice and miss a real problem.
Judge the requested visual direction, including restrained, familiar or
text-led designs. Do not penalize an appropriate design for lacking an example's
art, large numerals, borders, exposed world or screen structure.

## Answer these for each screen

1. **First look.** In one second, what does the eye land on? Is it the most
   important thing for the player's decision on this screen?
2. **Lead.** Does emphasis help the user's task? A title can lead orientation;
   equal-weight rows can support comparison. Identify actual competing demands.
3. **Numbers.** Are relevant values, units and relationships readable and easy
   to compare at the intended density? Large numerals, aligned table cells and
   compact sentences are possible treatments, not requirements.
4. **Visuals.** Does the representation help recognition or understanding?
   Images, models, glyphs, charts and text are alternatives. Do not request a
   visual where it adds no information or useful character.
5. **Identity.** Does the screen fit the brief and established visual language?
   Name evidence of consistency or conflict; uniqueness is not a requirement.
6. **Economy.** What can go without losing the decision: repeated facts, a
   wall of zeros, boxes inside boxes, an introduction above the choice?
7. **Space.** Does the space go to the subject and the decision, or is content
   stranded in a corner of a large plate?
8. **Commitment.** Is the action distinct from navigation and next to the facts
   it depends on?

## Scores

Score each dimension 1 to 5 against the brief. 5 means it serves the task well;
4 means no material issue is visible; 3 means a specific issue impairs the task;
2 means major difficulty; 1 means the task is obstructed. Give evidence for
each requested fix. When a dimension has no relevant content, record that in
`keep` and use 4; do not invent a need for numbers or art to increase the score.

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
