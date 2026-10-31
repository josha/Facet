# Tasks.minimap

Keep spatial information in the HUD and optionally open a larger map.

Use Composition and Region for ranked normal and compact forms. The game
supplies native map artwork. Use a Button and game-owned InputAction for
opening, NavigationStack and Screen for the full map, and ZoomView for pan
and zoom. No `UI.Minimap` constructor is needed.

A reduced Region reveals a Popover by default. Set `reveal = false` when its
forms provide their own full-map action. Keep the opening route in every
form. A passive radar needs no action; an interactive tactical map should keep
its marker actions separate from expansion.

Keep HUD size separate from map zoom and radar range. Keep shared state outside
disposable pages. Mount only active drawings inside stable forms, and release
update subscriptions with Compose cleanup.

Read the [minimap guide](../../guide/minimaps.md) for the composition, drawing
boundary, input and lifetime contracts. **Minimap patterns** in the Lab and the
[standalone example](../../../examples/minimap/default.project.json) use the
same component.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function mapShortcut(app: Facet.App, open: () -> ()): Frame
	local UI = app.UI
	return UI.Composition "MapHUD" {
		UI.Region "MapShortcut" { zone = "topRight", rank = 2, reveal = false,
			UI.Button "OpenMap" { label = "Map", onActivate = function() open() end } } }
end
```

- [Composition.regions](Composition.regions.md)
- [HUD-actions](HUD-actions.md)
- [Tasks.pages](Tasks.pages.md)
- [ZoomView.reference](ZoomView.reference.md)
