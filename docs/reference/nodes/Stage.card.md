# Stage.card

Inspect a 3D object in a bounded area.

Inside an app mount, set `local UI = app.UI`. The parent must bound both axes.

```luau
UI.Stage "Preview" {
    Size = UDim2.fromScale(1, 1),
    camera = CFrame.lookAt(Vector3.new(4, 3, 6), Vector3.zero),
    fieldOfView = 40,
    content = function(runtime, world)
        local Host = runtime.constructors
        Host.Part "Object" {
            Parent = Facet.Compose.static(world),
            Anchored = true,
            Size = Vector3.new(2, 2, 2),
            Color = Color3.fromRGB(40, 210, 230),
        }
        return nil
    end,
}
```

Compose owns scene parts built through the supplied runtime. Use
`Compose.static(world)` for their `Parent`. Bind them to selection or a draft.
This camera frames the sample cube. Adjust `camera` and `fieldOfView` for
the real subject and aspect ratio. Card sizes thumbnails; inspection art
must fill its bounded parent.

Open:

- [Stage.reference](Stage.reference.md)
