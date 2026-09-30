# Facet examples

Facet supplies UI controls.

- Compose owns state, composition, collection identity, animation and lifetime.
- Roblox owns layout, input routing, focus, scrolling, styling and the scene.

Every example uses the entry path from
[Getting started](../docs/guide/03-getting-started.md):

1. Make an app with `Facet.app({ theme = package })`. The theme is optional.
2. Get the controls from `app.UI`.
3. Write a component that returns the controls and the layout constructors.
   Mount it with `app.mount`. The app adds the ScreenGui, the StyleSheet and
   the StyleLink.
4. Call `app.dispose()` when the client ends.

The gallery examples get the same controls from their page context. Their
host mounts them with the runtime pieces that `Facet.app` uses.

| Task | Example |
|---|---|
| Interactive control catalog and device previews | [Foundation Lab](foundation-lab/README.md) |
| Small complete client | [Standalone consumer](consumer/src/screen.luau) |
| Editable local state | [Temperature converter](gallery/examples/01_temperature_converter.luau) |
| Shared model and table commands | [Playlist](gallery/examples/02_playlist_table.luau) |
| Server validation and optimistic state | [Settings sync](gallery/examples/03_settings_sync.luau) |
| Bound modal presentation | [Confirmation](gallery/examples/04_confirm_dialog.luau) |
| A game model with mounted views | [Word game](gallery/examples/05_word_game.luau), [crossword](gallery/examples/06_tile_game.luau) |
| Keyed rows and automatic coordinated motion | [Match 3](gallery/examples/07_match3.luau), [automatic motion](gallery/scenarios/component_motion.luau) |
| Motion values and activity indicators | [Progress](gallery/scenarios/progress_ring.luau) |
| Toast reflow, edge and width choices | [Toasts](gallery/scenarios/sponsor_toast.luau) |
| A shared model on a world surface | [Outpost terminal](gallery/examples/outpost_terminal/init.luau) |
| A complete multi-surface showcase | [Virtual monitors](virtual_monitors/README.md) |
| A farming game with crop growth, tools and a seed market | [Facet Farm](facet_farm/README.md) |

The checked-in places are in `examples/places`. Run `tools/build_places.sh`
to rebuild the maintained examples, including
[Virtual Monitors](places/Facet-VirtualMonitors.rbxl) and
[Facet Farm](places/Facet-Farm.rbxl). Facet Flap is part of Virtual Monitors.

## Patterns in the examples

- Keep durable state in Compose cells.
- Read current values in property functions through `use`.
- Use `Compose.keyed` for bounded keyed children. Use the virtual controls for
  large collections.
- Use `runtime.spring` and `runtime.tween` for animation.
- Use native `UIListLayout`, `UIGridLayout`, `UIPadding`, `CanvasGroup` and
  `StyleRule` for the presentation.

## Tests

The showcase has five main demos: Garage, Sipworks, Screen-anchored HUD,
Playlist and Arcade. Arcade contains Word Game, Crossword,
Match 3 and Outpost. The original control, collection and motion fixtures remain available
for the lab and regression tests. `tests/native_gallery.spec.luau` mounts those pages. It exercises the
games, the settings, the playlist and the standalone consumer. Additional
regression fixtures and the virtual monitors have separate native tests and
Studio evidence.

## Showcase

Build `examples/showcase.project.json` with Rojo and open the resulting place
in Studio. Garage is the opening demo. The existing Demos / Settings panel
keeps theme and palette switching, forced device and input previews,
orientation and reduced-motion choices. The navigation button switches roomy
layouts between sidebar and top tabs without resetting the current demo.

| Demo | First thing to try | Source |
|---|---|---|
| Garage | Change the car, paint and wheels, then save and restore a preset | [Garage](gallery/examples/08_garage.luau) |
| Sipworks | Open a recipe, check ingredients, follow a botanical to related blends, then go Back | [Sipworks](gallery/examples/14_sipworks.luau) |
| Screen-anchored HUD | Resize the screen, reveal tucked-away zones, change equipment and open HUD actions | [HUD](gallery/scenarios/hud.luau) |
| Playlist | Sort, rate and reorder tracks | [Playlist](gallery/examples/02_playlist_table.luau) |
| Arcade | Choose Word Game, Crossword, Match 3 or the Outpost power puzzle | [Arcade](gallery/examples/13_arcade.luau) |

Each main demo has a distinct role: Garage is a live 3D configurator with
anchored preset naming and inline saved cars; Sipworks is a searchable recipe
library with animated drill-down and checklists; Playlist demonstrates sortable,
editable, reorderable data; Arcade contains playable games and Outpost's world
terminal and radial actions; the HUD demonstrates screen anchoring and recovery
of commands when space is limited. Sipworks and Arcade retain sidebar/top
navigation. Sipworks uses NavigationStack at both widths and keeps its history
and ingredient checks across layout changes.

The demos use local state. Leaving a demo starts a fresh visit on return.
Outpost lives inside Arcade and retains its screen controls and native
SurfaceGui terminal.

[Showcase artwork](../assets/showcase/README.md) records the generated G-rated
illustrations, their original files and Roblox asset IDs. No purchases or
account sign-in are needed to try the showcase.
