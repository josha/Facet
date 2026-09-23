# Native primitives

Facet does not maintain a parallel primitive catalog. Use the class directly through `Host = runtime.constructors` when Compose Roblox can construct it.

```luau
return Host.Frame {
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    Host.UIListLayout {
        FillDirection = Enum.FillDirection.Vertical,
        Padding = UDim.new(0, 8),
    },
    UI.Label { label = "Inventory" },
    UI.Button { label = "Open", onActivate = openInventory },
}
```

A new Roblox class generally needs an example and appropriate tests, not a Facet constructor, adapter mapping, layout rule and renderer branch. Confirm its native property and event contracts from the engine documentation and exercise it in Studio.

If Compose cannot express a required host operation, demonstrate the missing capability in a focused upstream test. Change Compose upstream and synchronize its generated snapshot; do not patch the vendored files or construct a local parallel runtime.

If the missing piece is reusable interaction policy rather than a primitive, follow [new control](new-control.md).
