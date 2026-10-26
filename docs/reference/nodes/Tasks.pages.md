# Tasks.pages

Inside app mount:

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

Start with [HUD](Tasks.hud.md) or [hub](Tasks.hub.md), with an empty path.
Opener and gamepad use one callback. NavigationStack owns motion and focus. Close returns to gameplay; NavBar Back follows the body's
`back`. Screen reaches the glass; NavBar and body stay safe.

The default stack also moves its covered HUD. For a stationary HUD, use the
`parallax = 0` theme in [Tasks.theme](Tasks.theme.md). Check both directions.

Use `suspendGameplay = true`. While the path is nonempty or
a modal is open, Facet turns off GuiService.TouchControlsEnabled and
`UI.environment().gameplaySuspended` is true. Both return when the last one
closes, before exit motion ends. Derive the game's input from it:
`driving.Enabled = use(inKart) and not use(suspended)` in a `C.watch`.
The clock still runs. Keep saved values and drafts outside pages.

Give each body its task layout: [collection/detail](Tasks.collection-detail.md),
a [form](ScrollView.card.md), or subject and action. Keep commitment with its
terms; scroll the complete decision when room is short. Give unrelated tasks
separate scroll state. Use [Sheet](Tasks.sheet.md) for a short task.
