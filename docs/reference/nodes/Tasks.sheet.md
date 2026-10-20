# Tasks.sheet

A Sheet with dismissal and child-page Back.

Controls: Sheet and NavigationStack.

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
      title = "Details", isPresented = open,
      detents = { "medium" }, closeButton = false,
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
The root has no Back. The one-detent grabber closes on tap/click,
Return or gamepad A. For `closeButton = false`, read
[Sheet.layout](Sheet.layout.md) and test each input's exit and return focus.

NavigationStack fills its viewport; use a bounded detent. `hug` needs an
intrinsically sized short body. Keep large collections in bounded viewports.
Use Popover for anchored actions and DisclosureGroup for inline facts.

Match the panel's words to its trigger. Modals hide native touch controls and
restore them on exit; the game owns custom touch actions.

Open:

- [NavigationStack.reference](NavigationStack.reference.md)
- [Sheet.card](Sheet.card.md)
- [Sheet.detents](Sheet.detents.md)
- [Sheet.grabber](Sheet.grabber.md)
