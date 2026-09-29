# Facet Foundation Lab

An interactive catalog for every Facet control, with device, input, motion,
text-size and theme previews. The control list uses larger text and taller rows.

## Build and run

From this directory, run `./build.sh`, then open
`build/Facet-FoundationLab.rbxl` in Roblox Studio and start Play.
The build checks catalog coverage and keeps all generated outputs in `build/`.

The build also creates `build/Foundation-Light.rbxm` and
`build/Foundation-Dark.rbxm`. These themes are optional. The Facet runtime
package does not install them; import a standalone model or copy the
`themes/foundation.luau` package when a game chooses to use Foundation.
The standalone entries expose `build(Facet.themes)` for `Facet.app`'s `theme` option.

`lune run tools/check_themes.luau` validates both palettes through the public
theme compiler. `lune run tools/coverage.luau check` checks catalog coverage
against Facet's exported control types.

## Browse controls

The outline groups controls by family and supports search. Select a control
for its playground, options, states, variants and usage examples. Settings
contains the device, input, text, motion and theme previews. Compact layouts
open the control list through Browse and Back.

The previews use Facet's environment options. A simulated text preference
changes Facet's layout decisions; the engine's text preference must still be
set in Studio to test native accessibility rendering.

## Studio driver

`workspace.FacetLabAPI` exposes `pages`, `open`, `section`, `top`, `report`,
`configure`, `sweep`, `probe`, `audit`, `themes`, `theme`, `preview`,
`orientation`, `input`, `distance`, `text`, `motion`, `transparency`, `hover`,
`reset` and `status`. Each entry is a BindableFunction.

Source files live in `src/`, optional Foundation palettes and entry modules
in `themes/`, and local captures in the ignored `evidence/` directory.
The project maps Facet and the shared gallery directly from this repository.
