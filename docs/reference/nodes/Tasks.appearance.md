# Tasks.appearance

Use this for an editable 3D subject. The camera frames a sample cube; choose
its pose and field of view for the actual subject. The parent bounds both axes.
Stage uses a native ViewportFrame, Camera and WorldModel. Compose owns the scene.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function appearance(app: Facet.App, paint: Facet.Value<Color3>, palette: { Facet.ColorSwatch }): Frame
  local C, UI = Facet.Compose, app.UI
  return UI.VStack {
    width = "fill", height = "fill", gap = "s",
    UI.ZStack {
      width = "fill", height = "fill", UI.fill(),
      UI.Stage "Subject" {
        Size = UDim2.fromScale(1, 1),
        Ambient = Color3.new(1, 1, 1), LightColor = Color3.new(1, 1, 1),
        camera = CFrame.lookAt(Vector3.new(4, 3, 6), Vector3.zero),
        fieldOfView = 40,
        content = function(runtime: Facet.Runtime, world: WorldModel)
          local Host = runtime.constructors
          Host.Part {
            Parent = C.static(world), Anchored = true,
            Size = Vector3.new(2, 2, 2), Color = paint,
          }
          return nil
        end,
      },
    },
    UI.ColorPicker {
      label = "Color", value = paint, swatches = palette,
      style = "inline", modes = { "swatches" },
    },
  }
end
```

Supply labeled palette entries. Keep the preview lighting near white when
comparing colors. Bind scene parts to the selected record and the same draft
as its facts. Use Compose.show for a different model or an owned clone for
existing art; do not move the game's live model into the preview.

This edits local state. Put Save, pending, failure and accepted copy beside
the decision; the server owns validation. A long palette needs a bounded
[detail ScrollView](Tasks.collection-detail.md). A text-led record or a quiet
plugin property list may need no 3D subject.

[Stage contract](Stage.reference.md), [ColorPicker](ColorPicker.card.md).
