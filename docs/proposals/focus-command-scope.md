# Focus and command scope

A player focuses a board cell and types A. One game handler chooses one rack
A, places it and advances focus. Backspace returns the tile. A TextInput must
receive these keys while it edits text. Mouse, touch and native gamepad focus
must select the same cell. The game owns matching and placement.

Add UI.commandScope(root, spec). targets is a readable array of { key, node }.
commands is an array of { id, keys, enabled?, onInvoke(key) }. The returned
CommandScope has current, focus(key), clear() and actions by command id.
Use GuiService.SelectedObject and SelectionGained for visible native focus.
InputBegan can focus a touched or clicked target. Do not create a second focus
graph. Targets can contain native descendants. Each command has one handler.

InputContext.Enabled, Priority and Sink already arbitrate native InputActions
and InputBindings. UserInputService.GetFocusedTextBox, TextBoxFocused and
TextBoxFocusReleased identify text entry. Compose.formula and cleanup own
observation and connections. Compose.createFocusScope supplies a model but
native GuiService selection is already the source of truth for these nodes.
The internal ctx.action already creates owned actions and includes Facet's
Tab and Escape reserved-key dispatcher. Expose control policy through it.

Text entry wins. Modal availability and existing control actions win next.
Only the most specific enabled scope that contains native selection can handle
a key. A scope has lower priority than existing Facet control actions. Native
selection chooses gamepad navigation; the scope does not intercept directions.
Each physical key belongs to one command in a scope. Do not bind the same key
to two commands. A command does not run without a focused target.

First fail a public case with duplicate rack letters and no commandScope API.
Then prove one handler, key changes, Backspace, text-entry suppression, reserved
Escape precedence, pointer focus, gamepad selection, disabled targets, disposal
and a readable target list. Extend the board-and-rack Lab and live suite.
