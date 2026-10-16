## Focus and command scopes

`UI.commandScope(root, spec) -> CommandScope<K>` attaches commands to an
existing GuiObject. `targets` is a value or readable array of `{ key, node }`.
Each key and node must be unique. A node can contain native selection targets.
`commands` is an array of `{ id, keys, enabled?, onInvoke(key) }`. Each id is
unique. `keys` contains KeyCode names. One key belongs to one command in the
scope. `enabled` on the spec or command is a boolean or readable.

The returned handle has `current: Readable<K?>`, `focus(key) -> boolean`,
`clear()`, and `actions` by command id. Actions are native InputActions and
can be used with ShortcutHint. `focus` selects an available native target.
It returns false if the key is absent, disabled or unmounted. `clear` clears
native selection only when this scope owns it. Mouse and touch select their
target. Keyboard and gamepad use native selection and the same commands.
The scope does not bind directional navigation. Bound W, A, S and D commands
hold the current native selection in their direction while the command is
active. Unbound navigation stays native. Text entry and disposal restore the
previous selection links.

TextInput text entry wins. Commands are disabled while any TextBox is focused.
Existing control actions and modal availability win next. Among scopes that
contain native selection, the most specific enabled scope wins. A scope uses
InputContext priority 1500, below existing Facet control actions. Tab and
Escape use the shared reserved-key dispatcher with the same precedence.
One handler receives the current key. The game chooses the matching item and
owns placement, validation and cursor advance. Compose owns actions and
connections. Disposal clears current and makes focus return false.

```luau
local cell = UI.Button { label = "Board cell" }
local board = UI.Grid { columns = 1, cell }
local scope = UI.commandScope(board, {
    targets = { { key = "centre", node = cell } },
    commands = {
        { id = "PlaceA", keys = { "A", "ButtonX" }, onInvoke = function(key)
            print("Place one A at", key)
        end },
        { id = "Recall", keys = { "Backspace", "ButtonY" }, onInvoke = function(key)
            print("Recall from", key)
        end },
    },
})
scope.focus("centre")
```
