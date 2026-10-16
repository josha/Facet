### TextInput

<!-- aliases: TextInput | textinput -->

`value` is the string model. Roblox TextBox owns editing, IME, the caret, the
text selection and focus. `onChange(text)` handles user edits. An external
model update does not send it. `onCommit(value, reason)` receives `submit` or
`focusLost`. The number presentation also reports `clamped`. `onCancel`
observes cancellation and the restoration of the initial value of the edit.

`presentation` is `plain`, `search` or `number`. The number presentation also
uses a writable `numericValue`, `min`, `max`, `parse` and `format`, and the
number options of [NumberInput](NumberInput.reference.md). If a callback disables the input
during a commit, the commit stops. `numericValue` does not change and
`onCommit` does not run. `validate(proposed)` returns the accepted text, or
`nil` to reject it. `maxLength` counts UTF-8 characters.

The other options are `placeholder`, `multiline`, `invalid`, `enabled`,
`disabled`, `clearButton` and `clearButtonMode` (`never`, `always`,
`whileEditing` or `unlessEditing`). Native TextBox properties stay available.
The placeholder uses the `contentSecondary` colour of the theme. A
plain TextInput without field chrome (no `label`, `hint` or other chrome option) is
the TextBox itself, so it keeps the flat `facet-field` plate in a skinned
theme. A framed TextInput shows the `field` art on its `Input` plate.
The clear button is a 44 by 44 `utility` Button named `Clear`. It shows the
`close` icon and no text. Its accessible name is "Clear".

- `readOnly`: a boolean or a readable boolean. A read-only field stays
  selectable, keeps full contrast and can take focus. `TextEditable` is false,
  the control refuses each edit, the clear button does not show and focus loss
  commits nothing. A live change keeps the same TextBox and the edit.
- `selectOnFocus`: `none` (the default), `all` or `end`, or a readable of one.
  The control applies it once for each focus session. A pointer focus applies
  it at the release of that pointer. Other focus applies it at once. A change
  during focus applies at the next focus. A live value that is not one of the
  three words causes an error, and the control keeps the last correct word. The
  TextBox has the `selectOnFocus` attribute only when you supply the option.
- `visibleLines`: a whole number of at least 1, for a multiline field only. The
  field shows that number of body lines in a native ScrollingFrame named
  `Viewport`. Longer text scrolls in the viewport, and the viewport keeps its
  size. The viewport is selectable, so a D-pad move reaches the field while the
  viewport is still off the screen, and the selection passes to the field. Without `visibleLines`, a multiline field grows to hold all its lines,
  including a final empty line.

Open:

- [Field-chrome](Field-chrome.md)
