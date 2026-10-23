# Tasks.pages

Open a destination from gameplay, with a readable surface, Close and return focus.

Call inside the app mount. Supply the HUD and body as components.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function pages(app: Facet.App, title: string,
  hud: (() -> ()) -> GuiObject, body: () -> GuiObject,
  suspendGameplay: () -> (() -> ())): Frame
  local C, UI = Facet.Compose, app.UI
  local path = C.cell({} :: { Facet.NavigationEntry<string> })
  return UI.NavigationStack {
    path = path, chrome = "hidden",
    root = { content = function()
      return hud(function() path:set({ { id = "task", value = title } }) end)
    end },
    destinations = { task = { content = function()
      C.cleanup(suspendGameplay())
      return UI.VStack "Surface" { surface = "surface", width = "fill", height = "fill",
        UI.Screen "Task" {
          UI.NavBar { title = title, trailing = UI.Button { label = "Close",
            appearance = "utility", onActivate = function() path:set({}) end } },
          UI.VStack "Body" { width = "fill", height = "fill", UI.fill(), body() },
        },
      }
    end } },
  }
end
```

Use [Composition](Tasks.hud.md) for the HUD. Its visible opener and gamepad
command call the same callback. NavigationStack owns motion, Back and focus
restoration. Close returns to gameplay; the body owns Back within the task.

suspendGameplay disables the game's InputContext and custom touch commands,
and sets GuiService.TouchControlsEnabled to false. Its returned function
restores their previous values on disposal. This changes input, not the game
clock. Keep saved values, filters and selection in the model outside the page.

Use [collection/detail](Tasks.collection-detail.md) or a
[scrolling form](ScrollView.card.md) as the body. Keep commitment outside long
scrolling content. Test compact fit and input return. Use [Sheet](Tasks.sheet.md) for a bounded
interruption; [TabView](Tasks.tabs.md) switches peer destinations.
