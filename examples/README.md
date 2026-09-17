# Facet examples

Start with [component authoring](../docs/guide/15-components.md). Maintained
examples use ordinary Luau tables with ordered numeric children. A component
sets up once per mount; getters update individual properties. Callbacks command
the model. The component owns its local state, memos, effects and controls.

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

Borrow durable application state with `ui.read`; keep view-only calculations in
`ui.memo` or property functions. Key collections by stable identity and read the
row's current item getter in handlers. Use `ui.animate` when a calculation needs
an animated number, container `animation` for layout changes, and `transition`
for insertion/removal. Arrays guarantee child order; hash-table order does not.

The gallery also contains diagnostic fixtures. A handle whose `dump`, placement,
scroll or imperative methods are under test needs an explicit lifetime. Shared
reference-app models, scenario drivers and performance measurements may retain
Core signals/scopes because their state must survive screen replacement. These
are integration boundaries, not a requirement to manually own ordinary controls.
Use `Facet.View` for composition and `ui.own` for an external handle needed by a
component. Custom primitive controls must explain the behavior their composite
counterpart cannot express.

For a new feature, update its typed View declaration, mounted scenario and guide
together. Do not copy historical proposal snippets or the "before" half of a
migration summary into new code. Follow [AGENTS.md](../AGENTS.md) and the
[extension playbooks](../docs/extending/new-control.md).
