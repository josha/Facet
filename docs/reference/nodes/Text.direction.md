# Text.direction

<!-- aliases: Text.textAlign | text direction | right-to-left -->

How `textAlign` and `direction` place the text of a UI.Text.

`direction` is `auto`, `ltr` or `rtl` and sets `TextDirection`. `textAlign`
is `start`, `center` or `end` and sets `TextXAlignment`. It can be bound.

`start` and `end` follow the text direction. With `direction = "rtl"`,
`start` is the right edge. With `direction = "auto"` or no `direction`, the
first strong character of the text sets the direction, as the engine does
for `TextDirection.Auto`. Hebrew or Arabic text at the start of the string
is right to left. Digits, punctuation and emoji have no direction. The engine
does not mirror `TextXAlignment`, so Facet resolves `start` and `end`.

Set `direction` when the engine translates the text into a script with
another direction. Facet reads the text that you give, not the translation.

Without `textAlign`, the alignment comes from the layout, as
[Text](Text.reference.md) describes, or is the left edge. Stack alignment
does not follow the text direction.

UI.Text refuses the native `TextXAlignment` and `TextDirection`: use
`textAlign` and `direction`.

Back to [Text](Text.reference.md).
