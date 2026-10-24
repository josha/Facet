# Tasks.pages

Call inside the app mount.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function pages(app: Facet.App, title: string,
  hud: (() -> ()) -> GuiObject, body: () -> GuiObject,
  suspendGameplay: () -> (() -> ())): Frame
  local C, UI = Facet.Compose, app.UI
  local path = C.cell({} :: { Facet.NavigationEntry<string> })
  local hasPage = C.formula(function(use) return #use(path) > 0 end)
  C.watch(function(use)
    if use(hasPage) then C.cleanup(suspendGameplay()) end
  end)
  return UI.NavigationStack {
    path = path, chrome = "hidden",
    root = { content = function()
      return hud(function() path:set({ { id = "task", value = title } }) end)
    end },
    destinations = { task = { content = function()
      return UI.Screen "Task" { surface = "surface",
        UI.NavBar { title = title, trailing = UI.Button { label = "Close",
          appearance = "utility", onActivate = function() path:set({}) end } },
        UI.VStack "Body" { width = "fill", height = "fill", UI.fill(), body() },
      }
    end } },
  }
end
```

The [HUD](Tasks.hud.md) opener and gamepad command share the callback.
NavigationStack owns motion, Back and return focus. Close returns to gameplay.
The Screen surface reaches each edge of the glass; the NavBar and body stay in
the safe area. Keep the default ScreenInsets.

suspendGameplay disables the game's InputContext, custom touch commands and
GuiService.TouchControlsEnabled. Its returned function restores their prior
values. One suspension covers the nonempty path; root or unmount releases it
without waiting for exit motion. This does not pause the clock. Keep saved
values and drafts outside pages.

The body owns its layout and inner Back: use [collection/detail](Tasks.collection-detail.md),
a [form](ScrollView.card.md), or a focal subject with its facts and action.
Keep commitment outside long scrolling content. Test compact fit and input return.
Use [Sheet](Tasks.sheet.md) for a short task.
