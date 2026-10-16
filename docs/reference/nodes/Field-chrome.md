#### Field chrome

A field can have these field chrome options: `label`, `requiredMark`, `hint`,
`errorText`, `leading`, `trailing`, `controlSize`, `appearance` and `corners`.
A field without search presentation, chrome options, number units, step buttons or `visibleLines`
keeps the native TextBox as its root. Other fields return a Frame. The root
Frame holds these children in order:

1. `Label`: a TextButton that is not selectable. Its `Title` text is the label.
   Activation focuses the TextBox. The label height fits its text, including
   wrapped lines. It follows `enabled`. The input keeps its minimum touch size.
2. `Input`: the plate. It holds `SearchIcon` or `Leading`, `Prefix`, the
   TextBox named `Field`, `Suffix`, `Clear`, `Decrement`, `Increment` and
   `Trailing`, in that order. A named `controlSize` puts the plate in an
   `Input+target` Frame that is 44 pixels tall or more.
3. `Message`: one line. It shows `errorText` when it is not empty, then the
   number rejection text, then `hint`. An error shows the `status.error` mark
   (`MessageMark`), adds the `facet-validation` tag to the text and the
   `facet-invalid` tag to the plate. The plate does not move or shake.

`requiredMark` is `required` or `optional`. It is notation only. It does not
validate. `required` adds ` *` to the label text, also for a readable label.
`optional` adds no word. Put localized "optional" text in `hint`.

`leading` and `trailing` are children, such as native Instances. `leading` is
decoration and is not a focus stop. A search field refuses `leading`, because its search mark
leads. The focusable parts of `trailing` come after the TextBox and the clear
button.

`appearance` is `standard` (the `facet-field` plate), `contrast` (the
`facet-control` plate) or `utility` (no plate). A readable word changes the tag
in place. A word that is not one of these causes an error, and the plate keeps
the last correct paint. `corners` is `pill` or `square`. It adds a native
UICorner named `Corners`. `controlSize` is `xsmall`, `compact`, `regular` or
`large`.

A word that the chrome does not know causes an error that names the option.
