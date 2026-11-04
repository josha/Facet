### Design event fields

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
