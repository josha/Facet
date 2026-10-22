# Text fit

<!-- aliases: Text fit | text-fit -->

`textSize = "fit"` sets `TextScaled` and adds a `UITextSizeConstraint`. The
engine paints the largest size that fits the label's box, which fills its
parent by default. Use this for a box of fixed size; let ordinary text hug
or wrapped text grow vertically.

`textSize = { fit = { cap = size, floor = size } }` sets the size band.
A size is a positive pixel number or a type role name. The default `cap` is
the label's `textRole`, or `body`. The default `floor` is `caption`.
Role sizes follow the theme. Other keys in `fit` cause an error.
If the box cannot hold the text at the floor, the engine keeps the floor,
so the text can clip. Check longer localized text in the actual box.

Open:

- [Text-fit.truncate](Text-fit.truncate.md)
