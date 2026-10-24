# Collections and actions

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

## Choose the representation

Start with how the player recognizes and compares the objects. Show the
attributes that change the decision, in a consistent order and with common
units. Keep identity, availability and cost visible before commitment.
An unavailable object may still help the player plan if its reason and next
step are clear. Do not make them remember a previous object's facts to compare
it with the current one.

Use VirtualGrid for visual recognition, VirtualList for descriptions, Table
for shared attributes and Outline for an actual hierarchy. Item count alone
does not decide whether selection, reordering and collection focus are needed.
Use stable keys and keep durable row state in the model, outside recycled rows.

For bounded repeated content without collection interaction, Compose.keyed
keeps children associated with their model keys. Use the virtual controls when
rows need collection selection, activation, editing, reordering or windowing.
Facet supplies that interaction policy through native scrolling and selection;
do not add another row focus or click system.

Bound the collection viewport. Fixed item sizes must fit real content; use
the supported measurement option for varying content. Artwork should identify
the object, not decorate a repeated text button. Keep useful identity and
comparison visible in compact forms.

Keep browsing quieter than the selected object's inspection area. Match camera
angle, lighting and scale across comparable objects; frame each silhouette with
room for its extremes. Use a different view when inspection needs detail that
the collection thumbnail cannot show. A decorative image repeated across every
item does not establish identity. Show the selected object's name and status
beside its action, and distinguish that selection from the equipped object.

A spatial map or skill tree needs its authored relationships to remain visible,
not an Outline merely because its data is hierarchical. ZoomView can pan and
zoom a stable content tree. SpatialGrid is for a bounded inventory board with
explicit cell footprints and placement rules; it is not a world-map layout.

## Separate intentions

Focus identifies the next input target. Selection identifies an object under
consideration. Activation opens or operates it. Equip, Buy or Delete commits
a specific consequence. Do not treat these as interchangeable.

Bind collection `selection` when the player must see a persistent chosen set.
Use `onSelectionChange` for selection policy and `onActivate(item, key)` for
opening detail or entering actions. When supplied, `onSelectionChange` owns
accepting the proposed map with `selection:set(nextMap)`. With selection
enabled, a mouse click selects and a double click activates; touch and gamepad
activate directly outside collection editing mode.
Make every route identify the same object before commitment. For example,
moving focus across upgrades can reveal facts without buying an upgrade.

The `Tasks.collection-detail` recipe uses the model's selected key set to
derive one inspected object. Supply loaded items and exactly one valid selected
key. A mouse click updates the visible detail. In compact room, the visible
Inspect selection command opens it; activation provides the other input routes.
Only the detail action commits. Keep the selected key outside the page so the
chosen object returns when the page opens again. The caller handles loading,
empty, no-match and failed-request states, and removal of the chosen object.

Expose frequent important actions directly. Use Menu for secondary commands,
SplitButton for a meaningful default with alternatives, and RadialMenu for
quick spatial choices. A radial still needs readable names, a clear cancel
route and its compact fallback.

Use Card's supported actionable boundary and browseTarget relationship.
Avoid nested competing click targets or a second activation system over a
collection row. Set `reveal = "always"` when a frequent action must be
discoverable without hover. This does not wire gamepad entry: use
`Card.browseTarget` and `controls.enterActions()` to enter the action group
from collection activation without running its primary action. Back returns
to the browse stop. Hover feedback must stay within reserved paint space.

## Edit without losing state

Search, filter and sort the model. Preserve stable selection, favorites and
drafts through recycling and reopening. Show hidden-selection scope for bulk
actions. Set `selectionFrom` to the authoritative records on each filtered
view that must keep hidden selections; otherwise the collection prunes
selection against its visible source. Keep manual reorder separate from a
contradictory sort.

Show the active filter and result state, with a direct route to clear it.
Distinguish an empty collection from no matches, loading and a failed request.
Choose a useful initial order for the decision. Avoid moving the focused row
continually as live values change; make any requested sort and its direction
clear. If an update removes the selected object, explain the change and move
focus to a useful surviving target without acting on its behalf.

Read a virtual row's `current` in property bindings and `current:peek()` when
an action starts. A stable key can receive a replacement record. Capturing
the first record can leave its price or eligibility stale. Requests must use
the game's current validation and accepted state.

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

Read `Tasks.collection-detail`, `VirtualList-and-VirtualGrid.from`,
`VirtualList-and-VirtualGrid.selection` and `Card.browseTarget` for the
interaction contract. Read `CellEditor.draft` for retained edits and
`Tasks.purchase` for pending and accepted actions.
