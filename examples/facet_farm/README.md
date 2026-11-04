# Facet Farm

A small top-down farming game built only with Facet's public API. Plow grass,
plant seeds, wait for them to grow, and harvest them before they wither. Coins
buy seeds, harvests give experience, and each level unlocks a new crop.

- `model.luau` holds the game rules. It has no UI and takes a clock, so the
  rules are tested without Roblox (`tests/native_facet_farm.verify.luau`).
- `screens.luau` builds the screen from Facet controls: a Grid of plot Buttons,
  crop art drawn with `UI.Path` and `Facet.pathShapes`, ProgressView growth
  timers, Badges, a segmented and a menu Picker, a RadialMenu for gamepad
  tools, a Sheet seed market, an Alert on level up and Toast harvest notes.
- `theme.luau` is the game's theme package and its art colours.

Build from the repository root, then open `examples/places/Facet-Farm.rbxl`
in Studio:

```sh
lute run tools/facet build places
```

To build only this example, run
`rojo build examples/facet_farm/default.project.json -o examples/places/Facet-Farm.rbxl`.
