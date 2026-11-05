### Design event fields

Button exposes `MouseEnter`, `MouseLeave` and `SelectionGained` as event fields.
Bind them to named contract outputs to show related content on pointer hover
or controller focus. These events do not activate the Button. `MouseEnter`
and `MouseLeave` pass the pointer's x and y screen coordinates to outputs with
`args = { "number", "number" }`. Use an output with no arguments when the
action does not need the coordinates. `SelectionGained` supports an output
with no arguments.

Sheet exposes `initialFocus` as a string field. Set it to the name of the
action that must receive controller focus when the Sheet opens. The runtime
uses a control name for this field, so use a string literal or a string input.

Toggle and Picker expose `onChange` as an event field. Bind it to a named
contract output with the value type of that control. Parse, emit and render
keep the input and output bindings.

Toggle requests a value. Use a boolean output and let the host action update
the readable `value` input. If the host does not accept the request, the
control keeps its current value.

Picker writes its writable `selected` cell before it calls the output. Use
a cell input for `selected` and an output with the selection's type. Its
`options` can be a readable list. Choosing the current single selection does
not emit another change.

TextInput exposes `onChange` with the new text and the native `Focused` event
with no arguments. Use `onChange` for a string output. The host action accepts
the edit and updates the readable value. `Focused` can bind to a row output
that selects the row key with `fields`.

The pinned Compose Design supports selected row fields or event arguments.
Combining row fields and event arguments in one ordered output needs the
Compose Design row-event change before Facet can expose that binding.
