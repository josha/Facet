# Facet guide

Facet is a library of UI controls. The controls use Compose and Roblox.

- Compose owns the tree, bindings, ownership, structural operations and motion.
- Roblox owns native layout, text editing, scrolling, selection and styling.
- Facet owns interaction rules and adaptive control presentation.

Start with [a working screen](03-getting-started.md) and
[components](15-components.md). Use the [control chooser](14-choosing-controls.md)
to select a control. Then read the exact contract of that control in the
[API reference](../reference/api.md).

## Reading map

| Topic | Guide |
|---|---|
| When to use Facet | [Choosing the abstraction](14-choosing-a-ui-library.md) |
| Ownership, state and native nodes | [Concepts](01-concepts.md), [Architecture](02-architecture.md), [Components](15-components.md) |
| Complete maintained examples | [Tutorial examples](04-tutorial-examples.md) |
| Native paint, theme transitions and semantic themes | [Styling](05-styling.md), [Custom themes](09-custom-themes.md), [Rich skinning](10-rich-skinning.md), [Theme catalog](13-theme-catalog.md) |
| Domain authority and requests | [Client and server](06-client-server.md) |
| Input, focus and cancellation | [Input](07-input.md) |
| Installation without a source sync | [Without Rojo](08-without-rojo.md) |
| What has been exercised, and what has not | [Device verification](11-device-verification.md), [Performance lab](12-performance-lab.md), [Paired performance](19-paired-performance.md), [Verification scope](18-verification-scope.md), [Verification parity](20-verification-parity.md), [Retired promises](21-retirements.md) |
| Layout and control decisions | [Choosing controls](14-choosing-controls.md), [Adaptive recipes](15-adaptive-recipes.md), [Control families](16-controls.md), [Recipes](17-recipes.md) |
| Contribution boundaries | [Maintainers](../MAINTAINERS.md), [Constitution](../reference/constitution.md) |
| Extension playbooks | [Adding a control](../extending/new-control.md), [Adding artwork to a control](../extending/skinned-control.md), [Native primitives](../extending/new-primitive.md), [Adding a theme package](../extending/new-theme.md), [Mounting into native targets](../extending/new-render-target.md), [Adapting to another platform context](../extending/new-platform-mode.md), [Adopting an engine feature](../extending/new-engine-feature.md) |

## Capability catalog

| Capability | Public surface |
|---|---|
| Version | `Facet.VERSION` |
| Reactive graph, owners, keyed and presented composition | `Facet.Compose` |
| Native host, runtime and target construction | `Facet.Roblox`; `runtime.constructors` as `Host` |
| Control constructors | `Facet.controls(runtime, options?)` |
| A runtime, controls and a themed ScreenGui mount in one call | `Facet.app(options?)`; `app.mount(Component)`; `app.dispose()` |
| Screen roots, stacks and layers | `UI.Screen`, `UI.VStack`, `UI.HStack`, `UI.ZStack` |
| Scrolling content and grids | `UI.ScrollView`, `UI.Grid` |
| Programmatic scrolling to a position or a node | `UI.scrollTo`, `UI.scrollToVisible` |
| Viewport classes, input classes, safe insets, text size and reduced motion | `UI.environment`, `Facet.adaptive` |
| Screen anchors for world objects | `UI.worldAnchor` |
| Main-axis fill, flexible space and separators | `UI.fill`, `UI.Spacer`, `UI.Divider` |
| Failure containment with fallback content | `UI.ErrorBoundary` |
| One reactive graph with the game's own Compose | `Facet.bind(Compose, Roblox)`; `Facet.COMPOSE_COMMIT` |
| Semantic native styling and art | `Facet.themes` |
| Civil dates, and an arithmetic parser for number fields | `Facet.civilDate`, `Facet.recipes` |
| Activation and rich action rows | `UI.Button` |
| Boolean and mixed selection | `UI.Toggle` |
| Native editing, field chrome and numeric input | `UI.TextInput`, `UI.NumberInput` |
| Civil date and date range fields with a calendar | `UI.DateTimePicker` |
| Colour wells with swatches, a spectrum, sliders and engine BrickColors | `UI.ColorPicker` |
| Numeric adjustment | `UI.Stepper`, `UI.Slider` |
| Rating and discrete levels | `UI.Rating`, `UI.LevelPicker` |
| Up and down votes | `UI.Vote` |
| Selected and removable chips | `UI.Chip` |
| Shortcut display | `UI.ShortcutHint` |
| Action menus, and primary and secondary actions | `UI.Menu`, `UI.SplitButton` |
| Choice and accepted custom text | `UI.Picker`, `UI.ComboBox` |
| Named destinations, drill-down and sequential pages | `UI.TabView`, `UI.NavigationStack`, `UI.PageView` |
| Numbered result pages and workflow steps | `UI.Pagination`, `UI.StepIndicator` |
| Contextual radial actions | `UI.RadialMenu` |
| Brief decisions and substantial presented content | `UI.Alert`, `UI.Dialog`, `UI.Sheet` |
| Inline disclosure and larger content presentation | `UI.DisclosureGroup`, `UI.CollapsibleView` |
| Contextual teaching | `UI.Callout` |
| Page status that stays in view | `UI.Notice` |
| A short confirmation at the bottom of the screen | `UI.Snackbar` |
| A surface top bar with Back, a title and tools | `UI.NavBar` |
| Anchored content for one control | `UI.Popover` |
| Windowed lists and grids | `UI.VirtualList`, `UI.VirtualGrid` |
| Browsable items with artwork and revealed actions | `UI.Card` |
| A count or dot seal on a host's corner | `UI.badged` |
| Sorting, selection, resizing and row reorder | `UI.Table` |
| Row swipe and context actions | `UI.RowActions` |
| Plain text, and an icon with a title | `UI.Text`, `UI.Label` |
| Compact status | `UI.Badge`, `UI.StatusIndicator` |
| Progress and loading | `UI.ProgressView`, `UI.Skeleton` |
| Images with scale, tile and nine-slice modes | `UI.Image` |
| Async image state and cancellation | `UI.AsyncImage` |
| Identity groups | `UI.Avatar`, `UI.AvatarGroup` |
| Embedded 3D content | `UI.Stage` |

Every control root is a native Instance. The layout constructors make native
frames and layout objects with theme spacing. Use Host constructors and native
properties for layout that they do not cover. Use the Compose structural
operations directly. Do not add Facet aliases for them.

The design records in `docs/plans` and `docs/superpowers` are historical. They
can describe removed APIs. This guide and the API reference describe the
supported surface.
