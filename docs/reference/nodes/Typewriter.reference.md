### Typewriter

<!-- aliases: Typewriter | typewriter -->

`UI.Typewriter(spec: TypewriterProps) -> TextLabel` takes the Text options and
reveals the full `text` through native `MaxVisibleGraphemes`. It never slices
the string. It counts graphemes in engine `ContentText`, so rich-text tags and
entities do not add reveal steps. A new text value restarts the reveal.
`MaxVisibleGraphemes`, a middle cut and `reveal = "auto"` are refused.

The theme tokens `motion.typewriter.grapheme` (seconds per grapheme, default
0.035) and `motion.typewriter.pause` (initial seconds, default 0) set timing.
The interval must be positive and the pause must be nonnegative. The neutral
theme supplies missing tokens. At motion level `limited` or `none`, the whole
line shows at once. Text styles and the font follow the theme.

`onRevealed()` runs once when the line finishes, including an empty line,
Skip or reduced motion. Pass a `TypewriterControls` table as `controls` to
get `revealed: Readable<boolean>` and `finish: () -> ()`. `finish()` shows
the whole line at once. Repeated calls do not repeat the callback. A new line
resets `revealed`. Unmount cancels the clock and clears the controls fields.

```luau
local reveal: Facet.TypewriterControls = {}
local dialogueLine = Compose.cell("<b>Guide:</b> Follow the lights to the next camp.")
UI.Typewriter "Guide" { text = dialogueLine, rich = true, wrap = true, controls = reveal }
UI.Button { label = "Skip", onActivate = function() if reveal.finish then reveal.finish() end end }
```
