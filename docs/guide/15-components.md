# Components

A component is a function that returns a native Instance.

- Make an app with `Facet.app()`. Its `UI` field has the controls.
- Mount a component with `app.mount(Component)`. The component runs in the
  owner of that mount.
- Make native objects with `Host = app.runtime.constructors` only when no
  control or layout constructor makes them.
- Make controls inside a Compose owner. This is usually the component that you
  give to `app.mount`.
- Put a semantic name directly after the constructor: `UI.HStack "Toolbar" { ... }` or `UI.Button "Save" { ... }`. Do not write `Name = "..."` for a fixed name. Use `Name` only when the name is computed.
- Use numeric children and native property names.

## State and requests

A component runs when its owner is created. A reactive property body runs again
when a value that it reads changes. The whole component does not need to run
again.

| Purpose | Compose API |
|---|---|
| Local state | `Compose.cell` |
| Shared calculations | `Compose.formula` |
| External effects | `Compose.watch` |
| Teardown | `Compose.cleanup` |

This component uses the `Compose` and `UI` setup from
[Getting started](03-getting-started.md):

```luau
local function Settings()
    local enabled = Compose.cell(true)
    local status = Compose.formula(function(use)
        return if use(enabled) then "Notifications are on" else "Notifications are off"
    end)
    return UI.VStack {
        gap = "s",
        UI.Toggle {
            label = "Notifications",
            value = enabled,
            onChange = function(nextValue) enabled:set(nextValue) end,
        },
        UI.Label { text = status },
    }
end
```

- Read state through `use` in reactive bodies.
- `:peek()` reads the current value and does not subscribe. Use it in event
  callbacks.
- `:set` replaces a value.
- `:update` calculates the replacement from the previous value.

For an input value control, you can omit the change callback. The control then
writes a writable cell. If you supply a callback, update the model in it to
accept the request. Navigation controls have their own write-then-notify
contracts. See the [API reference](../reference/api.md#menus-and-navigation).

## Branches and keyed children

Use the Compose structural operations directly as native children.
`Compose.show` makes its branch while the condition is true. It disposes the
branch when the condition is false. State that the branch makes therefore
resets when the branch appears again. If state must survive hiding or
navigation, keep it outside that owner.

```luau
local detailsOpen = Compose.cell(false)
return UI.VStack {
    gap = "s",
    UI.Toggle { label = "Show details", value = detailsOpen },
    Compose.show(detailsOpen, function()
        return UI.Label { text = "Changes are saved to this session." }
    end),
}
```

For a bounded collection that stays mounted, use `Compose.keyed` with `from`, a
key function and `render(current, index, key)`. The Facet collection controls
also accept a field name as the key: `key = "id"`. Read the current item inside
property bindings. An existing key can receive a replacement item.

For large scrolling collections, use the Facet
[VirtualList or VirtualGrid](../reference/api.md#virtuallist-and-virtualgrid).
Keep durable row edits and selections in the model, outside the windowed row
owners. Compose `OrderedCollection` and `Pool` supply the collection mechanisms
for those controls. Screens do not need their own windowing.

Use `UI.ScrollView` for a vertical page. If you make a native
`ScrollingFrame` yourself, put a `UIListLayout` directly in it. Without a
layout, Roblox sizes a full-width child against the whole frame, so the child
goes under the scroll bar. With a layout, the child fits the window beside the
scroll bar.

## Layout

Use the layout constructors for screens, stacks, layers, scrolling pages and
grids. Each one makes an ordinary native frame and a native layout object.
Roblox does the layout.

| Need | Constructor |
|---|---|
| The root of a screen, with theme padding | `UI.Screen` |
| A vertical or horizontal stack | `UI.VStack`, `UI.HStack` |
| Children on top of each other | `UI.ZStack` |
| A page that scrolls | `UI.ScrollView` |
| Cells in columns | `UI.Grid` |
| A child that takes the remaining space | `UI.fill()` |

- Write `gap` and `padding` as spacing steps: `xs`, `s`, `m`, `l` or `xl`.
  The steps come from the theme package. A number is a pixel value.
- The containers set `LayoutOrder` from the order of the children. Do not
  write it.
- Set `width` or `height` to `"fill"`, `"hug"` or a number of pixels.
- Native properties, such as `BackgroundTransparency` or `Visible`, go to the
  root.

```luau
local function Profile()
    local name = Compose.cell("")
    return UI.Screen "Profile" {
        gap = "m",
        UI.Label { text = "Profile", textRole = "title" },
        UI.ScrollView "Form" {
            gap = "s",
            UI.TextInput { value = name, placeholder = "Name" },
            UI.HStack { gap = "s", UI.Button { label = "Save" }, UI.Button { label = "Cancel" } },
        },
    }
end
```

The ScrollView puts a `UIListLayout` in its `ScrollingFrame` and sets the
automatic canvas size. Thus each child fits the window beside the scroll bar.
Use Host constructors directly for a layout that these constructors do not
make. See the [layout reference](../reference/api.md#layout).

## Ownership and native references

The `ref` callback of a control receives its native root Instance. A borrowed
Instance property, such as `StyleLink.StyleSheet`, uses
`Compose.static(instance)`. Ownership comes from making and parenting the node,
not from the reference.

- Use `runtime.connect` for native events that are bound to an owner.
- For an external connection, register its disconnect function with
  `Compose.cleanup`.
- The stop function from `app.mount` releases that mount. `app.dispose()`
  releases every mount of the app and the runtime that the app made.
- If you use `runtime.mount` directly, stop the mounts before you call
  `runtime:dispose()`.
- If durable model cells must outlive the screen component, keep them outside
  it.

## Portals, retained content and motion

Use `Compose.portal` for content under a different parent. Use
`Compose.LayerStack` for retained content. Facet navigation and presented
controls already manage their own content owners.

Use `runtime.spring`, `runtime.tween` and `runtime.timeline` for motion. Obey
the reduced-motion setting. Bind animated values to native properties. Roblox
StyleRule transitions own the theme paint animation.

Navigation and presented controls animate by default. Do not add your own
motion to them. NavigationStack slides a pushed page in from the trailing edge.
TabView crossfades its pages. Sheet slides up. Alert, Dialog and
CollapsibleView scale and fade in. Callout, Button `help`, Menu and Popover
scale and fade from their anchor. Snackbar slides up and fades in.
DisclosureGroup and Notice open their height. Each exit plays the reverse,
faster. Reduced motion removes this motion. To use a
crossfade in NavigationStack or TabView, supply `transition` with Compose tween
options. To remove the motion, supply `transition = false`. The
[motion table](../reference/api.md#motion) gives each duration and curve.

```luau
local path = Compose.cell({})
return UI.NavigationStack {
	path = path,
	root = { title = "Library", content = UI.VStack {} },
	destinations = { game = { title = "Game", content = UI.VStack {} } },
	transition = { seconds = 0.25, ease = Compose.easing.outCubic },
}
```

Haptics are restrained. The `pressHaptic` of the controls plays only for a
control that changes a state or a value, for example a Toggle or a Stepper
step. To make a game-specific Button play it, set `haptic = true`.

See the [native API contract](../reference/api.md),
[adaptive composition](15-adaptive-recipes.md) and
[practical recipes](17-recipes.md).
