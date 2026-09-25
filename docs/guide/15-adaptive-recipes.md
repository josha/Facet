# Adaptive native composition

Make decisions from the available space and the published engine facts. Native
layouts own the resulting geometry. Facet controls own their internal adaptive
choices. Observe the native bounds when a screen must choose between two
different arrangements.

## A wrapping action band

```luau
return UI.HStack "Actions" {
    wrap = true,
    gap = "s",
    width = "fill",
    UI.Button { label = "Save", onActivate = save },
    UI.Button { label = "Preview", onActivate = preview },
}
```

`wrap = true` sets `UIListLayout.Wraps`. The stack sets `LayoutOrder` from the
order of the children. Wrapping changes the geometry. It does not change what
an action means.

## Read native bounds

A column count that follows the width needs the native bounds. Read them in
the `ref` of the control. Register the disconnect with `Compose.cleanup`.

```luau
local width = Compose.cell(0)
return UI.VirtualGrid "Cards" {
    from = rows,
    key = "id",
    itemSize = 180,
    render = renderCard,
    columns = function(use)
        return math.max(1, math.floor(use(width) / 240))
    end,
    ref = function(grid)
        local function measure() width:set(grid.AbsoluteSize.X) end
        measure()
        local connection = grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(measure)
        Compose.cleanup(function() connection:Disconnect() end)
    end,
}
```

The VirtualGrid fills its parent by default. The initial native bounds can be
zero. Use safe minimum values. Let later engine observations update the policy.
Do not run a second settle loop to force synchronous measurements.

## Text and safe areas

- Use `TextWrapped`, the `width` and `height` options of the layout
  constructors, `UI.fill()` and native constraints.
- Let the engine calculate the text bounds. Do not estimate glyph widths in a
  screen.
- Use the ScreenGui inset and safe-area properties to configure the target.
- Use the adaptable presentation of TabView. Do not make a new sidebar switch
  in each screen.

Keep the structural ownership stable when only a size changes. Use a property
binding for dimensions. Use `Compose.show` or `Compose.keyed` only when the
composition itself changes.
