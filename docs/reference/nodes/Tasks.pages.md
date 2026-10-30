# Tasks.pages

Use this inside app mount when a task replaces play. For a panel over play,
keep the HUD beside a centered [Sheet](Tasks.sheet.md), with navigation inside.

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

The [HUD](Tasks.hud.md) opener and gamepad use one callback. Close returns to
gameplay; NavBar Back follows the body's `back`. Screen reaches the glass.

The default stack moves and then hides its covered HUD. `parallax = 0` only
removes that movement; it does not keep the HUD visible. Use a sibling Sheet
when the task should preserve that context.

Use `suspendGameplay = true`. While the path is nonempty or
a modal is open, Facet turns off GuiService.TouchControlsEnabled and
`UI.environment().gameplaySuspended` is true. Both return when the last one
closes, before exit motion ends. Derive the game's input from it:
`driving.Enabled = use(inKart) and not use(suspended)` in a `C.watch`.
The clock still runs. Keep saved values and drafts outside pages.

Give each body its task layout: [collection/detail](Tasks.collection-detail.md),
a [form](ScrollView.card.md), or subject and action. Keep commitment with its
terms. Give unrelated tasks separate scroll state.
