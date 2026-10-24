# Tasks.pages

Open a destination from gameplay, with a readable surface, Close and return focus.

Call inside the app mount; the HUD and body are components.

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

Build the HUD as in [Tasks.hud](Tasks.hud.md); its opener and gamepad command
call one callback. NavigationStack owns motion, Back and focus
restoration. Close returns to gameplay; the body owns Back within the task.

suspendGameplay turns off the game's InputContext, custom touch commands and
GuiService.TouchControlsEnabled, and returns a function that restores them. It
changes input, not the game clock. Keep values, filters and selection in the
model, outside the page.

With `screen = { ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets }` on the
app, the surface fills behind the Roblox top bar and content stays below it.

The body can be [collection/detail](Tasks.collection-detail.md) or a
[scrolling form](ScrollView.card.md), with commitment outside the scrolling.
Use [Sheet](Tasks.sheet.md) for a bounded interruption; [TabView](Tasks.tabs.md)
switches peer destinations.
