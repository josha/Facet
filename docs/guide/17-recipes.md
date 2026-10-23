# Practical recipes

## Confirm a destructive command

Keep the presentation state in a cell. The Alert dismisses before it calls the
selected action. Then it restores the previous selection if that object still
exists.

```luau
local confirm = Compose.cell(false)
return UI.VStack {
    UI.Button { label = "Delete", onActivate = function() confirm:set(true) end },
    UI.Alert {
        isPresented = confirm,
        title = "Delete this draft?",
        message = "This removes the saved draft.",
        actions = {
            { id = "cancel", label = "Keep draft", role = "cancel" },
            { id = "delete", label = "Delete", role = "destructive", onActivate = deleteDraft },
        },
    },
}
```

## Filter a large list

```luau
local query = Compose.cell("")
local visible = Compose.formula(function(use: Facet.Use)
    local term = string.lower(use(query))
    local result = {}
    for _, item in use(items) do
        if string.find(string.lower(item.title), term, 1, true) then
            table.insert(result, item)
        end
    end
    return result
end)
local list = UI.VirtualList {
    from = visible,
    key = function(item) return item.id end,
    itemSize = 48,
    render = function(current)
        return UI.Button {
            label = function(use) return use(current).title end,
            onActivate = function() openItem(current:peek().id) end,
            Size = UDim2.new(1, 0, 0, 48),
            AutomaticSize = Enum.AutomaticSize.None,
        }
    end,
}
```

Mount `list` next to a TextInput that is bound to `query`. Use native layout.
Keep the selected ids and the row drafts in the shared model. Let Compose keep
the collection anchor after filtering and sorting.

## Keep a drill-down path

```luau
local path = Compose.cell({})
return UI.NavigationStack {
    path = path,
    root = { title = "Catalog", content = Catalog },
    destinations = {
        item = {
            title = "Details",
            content = function(entry) return ItemDetails(entry.value) end,
        },
    },
}
```

Push `{ id = "item", value = itemId }` into `path` from the catalog action. The
control uses Compose `LayerStack` and owns the Back behavior. Do not keep a
separate presenter stack.

## Containers without a View

Facet has no catchall `View`. Each container job uses a native object or a
layout constructor. The gallery tab **Motion and layout > Layout > Containers**
shows each job.

| Job | Use |
|---|---|
| A styled group | A `Frame` with a theme tag, such as `facet-panel` |
| One activation | A `UI.Button` in the group. `Interactable = false` on the group disables every control in it |
| Size | `Size` in pixels or scale, `width`/`height` on a stack, and `UI.fill()` for the rest of a row |
| Aspect ratio in a known box | Size the subject from the box: `96 * math.min(1, ratio)` by `96 / math.max(1, ratio)`, centered in a `UI.ZStack` |
| Scale | A `UIScale` child. The engine paints the node larger or smaller. The layout box and the hit area do not change |
| Group transparency | A `CanvasGroup` with `GroupTransparency`. The subtree fades as one group and stays laid out |
| Hide and keep the space | A `CanvasGroup` with `GroupTransparency = 1` and `Interactable = false` |
| Remove from the layout | `Compose.show`, or `Visible = false` in a `UIListLayout`. The siblings close up |
| Alignment | `alignH` and `alignV` on a `UI.ZStack`, or `align` and `distribute` on a stack |
| Gap and padding | `gap` spaces the siblings. `padding = inset`, with `local inset: Facet.Sides = { left = 32, top = 8 }`, moves only the named edges |
| Wrap and clip | `wrap = true` on a stack. A `UI.ScrollView` with `axis = "x"` keeps one line reachable. `ClipsDescendants` cuts at the edge |
| Rounding, border and shadow | `UICorner`, `UIStroke` and `UIShadow` children. A `UICorner` rounds every corner with one radius |

```luau
local function contain(name, ratio)
    return UI.ZStack {
        Name = name,
        width = 96,
        height = 96,
        alignH = "center",
        alignV = "center",
        Host.ImageLabel {
            Image = art,
            ScaleType = Enum.ScaleType.Crop,
            Size = UDim2.fromOffset(96 * math.min(1, ratio), 96 / math.max(1, ratio)),
        },
    }
end
```

Colors, strokes, radii and shadows come from the theme tokens. A game that
wants a larger named set adds it to its own theme package.

## HUD settings during gameplay

Use an ordinary settings Button and a Popover. `modal = false` leaves gameplay
input available outside the panel. `compact = "popover"` keeps that policy on
small touch screens instead of adapting to a sheet. Give the panel an explicit
Close control because a non-modal Popover has no outside catcher or Cancel
binding. The **Screen-anchored HUD** showcase uses this pattern for its URL bar
and topbar strip settings.

```luau
local settingsOpen = Compose.cell(false)
local musicEnabled = Compose.cell(true)
return UI.Popover {
    isPresented = settingsOpen,
    onPresentedChange = function(open) settingsOpen:set(open) end,
    trigger = UI.Button { icon = "settings", name = "HUD settings" },
    title = "HUD settings",
    modal = false,
    compact = "popover",
    closeButton = true,
    content = function()
        return UI.Toggle { label = "Music", value = musicEnabled }
    end,
}
```

Keep the trigger in the HUD's responder; a `Composition` is one already. A
passive responder does not enter from a D-pad press while at rest. Give gamepad players an explicit menu entry:
engage the responder and set `GuiService.SelectedObject` to the settings
trigger when the game opens its menu. Once a sibling is selected, native
selection moves between eligible controls. Use `NextSelectionDown` and the
other native links when the game requires an exact neighbour. A non-modal
Popover does not claim focus; enter its content explicitly if the game needs
that behavior.

For a layer that requires screen-pixel coordinates, use `app.runtime.mount`
with `app.Host.ScreenGui { ScreenInsets = Enum.ScreenInsets.None, ... }`.
Install the theme StyleSheet and StyleLink in that root, as in the styling
guide, and retain the returned unmount function. This uses the native screen
boundary without adding per-mount options to `app.mount`.

## Reactive label size

`UI.Button { textSize = sizeCell }` accepts a readable number or type role.
The Lab's **reactive numeric text size** state switches between 16 and 24 pixels.
For a custom `UI.Text` child, bind the native `TextSize = sizeCell` property.
For `UI.Text`, use `textSize = "fit"` only when text should shrink to fit a fixed box.
