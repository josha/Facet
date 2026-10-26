# Tasks.pages

Call inside the app mount.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function pages(app: Facet.App, title: string,
	hud: (() -> ()) -> GuiObject, body: (Facet.Value<boolean>) -> GuiObject): Frame
	local C, UI = Facet.Compose, app.UI
	local path = C.cell({} :: { Facet.NavigationEntry<string> })
	local back = C.cell(false)
	return UI.NavigationStack {
		path = path, chrome = "hidden",
		root = { content = function()
			return hud(function() path:set({ { id = "task" } }) end)
		end },
		destinations = { task = { content = function()
			return UI.Screen "Task" { surface = "surface",
				UI.NavBar { title = title, onBack = back, trailing = UI.Button { label = "Close",
					appearance = "utility", onActivate = function() path:set({}) end } },
				UI.VStack "Body" { width = "fill", height = "fill", UI.fill(), body(back) },
			}
		end } },
	}
end
```

The [HUD](Tasks.hud.md) opener and gamepad command share the callback.
NavigationStack owns motion and return focus; focus starts in the body, not on
Close. Close returns to gameplay; NavBar Back follows the body's `back`.
The Screen surface reaches the glass; the NavBar and body stay safe.

Create the app with `suspendGameplay = true`. While the path is nonempty or
a modal is open, Facet turns off GuiService.TouchControlsEnabled and
`UI.environment().gameplaySuspended` is true. Both return when the last one
closes, without waiting for exit motion. Derive the game's input from it:
`driving.Enabled = use(inKart) and not use(suspended)` in a `C.watch`.
This does not pause the clock. Keep saved values and drafts outside pages.

The body owns its layout: use [collection/detail](Tasks.collection-detail.md),
a [form](ScrollView.card.md), or a focal subject with its facts and action.
Keep commitment outside long scrolling content.
Use [Sheet](Tasks.sheet.md) for a short task.
