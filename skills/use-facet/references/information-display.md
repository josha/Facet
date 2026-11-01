# Information display

Choose a representation from what the user needs to recognize, read or compare.
These recipes illustrate possible treatments. A dense table, sentence, quiet
readout or visual card can each be appropriate; preserve the brief's priorities.

## Decision criteria

- Separate facts when alignment, scanning or independent updates benefit.
  Compact summaries and related values can share a label. Punctuation alone
  does not make a display unclear; inspect `joined-facts` findings in context.
- Emphasize the information needed for the decision. `numeral` suits a leading
  value; `strong` or body text can suit dense comparisons. Keep units and labels
  readable. A title or instruction can lead when orientation is the task.
- Use art for recognition, swatches for color, and bars or pips when magnitude
  matters. Text and aligned numbers can be clearer than decorative glyphs.
- Distinguish a meaningful zero from missing data or an empty state. Keep a
  zero that affects the decision; offer a next step when there is no record.
- Use space, alignment and surfaces to explain grouping. Nested surfaces need
  a useful relationship, not a blanket prohibition.

Choose type contrast for density and viewing distance. `Facet.themes.define`
can report a flat scale in `report.advice`; assess readability and hierarchy
in the actual task instead of treating its threshold as a required ratio.

## Recipes

Each recipe uses `local C, UI = Facet.Compose, app.UI`.

### Stat block

A glyph, the value, then the label. Use three or four in a row for a record.
Under a hero value, such as a rating, the stat values use `heading` so the
hero stays the one lead; alone, they use `numeral`.

```luau
local function stat(name: string, icon: string, value: (Facet.Use) -> string): Frame
	return UI.VStack(name)({
		align = "center",
		gap = "xs",
		UI.Label { title = name, icon = icon, presentation = "iconOnly", iconSize = 28 },
		UI.Text { text = value, textRole = "heading" },
		UI.Text { text = name, textRole = "caption", role = "secondary" },
	})
end
UI.HStack "Record" { width = "fill", distribute = "spaceEvenly",
	stat("Wins", "trophy", wins), stat("Losses", "close", losses), stat("Draws", "flag", draws) }
```

### Rank and rating

When tier recognition matters, an emblem can lead beside the rating and tier
name. Use a bar for relative progress or text for exact requirements. See
[standing](../examples/standing.luau) for the complete card.

### Placement and other goals

For a small fixed number of steps, pips can accompany the exact goal. This
example uses ten placement games; use the real task's requirement.

```luau
UI.ProgressView "Placements" { value = placed, max = 10, segments = 10 }
UI.Text { text = "Play 10 ranked games to place your rank.", wrap = true }
```

### Price

The amount in `numeral` (or `strong` in a list row) beside the currency glyph.
Keep price in one treatment everywhere, so the eye compares amounts.

```luau
UI.Label { title = price, icon = "coin", textSize = "numeral" }
```

### Item row or card

Subject first, then the name, then a strip of facts, then the price. The
[collection](../examples/collection.luau) example shows browse and detail.

| Part | Treatment |
|---|---|
| Subject | `Image`, `Stage` or, without art, a glyph on a plate that contrasts with the row |
| Category | `caption` or `label`, secondary, above the name |
| Name | `heading` in a row (one step above the fact values), `title` in detail |
| Facts | an `HStack` of value (`strong`) over label (`caption`); in detail the value is `heading` |
| Price | `Label` with the currency glyph |

Use a Table when players compare many facts across many items.

### Stat change

For an upgrade, show the current value, a `chevron.trailing` glyph and the new
value in the accent. Add a `ProgressView` against the stat's maximum when the
scale matters.

### Leaderboard row

A fixed-width rank numeral, the `Avatar`, the name in `strong`, a `Spacer {}`
and the score as a numeral at the end. Mark the player's own row with
selection paint and an accessible identification such as "You" when needed.

### Balance in the HUD

`UI.Label { title = Facet.format.compact(coins), icon = "coin", textSize = "numeral" }`
can fit in the free strip beside the top bar. Repeat the balance at a distant
purchase decision when it helps; compact notation must not hide required precision.

## Before and after

The [rank card pair](before-after/rank-card.md) shows choices for one game's
standing card. It does not establish a required treatment for all records.
