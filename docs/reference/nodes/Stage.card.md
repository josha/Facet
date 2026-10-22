# Stage.card

Show a native 3D viewport.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Stage "Preview" {
    Size = UDim2.new(1, 0, 0, 180),
    camera = CFrame.lookAt(Vector3.new(4, 3, 6), Vector3.zero),
    content = function(runtime, world)
        local Host = runtime.constructors
        local part = Host.Part("Object")({
            Anchored = true,
            Size = Vector3.new(2, 2, 2),
            Color = Color3.fromRGB(40, 210, 230),
        }) :: Part
        part.Parent = world
        return nil
    end,
}
```

Key options: `camera`, `content`, `lazy`.

Stage owns the native viewport, camera, and WorldModel. Its content callback
runs in the same Compose owner. Create the object's parts with the supplied
runtime and parent the root to `world`. Bind their properties to the selected
object or editable draft. The containing task must establish the fill width.

Use `camera` with a CFrame for an owned camera.

Open:

- [Stage.reference](Stage.reference.md)
