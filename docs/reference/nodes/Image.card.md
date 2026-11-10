# Image.card

Show an image.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Image "Image" { image = "rbxassetid://0" }
```

Key options: `image`, `scaleMode`, `tint`, `width`, `height`, `aspectRatio`.

Use a valid game-owned asset. Size art with `width` and `height`, for example
`width = "fill", aspectRatio = 16 / 9`, and not with a native `Size`.

Related controls: [Controls](Controls.md).

Open:

- [Image.reference](Image.reference.md)
