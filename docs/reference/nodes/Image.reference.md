### Image

<!-- aliases: Image | image -->

`UI.Image(spec) -> ImageLabel` shows an image. `image` is an asset string and
can be bound. It can be empty. The default size is a square of the regular
control height. A native `Size` replaces it.

- `width` and `height` are `"fill"` or a number of pixels. They can be bound.
  An axis without a value keeps the regular control height.
- `aspectRatio` is width divided by height, a number above zero. With `width`
  or with `height`, the other axis follows: `width = "fill", aspectRatio = 2`
  is as wide as the parent and half as tall. Alone, it uses the regular
  control height. With `width` and `height` together, the image fits inside
  that box. A circle has its own ratio.

- `tint` sets `ImageColor3`.
- `scaleMode` is `fit`, `fill`, `crop`, `stretch`, `tile` or `slice`, and
  sets `ScaleType`. `fill` and `crop` both give `Crop`. It can be bound, but a
  bound mode cannot be `tile` or `slice`.
- `tile` requires `tileSize = { width, height }` in whole pixels above zero.
  `slice` requires `sliceCenter = { x0, y0, x1, y1 }`, the centre rectangle in
  source pixels, and takes an optional `sliceScale` above zero (default 1). A
  geometry key without its mode, or a mode without its geometry, causes an
  error.
- `paintRect = { x0, y0, x1, y1, width, height }` (named fields) declares the
  rectangle that holds the paint of the art, in the source pixels of an image
  that is `width` by `height`. With `ImageRectSize`, use the pixels of that crop. It
  does not change the picture. `Facet.review` uses it as the painted bounds
  of the image, and a stack that takes the image as its `ground` starts its
  padding at this rectangle. It requires a static `image`.
  `Facet.review.paintRect(image)` reads the values in Studio.
- `resample` is `default` or `pixelated` and sets `ResampleMode`. It can be
  bound.
- `shape = "circle"` adds a `UICorner` of half the size and a square
  `UIAspectRatioConstraint`. A circle cannot use `slice`.
