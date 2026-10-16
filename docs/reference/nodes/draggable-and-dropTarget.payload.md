# draggable-and-dropTarget.payload

draggable-and-dropTarget.payload option values and behavior.

- `payload`: required. The value every target receives. A function is called
  with the source at pickup.
- `enabled`: a boolean or a readable. While false the source cannot be picked
  up, and it stays selectable and activatable.
- `armOnTap`: a touch tap picks the source up (above). Default `false`.
- `touchPickup`: `"longPress"` (default) leaves early finger movement to the
  scroller. `"immediate"` picks the source up when the finger moves 6 pixels
  after touch-down. A shorter movement remains a tap. The preview keeps the
  original contact point under the finger.
  Collection drag factories use the same touch policy. Facet calls the factory
  on touch-down and keeps its returned spec, payload and selected keys for
  pickup. Immediate movement starts the existing collection transfer session,
  including the recess, preview and insertion slot. An omitted policy keeps
  native long-press pickup.
- `touchDragAxis`: `"XY"` (default), `"X"`, or `"Y"`. With immediate pickup,
  the first movement of 6 pixels chooses the gesture. Movement mainly along
  the selected axis starts a drag and stops the enclosing ScrollingFrame until
  release. Movement mainly across that axis stays with the scroller for the
  whole gesture. Use `"X"` for tiles inside a vertical scrolling list, or
  `"Y"` inside a horizontal scrolling list.
- `statusLabels`: show operation, rejection and pending text. Default `true`.
  Set `false` to hide these labels. Armed input instructions remain visible.
  Collection sources set this in the spec returned by `drag(items, keys)`.

The source also accepts `operations = { "copy", "move", "apply" }`, a
`valid()` predicate, `onStart(payload, mode)`, and `onEnd(accepted, reason)`.
`valid` is checked during the session and before completion. The game owns
payload validation and model changes. Pointer previews preserve the proportional
pickup point under the mouse or touch contact. Collection stacks use the grabbed
cell as the front card and preserve its pickup point and UI scale.
An explicit collection `onActivate` takes priority over pickup on A outside
Edit mode. In Edit mode, A on a row changes selection; the move handle starts
a drag. NavigationStack leaves B to the active drag before handling Back.
