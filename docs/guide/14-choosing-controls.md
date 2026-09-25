# Choosing controls

Start from the task and the existing screen. If a new action belongs in the
toolbar, navigation or settings of the host screen, put it there. Add a new
surface only when the existing surface cannot express the task clearly.

## Task to control

| Need | Control |
|---|---|
| Do one action | Button. |
| Do a primary action that has alternatives | SplitButton. |
| Select an independent boolean | Toggle. |
| Choose one value from a set | Picker; ComboBox when custom values are valid. |
| Edit text or a number | TextInput. |
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
| Confirm what the player just did | Snackbar. |
| Put Back, a title and tools at the top of a surface | NavBar. |
| Organize named peer destinations | TabView. |
| Navigate a hierarchy | NavigationStack. |
| Step through peer pages | PageView. |
| Select a page of numbered results | Pagination. |
| Show the progress of a workflow | StepIndicator. |
| Compare sortable columns | Table. |
| Show large scrolling data | VirtualList or VirtualGrid. |
| Show a browsable item with a picture and actions | Card, in a VirtualGrid for many items. |
| Add operations for one row | RowActions. |

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

Keep a clear Back path and a cancellation gesture.

For a world object, use `UI.worldAnchor` to project the object. Then bind its
`anchor` to the control. One primary proximity command is
usually a direct prompt. Two or more contextual operations can justify a menu. Do not
add a second input or focus system around it.

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
