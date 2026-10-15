# Start a game screen

Use one app and one mounted root. The server owns game state and validates
requests. The component owns local state. Keep durable row state in the model.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local Compose = Facet.Compose
local app = Facet.app({ name = "Game" })
local UI = app.UI
local Host = app.runtime.constructors
local open = Compose.cell(false)
app.mount(function()
    return UI.Screen "Root" {
        UI.Button "Open" { label = "Open", onActivate = function() open:set(true) end },
        UI.Sheet "Panel" {
            title = "Details", isPresented = open, closeButton = "Close",
            content = function()
                return UI.VStack "Body" {
                    width = "fill", gap = "s", padding = "m",
                    UI.Text "Message" { text = "Ready", wrap = true },
                }
            end,
        },
    }
end)
script.Destroying:Connect(app.dispose)
```

## Task recipes and call shapes

Use named constructors so strict mode checks literal options and children.
Control options use lower camel case. Native properties keep Roblox names.

| Player task | Controls and call shape | More options with `docs NAME` |
| --- | --- | --- |
| Read a HUD | `UI.Composition "HUD" { UI.fill(), UI.Region "Status" { zone = "topRight", rank = 1, ... } }` | HUD panels |
| Open temporary details | `UI.Sheet "Panel" { title = "Details", isPresented = open, content = build }` | Sheet |
| Read details in place | `UI.DisclosureGroup "Details" { label = "Details", expanded = open, content = build }` | DisclosureGroup |
| Open anchored content | `UI.Popover "Menu" { title = "Actions", isPresented = open, trigger = button, content = build }` | Popover |
| Move through child pages | `UI.NavigationStack "Pages" { path = path, root = { title = "Home", content = build }, destinations = destinations }` | NavigationStack |
| Filter rows or tiles | `UI.VirtualList "Entries" (spec)` or `UI.VirtualGrid "Entries" (spec)` | Collection screen |
| Edit text | `UI.TextInput "Filter" { value = query, placeholder = "Filter" }` | TextInput |
| Change a setting | `UI.Toggle "Music" { label = "Music", value = enabled }` | Toggle |
| Confirm an action | `UI.Alert "Confirm" { title = "Continue?", isPresented = open, actions = actions }` | Alert |
| Show status | `UI.Text "Status" { text = status, textRole = "caption", wrap = true }` | Text |
| Arrange content | `UI.VStack "Body" { width = "fill", gap = "s", padding = "m", ... }`; `UI.HStack` for a row; `UI.fill()` for remaining space | Layout options |

## Typed state and collections

Use `function(use: Facet.Use)` for every reactive function that reads different
cell types. `Facet.Use` is an exported type, not a runtime value or an import.
Use `cell:peek()` in actions and `cell:set(value)` to write.
Give empty arrays, optional values and maps a type before `Compose.cell`.
A table literal has only its named keys. For dynamic keys use
`local initial: { [string]: number } = { Credits = 0 }`, then
`local balances = Compose.cell(initial)` and `use(balances)[key] or 0`.
Use a key union instead when the set of keys is closed.

```luau
type Entry = { id: string, title: string }
local initial: { Entry } = {}
local entries = Compose.cell(initial)
local query = Compose.cell("")
local filtered = Compose.formula(function(use: Facet.Use)
    local term = string.lower(use(query))
    local result: { Entry } = {}
    for _, entry in use(entries) do
        if string.find(string.lower(entry.title), term, 1, true) then
            table.insert(result, entry)
        end
    end
    return result
end)
local spec: Facet.KeyedCollectionSpec<Entry, string> = {
    UI.fill(), from = filtered, key = "id", itemSize = 64,
    render = function(current)
        return UI.Button "Entry" {
            label = function(use: Facet.Use) return use(current).title end,
            onActivate = function() print(current:peek().id) end,
        }
    end,
}
```

Put the collection in a bounded parent. VirtualGrid also takes
`minColumnWidth` and `itemSize` as the estimated tile height. Use `measure = true`
for variable heights. Bind TextInput to `query`; Clear calls `query:set("")`.
Show an empty result with `Compose.show(function(use: Facet.Use)
return #use(filtered) == 0 end, buildEmpty)`.

## Ownership, layout and checks

Use `Compose.show(condition, build)` for branches, `Compose.keyed({ from,
key, render })` for keyed children, and `Compose.cleanup(fn)` for resources.
Use `Host` for native objects. Native layout objects and constraints own layout.
Use theme tokens for paint, type, gap, padding and motion. Text has no `width`
option: put wrapped text in a stack with `width = "fill"`. Sheets own scrolling,
Close and modal selection. Controls own input. Do not bind Escape or Start.

Run `lute run tools/facet verify --tap TEXT...` after a coherent edit. It runs
strict types, usage lint, a Rojo build, and one capture session for audit and
screenshots on all five devices. Give each control in the path to a screen
one `--tap`. Inspect the reported screenshots. Fix problems, then repeat only
the affected checks. No separate audit or preview is needed for those screens.
Without Studio, use `verify --static` and report the live evidence limit.
The tools remove a UTF-8 BOM from application Luau files before engine tools
read them. In Windows PowerShell 5.1, use `Set-Content -Encoding utf8`;
the default encoding is not UTF-8. Other encodings need conversion.

For other options, use `docs <Control>` or `docs --search TEXT`. A long section
prints an outline; `--full` prints its complete contract. Starter components
are in `examples/blocks/`. Use `project [directory]` for file discovery.
