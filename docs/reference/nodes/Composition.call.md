# Composition.call

Put presented Sheet and Dialog controls beside Composition in Screen. A
Region measures HUD content and does not define a modal viewport.

`UI.Composition(spec) -> Frame` places ranked regions at the edges and
corners of the screen, as a game HUD does. `UI.Region(spec) -> Frame` is one
of those regions. Put the composition in a ScreenGui, or in any Frame that
covers the area to use. It fills its parent. The ScreenGui `ScreenInsets`
keeps it inside the device safe area. When the composition reaches into the
`GuiService.TopbarInset` band, it adds the covered height to its top padding,
as `Screen` does.

```luau
local hidden = Compose.cell(1)
return UI.Composition "Hud" {
	UI.Region "Score" { zone = "top", rank = 1, UI.Text { text = "12 : 9" } },
	UI.Region "Tasks" {
		zone = "left",
		rank = 3,
		mayDrop = true,
		form = hidden,
		UI.Text { text = "Win a round, land 25 hits" },
		UI.Button { label = "Tasks 1/2" },
	},
	UI.Region "Objective" { zone = "topbar", rank = 2, UI.Text { text = "Round 3" } },
}
```

Composition options:

- `gap`: the space between the regions of one zone, between the three lanes
  and between the zones of one lane. The default is `s`.
- `padding`: the space inside the edges. The default is `s`.
- `topbar`: a boolean or a readable. The default is `true`.
  See [Composition.adaptation](Composition.adaptation.md) for top-bar behavior.
- The children are `UI.Region` nodes. A `UI.fill()` child is also allowed, so
  the composition can take the free height of a stack.

See [Composition.regions](Composition.regions.md) for region options.
