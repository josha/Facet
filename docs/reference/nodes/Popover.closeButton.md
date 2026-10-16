# Popover.closeButton

Dismissible modal Popovers show Close in a compact room (less than 600 layout
units wide), or when the content covers at least 75 percent of the safe room.
Small floating Popovers use outside input, Escape, or gamepad B to close.
Close is a square utility button at the upper right of the anchored panel.
Nonmodal panels do not show Close by default. `closeButton = true` or `false`
decides either way. `cancelPolicy = "none"` hides Close. The compact Sheet
shows Close by default and follows the same explicit choice.

`title` (a string or a readable string) names the panel.  An anchored panel
shows it as a heading at the top, in one row with Close (Close at the right
end).  The compact Sheet shows it in its header.  Without a title and without
Close, the anchored panel has no header row.

`UI.Popover` returns its `trigger`, or an empty Frame for a `source` popover.

```luau
local open = Compose.cell(false)
runtime.mount(function()
    return Host.ScreenGui {
        UI.Popover "About" {
            isPresented = open,
            onPresentedChange = function(nextValue) open:set(nextValue) end,
            trigger = UI.Button { label = "About scoring" },
            maxWidth = 320,
            content = function() return UI.Text { text = "Laps score by position." } end,
        },
    }
end, playerGui)
```

Supply exactly one of `trigger` (a native GuiButton) or `source`. `source` is
`{ node = GuiObject }` or `{ rect = { x, y, w, h } }`. A trigger press, Cancel
and a tap outside call `onPresentedChange(next)`. The popover changes only when
the caller's fact changes. An open popover is modal, so a press on its own
trigger lands outside it. `onDismiss(reason)` reports each closure once:
`cancel`, `outside` or `anchorLost`. The trigger proposal uses `trigger`.

When a source node leaves the layer, the popover closes at once, proposes
false and reports `anchorLost`. It does not open again until the caller's fact
goes from false to true. A source node that is not mounted yet is not lost.
The popover waits for it and warns once. A `rect` source never draws a tail.
