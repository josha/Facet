# Facet guide

Facet is UI controls over Compose and Roblox. Compose owns the tree, bindings, ownership, structural operations and motion. Roblox owns native layout, editing, scrolling, selection and styling. Facet owns interaction rules and adaptive control presentation.

Begin with [a working screen](03-getting-started.md) and [components](15-components.md). Choose a control with the [control chooser](14-choosing-controls.md), then use the [API reference](../reference/api.md) for its exact contract.

## Reading map

| Topic | Guide |
|---|---|
| Ownership, state and native nodes | [Concepts](01-concepts.md), [Architecture](02-architecture.md), [Components](15-components.md) |
| Complete maintained examples | [Tutorial examples](04-tutorial-examples.md) |
| Native paint, coordinated theme transitions and semantic themes | [Styling](05-styling.md), [Custom themes](09-custom-themes.md), [Rich skinning](10-rich-skinning.md), [Theme catalog](13-theme-catalog.md) |
| Domain authority and requests | [Client/server](06-client-server.md) |
| Input, focus and cancellation | [Input](07-input.md) |
| Installation without a source sync | [Without Rojo](08-without-rojo.md) |
| What has been exercised | [Device verification](11-device-verification.md), [Performance lab](12-performance-lab.md) |
| Layout and control decisions | [Choosing controls](14-choosing-controls.md), [Adaptive recipes](15-adaptive-recipes.md), [Control families](16-controls.md), [Recipes](17-recipes.md) |
| Contribution boundaries | [Maintainers](../MAINTAINERS.md), [Extension playbooks](../extending/new-control.md), [Constitution](../reference/constitution.md) |

## Capability catalog

| Capability | Public surface |
|---|---|
| Version | `Facet.VERSION` |
| Reactive graph, owners, keyed/presented composition | `Facet.Compose` |
| Native host/runtime and target construction | `Facet.Roblox`; `runtime.constructors` as `Host` |
| Control constructors | `Facet.controls(runtime, options?)` |
| Semantic native styling and art | `Facet.themes` |
| Activation and rich action rows | `UI.Button` |
| Boolean/mixed selection | `UI.Toggle` |
| Native editing and numeric input | `UI.TextInput` |
| Numeric adjustment | `UI.Stepper`, `UI.Slider` |
| Rating and discrete levels | `UI.Rating`, `UI.LevelPicker` |
| Selected/removable chips | `UI.Chip` |
| Shortcut display | `UI.ShortcutHint` |
| Action menus and primary/secondary actions | `UI.Menu`, `UI.SplitButton` |
| Choice and accepted custom text | `UI.Picker`, `UI.ComboBox` |
| Named destinations, drill-down and sequential pages | `UI.TabView`, `UI.NavigationStack`, `UI.PageView` |
| Contextual radial actions | `UI.RadialMenu` |
| Brief decisions and substantial presented content | `UI.Alert`, `UI.Sheet` |
| Inline disclosure and larger content presentation | `UI.DisclosureGroup`, `UI.CollapsibleView` |
| Contextual teaching | `UI.Callout` |
| Windowed lists and grids | `UI.VirtualList`, `UI.VirtualGrid` |
| Sorting, selection, resizing and row reorder | `UI.Table` |
| Row swipe/context actions | `UI.RowActions` |
| Text and compact status | `UI.Label`, `UI.Badge`, `UI.StatusIndicator` |
| Progress/loading | `UI.ProgressView`, `UI.Skeleton` |
| Async image state and cancellation | `UI.AsyncImage` |
| Identity groups | `UI.Avatar`, `UI.AvatarGroup` |
| Embedded 3D content | `UI.Stage` |

All control roots are native Instances. Layout is expressed with Host constructors and native properties. Use Compose structural operations directly instead of introducing Facet aliases for them.
