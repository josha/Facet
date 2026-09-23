# Facet examples

Facet supplies UI controls. Compose owns state, composition, collection identity, animation and lifetime. Roblox owns layout, input routing, focus, scrolling, styling and the scene.

Create a runtime with `Facet.Roblox.createRuntime()`, bind `Host = runtime.constructors`, and get controls with `Facet.controls(runtime)`. A component returns native instances. Mount it with `runtime.mount`, and stop the mount before disposing the runtime. Install a theme through `Facet.themes.createStyleSheet` and a native `Host.StyleLink`.

| Task | Example |
|---|---|
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
| Every public control and modifier at once | [Virtual monitors](virtual_monitors/README.md) |


Keep durable state in Compose cells. Read current values in property functions through `use`. Use `Compose.OrderedCollection` for keyed children and the virtual controls for large collections. Use `runtime.spring` and `runtime.tween` for animation. Native `UIListLayout`, `UIGridLayout`, `UIPadding`, `CanvasGroup` and `StyleRule` express the presentation directly.

The gallery keeps ten main demos with nested control, collection and motion pages. `tests/native_gallery.spec.luau` mounts those pages and exercises the games, settings, playlist and standalone consumer. Reference applications and virtual monitors have separate native tests and Studio evidence.
