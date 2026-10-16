#### Saved colours

<!-- aliases: Saved colours | saved-colours -->

The control keeps no colours of its own. `swatches` stays yours.

- With `onSaveSwatch`, the grid ends with a `Save` cell named "Save colour".
  It proposes the current colour. It is disabled when the list has the colour.
- With `onRemoveSwatch`, an `Edit` button toggles editing. While editing, a
  cell shows `Remove`. A press on a cell proposes its removal. Delete,
  Backspace or ButtonX on the selected cell does the same. Then the selection
  moves to the cell that takes its place.

The root Frame has these attributes: `value`, `text`, `hue`, `saturation`,
`brightness`, `mode`, `format`, `presented`, `placement`, `hexError`,
`columns`, `editing` and `diagnostics`. `ref` receives the root Frame.
