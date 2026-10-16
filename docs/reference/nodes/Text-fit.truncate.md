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

`textSize = "fit"` sets `TextScaled` and adds a `UITextSizeConstraint`. The
engine then paints the largest size that fits the box of the label. The
default box fills its parent. `textSize = { fit = { cap = size, floor = size } }`
sets the band. A size is a pixel number or a type role name. The default `cap`
is the `textRole` of the label, or `body`. The default `floor` is `caption`.
Role sizes come from the theme package and follow a theme change. Another
`textSize` value, or another key in `fit`, causes an error.

The AsyncImage loader receives `(source, resolve, reject)`. It can return a
cancellation. A superseded result cannot replace the current image. Loading and
failure stay observable. The control does not invent successful assets.
`resource` is a function that returns an `ImageResource`. The resource contains
`value` and either `state` or `status`. The function can register cleanup with
`Compose.cleanup`. A Compose shared resource acquire function also fits this
contract. Resource lifetime uses Compose ownership.
