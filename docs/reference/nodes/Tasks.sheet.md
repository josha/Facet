# Tasks.sheet

Open a temporary task with sheet dismissal and child-page Back.

Controls: Screen, Button, Sheet, NavigationStack, Text.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local Compose = Facet.Compose
local app = Facet.app({ name = "Game" })
local UI = app.UI
local open = Compose.cell(false)
type Route = { id: string, value: string }
local initial: { Route } = {}
local path = Compose.cell(initial)
app.mount(function()
    return UI.Screen "Root" {
        UI.Button "Open" { label = "Details", onActivate = function() open:set(true) end },
        UI.Sheet "Panel" {
            title = "Details", isPresented = open,
            detents = { "hug" }, closeButton = false,
            content = function()
                return UI.NavigationStack "Pages" {
                    path = path,
                    root = { title = "Home", content = function()
                        return UI.Button "More" { label = "More", onActivate = function()
                            path:set({ { id = "more", value = "Ready" } })
                        end }
                    end },
                    destinations = { more = { title = "More", content = function(entry)
                        return UI.Text "Body" { text = entry.value }
                    end } },
                }
            end,
        },
    }
end)
script.Destroying:Connect(app.dispose)
```

Sheet owns dismissal and scrolling; NavigationStack owns child-page Back.
Its root has no Back command. Here the one-detent grabber closes on tap/click,
Return or gamepad A, so the header Close is redundant. Before reusing
`closeButton = false`, read [Sheet.layout](Sheet.layout.md) and test every
input's exit and return focus.

Match the panel's words to its trigger. Modals hide native touch controls and
restore them on exit; the game owns custom touch actions.

Open:

- [NavigationStack.reference](NavigationStack.reference.md)
- [Sheet.card](Sheet.card.md)
- [Sheet.detents](Sheet.detents.md)
- [Sheet.grabber](Sheet.grabber.md)
