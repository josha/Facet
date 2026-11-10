# Choose an interaction

Find the player's task, then read the named `.card` node. These are starting
choices, not a closed list of supported features. Choose controls for behavior,
not to demonstrate coverage. For an unfamiliar capability use the complete
reference routes below, then read only the relevant contract and exported types.

Before custom UI behavior, use this order: Facet controls/options/helpers,
Compose, native Roblox, then custom code for a confirmed gap. For adaptive forms,
richer navigation, editable collections or spatial/world UI, choose a task in
[richer compositions](#richer-compositions). For the game's
visual system and image-based surfaces, use [game themes](game-themes.md).

| Player task | Starting choice and distinction |
| --- | --- |
| Act immediately | Button; SplitButton when one primary action has alternatives |
| Reveal secondary commands | Menu for a readable list; RadialMenu when direction or a learned spatial arrangement helps selection; keep urgent actions direct |
| Monitor during play | Composition with ranked Region forms; WorldMarker for a world target |
| Learn the current action | Callout at its source or a small guide; StepIndicator for stages; ButtonGuide for bindings |
| Move among peer destinations | TabView; NavigationStack for deeper destinations and return |
| Browse and inspect an object | NavigationSplitView with VirtualGrid or VirtualList; compact form opens detail |
| Compare shared attributes | Table; Outline for an actual hierarchy |
| Inspect a 3D object | Stage with decisive art scale; Image or AsyncImage for flat art |
| Show people | Avatar or AvatarGroup; preserve names when identity matters |
| Pick a value | Picker for a finite choice; ComboBox when searching choices helps |
| Change an independent setting | Toggle; do not use it to navigate |
| Enter text or a number | TextInput or NumberInput; CellEditor inside a table |
| Adjust a range or increment | Slider or Stepper; keep a digital alternative to dragging |
| Pick a color, level, date or rating | Chips with a swatch for a named palette ([game screens](game-screens.md)); ColorPicker for free color; LevelPicker, DateTimePicker or Rating |
| Inspect optional context | Popover near the source; DisclosureGroup in the reading flow |
| Complete a temporary task | Sheet or Dialog; Alert for a brief consequential confirmation |
| Follow a short sequence | PageView; Pagination for actual bounded result pages |
| Navigate spatial information | ZoomView with Path; SpatialGrid for spatial arrangement |
| Show accepted progress | ProgressView or Timer; StepIndicator for task stages |
| Notice a result | Toast for brief feedback; Notice for persistent information; StatusIndicator for state |
| Make a shared choice | Vote; show local intent separately from accepted shared state |
| Show an item and its state | Card, Badge or Chip; RowActions for contextual row commands |
| Arrange a chosen relationship | VStack, HStack, Grid or ZStack; AdaptiveStack for two or three actions that reflow; `HStack { wrap = true }` for chips, swatches and filters |
| Fit distinct complete forms | ViewThatFits; final form must work at minimum room |
| Bound extended content | ScrollView; use virtual collections for large record sets |
| Provide page chrome | Screen and NavBar; chrome does not own navigation history |
| Explain text or input | Text, Label or ShortcutHint |
| Separate or disclose content | Spacer, Divider, CollapsibleView or DisclosureGroup |
| Handle waiting or render failure | Skeleton or ErrorBoundary; retain a useful recovery path |
| Explain a transition | Travel, Flash or Typewriter only when motion serves the task |
| Place UI on a world surface | DiegeticScreen.reference; retain readable input alternatives |

## Complete reference routes

Retrieve these node names with the runtime reference's docs command. The installed
version's reference and exported types define the available API; examples do not
limit it. Search a feature before building a substitute or assuming it is absent.

| Need beyond a control's card | Contract route |
| --- | --- |
| Every control and its option groups | `Controls`, the linked card/reference, then generated `Name.props`; resolve binding modes from the reference |
| Public Facet functions, runtime integration, plugins and binding Compose | `Public-entry-points`, `Mounting`, `Your-own-Compose` |
| Exported types and constructor/reactive contracts | `Types`, `Constructor-contract` |
| Environment, focus, command scopes, adjustment and drag/drop | `Adaptive-environment`, `Focus-and-command-scopes`, `Actions-and-input` |
| Collections, keys, selection, editing and virtualization | `Collections` |
| Theme packages, tokens, icons and custom skins | `Themes.index`, `Themes` |
| Layout, presentation, navigation and native boundaries | `Layout`, `Presented-controls`, `Menus-and-navigation`, `Native-targets-and-boundaries` |
| Media, dates, paths, zoom, transitions and effects | `Media-and-status`, `Civil-dates`, `Path-shapes`, `Zoom-and-travel`, `Custom-transitions`, `Effect-sequences` |
| Remaining contract groups or helpers | `Contracts`, `Recipes` |

For custom interaction, effects or existing native content, use the
[helper decision table](helpers.md). It routes runtime helpers without
making them prerequisites for an ordinary screen.

For each unfamiliar control, resolve value ownership, callback/commit meaning,
focus/Back, sizing, adaptation and disposal before copying it across the game.
Retrieve missing options; do not invent props or infer behavior from a name.

## Richer compositions

Use a capability when it makes the player's task clearer or more direct. Read
only the matching resource. This is not a feature checklist.

| Player need | Design opportunity | Read next |
| --- | --- | --- |
| Keep play visible while offering commands | A compact launcher, contextual disclosure or radial; urgent actions stay direct | [Surfaces: disclosure and commands](advanced-surfaces.md#disclosure-and-commands) |
| Complete a temporary task | A sheet beside the subject or above the lower edge, with clear acceptance and cancellation | [Surfaces: temporary tasks](advanced-surfaces.md#temporary-tasks) |
| Browse, search and return | Navigation chrome follows the information structure; collection and detail can share room | [Surfaces: navigation](advanced-surfaces.md#navigation) |
| Preserve the task in less room | Reflow first; then complete smaller forms with access to omitted detail | [Surfaces: adaptive forms](advanced-surfaces.md#adaptive-forms) |
| Compare records or explore a hierarchy | Aligned attributes or expandable branches instead of repeated cards | [Data: comparison and hierarchy](advanced-data-and-space.md#comparison-and-hierarchy) |
| Act on one record | Discoverable row commands, separate from selection and opening detail | [Data: row actions](advanced-data-and-space.md#row-actions) |
| Edit, reorder, transfer or pack items | Durable drafts, direct manipulation and an equivalent selection path | [Data: editing and placement](advanced-data-and-space.md#editing-and-placement) |
| Inspect an object or explore a map | Large useful subject, deliberate camera or spatial canvas | [Space: inspection and maps](advanced-data-and-space.md#inspection-and-maps) |
| Relate information to the game world | A bounded world marker or an existing interface on a world surface | [Space: world information](advanced-data-and-space.md#world-information) |
| Explain change and recover from failure | Accepted-state feedback and purposeful motion with owned lifetimes | [Feedback](advanced-data-and-space.md#feedback-and-continuity) |
