# Collections and actions

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

Players browse collections to recognize, compare and choose objects.  Design for how they tell objects apart, then for the actions they take on the one they choose.

## Choose the representation

Start with how the player recognizes and compares the objects.  Show the attributes that change the decision in a consistent order and with common units.  Keep identity, availability and cost visible before commitment.  Show what a candidate changes: put its values beside the equipped values on the same scale.  Mark the difference with a sign or an arrow as well as color.  When the player cannot afford it, show the shortfall and a route to earn more.  An unavailable object can still help the player plan when its reason and next step are clear.  Never make players remember one object's facts to compare it with the next.

| How players tell objects apart | Control |
| --- | --- |
| By sight: silhouette, color, art | VirtualGrid of Cards with art |
| By description | VirtualList |
| By shared attributes | Table |
| By an actual hierarchy | Outline |
| By authored spatial relationships, such as a skill tree or map | ZoomView over a stable content tree |
| By cell footprint on a bounded inventory board | SpatialGrid |

Item count alone does not decide this.  A skill tree keeps its authored connections visible even though its data is hierarchical.  SpatialGrid has explicit cell footprints and placement rules; it is not a world-map layout.

Keep browsing quieter than the selected object's inspection area.  Match the camera angle, lighting and scale across comparable objects, and frame each silhouette with room for its extremes.  Use a different view when inspection needs more detail than a thumbnail can show.  Show the selected object's name and status beside its action, and distinguish that selection from the equipped object.

Facet:

- Use stable keys, and keep durable row state in the model, outside recycled rows.
- For bounded repeated content without collection interaction, `Compose.keyed` keeps children with their model keys.  Use the virtual controls when rows need collection selection, activation, editing, reordering or windowing.  Facet supplies that policy through native scrolling and selection; do not add another row focus or click system.
- Bound the collection viewport.  Fixed item sizes must fit real content; use the supported measurement option for varying content.

## Separate the intentions

Focus identifies the next input target.  Selection identifies the object under consideration.  Activation opens or operates it.  Equip, Buy or Delete commits a specific consequence.  Every route identifies the same object before commitment.  Moving focus across upgrades can reveal their facts, but it never buys one.

Facet:

- Bind the collection's `selection` when the player must see a persistent chosen set.  Use `onSelectionChange` for selection policy and `onActivate(item, key)` to open detail or enter actions.  When you supply `onSelectionChange`, it owns acceptance: it must call `selection:set(nextMap)` to accept the proposed map.
- With selection enabled, a mouse click selects and a double click activates.  Touch and gamepad activate directly outside collection editing mode.
- `Tasks.collection-detail` derives one inspected object from the model's selected key set.  Supply loaded items and exactly one valid selected key.  A mouse click updates the visible detail.  In compact room, the detail opens from the visible Inspect selection command or by activating the item.  Only the detail action commits.  Keep the selected key outside the page so the chosen object returns when the page opens again.  The caller handles loading, empty, no-match and failed states, and the removal of the chosen object.

## Expose the commands

Put frequent, important actions directly on the selected object.  Use Menu for secondary commands, SplitButton for a meaningful default with alternatives, and RadialMenu for quick spatial choices.  A radial still needs readable names, a clear cancel route and a compact fallback.

Use Card's supported actionable boundary and its `browseTarget` relationship.  Avoid nested click targets that compete, or a second activation system over a collection row.  Set `reveal = "always"` when a frequent action must be discoverable without hover.  That does not wire gamepad entry: use `Card.browseTarget` and the card's `enterActions()` to enter the action group from collection activation without running its primary action.  Back returns to the browse stop.  Hover feedback stays within reserved paint space.

## Edit without losing state

Search, filter and sort the model.  Keep selection, favorites and drafts stable through recycling and reopening.  Show the scope of hidden selections before a bulk action.  Set `selectionFrom` to the authoritative records on each filtered view that must keep hidden selections; otherwise the collection prunes selection to its visible source.  Keep manual reordering separate from a sort that contradicts it.

Show the active filter and the result state, with a direct route to clear it.  Distinguish an empty collection from no matches, loading and a failed request.  Choose a useful initial order for the decision, and make any requested sort and its direction clear.  Avoid moving the focused row while live values change.  When an update removes the selected object, explain the change and move focus to a useful surviving target without acting for the player.

Read a virtual row's `current` in property bindings and `current:peek()` when an action starts.  A stable key can receive a replacement record, so a captured first record can leave its price or eligibility stale.  Requests use the game's current validation and accepted state.

Use CellEditor for a record edit and RowActions for contextual row commands.  Disable `fullSwipe` on consequential edges where an accidental swipe must not commit.  Context commands state whether they affect one row or the selected set.

Drag routes and command routes share validation and accepted results.  Keep rejected drafts, and handle late replies after a row is removed.  See the [manipulation chapter](ADAPTIVE_INTERACTION_AND_DIRECT_MANIPULATION.md) when a collection supports drag.

## Check

Test the first and last visible rows, empty and filtered-empty states, long labels, updates while selected, recycling and focus restoration.  Perform every required action with touch and gamepad as well as pointer.

Read `Tasks.collection-detail`, `VirtualList-and-VirtualGrid.from`, `VirtualList-and-VirtualGrid.selection` and `Card.browseTarget` for the interaction contract.  Read `CellEditor.draft` for retained edits and `Tasks.purchase` for pending and accepted actions.
