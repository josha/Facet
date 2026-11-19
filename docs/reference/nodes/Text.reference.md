### Text

<!-- aliases: Text | text -->

Open one option group below. Each group gives part of this contract.

`UI.Text(spec) -> TextLabel` shows plain text. `text` is a string, a readable
or a function of `use`. It is required. `label` and the native `Text` cause an
error, and so do `color` and `font`, because the theme owns them. Use `role`
or `textRole` instead.

Unwrapped text with automatic size keeps its largest measured box while its
text keeps the same length, so a counting number does not jitter. Text given as a
fixed string uses the native automatic size. Facet measures it with font metrics
only after its text first changes, or when the engine reports that the text
does not fit. Text with a
different length fits again: a wallet that falls from 1,000,000 to 12 shrinks.
A change to the font, text size or layout mode resets the reserved size.
Wrapped text, truncated text and authored size constraints keep their native
layout behavior.

A one-line Text that is wider than its room shrinks to fit with a `UIScale`
named `TextFit`, down to 70 percent of its size and not below 10 pixels. Its
room is its own width when it fills its parent, and the box of an aligned
ZStack when it hugs there; a hugging Text in a row keeps the row's wrap and
spill behavior. A text that does not fit at that size runs past its room.
`truncate` or a native `TextTruncate`, `wrap`, `lines`, a fitted `textSize`,
`reveal`, `disclose` and an authored `AutomaticSize` turn this off. When the player chooses a text size
larger than the default (`GuiService.PreferredTextSize`), the Text keeps that
size and does not shrink: let it wrap or give it more room.

Without native `Size` and `AutomaticSize`, a Text fills the width that its
parent gives and grows only in height (`Size = UDim2.fromScale(1, 0)`,
`AutomaticSize = Enum.AutomaticSize.Y`). A one-line Text hugs its text
(`AutomaticSize = Enum.AutomaticSize.XY`) in a horizontal stack, in a parent
that hugs its width, outside a GuiObject, in an aligned ZStack, and at an
explicit `Position` or `AnchorPoint` in a parent without a layout. A filled
one-line Text in a vertical stack takes the stack's horizontal alignment
unless `textAlign` is set. Set
`AutomaticSize = Enum.AutomaticSize.XY` to hug in any parent.

Bound text, given as a readable or a function, sets `AutoLocalize` to false
unless you set `AutoLocalize`. Bound text is usually data, such as a name or a
count. The engine localizes each change again, and that costs about 15 µs for
each change that contains letters. To translate bound text, use the controls
translator or set `AutoLocalize = true`.

Open:

- [Text-fit](Text-fit.md)
- [Text.Facet.richText.escape](Text.Facet.richText.escape.md)
- [Text.textRole](Text.textRole.md)
