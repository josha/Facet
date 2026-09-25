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

## Patterns in the examples

- Keep durable state in Compose cells.
- Read current values in property functions through `use`.
- Use `Compose.keyed` for bounded keyed children. Use the virtual controls for
  large collections.
- Use `runtime.spring` and `runtime.tween` for animation.
- Use native `UIListLayout`, `UIGridLayout`, `UIPadding`, `CanvasGroup` and
  `StyleRule` for the presentation.

## Tests

The gallery has ten main demos with nested control, collection and motion
pages. `tests/native_gallery.spec.luau` mounts those pages. It exercises the
games, the settings, the playlist and the standalone consumer. The reference
applications and the virtual monitors have separate native tests and Studio
evidence.
