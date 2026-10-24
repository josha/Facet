# Tasks.pages

Open a destination from gameplay, with a readable surface, Close and return focus.

Call inside the app mount. Supply the HUD and body as components.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function pages(app: Facet.App, title: string,
	hud: (() -> ()) -> GuiObject, body: (Facet.Cell<boolean>) -> GuiObject,
	suspendGameplay: () -> (() -> ())): Frame
	local C, UI = Facet.Compose, app.UI
	local path = C.cell({} :: { Facet.NavigationEntry<string> })
	local back = C.cell(false)
	return UI.NavigationStack {
		path = path, chrome = "hidden",
		root = { content = function()
			return hud(function() path:set({ { id = "task" } }) end)
		end },
		destinations = { task = { initialFocus = "Body", content = function()
			C.cleanup(suspendGameplay())
			return UI.VStack "Surface" { surface = "surface", width = "fill", height = "fill",
				UI.Screen "Task" {
					UI.NavBar { title = title, onBack = back, trailing = UI.Button { label = "Close",
						appearance = "utility", onActivate = function() path:set({}) end } },
					UI.VStack "Body" { width = "fill", height = "fill", UI.fill(), body(back) },
				},
			}
		end } },
	}
end
```

Use [Composition](Tasks.hud.md) for the HUD. Its visible opener and gamepad
command call the same callback. NavigationStack owns motion, Back and focus;
focus starts in the body, not on Close. Close returns to gameplay; NavBar Back
follows the body's `back`.

suspendGameplay disables the game's InputContext and custom touch commands,
and sets GuiService.TouchControlsEnabled to false. Its returned function
restores their previous values. This changes input, not the game clock. Keep
saved values, filters and selection in the model outside the page.

Use [collection/detail](Tasks.collection-detail.md) or a
[scrolling form](ScrollView.card.md) as the body. Keep commitment outside long
scrolling content. Test compact fit and input return. Use [Sheet](Tasks.sheet.md) for a bounded
interruption; [TabView](Tasks.tabs.md) switches peer destinations.
