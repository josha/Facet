# Choosing controls

Start from the task and the existing screen. If a new action belongs in the
toolbar, navigation or settings of the host screen, put it there. Add a new
surface only when the existing surface cannot express the task clearly.

Choose the control that owns the required interaction before composing its
visual parts. Item count decides whether to window content; it does not decide
whether selection, reordering or collection focus is needed. This applies to
game screens and Studio plugin interfaces.

## Task to control

| Need | Control |
|---|---|
| Do one action | Button. |
| Do a primary action that has alternatives | SplitButton. |
| Select an independent boolean | Toggle. |
| Choose one value from a set | Picker; ComboBox when custom values are valid. |
| Edit text or a number | TextInput. |
| Filter a collection | TextInput with `presentation = "search"`; it includes a clear action. |
| Check off completed items | Toggle with `presentation = "checkbox"`. |
| Adjust a bounded value | Slider; Stepper for exact increments. |
| Select a rating or a level | Rating or LevelPicker. |
| Vote up or down on an item | Vote. |
| Show or remove compact selections | Chip. |
| Show secondary document content | DisclosureGroup. |
| Expand a compact preview | CollapsibleView. |
| Ask for a brief confirmation | Alert. |
| Ask for a decision that needs a body, a picture or more than two actions | Dialog. |
| Do a substantial temporary task | Sheet. |
| Show short content or a small task for one control | Popover. |
| Teach a contextual action | Callout anchored to the action. |
| Keep a status in the page until the state changes | Notice. |
| Confirm what the player just did | Toast, with an action for Undo. |
| Put Back, a title and tools at the top of a surface | NavBar. |
| Organize named peer destinations | TabView. |
| Navigate a hierarchy of pages with Back | NavigationStack. |
| Step through peer pages | PageView. |
| Select a page of numbered results | Pagination. |
| Show the progress of a workflow | StepIndicator. |
| Compare sortable columns | Table. |
| Select or reorder data rows, even a short list | VirtualList; VirtualGrid for tiles, Table for columns. |
| Edit a layer outline | VirtualList for visible rows; the model owns hierarchy and valid moves. |
| Move user-ordered items | The collection's `reorderable` and `onReorder` options. |
| Show large scrolling data | VirtualList or VirtualGrid. |
| Show a browsable item with a picture and actions | Card, in a VirtualGrid for many items. |
| Add operations for one row | RowActions. |
| Drag data between separate controls or targets | draggable and dropTarget; use collection reordering for row order. |

## Compose in the existing screen

- Use native stacks and grids: `Host.UIListLayout`, `Host.UIGridLayout`, flex
  items, constraints and native scrolling.
- Use Facet controls for behavior.
- Customize the semantic themes and the skin slots before you make new control
  variants.
- Add a reusable missing behavior to Facet. Keep game-specific rules and content
  in the game.

Use numeric children and native properties. Use `Compose.show`,
`Compose.keyed`, `Compose.LayerStack` and `Compose.portal` directly for
structure. You do not need a custom layout container only to name a vertical
group.

## Two-level navigation

Use `TabView` with `style = "sidebarAdaptable"` for top-level peer
destinations. Inside one destination, ordinary page tabs can select local
views. A label such as "game" or "gallery" does not change the navigation role.
Use NavigationStack for drill-down. Do not encode a path as a set of unrelated
tabs.

Leave the placement automatic at both levels. Build the inner TabView anywhere
under an outer page: in its content factory, or later in a `Compose.show` or
`Compose.keyed` branch of that page. The inner TabView is then nested and uses a
top band.

If a detail pane has child pages, put a NavigationStack in that pane.
Use the same path in wide and compact layouts.
Let NavigationStack control the page history, motion, and Back command.
Do not replace it with keyed content and a separate Back button.
Do not show a disabled Back command on the root page.

## Small tasks and secondary content

Keep related information near its control.
Use DisclosureGroup for an ingredient checklist or a list of saved cars.
Use Popover for a short form that names a saved item.
Connect the Popover to the Save button.
Use CollapsibleView to expand a compact power display.
Use Sheet for a larger temporary task, such as equipment management.
Use NavigationStack to move between related recipes or field guide pages.

For a search field, set `presentation = "search"`.
This presentation supplies the Clear action.
Enter filter text. Then press Clear and check that all items return.
Use checkbox Toggles for a checklist.
Use button Toggles for saved items.
Use Picker to select one vehicle or one nectar type.

## Radial actions

Choose a RadialMenu when all these conditions are true:

- the action set is contextual,
- the action set is small enough to scan spatially,
- a stable anchor makes the relationship clear.

Use a linear Menu when the labels are long or when the action hierarchy is the
main information. For frequently used global actions, a permanent toolbar is
better.

Choose the radial preset, distribution and content-fit options for the
available rectangle. The task decides the nested navigation and the completion
policy:

- close after a final command,
- stay open for repeated toggles,
- return to the parent or the root to continue in a category.

For a continuous action ring over a busy page, use these options.
Supply the game functions `inspect` and `openInventory`:

```luau
UI.RadialMenu {
    label = "Quick actions",
    preset = "donut",
    contentFit = "radial",
    ringWidth = "wide",
    center = "empty",
    scrim = "dark",
    items = {
        { id = "inspect", label = "Inspect", onSelect = inspect },
        { id = "inventory", label = "Inventory", onSelect = openInventory },
    },
}
```

`contentFit = "radial"` keeps the full sectors of the ring.
The default value, `"both"`, can decrease each sector to a separate wedge.
`ringWidth = "wide"` gives text labels more space near the screen edges.
`center = "empty"` puts Close on the ring.
The dark scrim separates the labels from the page below the ring.
Check the open menu at compact and wide sizes.
Include long labels and disabled actions in the check.
If the ring cannot fit, use its linear list presentation.

Keep a clear Back path and a cancellation gesture.

For a world object, use `UI.worldAnchor` to project the object. Then bind its
`anchor` to the control. One primary proximity command is
usually a direct prompt. Two or more contextual operations can justify a menu. Do not
add a second input or focus system around it.

## Interactive collections

Use VirtualList for rows, VirtualGrid for tiles, and Table when columns help
compare or edit fields. These controls are appropriate for short collections
when the task needs row selection, reordering or collection focus. A layer pane
with five items still needs the same interaction contract as one with 500.

A Button inside `render` is valid row content. The collection owns the row's
identity, selection, focus and reorder gesture. A stack of independent Buttons
does not supply those behaviors. Use native layout and `Compose.keyed` for
repeated content that does not need a collection interaction contract, such as
toolbar commands or independent form sections. ScrollView can scroll a document
or form; it does not add row selection or reordering.

For a user-ordered collection:

- Give items stable keys and keep selection and durable edits in the model.
- Set `reorderable = true`. In `onReorder(keys, insertionSlot)`, validate the
  move and update the model. The slot is zero-based among the rows left after
  removing the moved keys. The control proposes a move; it does not change the
  caller's array. Use `movable(item)` to exclude fixed rows.
- Preserve pointer dragging, touch pickup, and the keyboard/gamepad move paths.
  Supply an `editing` cell and an Edit control for a VirtualList when its
  non-pointer edit handles are needed. Read the full
  [editable collection contract](../reference/api.md#editable-collections).
- Do not replace the gesture with a pair of Up/Down buttons merely because the
  list is short or the rows are custom. Add such commands only for a requested
  or task-specific interaction; they can use the same model operation.

A layer outline is a hierarchy of items, not a history of pages. Render its
visible rows with stable IDs and depth in VirtualList. The model owns expansion,
parent/child relationships, and valid destinations. Translate a flat insertion
slot into a domain move; do not treat it as automatic tree reparenting. Use
NavigationStack when opening child pages with Back. Use `UI.draggable` and
`UI.dropTarget` when the task needs transfers between separate targets rather
than order changes within a collection.

## Collection size and lifetime

Use windowing for large or unbounded lists. VirtualList and VirtualGrid give
range selection and anchoring to Compose `OrderedCollection`. The native
ScrollingFrame owns the viewport. Stable keys identify data independently of
order. When row data can change, read `current` inside bound properties.

Keep durable edits and selections outside the row. When a row leaves the
window, Compose can dispose it and reuse its native host. Use `mode = "all"`
only when the collection is bounded and a concrete requirement needs every row
mounted.

After a sort, native anchor preservation can keep the same item visible. That
is the collection contract. Do not calculate a second, independent window. Do
not force a conflicting scroll offset.

## Accessibility and input

Design with the actual available size, the preferred text size and the input
facts. Keep labels clear. Keep actions reachable without a pointer. Let the
controls own native selection containment, adjustment and cancellation. In the
target application, exercise long copy, keyboard, gamepad, touch and reduced
motion.

World-fixed and billboard surfaces also contain flat UI. Facet does not supply
3D layout or ray, hand or gaze input.
