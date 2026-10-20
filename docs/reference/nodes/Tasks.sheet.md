# Tasks.sheet

Open a modal Sheet with Close and child-page Back.

Controls: Screen, Button, Sheet, NavigationStack, Text.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local Compose = Facet.Compose
local app = Facet.app({ name = "Game" })
local UI = app.UI
local open = Compose.cell(false)
type Route = { id: string, value: string }
local path = Compose.cell({} :: { Route })
app.mount(function()
    return UI.Screen "Root" {
        UI.Button "Open" { label = "Details", onActivate = function() open:set(true) end },
        UI.Sheet "Panel" {
            title = "Details", isPresented = open, closeButton = "Close",
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

Sheet owns Close, scrolling and modal selection. NavigationStack owns Back;
its root has no Back.

Keep Close in its header. `hug` needs an intrinsically sized short body.
NavigationStack fills its viewport; use a bounded detent.
Keep large collections in bounded scrolling viewports.

Use Popover for anchored actions and DisclosureGroup for inline facts.

Modals use `GuiService.TouchControlsEnabled` to hide native touch controls
and restore them when the last modal closes. The game owns custom touch actions.

Open:

- [NavigationStack.reference](NavigationStack.reference.md)
- [Sheet.card](Sheet.card.md)
- [Sheet.detents](Sheet.detents.md)
