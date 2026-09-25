# Native primitives

Facet does not keep a parallel catalog of primitives. If Compose Roblox can
make the class, use it directly through `Host = runtime.constructors`. Put it
in the layout constructors like any other child.

```luau
return UI.VStack {
    gap = "s",
    UI.Label { text = "Inventory" },
    Host.ImageLabel "Crest" { Image = ownedPanelAsset, Size = UDim2.fromOffset(48, 48) },
    UI.Button { label = "Open", onActivate = openInventory },
}
```

A new Roblox class usually needs an example and applicable tests. It does not
need a Facet constructor, an adapter mapping, a layout rule or a renderer
branch. Confirm its native property and event contracts in the engine
documentation. Exercise it in Studio.

If Compose cannot express a necessary host operation, show the missing
capability in a focused upstream test. Change Compose upstream and synchronize
its generated snapshot. Do not patch the vendored files. Do not make a local
parallel runtime.

If the missing item is reusable interaction policy, not a primitive, follow
[new control](new-control.md).
