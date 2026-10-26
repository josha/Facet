# Collections.focus-controls

<!-- aliases: FocusControls | Facet.FocusControls -->

Pass a retained `FocusControls<K>` table as a collection's `focus` option.
Its optional fields are populated during mounting; read them only after mount.
The keys are the collection's keys, not row Instances or indices.

| Field | Contract |
| --- | --- |
| `current` | `ReadOnlyValue<K?>`, the current key or nil; read it through Compose. |
| `focus(key)` | Returns boolean: true for an available, eligible key; false otherwise. |
| `clear()` | Clears the current key; returns nothing. |
| `next()`, `previous()` | Set and return the next/previous key, or nil when empty. Without current focus they choose first/last. They clamp at the ends unless `wrapFocus` is true. |
| `first()`, `last()` | Set and return the first/last eligible key, or nil when empty. |
| `move(direction)` | Accepts `"left"`, `"right"`, `"up"`, `"down"`; sets and returns a directional neighbor. Without current focus it chooses first; without a neighbor it returns the current key. Returns nil when empty; invalid direction errors. |
| `isFocused(key)` | Returns a `ReadOnlyValue<boolean>`, not a boolean snapshot. |

These methods belong to the mounted collection's Compose owner. Stop using
retained methods/readables when it is disposed; do not infer liveness from
fields remaining in the table. `isFocused` creates an owned reactive formula.
Focus candidates exclude disabled items and hidden outline descendants.
Changing focus does not activate a row or commit its selection/business action.
For key/index retention, dragging, and native directional wrapping, see
[focus policies](VirtualList-and-VirtualGrid.ContentProvider.md).
