# Information display

Show each fact in the form the player reads at a glance. A value leads; its
label is small; every item and stat carries a visual. These recipes replace
the most common generic pattern: several facts joined in one caption.

## Rules

- **One fact, one element.** Do not join facts with ` · `, ` • `, ` | ` or
  ` / `. `Facet.review` reports it as `joined-facts`.
- **Value leads, label follows.** Put the deciding number in `numeral` (or
  `strong` inside a dense row) and its label or unit in `caption` beside or
  under it. Never "Speed 88" in body type.
- **A visual by default.** Every item, record and stat gets its image or
  model, else a theme glyph (`UI.Label { presentation = "iconOnly" }` with a
  name from Icons.names), an emblem, a swatch, pips or a bar. Text-only is an
  exception with a reason, such as a word list in a word game.
- **One lead per group.** The mode name, a filter or a title must not match
  the size of the value the player came for.
- **A goal, not a wall of zeros.** When a record is empty, show what the
  player does next and how far it is.
- **One plate per layer.** Separate groups with space or one hairline, not a
  card inside a card.

The theme must make `numeral` clearly larger than `body` (1.6 times or more);
`Facet.themes.define` reports a flat scale in `report.advice`.

## Recipes

Each recipe uses `local C, UI = Facet.Compose, app.UI`.

### Stat block

A glyph, the value, then the label. Use three or four in a row for a record.

```luau
local function stat(name: string, icon: string, value: (Facet.Use) -> string): Frame
	return UI.VStack(name) {
		align = "center",
		gap = "xs",
		UI.Label { title = name, icon = icon, presentation = "iconOnly", iconSize = 28 },
		UI.Text { text = value, textRole = "numeral" },
		UI.Text { text = name, textRole = "caption", role = "secondary" },
	}
end
UI.HStack "Record" { width = "fill", distribute = "spaceEvenly",
	stat("Wins", "trophy", wins), stat("Losses", "close", losses), stat("Draws", "flag", draws) }
```

### Rank and rating

An emblem leads the row, the rating is the numeral and the tier name is the
label. Progress to the next tier is a bar, not a sentence. See
[standing](../examples/standing.luau) for the complete card.

### Placement and other goals

Replace "Provisional · 0 of 10 ranked games" with pips and the next step.

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
| Subject | `Image`, `Stage` or, without art, a glyph on a `pane` plate |
| Category | `caption` or `label`, secondary, above the name |
| Name | `strong` in a row, `title` in detail |
| Facts | an `HStack` of value (`strong`) over label (`caption`); in detail the value is `numeral` |
| Price | `Label` with the currency glyph |

Use a Table when players compare many facts across many items.

### Stat change

For an upgrade, show the current value, a `chevron.trailing` glyph and the new
value in the accent. Add a `ProgressView` against the stat's maximum when the
scale matters.

### Leaderboard row

A fixed-width rank numeral, the `Avatar`, the name in `strong`, a `Spacer {}`
and the score as a numeral at the end. Mark the player's own row with
selection paint, not a word.

### Balance in the HUD

`UI.Label { title = Facet.format.compact(coins), icon = "coin", textSize = "numeral" }`
in the free strip beside the top bar. One balance per glyph; do not repeat it
in other groups.

## Before and after

The [rank card pair](before-after/rank-card.md) applies these rules to a real
screen.
