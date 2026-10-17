# Facet control and capability index

Part of [Designing game interfaces with Facet](../GAME_UI_DESIGN_GUIDE.md). Start with the player task and the general/game design principles in the guide, then follow a control to its purpose, alternatives, and design-significant configuration choices. Shared collection behavior is covered in [Collection editing and bulk actions](COLLECTIONS_AND_ACTIONS.md#collection-editing-and-bulk-actions); do not read an individual collection entry in isolation when designing editing.

This index covers all 71 public controls in the inspected Facet 0.12.0 reference. Interaction capabilities that are not controls follow the control table. It is a design map, not a replacement for exact API signatures or an evaluation of the finished experience.

| Control | Use it to… |
| --- | --- |
| [AdaptiveStack](LAYOUT_AND_NAVIGATION.md#adaptivestack) | Turn the same local content between row and column. |
| [Alert](SURFACES_INFORMATION_AND_FEEDBACK.md#alert) | Resolve a short consequential decision. |
| [AsyncImage](SURFACES_INFORMATION_AND_FEEDBACK.md#image-and-asyncimage) | Show visual content with deliberate loading and failure states. |
| [Avatar](SURFACES_INFORMATION_AND_FEEDBACK.md#avatar-and-avatargroup) | Identify a player and, when relevant, their presence. |
| [AvatarGroup](SURFACES_INFORMATION_AND_FEEDBACK.md#avatar-and-avatargroup) | Summarize a group while retaining access to omitted members. |
| [Badge](SURFACES_INFORMATION_AND_FEEDBACK.md#badge-and-statusindicator) | Annotate an object with a compact label or count. |
| [Button](COLLECTIONS_AND_ACTIONS.md#button) | Perform a named action. |
| [Callout](SURFACES_INFORMATION_AND_FEEDBACK.md#callout) | Teach a specific feature at a useful moment. |
| [Card](COLLECTIONS_AND_ACTIONS.md#card) | Present one coherent browsing object and its actions. |
| [CellEditor](COLLECTIONS_AND_ACTIONS.md#celleditor) | Edit one short value in collection context. |
| [Chip](CHOICES_AND_INPUT.md#chip) | Represent a toggled or removable compact concept. |
| [CollapsibleView](SURFACES_INFORMATION_AND_FEEDBACK.md#collapsibleview) | Expand a compact summary into a temporary overlaid panel. |
| [ColorPicker](CHOICES_AND_INPUT.md#colorpicker) | Explore or precisely choose a color. |
| [ComboBox](CHOICES_AND_INPUT.md#combobox) | Find a value by typing, optionally accepting custom input. |
| [Composition](LAYOUT_AND_NAVIGATION.md#composition-and-region) | Coordinate HUD groups competing for the same room. |
| [DateTimePicker](CHOICES_AND_INPUT.md#datetimepicker) | Choose a calendar date, time, or range. |
| [Dialog](SURFACES_INFORMATION_AND_FEEDBACK.md#dialog) | Present a custom bounded modal interaction. |
| [DisclosureGroup](SURFACES_INFORMATION_AND_FEEDBACK.md#disclosuregroup) | Expand optional detail within the reading flow. |
| [Divider](LAYOUT_AND_NAVIGATION.md#spacer-and-divider) | Mark a meaningful boundary within a surface. |
| [ErrorBoundary](SURFACES_INFORMATION_AND_FEEDBACK.md#skeleton-and-errorboundary) | Keep a rendering failure local and recoverable. |
| [Flash](SURFACES_INFORMATION_AND_FEEDBACK.md#flash-and-travel) | Briefly emphasize a meaningful change. |
| [Grid](LAYOUT_AND_NAVIGATION.md#grid) | Align a small static arrangement in two dimensions. |
| [HStack](LAYOUT_AND_NAVIGATION.md#vstack-and-hstack) | Arrange one closely related horizontal unit. |
| [Image](SURFACES_INFORMATION_AND_FEEDBACK.md#image-and-asyncimage) | Present an available visual with intentional framing. |
| [Label](SURFACES_INFORMATION_AND_FEEDBACK.md#label-and-shortcuthint) | Name a concept with text and/or an icon. |
| [LevelPicker](CHOICES_AND_INPUT.md#levelpicker) | Choose or display a short discrete intensity scale. |
| [Menu](COLLECTIONS_AND_ACTIONS.md#menu) | Expose a short set of contextual or secondary commands. |
| [NavBar](LAYOUT_AND_NAVIGATION.md#navbar) | Organize location, Back, and a few contextual actions. |
| [NavigationSplitView](LAYOUT_AND_NAVIGATION.md#navigationsplitview) | Show a collection and its selected detail, adapting to one pane. |
| [NavigationStack](LAYOUT_AND_NAVIGATION.md#navigationstack) | Navigate a meaningful path from overview to deeper detail. |
| [Notice](SURFACES_INFORMATION_AND_FEEDBACK.md#notice) | Keep an ongoing condition and recovery available. |
| [NumberInput](CHOICES_AND_INPUT.md#numberinput) | Enter an exact numeric value. |
| [Outline](COLLECTIONS_AND_ACTIONS.md#outline) | Explore and manage a real record hierarchy. |
| [PageView](LAYOUT_AND_NAVIGATION.md#pageview) | Inspect a short sequence one page at a time. |
| [Pagination](LAYOUT_AND_NAVIGATION.md#pagination) | Navigate meaningfully bounded pages of results. |
| [Path](LAYOUT_AND_NAVIGATION.md#zoomview-and-path) | Draw meaningful spatial connections or routes. |
| [Picker](CHOICES_AND_INPUT.md#picker) | Choose one or several values from a defined set. |
| [Popover](SURFACES_INFORMATION_AND_FEEDBACK.md#popover) | Explain or adjust something in relation to its source. |
| [ProgressView](SURFACES_INFORMATION_AND_FEEDBACK.md#progressview) | Show a known amount of progress or honest indeterminate work. |
| [RadialMenu](COLLECTIONS_AND_ACTIONS.md#radialmenu) | Offer a small stable set through directional recognition. |
| [Rating](CHOICES_AND_INPUT.md#rating) | Express evaluation on an ordered rating scale. |
| [Region](LAYOUT_AND_NAVIGATION.md#composition-and-region) | Give one HUD group a home, priority, and compact alternatives. |
| [RowActions](COLLECTIONS_AND_ACTIONS.md#rowactions) | Expose a few verbs belonging to one collection object. |
| [Screen](LAYOUT_AND_NAVIGATION.md#screen) | Establish a screen content root and safe-room policy. |
| [ScrollView](LAYOUT_AND_NAVIGATION.md#scrollview) | Read or edit bounded content longer than its viewport. |
| [Sheet](SURFACES_INFORMATION_AND_FEEDBACK.md#sheet) | Perform a temporary task with a clear return to its origin. |
| [ShortcutHint](SURFACES_INFORMATION_AND_FEEDBACK.md#label-and-shortcuthint) | Show a truthful input prompt for an action. |
| [Skeleton](SURFACES_INFORMATION_AND_FEEDBACK.md#skeleton-and-errorboundary) | Reserve recognizable structure while content loads. |
| [Slider](CHOICES_AND_INPUT.md#slider) | Adjust relative magnitude, continuous feel, or an interval. |
| [Spacer](LAYOUT_AND_NAVIGATION.md#spacer-and-divider) | Distribute spare room between meaningful groups. |
| [SplitButton](COLLECTIONS_AND_ACTIONS.md#splitbutton) | Expose a primary action with related alternatives. |
| [Stage](SURFACES_INFORMATION_AND_FEEDBACK.md#stage) | Inspect a 3D object when its actual form matters. |
| [StatusIndicator](SURFACES_INFORMATION_AND_FEEDBACK.md#badge-and-statusindicator) | Attach a small status or count signal to an object. |
| [StepIndicator](LAYOUT_AND_NAVIGATION.md#stepindicator) | Explain position in a named multistage task. |
| [Stepper](CHOICES_AND_INPUT.md#stepper) | Adjust a small discrete quantity in useful increments. |
| [TabView](LAYOUT_AND_NAVIGATION.md#tabview) | Switch between stable peer destinations. |
| [Table](COLLECTIONS_AND_ACTIONS.md#table) | Compare shared attributes across records. |
| [Text](SURFACES_INFORMATION_AND_FEEDBACK.md#text) | Communicate readable information with a deliberate hierarchy. |
| [TextInput](CHOICES_AND_INPUT.md#textinput) | Compose or search with free text. |
| [Timer](SURFACES_INFORMATION_AND_FEEDBACK.md#timer) | Communicate elapsed time or a deadline. |
| [Toast](SURFACES_INFORMATION_AND_FEEDBACK.md#toast) | Briefly acknowledge an event that can safely expire. |
| [Toggle](CHOICES_AND_INPUT.md#toggle) | Change or show one independent binary state. |
| [Travel](SURFACES_INFORMATION_AND_FEEDBACK.md#flash-and-travel) | Explain a visual moving between meaningful slots. |
| [Typewriter](SURFACES_INFORMATION_AND_FEEDBACK.md#typewriter) | Pace narrative text with player-controlled completion. |
| [VStack](LAYOUT_AND_NAVIGATION.md#vstack-and-hstack) | Arrange sections in a reading sequence. |
| [ViewThatFits](LAYOUT_AND_NAVIGATION.md#viewthatfits) | Choose among authored alternatives for one local group. |
| [VirtualGrid](COLLECTIONS_AND_ACTIONS.md#virtualgrid) | Browse and select repeated objects by appearance. |
| [VirtualList](COLLECTIONS_AND_ACTIONS.md#virtuallist) | Browse and manage repeated items mainly one at a time. |
| [Vote](CHOICES_AND_INPUT.md#vote) | Express an up/down/no-vote judgment. |
| [ZStack](LAYOUT_AND_NAVIGATION.md#zstack) | Layer parts of one intentional visual object. |
| [ZoomView](LAYOUT_AND_NAVIGATION.md#zoomview-and-path) | Inspect a stable spatial structure at useful scales. |

## Interaction capabilities beyond controls

| Mechanism | Decision guidance |
| --- | --- |
| Adaptive controls and object manipulation across input methods | [Keep the operation consistent while its interaction adapts](ADAPTIVE_INTERACTION_AND_DIRECT_MANIPULATION.md#what-stays-common-and-what-adapts); distinguish automatic Facet behavior from game-owned decisions |
| Built-in motion, theme motion tokens, control transitions | [Choose the motion mechanism](MOTION_AND_FEEDBACK.md#choose-the-facet-motion-mechanism) before adding another animation |
| `UI.sequence` | [Coordinate a deliberate sequence](MOTION_AND_FEEDBACK.md#sequence), including finish, cancellation, and repeated events |
| `UI.countUp` | [Animate a displayed total](MOTION_AND_FEEDBACK.md#countup-and-flash) without confusing it with authoritative values |
| Collection `reorderable`, `drag`, `drop`, `rowDrop` | [Choose reorder versus transfer](ADAPTIVE_INTERACTION_AND_DIRECT_MANIPULATION.md#decide-whether-drag-and-drop-is-the-right-interaction) and own selection/model changes correctly |
| `UI.draggable`, `UI.dropTarget` | [Add object transfer](ADAPTIVE_INTERACTION_AND_DIRECT_MANIPULATION.md#add-drag-and-drop-through-the-owning-facet-behavior) with pickup policy, validation, pending work, and recovery |
| Transfer `travel`, `returnTravel`, `landing`; reserved slots | [Choose landing feedback](ADAPTIVE_INTERACTION_AND_DIRECT_MANIPULATION.md#5-choose-landing-feedback) and understand when it delays commitment |
| `UI.responder` | [Share input with gameplay](INPUT_FOCUS_AND_ACCESS.md#assign-input-ownership-by-task) through deliberate engagement |
| `UI.focusSection`, `UI.focusRing` | [Define focus entry, traversal, and return](INPUT_FOCUS_AND_ACCESS.md#make-focus-a-visible-route-through-the-task) |
| `UI.scrollTo`, `UI.scrollToVisible` | [Reveal relevant content](INPUT_FOCUS_AND_ACCESS.md#make-focus-a-visible-route-through-the-task) without fighting the player's reading position |
| `UI.commandScope`, `UI.adjustable` | [Support custom focused commands and adjustment](INPUT_FOCUS_AND_ACCESS.md#scope-specialized-commands-instead-of-reinventing-navigation) |
| `UI.worldAnchor` | [Connect UI to world targets](INPUT_FOCUS_AND_ACCESS.md#connect-world-information-without-losing-reliability) with explicit offscreen and occlusion behavior |
| `UI.environment`, scaled lengths, adaptive controls | [Adapt to actual conditions](INPUT_FOCUS_AND_ACCESS.md#adapt-to-capabilities-and-viewing-conditions) independently of input labels |
| `pressHaptic`, Button `haptic`, `UI.feedback` | [Coordinate tactile and visual feedback](INPUT_FOCUS_AND_ACCESS.md#combine-visual-sound-and-tactile-feedback) with accepted state changes |
| Theme definition, semantic palette, chrome, typography | [Establish a coherent visual system](DESIGN_WORKFLOW_AND_CRITIQUE.md#establish-a-visual-system-that-can-survive-content) |
| Control `help`, contextual Callout, durable help | [Teach at the right moment](GAME_FLOWS_AND_INFORMATION.md#learning-help-and-discovery) and preserve repeatable access |
| Translator integration, `richText.escape`, text layout | [Design real localized and player-created content](GAME_FLOWS_AND_INFORMATION.md#text-localization-and-player-created-content) |

## Whole-experience decisions

Start with [the design brief](DESIGN_WORKFLOW_AND_CRITIQUE.md#establish-the-design-brief), [game flow patterns](GAME_FLOWS_AND_INFORMATION.md), and [the review rubric](DESIGN_WORKFLOW_AND_CRITIQUE.md#evaluate-comprehension-and-behavior). Use them to assess whether the chosen controls and capabilities serve a coherent experience.
