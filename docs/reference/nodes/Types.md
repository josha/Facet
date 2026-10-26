### Types

<!-- aliases: Types | types -->

Find the type family for the operation, then read the owning contract. This is
a route through the public types, not a separate explanation of every export.

| Family | Contract route |
| --- | --- |
| App, runtime and presenter options/handles | [Mounting](Mounting.md), [Public entry points](Public-entry-points.md) |
| Constructor props, callback values and ownership overloads | [Constructor contract](Constructor-contract.md), [binding shapes](Types.ToggleCellProps.md), then the control's card and props |
| Cells, readables, owners and use callbacks | [Reactive types](Types.reactive.md), [Compose integration](Your-own-Compose.md) |
| Collection keys, rows, drafts and focus controls | [Collections](Collections.md), [CellEditor](CellEditor.reference.md) |
| Action, menu and overlay parts | [Actions and input](Actions-and-input.md), [presented controls](Presented-controls.md), [solver distinctions](Types.Dialog.md) |
| Commands, drag/drop and returned control handles | [Focus and commands](Focus-and-command-scopes.md), [drag/drop](draggable-and-dropTarget.md), [Zoom](ZoomView.reference.md), [Timer](Timer.reference.md), [sequences](Effect-sequences.md) |
| Theme, civil-date, path and formatting values | [Themes](Themes.md), [Civil dates](Civil-dates.md), [Path shapes](Path-shapes.md), [formatting](HUD-formatting.md) |

Use the exported `Facet` types or the public function's signature for nested
option shapes. Returned handles have their owning operation's lifetime; they
are not automatically Instances. Follow the control's reference for methods
and disposal. The exported type names live in the installed Facet module
(`src/init.luau` with filesystem access); a familiar name alone does not prove
its callback meaning or runtime behavior. Native Host props use Roblox types;
the pinned Compose and Roblox modules retain their upstream contracts.

Open:

- [Types.reactive](Types.reactive.md)

- [Types.Dialog](Types.Dialog.md)
- [Types.TileCollection](Types.TileCollection.md)
- [Types.ToggleCellProps](Types.ToggleCellProps.md)
- [Types.nil](Types.nil.md)
