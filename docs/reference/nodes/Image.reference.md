### Image

`UI.Image(spec) -> ImageLabel` shows an image. `image` is an asset string and
can be bound. It can be empty. The default size is a square of the regular
control height. A native `Size` replaces it.

- `tint` sets `ImageColor3`.
- `scaleMode` is `fit`, `fill`, `crop`, `stretch`, `tile` or `slice`, and
  sets `ScaleType`. `fill` and `crop` both give `Crop`. It can be bound, but a
  bound mode cannot be `tile` or `slice`.
- `tile` requires `tileSize = { width, height }` in whole pixels above zero.
  `slice` requires `sliceCenter = { x0, y0, x1, y1 }`, the centre rectangle in
  source pixels, and takes an optional `sliceScale` above zero (default 1). A
  geometry key without its mode, or a mode without its geometry, causes an
  error.
- `resample` is `default` or `pixelated` and sets `ResampleMode`. It can be
  bound.
- `shape = "circle"` adds a `UICorner` of half the size and a square
  `UIAspectRatioConstraint`. A circle cannot use `slice`.
