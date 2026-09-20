# Facet examples

Start with [component authoring](../docs/guide/15-components.md). A maintained
example is a plain Luau function that returns a node built from `app.controls`,
with ordered numeric children and named properties. Setup runs once per mount;
property functions update individual properties. Callbacks command the model.

State is Compose's. `Compose.cell` holds a value, `Compose.formula` derives one,
`Compose.watch` runs a reactive external effect, and `Compose.cleanup` ties an
external subscription to the component's lifetime. A cell created inside the
component dies with it. A shared model's cells are created outside the component
so they survive the screen being replaced, and the same cells are passed to each
presentation of that model. See the [runtime contract](../src/core/README.md) for
ownership, containment and settling.

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

Read durable application state through `use` in a property function. Keep
view-only calculations in `Compose.formula` or in the property function itself.
Key collections by stable identity and read the row's current item readable in
handlers. Use `app.runtime.spring` / `.tween` when a calculation needs an
animated number, container `animation` for layout changes, and `transition` for
insertion and removal. Arrays guarantee child order; hash-table order does not.

The gallery also contains diagnostic fixtures. A composite control whose `api` or
`dump` is under test receives them through `ref`, which is called once while the
control is built with a frozen `{ api, dump }`. Shared reference-app models,
scenario drivers and performance measurements keep their Compose cells and owners
outside any one screen, because their state must survive screen replacement.
Those are integration boundaries, not a requirement to own ordinary controls by
hand. A custom primitive must explain the behavior its composite counterpart
cannot express.

For a new feature, update its reference entry, its mounted scenario and the guide
together. Follow [AGENTS.md](../AGENTS.md) and the
[extension playbooks](../docs/extending/new-control.md).
