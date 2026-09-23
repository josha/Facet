# Choosing controls

Start from the task and existing screen. Put a new action in the host toolbar, navigation or settings composition when it belongs there. Add another surface only when the existing one cannot express the task clearly.

## Task to control

| Need | Choice |
|---|---|
| Perform one action | Button. |
| Primary action with alternatives | SplitButton. |
| Select an independent boolean | Toggle. |
| Choose one value from a set | Picker; ComboBox when custom values are valid. |
| Edit text or a number | TextInput. |
| Adjust a bounded value | Slider; Stepper for exact increments. |
| Select a rating or level | Rating or LevelPicker. |
| Show/remove compact selections | Chip. |
| Reveal secondary document content | DisclosureGroup. |
| Expand a compact preview | CollapsibleView. |
| Ask for a brief confirmation | Alert. |
| Perform a substantial temporary task | Sheet. |
| Teach a contextual action | Callout anchored to the action. |
| Organize named peer destinations | TabView. |
| Navigate a hierarchy | NavigationStack. |
| Step through peer pages | PageView. |
| Compare sortable columns | Table. |
| Show large scrolling data | VirtualList or VirtualGrid. |
| Add row-specific operations | RowActions. |

## Compose in the existing screen

Use native stacks/grids with `Host.UIListLayout`, `Host.UIGridLayout`, flex items, constraints and native scrolling. Reuse Facet controls for behavior. Customize semantic themes and skin slots before making new control variants. Add a reusable missing behavior to Facet; keep game-specific rules and content in the game.

Use numeric children and native properties. Use Compose.show/keyed/LayerStack/portal directly for structure. A custom layout container is not needed merely to name a vertical group.

## Two-level navigation

Use `TabView` with `style = "sidebarAdaptable"` for top-level peer destinations. Within one destination, ordinary page tabs can select local views. A game or gallery label does not change the navigation role. Use NavigationStack for drill-down instead of encoding a path as a set of unrelated tabs.

## Radial actions

Choose a RadialMenu when the action set is contextual, small enough to scan spatially, and a stable anchor makes the relationship clear. Use a linear Menu when labels are long or the action hierarchy is the main information. A permanent toolbar is better for frequently used global actions.

Choose the radial preset, distribution and content-fit options for the available rectangle. Nested navigation and completion policy belong to the task: close after a final command, remain open for repeated toggles, or return to the parent/root when continuing a category. Keep a clear Back path and cancellation gesture.

For a world object, project the object using the engine camera, then bind the resulting screen anchor to the control. One primary proximity command is usually a direct prompt; multiple contextual operations can justify a menu. Do not introduce a second input/focus system around it.

## Collection size and lifetime

Use windowing for large or unbounded lists. VirtualList/Grid delegate range selection and anchoring to Compose OrderedCollection, and native ScrollingFrame owns the viewport. Stable keys identify data independently of order. Read `current` inside bound properties when row data can change.

Keep durable edits and selections outside the row. A row leaving the window may be disposed and its native host reused. Use `mode = "all"` only when the collection is bounded and keeping every row mounted serves a concrete requirement.

Native anchor preservation can keep the same item visible after a sort. That is the collection contract; do not calculate a second independent window or force a conflicting scroll offset.

## Accessibility and input

Design with actual available size, preferred text size and input facts. Keep labels understandable and actions reachable without a pointer. Let controls own native selection containment, adjustment and cancellation. Exercise long copy, keyboard, gamepad, touch and reduced motion in the target application.

World-fixed and billboard surfaces still contain flat UI. Facet does not supply 3D layout or ray/hand/gaze input.
