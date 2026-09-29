# Control families

Make controls with `local UI = Facet.controls(runtime)`. Controls return native
Instances and accept native properties. They use Compose readables for data.
[The API reference](../reference/api.md) lists the required fields and
callbacks.

Use this map to understand each control's role, then read its linked contract.
[Choosing controls](14-choosing-controls.md) explains the interaction decisions
and gives recipes for search, drill-down and contextual actions.

## Actions and values

| Control | Use it for | Choose something else when |
|---|---|---|
| [Button](../reference/api.md#button) | One command, such as Save or Equip. | A persistent boolean is a Toggle; a selected value is a Picker. |
| [SplitButton](../reference/api.md#menu-and-splitbutton) | A primary command with less common alternatives. | Equally important commands belong in a Menu or toolbar. |
| [Menu](../reference/api.md#menu-and-splitbutton) | A compact list of contextual commands. | A value choice belongs in Picker. |
| [RadialMenu](../reference/api.md#radialmenu) | A small spatial action set anchored to an object or control. | Long labels or deep hierarchies scan better in Menu. |
| [Toggle](../reference/api.md#toggle) | Independent on/off state; checkbox for a checklist, button for saved state. | Mutually exclusive values need Picker. |
| [TextInput](../reference/api.md#textinput) | Native text editing; search presentation for a filter with Clear. | Validated numeric entry needs NumberInput. |
| [NumberInput](../reference/api.md#numberinput) | Typed numeric values. | Stepper suits exact small increments; Slider suits bounded adjustment. |
| [Slider](../reference/api.md#stepper-and-slider) | Adjusting a bounded value with immediate feedback. | Precise typed values need NumberInput. |
| [Stepper](../reference/api.md#stepper-and-slider) | Increasing or decreasing by a defined increment. | A broad continuous range is easier with Slider. |
| [Picker](../reference/api.md#picker) | Selecting one known value. | Custom accepted text needs ComboBox; commands need Menu. |
| [ComboBox](../reference/api.md#combobox) | Selecting a known value or entering validated custom text. | A closed set only needs Picker. |
| [ColorPicker](../reference/api.md#colorpicker) | Choosing a color through swatches or detailed color controls. | A named material choice needs Picker. |
| [DateTimePicker](../reference/api.md#datetimepicker) | Civil date or range selection with a calendar. | A gameplay duration is numeric input. |
| [Rating](../reference/api.md#rating-and-levelpicker) | A score such as stars. | Ordered named levels need LevelPicker. |
| [LevelPicker](../reference/api.md#rating-and-levelpicker) | A discrete ordered level. | Unordered alternatives need Picker. |
| [Vote](../reference/api.md#vote) | Up/down sentiment on an item. | A star score needs Rating. |
| [Chip](../reference/api.md#chip-and-shortcuthint) | A compact selected or removable value. | A full option chooser needs Picker. |

## Navigation and presentation

| Control | Use it for | Choose something else when |
|---|---|---|
| [TabView](../reference/api.md#tabview) | Named peer destinations; sidebarAdaptable for outer navigation. | A hierarchy needs NavigationStack. |
| [NavigationStack](../reference/api.md#navigationstack) | Retained drill-down pages with animated transitions and Back. | Peer destinations need TabView. |
| [PageView](../reference/api.md#pageview) | Moving through sequential peer pages. | Numbered query results need Pagination. |
| [Pagination](../reference/api.md#pagination) | Choosing a numbered page of results. | Workflow progress needs StepIndicator. |
| [StepIndicator](../reference/api.md#stepindicator) | Showing a workflow's current stage. | General navigation needs TabView or NavigationStack. |
| [NavBar](../reference/api.md#navbar) | A surface title, tools and an explicit Back action. | Retained history and transitions need NavigationStack. |
| [Alert](../reference/api.md#alert) | A brief confirmation or decision. | A rich decision needs Dialog; a task needs Sheet. |
| [Dialog](../reference/api.md#dialog) | A decision with substantial supporting content or several actions. | Simple confirmation needs Alert. |
| [Sheet](../reference/api.md#sheet) | A substantial temporary task. | Short anchored tasks need Popover; browsing needs NavigationStack. |
| [Popover](../reference/api.md#popover) | Short content or a small task tied to a control. | Longer independent work needs Sheet. |
| [DisclosureGroup](../reference/api.md#disclosuregroup-and-collapsibleview) | Revealing secondary content inline. | An expanding compact preview needs CollapsibleView. |
| [CollapsibleView](../reference/api.md#disclosuregroup-and-collapsibleview) | Expanding a compact preview into fuller content. | Ordinary inline sections need DisclosureGroup. |
| [Callout](../reference/api.md#callout) | Teaching an action next to its control. | Durable page status needs Notice. |
| [Notice](../reference/api.md#notice) | Status that remains relevant until state changes. | Transient confirmation needs Toast. |
| [Toast](../reference/api.md#toast) | Passing confirmation, optionally with Undo. | A required decision needs Alert or Dialog. |

## Collections and layout

| Control | When to use it |
|---|---|
| [VirtualList / VirtualGrid](../reference/api.md#virtuallist-and-virtualgrid) | Large or unbounded collections; choose rows or tiles to suit the data. Use ScrollView for small heterogeneous content. |
| [Table](../reference/api.md#table) | Comparing, sorting, selecting or reordering columnar data. Use cards when artwork and individual browsing matter more. |
| [Card](../reference/api.md#card) | A browsable item with artwork and actions; compose it in VirtualGrid for many items. |
| [RowActions](../reference/api.md#rowactions) | Commands on one row, including swipe/context actions. Keep primary navigation on the row itself. |
| [Screen](../reference/api.md#screen) | A themed screen root with native layout. It does not own application state or routes. |
| [VStack / HStack](../reference/api.md#vstack-and-hstack) | Vertical or horizontal groups. Use AdaptiveStack when the axis must change with space. |
| [ZStack](../reference/api.md#zstack) | Ordinary overlapping content. Modal presentation belongs to a presented control. |
| [ScrollView](../reference/api.md#scrollview) | A small document or form that may exceed its viewport. Large data needs a virtual collection. |
| [Grid](../reference/api.md#grid) | A bounded arrangement of cells. Large collections need VirtualGrid. |
| [AdaptiveStack](../reference/api.md#adaptivestack) | A group that changes orientation to fit the available space. |
| [ViewThatFits](../reference/api.md#viewthatfits) | Selecting among authored presentations based on available space. |
| [Composition / Region](../reference/api.md#composition-and-region) | Screen-anchored HUD regions with priorities and compact forms. Ordinary app layouts use stacks or grids. |
| [Spacer](../reference/api.md#spacer) / [fill](../reference/api.md#fill) | Flexible empty space or a child that takes remaining space. |
| [Divider](../reference/api.md#divider) | A visual separator between related groups. |
| [ErrorBoundary](../reference/api.md#errorboundary) | Local failure containment with fallback content. |

## Information and media

The [media and status reference](../reference/api.md#media-and-status) gives
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
| [Path](../reference/api.md#path-shapes) | Simple vector strokes such as arcs or gauge needles. Use Image for raster artwork. |

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
