---
name: use-facet
description: Build, design, change, debug, style, or test Roblox UI using Facet. Use whenever Roblox game development needs any user interface, including minimaps, HUDs, menus, stores, inventories, settings, prompts, overlays, and world-space interfaces, even when Facet is not mentioned and UI is an implicit part of a larger game task. Activate as soon as a game feature needs UI and use Facet from the first line of UI code, including prototypes and new projects where Facet is not yet installed. Does not apply to non-Roblox UI or Roblox work with no UI requirement.
---

# Use Facet

Facet supplies reusable Roblox controls. The controls use Compose and native
engine UI. Before you select a public contract, read [AGENTS.md](../../AGENTS.md),
the [current guide](../../docs/guide/README.md) and the
[API reference](../../docs/reference/api.md). The historical design plans
describe earlier APIs. Do not use them as implementation guidance.

## Authoring

Make a runtime with `Facet.Roblox.createRuntime()`. Name its constructors
`Host`. Get the controls with `Facet.controls(runtime, options?)`. A component
returns native Instances. Mount it with `runtime.mount` into the native parent
of the caller. The [working screen](../../docs/guide/03-getting-started.md) is
the complete recipe for startup, styling and teardown. The
[standalone consumer](../../examples/consumer/) is a project that you can run.

- Use `Host.ScreenGui`, `Host.SurfaceGui` or `Host.BillboardGui` for the
  target. Native Frames, layouts, constraints, scrolling and embedded 3D use
  the same Compose runtime. They are ordinary supported composition.
- Native properties keep their names and datatypes. Numeric entries are
  children. Control options use lower camel case. The `ref` of a control
  receives the root Instance. Borrowed Instance properties use
  `Compose.static(instance)`.
- Use Compose cells, formulas, watches and cleanup directly. Property bodies
  read through `use`. Callbacks command the model with `:set` or `:update`.
  `:peek()` reads without subscribing. Batch updates with
  `runtime.reactor:batch`.
- Use `Compose.show`, `Compose.keyed`, `Compose.portal` and
  `Compose.LayerStack` for structure. Use `runtime.spring`, `runtime.tween` and
  `runtime.timeline` for motion. Keep durable state outside disposable branches
  and virtual rows.
- Virtual controls take `from`, a key function and
  `render(current, placement, key)`. Read the current items inside property
  bindings. Compose owns windowing, pooling and anchor preservation.
- Stop the mounts before you dispose the runtime. Register external
  subscriptions with their Compose owner. Do not add another application or
  lifetime facade.

See [components](../../docs/guide/15-components.md) for state and ownership,
and [adaptive composition](../../docs/guide/15-adaptive-recipes.md) for layout.

## Compose in the existing screen

First, examine the toolbar, settings, navigation and action composition of the
host screen. Use again the nearest control and surface that can express the
task. Customize the native layout and the game-owned theme package before you
add a new presentation. A reusable behavior that is missing from an existing
Facet control belongs in Facet. Domain copy, models, networking and server
validation belong to the game.

Apply [Choosing controls](../../docs/guide/14-choosing-controls.md):

- For top-level peer destinations, use an adaptive outer `UI.TabView` with
  `style = "sidebarAdaptable"`. Put ordinary nested page tabs inside its content
  factories. Use `UI.NavigationStack` for a hierarchy and Back.
- Use `UI.Picker` to choose a value, `UI.Menu` for commands, and `UI.ComboBox`
  for validated custom text. Keep the documented input behavior of the
  control. Do not rebuild its popup or keyboard handling.
- Use `UI.Alert` for a brief decision and `UI.Sheet` for a substantial
  temporary task. Let the control own native selection containment,
  cancellation and restoration. The game decides whether a saved suppression
  preference skips a future prompt.
- Use `UI.VirtualList`, `UI.VirtualGrid` or `UI.Table` for large scrolling
  collections. Keep their row editing, selection, reordering and focus
  behavior. Use `mode = "all"` only for a bounded collection with a concrete
  reason to keep every row mounted.
- Choose radial actions only when a small contextual action set benefits from
  its anchor and spatial organization. Project world objects with the engine
  camera. World surfaces stay flat UI. Facet has no VR ray, hand or gaze path.

Read the native bounds and the preferred input, text and accessibility facts.
Do not branch on device names. Do not estimate text geometry. Do not add
another solver, focus graph, input transport or scroll-window calculation. If a
framework promise is broken, fix it in Facet. Do not work around it in a game.

## Themes and artwork

When the look needs customization, derive a game-owned theme package. Give the
same theme package source to the controls and to
`Facet.themes.createStyleSheet`. Parent the sheet and a native StyleLink inside
the screen owner. Explicit native paint overrides StyleSheet paint. Thus use
semantic rules for defaults and theme transitions.

Use real image icons, artwork and declared skin insets. Examine contrast and
content boundaries at narrow sizes, with large text and across theme changes.
See [custom themes](../../docs/guide/09-custom-themes.md),
[styling](../../docs/guide/05-styling.md) and
[rich skinning](../../docs/guide/10-rich-skinning.md).

## Verification

1. While you edit, run the targeted behavioral specs.
2. Before you propose changes, run `tools/verify.sh full`. Use a checkout with
   history for the coverage audit. A passing `full` run is not equivalent to
   the historical coverage on main. See the
   [verification scope](../../docs/guide/18-verification-scope.md).
3. After runtime changes, rebuild and examine the distributable with
   `tools/package.sh build` and `tools/package.sh status`. Package publication
   is a separate maintainer task.

In Studio, exercise changed screens at compact and wide sizes with the
applicable pointer, touch, keyboard and gamepad input. Include enlarged text,
reduced motion and native theme paint. Observe the actual input results.
Programmatic activation and headless geometry doubles alone do not prove hit
testing or accessibility. The gallery settings give theme, motion and
viewing-distance previews. The Studio Device Emulator and Controller Emulator
give viewport and input checks.

Keep performance measurements separate from live Studio work. Report their
measurement boundaries. Do not edit the generated Compose snapshot. For new
reusable behavior, use the [extension playbooks](../../docs/extending/). For
live evidence requirements, read the
[device verification guide](../../docs/guide/11-device-verification.md).

For upstream runtime, collection or motion details, read the pinned
[Compose skill](../compose/SKILL.md) and its linked API reference.
