# Collections and actions

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

## Choose the representation

Use VirtualGrid for visual recognition, VirtualList for descriptions, Table
for shared attributes and Outline for an actual hierarchy. Item count alone
does not decide whether selection, reordering and collection focus are needed.
Use stable keys and keep durable row state in the model, outside recycled rows.

Bound the collection viewport. Fixed item sizes must fit real content; use
the supported measurement option for varying content. Artwork should identify
the object, not decorate a repeated text button. Keep useful identity and
comparison visible in compact forms.

A growing spatial map or skill tree needs spatial relationships, not an
Outline merely because its data is hierarchical. Use SpatialGrid or ZoomView
where those relationships matter.

## Separate intentions

Focus identifies the next input target. Selection identifies an object under
consideration. Activation opens or operates it. Equip, Buy or Delete commits
a specific consequence. Do not treat these as interchangeable.

Expose frequent important actions directly. Use Menu for secondary commands,
SplitButton for a meaningful default with alternatives, and RadialMenu for
quick spatial choices. A radial still needs readable names, a clear cancel
route and its compact fallback.

Use Card's supported actionable boundary and browseTarget relationship.
Avoid nested competing click targets or a second activation system over a
collection row. Hover feedback must stay within reserved paint space.

## Edit without losing state

Search, filter and sort the model. Preserve stable selection, favorites and
drafts through recycling and reopening. Show hidden-selection scope for bulk
actions. Keep manual reorder separate from a contradictory sort.

Use CellEditor for a record edit and RowActions for contextual row commands.
Full-swipe actions need particular care: disable fullSwipe on consequential
edges when an accidental swipe must not commit. Context commands must identify
whether they affect one row or the selected set.

Drag and command routes share validation and accepted results. Preserve
rejected drafts and handle late replies after row removal. See
[manipulation](ADAPTIVE_INTERACTION_AND_DIRECT_MANIPULATION.md) only when needed.

Test the first and last visible rows, empty and filtered-empty states, long
labels, updates while selected, recycling, focus restoration and every required
action using touch and gamepad as well as pointer.
