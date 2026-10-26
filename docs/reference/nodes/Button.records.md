# Button.records

Use one bounded button when the whole record opens the same task. Inside an
app mount, set `local UI = app.UI`.

```luau
UI.Button "Record" {
    Size = UDim2.new(1, 0, 0, 0),
    TextXAlignment = Enum.TextXAlignment.Left,
    appearance = "utility",
    label = "Sun prism",
    subtitle = "Carved stone · Ready for display",
    onActivate = function() print("Inspect record") end,
}
```

The whole record is the target. Bind the fields and action to the same stable
record key. In a measured VirtualList, the button's subtitle contributes to its
height. An external `caption` does not. The row wrapper does not resize a
hugging child to fill its width.

Selection marks the current record; focus marks the next input target. Keep
both visible without giving every row primary-action emphasis. Let the theme
supply these states. Use [RowActions](RowActions.card.md) for separate contextual
commands; opening a record is not a purchase or another commitment.

For a collection that owns selection and activation, render record content and
use its selection/onActivate contract instead. Do not add a second hit layer.
See [Collections](Collections.md) and [Button sizing](Button.disclose.md).
