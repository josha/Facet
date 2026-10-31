# Before and after: a rank card

A ranked-mode card in a word game. The player checks their standing and how
to improve it.

This is one design case, not a prescription for every record display. Its
emblem, type sizes, pips and theme suit this standing card. Other tasks can
use text, exact counts or dense tables. A clean automated report does not by
itself establish that the revision is better.

## Before

![Before](rank-card-before.png)

```luau
UI.VStack { surface = "panel", padding = "l", gap = "s",
	UI.Text { text = "Quick", textRole = "title" },
	UI.Text { text = `{tier} · {rating}`, textRole = "title" },
	UI.Text { text = `Wins {w} · Losses {l} · Draws {d}`, textRole = "caption" },
	UI.Text { text = `Provisional · {played} of 10 ranked games`, textRole = "caption" },
}
```

`Facet.review` reports `joined-facts` three times, `competing-peaks` for
"Quick" and "Spark · 1000", and `zero-wall`. A reviewer adds what no rule sees:

| Problem | Tag | Move |
|---|---|---|
| The mode name is as loud as the rating | `competing-leads` | Mode as a small `label` eyebrow; the rating is the one `numeral` |
| The rating hides in a sentence with the tier | `numbers-buried` | Rating alone as the numeral; tier name as the `heading` under it |
| The tier has no look | `stat-without-visual` | A tier emblem on a `pane` plate leads the row |
| Three zeros say nothing | `zero-wall` | While placing, hide the record and show the goal |
| Progress is a sentence | `progress-as-text` | Ten segmented pips and "Play 10 ranked games to place your rank." |
| The card sits on a card of nearly the same color | `boxed-everything` | One plate; the language setting moves to a settings row |

## After

![Before, in the Riverbank theme](rank-card-before-themed.png)
![After, while placing](rank-card-after.png)
![After, once placed](rank-card-after-placed.png)

[standing.luau](../../examples/standing.luau) builds the card:

- `MODE` eyebrow in `label`, secondary.
- An emblem (the tier glyph at 64 px on a `surface` pill) beside the rating as
  the one `numeral`, with the tier name as a `heading` under it.
- While placing: segmented pips and the goal sentence. After placement: three
  stat blocks (glyph, `heading` value, caption) and a bar toward the next tier.

`Facet.review` reports nothing on either state. The first captures did not
look like this. Each fix came from looking at a capture:

| First capture | Cause | Fix |
|---|---|---|
| The rating barely larger than the tier | `numeral` at 32 px beside a 28 px `heading` | The theme gives `numeral` 44 px |
| The emblem plate invisible | a `pane` plate on a `panel` of nearly the same color | A `surface` plate |
| No pips | the theme `control` color matched the panel | A darker `control` in the theme |
| "Next tier" past the card edge | a fill-width column in a row without `UI.fill()` | `UI.fill()` in the column |
| Record values as large as the rating (`competing-peaks`) | the stat blocks used `numeral` | Stat values use `heading` under a hero |

Open: empty segments draw one continuous track, so the ten slots do not show
before the first game. The goal sentence carries it for now.
