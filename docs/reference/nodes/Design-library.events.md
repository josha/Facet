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
