# Control families

Make controls with `local UI = Facet.controls(runtime)`. Controls return native
Instances and accept native properties. They use Compose readables for data.
[The API reference](../reference/api.md) lists the required fields and
callbacks.

Use this map to understand each control's role, then read its linked contract.
[Choosing controls](14-choosing-controls.md) explains the interaction decisions
and gives recipes for search, drill-down and contextual actions.

Use [Facet.format](../reference/nodes/HUD-formatting.md) for currency counters and
fixed durations. Use [Timer](../reference/nodes/Timer.reference.md) for a round deadline or
elapsed time. Use [Typewriter](../reference/nodes/Typewriter.reference.md) to reveal a dialogue
line with a Skip action.

## Actions and values

| Control | Use it for | Choose something else when |
|---|---|---|
| [Button](../reference/nodes/Button.reference.md) | One command, such as Save or Equip. | A persistent boolean is a Toggle; a selected value is a Picker. |
| [SplitButton](../reference/nodes/Menu-and-SplitButton.md) | A primary command with less common alternatives. | Equally important commands belong in a Menu or toolbar. |
| [Menu](../reference/nodes/Menu-and-SplitButton.md) | A compact list of contextual commands. | A value choice belongs in Picker. |
| [RadialMenu](../reference/nodes/RadialMenu.reference.md) | A small spatial action set anchored to an object or control. | Long labels or deep hierarchies scan better in Menu. |
| [Toggle](../reference/nodes/Toggle.reference.md) | Independent on/off state; checkbox for a checklist, button for saved state. | Mutually exclusive values need Picker. |
| [TextInput](../reference/nodes/TextInput.reference.md) | Native text editing; search presentation for a filter with Clear. | Validated numeric entry needs NumberInput. |
| [NumberInput](../reference/nodes/NumberInput.reference.md) | Typed numeric values. | Stepper suits exact small increments; Slider suits bounded adjustment. |
| [Slider](../reference/nodes/Stepper-and-Slider.md) | Adjusting a bounded value with immediate feedback. | Precise typed values need NumberInput. |
| [Stepper](../reference/nodes/Stepper-and-Slider.md) | Increasing or decreasing by a defined increment. | A broad continuous range is easier with Slider. |
| [Picker](../reference/nodes/Picker.reference.md) | Selecting one known value. | Custom accepted text needs ComboBox; commands need Menu. |
| [ComboBox](../reference/nodes/ComboBox.reference.md) | Selecting a known value or entering validated custom text. | A closed set only needs Picker. |
| [ColorPicker](../reference/nodes/ColorPicker.reference.md) | Choosing a color through swatches or detailed color controls. | A named material choice needs Picker. |
| [DateTimePicker](../reference/nodes/DateTimePicker.reference.md) | Civil date or range selection with a calendar. | A gameplay duration is numeric input. |
| [Rating](../reference/nodes/Rating-and-LevelPicker.md) | A score such as stars. | Ordered named levels need LevelPicker. |
| [LevelPicker](../reference/nodes/Rating-and-LevelPicker.md) | A discrete ordered level. | Unordered alternatives need Picker. |
| [Vote](../reference/nodes/Vote.reference.md) | Up/down sentiment on an item. | A star score needs Rating. |
| [Chip](../reference/nodes/Chip-and-ShortcutHint.md) | A compact selected or removable value. | A full option chooser needs Picker. |

## Navigation and presentation

| Control | Use it for | Choose something else when |
|---|---|---|
| [TabView](../reference/nodes/TabView.reference.md) | Named peer destinations; sidebarAdaptable for outer navigation. | A hierarchy needs NavigationStack. |
| [NavigationSplitView](../reference/nodes/NavigationSplitView.reference.md) | Related resizable panes, with one pane on compact and TV layouts. | A hierarchy inside a pane needs NavigationStack. |
| [NavigationStack](../reference/nodes/NavigationStack.reference.md) | Retained drill-down pages with animated transitions and Back. | Peer destinations need TabView. |
| [PageView](../reference/nodes/PageView.reference.md) | Moving through sequential peer pages. | Numbered query results need Pagination. |
| [Pagination](../reference/nodes/Pagination.reference.md) | Choosing a numbered page of results. | Workflow progress needs StepIndicator. |
| [StepIndicator](../reference/nodes/StepIndicator.reference.md) | Showing a workflow's current stage. | General navigation needs TabView or NavigationStack. |
| [NavBar](../reference/nodes/NavBar.reference.md) | A surface title, tools and an explicit Back action. | Retained history and transitions need NavigationStack. |
| [Alert](../reference/nodes/Alert.reference.md) | A brief confirmation or decision. | A rich decision needs Dialog; a task needs Sheet. |
| [Dialog](../reference/nodes/Dialog.reference.md) | A decision with substantial supporting content or several actions. | Simple confirmation needs Alert. |
| [Sheet](../reference/nodes/Sheet.reference.md) | A substantial temporary task. | Short anchored tasks need Popover; browsing needs NavigationStack. |
| [Popover](../reference/nodes/Popover.reference.md) | Short content or a small task tied to a control. | Longer independent work needs Sheet. |
| [DisclosureGroup](../reference/nodes/DisclosureGroup-and-CollapsibleView.md) | Revealing secondary content inline. | An expanding compact preview needs CollapsibleView. |
| [CollapsibleView](../reference/nodes/DisclosureGroup-and-CollapsibleView.md) | Expanding a compact preview into fuller content. | Ordinary inline sections need DisclosureGroup. |
| [Callout](../reference/nodes/Callout.reference.md) | Teaching an action next to its control. | Durable page status needs Notice. |
| [Notice](../reference/nodes/Notice.reference.md) | Status that remains relevant until state changes. | Transient confirmation needs Toast. |
| [Toast](../reference/nodes/Toast.reference.md) | Passing confirmation, optionally with Undo. | A required decision needs Alert or Dialog. |

## Collections and layout

| Control | When to use it |
|---|---|
| [Outline](../reference/nodes/Outline.reference.md) | Expandable data rows with shared collection selection, editing, drag and focus. Table accepts the same hierarchy options when columns help. |
| [VirtualList / VirtualGrid](../reference/nodes/VirtualList-and-VirtualGrid.md) | Data rows or tiles with selection, reordering or collection focus, including short editable lists; also large or unbounded collections. Use ScrollView for a document or form without those collection behaviors. |
| [Table](../reference/nodes/Table.reference.md) | Comparing, sorting, selecting or reordering columnar data. Use cards when artwork and individual browsing matter more. |
| [Card](../reference/nodes/Card.reference.md) | A browsable item with artwork and actions; compose it in VirtualGrid for many items. |
| [RowActions](../reference/nodes/RowActions.reference.md) | Commands on one row, including swipe/context actions. Keep primary navigation on the row itself. |
| [Screen](../reference/nodes/Screen.reference.md) | A themed screen root with native layout. It does not own application state or routes. |
| [VStack / HStack](../reference/nodes/VStack-and-HStack.md) | Vertical or horizontal groups. Use AdaptiveStack when the axis must change with space. |
| [ZStack](../reference/nodes/ZStack.reference.md) | Ordinary overlapping content. Modal presentation belongs to a presented control. |
| [ScrollView](../reference/nodes/ScrollView.reference.md) | A document or form that may exceed its viewport. Interactive rows need a collection control even when the list is short. |
| [Grid](../reference/nodes/Grid.reference.md) | A bounded arrangement of cells without collection behavior. Selectable or reorderable tiles, and large collections, need VirtualGrid. |
| [AdaptiveStack](../reference/nodes/AdaptiveStack.reference.md) | A group that changes orientation to fit the available space. |
| [ViewThatFits](../reference/nodes/ViewThatFits.reference.md) | Selecting among authored presentations based on available space. |
| [Composition / Region](../reference/nodes/Composition.reference.md) | Screen-anchored HUD regions with priorities and compact forms. Ordinary app layouts use stacks or grids. |
| [Spacer](../reference/nodes/Spacer.reference.md) / [fill](../reference/nodes/fill.md) | Flexible empty space or a child that takes remaining space. |
| [Divider](../reference/nodes/Divider.reference.md) | A visual separator between related groups. |
| [ErrorBoundary](../reference/nodes/ErrorBoundary.reference.md) | Local failure containment with fallback content. |

## Information and media

The [media and status reference](../reference/nodes/Media-and-status.md) gives
properties and state contracts for these controls.

| Control | When to use it |
|---|---|
| Text / Label | Plain text, or an icon with a title. Use a control with activation behavior for commands. |
| Badge / badged | A compact count or status seal; `badged` attaches it to an existing host. |
| StatusIndicator | A compact state such as connected or unavailable; keep a readable label. |
| ProgressView | Known progress or indeterminate activity. Use Skeleton for placeholder content shape. |
| Skeleton | Temporary placeholder geometry while content loads. |
| ShortcutHint | Showing an input shortcut; the game still owns its binding. |
| Image / AsyncImage | An available image, or an image with asynchronous loading and cancellation. |
| Avatar / AvatarGroup | One identity or a compact group of identities. |
| Stage | Embedded 3D content in a UI viewport. World-space UI uses native SurfaceGui or BillboardGui. |
| [Path](../reference/nodes/Path-shapes.md) | Simple vector strokes such as arcs or gauge needles. Use Image for raster artwork. |

## Callbacks

The screen owns the domain values. Input callbacks request changes. If you
supply a callback, it must update the model to accept the request. Picker and
the other navigation controls update their writable model first, and then
notify. Callbacks do not all have the same semantics. Read the contract of each
control.

## What is not a control family

Native layout composition uses Host classes. Reactive ownership and structure
use Compose. Facet does not duplicate those mechanisms as a control family.

Choose controls by task, as [Choosing controls](14-choosing-controls.md)
describes. Test the actual input paths and accessibility behavior in your game.
