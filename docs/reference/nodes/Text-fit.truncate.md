# Text-fit.truncate

`truncate = "end"` sets the native `TextTruncate.AtEnd`. `truncate = "middle"`
keeps the start and the end of the value and puts an ellipsis between them,
for example `Coastal circui…lap 14`. Use it when the end identifies the value,
such as a file name, a path or an id.

- The label is one line. It fills the width and hugs the height by default.
  `TextWrapped = true` or `RichText = true` with `truncate = "middle"` causes
  an error.
- The label measures each candidate with the engine `TextBounds` of the label
  itself, so the measurement uses the painted face and size. A cut never
  divides a UTF-8 character. When the value fits, the label shows all of it.
  When no character fits, it shows only the ellipsis.
- The label cuts the value again when the value, the width, `TextSize` or
  `FontFace` changes. It does not measure on other changes. Before the label
  has a width, it shows all of the value.

For a fitted font size in a fixed box, see [Text-fit](Text-fit.md).
