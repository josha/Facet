### Review

<!-- aliases: Review | Facet.review | design review | review.screen -->

`Facet.review` finds layout and type patterns that make a screen look generic.
It reads the screen. It does not change it. It is a tool for authors and
agents, not a runtime feature.

- `review.screen(options?) -> ReviewReport` collects the LocalPlayer's
  PlayerGui (or `options.root`) and analyzes it. Run it on the client.
- `review.collect(options?) -> ReviewSnapshot` returns the snapshot only. It
  reads ScreenGuis only, styled values (`GetStyled`), effective visibility,
  absolute rectangles, the rendered size of scaled text under `UIScale` and
  the `facet-type-*` tag of each Text.
- `review.analyze(snapshot) -> ReviewReport` analyzes a snapshot. It is pure.
- `review.fixes` maps each rule to its fix.

A report has `findings` (rule, severity, path, detail, rect), `prominence`
(the six most prominent texts by size, weight and contrast), `sizes` (the text
sizes in use), `fixes` (the fix for each rule found) and `text` (a printable
summary).

| Rule | Finds |
|---|---|
| `joined-facts` | One text that joins facts with a middle dot, a bullet, a vertical bar, a spaced slash or an en dash. Medium when a fact has a number. |
| `numbers-unemphasized` | Three or more texts with numbers, none larger than the common size or bold. |
| `flat-hierarchy` | The largest text is less than 1.35 times the common size. |
| `competing-peaks` | Two different texts share the lead size in one plate. The same slot in sibling groups, such as three stat values, counts once. |
| `record-without-visual` | Three or more sibling items (plates or controls) of one width, with two texts or 56 px tall, where fewer than half have an image of 32 px or more. |
| `nested-surface` | A plate in a plate of nearly the same color. |
| `zero-wall` | Three or more zeros that are at least half of the numbers. |
| `single-weight` | Six or more texts in one font and one weight. |
| `stacked-choices` | Four or more short interactive choices stacked one per row, each at most 60% of the width of their parent. |
| `hollow-plate` | A plate 280 pixels or wider whose content uses less than 35% of it; one finding per group of plates of the same size. |
| `lopsided-page` | On a screen 900 or more wide, a full-width surface with 85% or more of its content in one half. |
| `floating-text` | Three or more texts with no plate behind them, straight on the world. |
| `touch-control-overlap` | On a touch screen, a HUD control outside any scroll view and any large panel that covers a fifth or more of the place where Roblox draws Jump. |
| `stranded-content` | Content that uses less than 40% of a large surface and sits to one side. |

A finding is a prompt to look, not a verdict. A rule can find a deliberate
choice. The rules do not judge subject, art or identity. The critique-ui skill
pairs this report with captures for that judgment.

In Studio during Play, run `return Facet.review.screen().text` in the Client
data model through a Studio tool, or `print(Facet.review.screen().text)` in
the command bar. The pure form takes any snapshot:

```luau
local report = Facet.review.analyze({ width = 1920, height = 1080, elements = {} })
assert(#report.findings == 0)
```

`lute run tools/facet audit` and `lute run tools/facet critique` apply the
same rules to saved interface dumps.

Back to [Public entry points](Public-entry-points.md).
