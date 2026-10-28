# Critique rubric

Judge the screens as a player of this game would see them. Use the capture for
the whole impression, the squint render for what leads, and the blocks render
for layout. Use design.txt as evidence, not as the verdict: a rule can find a
deliberate choice and miss a real problem.

## Answer these for each screen

1. **First look.** In one second, what does the eye land on? Is it the most
   important thing for the player's decision on this screen?
2. **Lead.** Does each group have one lead? Is the largest or brightest element
   the most important fact, or is it a title, a filter or a Back button?
3. **Numbers.** Are the deciding values (price, stat, rating, reward, time)
   the heroes: large numerals with a small label or unit? Or are they words in
   a sentence such as "Speed 88 · Handling 76"?
4. **Visuals.** Does every item, record and stat carry a visual that tells it
   apart: its image or model, a glyph, an emblem, a swatch, pips or a bar?
   Text-only items need a clear reason.
5. **Identity.** Could this screen belong to an unrelated game? Name the cue in
   type, material, shape, color or subject that makes it this game.
6. **Economy.** What can go without losing the decision: repeated facts, a
   wall of zeros, boxes inside boxes, an introduction above the choice?
7. **Space.** Does the space go to the subject and the decision, or is content
   stranded in a corner of a large plate?
8. **Commitment.** Is the action distinct from navigation and next to the facts
   it depends on?

## Scores

Score each dimension 1 to 5. 5 is shippable in a commercial game; 3 is
competent and forgettable; 1 is broken or generic.

| Dimension | Covers questions |
|---|---|
| `lead` | 1, 2, 8 |
| `numbers` | 3 |
| `visuals` | 4 |
| `identity` | 5 |
| `economy` | 6, 7 |

The verdict is `pass` only when every score is 4 or more. Otherwise it is
`revise`.

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
