# Choose an interaction

Find the player's task, then read the named `.card` node. These are starting
choices, not a closed list of supported features. Choose controls for behavior,
not to demonstrate coverage. For an unfamiliar capability use the complete
reference routes below, then read only the relevant contract and exported types.

Before custom UI behavior, use this order: Facet controls/options/helpers,
Compose, native Roblox, then custom code for a confirmed gap. For adaptive forms,
richer navigation, editable collections or spatial/world UI, choose a task in
[advanced compositions](advanced-compositions.md). For the game's
visual system and image-based surfaces, use [game themes](game-themes.md).

| Player task | Starting choice and distinction |
| --- | --- |
| Act immediately | Button; SplitButton when one primary action has alternatives |
| Reveal secondary commands | Menu for a readable list; RadialMenu for a short spatial set; keep urgent actions direct |
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
| Pick a color, level, date or rating | ColorPicker, LevelPicker, DateTimePicker or Rating |
| Inspect optional context | Popover near the source; DisclosureGroup in the reading flow |
| Complete a temporary task | Sheet or Dialog; Alert for a brief consequential confirmation |
| Follow a short sequence | PageView; Pagination for actual bounded result pages |
| Navigate spatial information | ZoomView with Path; SpatialGrid for spatial arrangement |
| Show accepted progress | ProgressView or Timer; StepIndicator for task stages |
| Notice a result | Toast for brief feedback; Notice for persistent information; StatusIndicator for state |
| Make a shared choice | Vote; show local intent separately from accepted shared state |
| Show an item and its state | Card, Badge or Chip; RowActions for contextual row commands |
| Arrange a chosen relationship | VStack, HStack, Grid or ZStack; AdaptiveStack for reflow |
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
