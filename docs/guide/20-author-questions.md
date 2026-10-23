# Author questions

Short answers to the questions that authors ask most. Each answer names the
reference section that has the full contract. Print a section with
`lute run tools/facet docs <name>`.

## HUD panels

Use one `Facet.app` and one root for the interface. Put all HUD content in one
Composition. Put each HUD group in a Region. Give each region a zone, a rank
and a stable width. Add a smaller form before you use `mayDrop = true`.

For a temporary panel, use a Sheet next to the Composition. Bind
`isPresented` to a writable cell. The Sheet owns Close, scrolling and modal
selection. Use NavigationStack for child pages with Back. Use DisclosureGroup
for details inside a page, or Popover for content anchored to a control.

```luau
local open = Compose.cell(false)
return UI.Screen "Root" {
    UI.Composition "HUD" {
        UI.fill(),
        UI.Region "Commands" {
            zone = "topRight", rank = 1,
            UI.Button "Tasks" {
                label = "Tasks", onActivate = function() open:set(true) end,
            },
        },
    },
    UI.Sheet "TasksPanel" {
        title = "Tasks", isPresented = open, closeButton = "Close",
        content = function()
            return UI.VStack "Details" {
                width = "fill", gap = "s", padding = "m",
                UI.Text "Status" { text = "No active task", wrap = true },
            }
        end,
    },
}
```

Run this component inside `app.mount`. See `docs "App and runtime setup"`
for setup, or `examples/blocks/hud_panel.luau` for a complete component.

## Collection screen

Use VirtualList for rows, VirtualGrid for tiles and Table for columns. Keep
the data, selected IDs and row edits in the model. A row owner can be removed
when it leaves the viewport.

Give the spec a type before you call the constructor. Bind row properties to
`current` so that a replacement item with the same key updates the row. Use
`:peek()` in an action. Use `Facet.Use` when a property reads different cell
types. This prevents the type checker from treating every read as one type.

With `UI`, `Compose` and `Facet` from the app setup:

```luau
type Entry = { id: string, title: string }
local initial: { Entry } = {}
local entries = Compose.cell(initial)
local busy = Compose.cell(false)
local spec: Facet.KeyedCollectionSpec<Entry, string> = {
    UI.fill(), from = entries, key = "id", itemSize = 64,
    render = function(current)
        return UI.Button "Entry" {
            label = function(use: Facet.Use) return use(current).title end,
            enabled = function(use: Facet.Use) return not use(busy) end,
        }
    end,
}
return UI.VirtualList "Entries" (spec)
```

For tiles, use `UI.VirtualGrid` with `minColumnWidth` and an estimated
`itemSize` height. Set `measure = true` for variable heights. Give the
collection a bounded parent and `UI.fill()` for the available space.
Use a formula to filter or sort `entries`; keep a stable key. Show an empty
result message when the formula returns no entries.

See `docs VirtualList --full` for selection, reordering and measurement.

## Reactive type errors

If a property reads cells of different types and the checker reports
`Readable`, `peek` or a long cyclic type, give `use` its public type:

```luau
text = function(use: Facet.Use)
    return if use(busy) then "Working" else use(title)
end
```

Use `Facet.Readable<T>` for a readable parameter and `Facet.Cell<T>` for a
writable parameter. For an optional cell, give the initial value its type:
`local initial: Entry? = nil`, then `Compose.cell(initial)`.
Do not cast the property or the cell to `any`.

On Windows PowerShell 5.1, save Luau files as UTF-8 without a byte order mark:
`[System.IO.File]::WriteAllText(path, text, (New-Object System.Text.UTF8Encoding $false))`.
`Set-Content` uses the system code page; `-Encoding utf8` adds a byte order mark.

## App and runtime setup

Make one app for the whole game interface. The app makes one runtime, one
ScreenGui, one StyleSheet and the focus ring.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local Compose = Facet.Compose
local app = Facet.app({ name = "Game", parent = playerGui })
local UI = app.UI
local screen = Compose.cell("hub")
app.mount(function()
    return UI.Screen "Root" {
        Compose.show(function(use) return use(screen) == "hub" end, function()
            return UI.Button "Shop" { label = "Shop", onActivate = function() screen:set("shop") end }
        end),
    }
end)
```

- Call `Facet.app` one time and `app.mount` one time. Each screen, panel, HUD
  element and overlay is a branch of that tree. Switch them with Compose
  state, for example `Compose.show`.
- Do not make a second app, a second runtime or a second mounted tree for a
  screen. `lute run tools/facet lint` warns when you do.
- `app.UI` holds the controls. `app.runtime.constructors` makes native
  objects, for example `Host.UIListLayout`.
- A Sheet, Dialog, Popover, Alert and Toast use their own layer. Put them in
  the same tree, next to the content that opens them.

See `docs Mounting`.

## Sheet and overlay focus

- A Sheet, Dialog, Alert, Popover and Menu are modal. While one is open, a
  tap, a click or a drag does not reach the content below it. The gamepad
  selection stays inside the top modal.
- When a modal opens while a control is selected, or while a gamepad is the
  input, it selects its first control after it shows.
- When a modal closes, the selection goes back to the control that opened it.
- Back, Escape and the scrim close the top modal. Do not bind these keys
  yourself. Roblox reserves Escape and the gamepad Start button.
- Open a Sheet with a writable cell: `isPresented = open`. The Sheet sets the
  cell to false when the player closes it.
- Stack overlays by opening one from the content of another. Each close
  returns one level.

See `docs Sheet`, `docs "Modal input"` and `docs Selection`.

## Text wrapping and sizing

- Set `textRole` (`title`, `heading`, `body`, `caption`, `label`, `numeral`)
  for the size and the font. The theme owns both. Do not set `TextSize`,
  `Font` or `TextScaled`.
- Set `wrap = true` for text that can take more than one line. Give the
  label room: put it in a VStack or HStack with `width = "fill"`, as the
  `hud_panel` block does. Text has no `width` option.
- Set `lines = n` to show at most `n` lines with an ellipsis.
- A one-line label that can be too long ends with an ellipsis. Add
  `disclose = true` to show the whole value on hover, selection or a long
  press.
- Stacks hug their content. A panel grows with its text. Put long content in
  a `ScrollView` or a Sheet body, which scrolls.

See `docs Text`, `docs "Text fit"` and `docs "Layout options"`.

## Selection and gamepad focus

- Facet controls are selectable. The engine moves the selection with the
  D-pad and the arrow keys. A gamepad player can reach every Facet control
  without extra code.
- `app.mount` adds the focus ring. The ring is the PlayerGui
  `SelectionImageObject`. It shows after keyboard or gamepad input and hides
  after mouse or touch input.
- The first D-pad press selects the first control of the active screen. A
  passive responder at rest, such as a `Composition` HUD, is skipped, so the
  stick and the D-pad keep driving the game.
- Do not set `Selectable = false` on a control that a player uses. Do not set
  `NextSelection` links by hand, except to fix one specific move.
- Use `SelectionGroup = true` on a container to keep the arrows inside it.
- A collection keeps the selection on its rows when rows change.

See `docs Selection` and `docs focusRing`.

## Typed collections

- Give a VirtualList, VirtualGrid, Outline or Table spec a type on a local,
  then pass the local: `local spec: Facet.KeyedCollectionSpec<Item, string> =
  { ... }` and `UI.VirtualList "Items" (spec)`.
- Use `Facet.KeyedCollectionSpec<Item, Key>` with `key` and
  `Facet.IdentityCollectionSpec<Item>` without `key`.
- With the type on the local, `render` and `current` get their types, and a
  key function and `UI.fill()` check correctly. When a property reads cells
  of different types, use `function(use: Facet.Use)`. See
  `docs "Reactive type errors"`.
- `None of the overloads ... are compatible` on a collection constructor means
  that one entry of an untyped inline spec is wrong. Put the type on the spec
  to see which entry.

See `docs VirtualList`.
