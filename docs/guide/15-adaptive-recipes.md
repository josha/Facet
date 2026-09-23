# Adaptive native composition

Make decisions from available space and published engine facts. Native layouts own the resulting geometry; Facet controls own their internal adaptive choices. Observe native bounds when a screen must choose between two genuinely different arrangements.

## A wrapping action band

```luau
return Host.Frame {
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    Host.UIListLayout {
        FillDirection = Enum.FillDirection.Horizontal,
        Wraps = true,
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    },
    UI.Button { LayoutOrder = 1, label = "Save", onActivate = save },
    UI.Button { LayoutOrder = 2, label = "Preview", onActivate = preview },
}
```

Wrapping handles geometry; it does not change what an action means. Keep LayoutOrder explicit when order matters.

## Read native bounds

```luau
local frame = Host.Frame { Size = UDim2.fromScale(1, 1) }
local bounds = Compose.cell(frame.AbsoluteSize)
local connection = frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
    bounds:set(frame.AbsoluteSize)
end)
Compose.cleanup(function() connection:Disconnect() end)
local stop = runtime.mount(function()
    return UI.VirtualGrid {
        from = rows,
        key = function(row) return row.id end,
        columns = function(use) return math.max(1, math.floor(use(bounds).X / 240)) end,
        itemSize = 180,
        render = renderCard,
        Size = UDim2.fromScale(1, 1),
    }
end, frame)
Compose.cleanup(stop)
return frame
```

The initial native bounds may be zero. Use safe minimums and let later engine observations update the policy. Do not run a second settle loop to force synchronous measurements.

## Text and safe areas

Use TextWrapped, AutomaticSize, native constraints and appropriate flex behavior. Let the engine calculate text bounds; do not estimate glyph widths in a screen. ScreenGui inset and safe-area properties configure the target. TabView's adaptable presentation should be preferred over recreating a sidebar switch in every screen.

Keep structural ownership stable when only a size changes. Use a property binding for dimensions; use Compose.show or keyed only when the composition itself changes.
