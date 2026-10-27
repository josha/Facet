### Rating and LevelPicker

<!-- aliases: Rating and LevelPicker | rating-and-levelpicker -->

Both take a numeric `value`, a positive integer `count` (default `5`),
`allowZero` (default true), `readOnly`, `enabled` and `onChange`. The
`value` and `semanticValue` attributes stay in the range from the minimum to
`count`, also when the model holds a value outside it.

With `onChange`, a value change is a proposal: the caller must update the model
to accept it. Without the callback, a writable `value` cell updates directly.
A read-only value requires `onChange` unless `readOnly = true`.

- Rating supports `glyphs = { filled, empty }` and `starSize`. The mark size
  is the preferred size. In a bounded slot, the control first reduces spacing.
  If the marks still do not fit, it reduces their size together. Pointer input
  follows the displayed marks. Selection input can reach every value.
- LevelPicker supports `segment` (`bar`, `glyph` or `image`), `segmentSize`,
  `glyphs`, `images` and `tint` filled and empty Color3 pairs. A bar segment has
  the `facet-level-segment` tag, and a filled bar also has `facet-level-on`.

The named sizes are `small` (20), `medium` (28) and `large` (36).
