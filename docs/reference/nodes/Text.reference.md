### Text

<!-- aliases: Text | text -->

Open one option group below. Each group gives part of this contract.

`UI.Text(spec) -> TextLabel` shows plain text. `text` is a string, a readable
or a function of `use`. It is required. `label` and the native `Text` cause an
error, and so do `color` and `font`, because the theme owns them. Use `role`
or `textRole` instead.

Unwrapped text with automatic size keeps its largest measured box while its
text keeps the same length, so a counting number does not jitter. Text with a
different length fits again: a wallet that falls from 1,000,000 to 12 shrinks.
A change to the font, text size or layout mode resets the reserved size.
Wrapped text, truncated text and authored size constraints keep their native
layout behavior.

Bound text, given as a readable or a function, sets `AutoLocalize` to false
unless you set `AutoLocalize`. Bound text is usually data, such as a name or a
count. The engine localizes each change again, and that costs about 15 µs for
each change that contains letters. To translate bound text, use the controls
translator or set `AutoLocalize = true`.

Open:

- [Text-fit](Text-fit.md)
- [Text.Facet.richText.escape](Text.Facet.richText.escape.md)
- [Text.textRole](Text.textRole.md)
