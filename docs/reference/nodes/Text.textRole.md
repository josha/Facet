# Text.textRole

Text.textRole option values and behavior.

- `textRole` sets the type role tag, for example `facet-type-title`. The
  default is `body`. `textSize` can give the role instead, as a role name.
  Both together cause an error.
- `textSize` as a number sets `TextSize` in pixels. `"fit"` and
  `{ fit = { cap, floor } }` fit the text to its box. See below.
- `role = "secondary"` adds the `facet-secondary` tag. `role = "content"`
  removes it. `role` can be bound.
- `textAlign` is `start`, `center` or `end` and sets `TextXAlignment`. It can
  be bound. `wrap` sets `TextWrapped`. `rich = true` sets `RichText`.
- A wrapped text with automatic height measures its lines with
  `TextService:GetTextBoundsAsync` at its styled font, size and line height,
  and its `TextBoundsFloor` constraint keeps at least that height. The engine
  sizes automatic text with the native `FontFace` and `TextSize`, not the
  styled ones, so a styled two-line string could show one clipped line.
- `direction` is `auto`, `ltr` or `rtl` and sets `TextDirection`.
- `tint` sets `TextColor3` for a colour that no role gives.
- `disclose = true` keeps a truncated value readable. Unwrapped text uses an
  end ellipsis by default. An explicit `truncate` or native `TextTruncate`
  keeps its authored rule. While the engine
  reports that the text does not fit (`TextFits`), or a middle cut shortens
  it, the whole value shows in a panel named `Disclosure` beside the label:
  after a pointer rests on the label for 0.45 seconds, after a keyboard or
  gamepad selection rests on the label or on the control that holds it, or at
  once on a touch long-press on the label. Touch panels prefer the space above
  the held finger, with a side or lower fallback at the safe-area edges.
  The next touch anywhere closes it.
  The panel takes no selection.
- `reveal = "auto"` makes a one-line label that truncates at the end scroll its
  whole value. It rests in the engine's ellipsis for 1.2 seconds, then the
  whole string slides left as one strip (`Reveal`, clipped to the label's box)
  at about three characters a second until the tail shows, holds 1.2 seconds,
  slides back and rests again. The label's own paint is hidden by a
  `RevealHold` UIGradient while the strip shows. It is also a `disclose`
  label, and its `Disclosure` panel stops the strip while it shows. Only one
  strip moves at a time in the controls. It stays still under reduced motion
  and while the text fits. `reveal` refuses `wrap`, `lines` and a middle cut.
- `lines = n` shows at most `n` lines. The text fills the width, wraps, and
  ends with an ellipsis when it needs more lines. The box hugs shorter text.
  The limit follows the text size, the line height and the vertical padding.
  `lines` cannot combine with a middle cut or a fitted text size.
