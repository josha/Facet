### Layout options

<!-- aliases: Layout options | layout-options | Stack | Stack.layout | VStack.layout -->

Layout-options option values and behavior.

These options belong to containers. Text and Button size to their content.
For a leaf's width, set `align = "stretch"` on its parent VStack. For height,
use that option on its parent HStack. Put `UI.fill()` inside a leaf to share
the parent's main axis. For explicit width, use native
`Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y`.
For explicit height, use `Size = UDim2.fromOffset(0, 48),
AutomaticSize = Enum.AutomaticSize.X`. For a fixed box use native Size and
`AutomaticSize = Enum.AutomaticSize.None`.
Put gap, padding, align and distribute on the parent stack. For padding inside
a leaf, add a native UIPadding child through Host. For a leaf width limit,
add a native UISizeConstraint child with MaxSize. Name the constructor table
`local Host = app.runtime.constructors`.

| Option | Values | Native result |
|---|---|---|
| `gap` | a spacing step or a number of pixels | `UIListLayout.Padding` |
| `padding` | a spacing step, a number, or `{ top?, right?, bottom?, left? }` | a `UIPadding` child |
| `width`, `height` | `"fill"`, `"hug"` or a number of pixels | `Size` and `AutomaticSize` |
| `maxWidth` | a finite number of pixels, 0 or more | `UISizeConstraint.MaxSize.X` |
| `align` | `start`, `center`, `end` or `stretch` | cross-axis alignment, `ItemLineAlignment` and the cross-axis flex |
| `distribute` | `start`, `center`, `end`, `spaceBetween`, `spaceAround` or `spaceEvenly` | main-axis alignment and `HorizontalFlex` or `VerticalFlex` |

- The spacing steps are `xs`, `s`, `m`, `l` and `xl`. They come from
  `metrics.space` of the theme package in the `theme` factory option. The
  neutral values are 4, 8, 16, 24 and 40 pixels. A package without a step uses
  the neutral value.
- When the theme package changes, the containers write the new pixel values.
  The native layout objects stay the same.
- An unknown step, alignment or size causes an error that names the valid
  values.
- `"fill"` sets the scale of that axis to 1. `"hug"` sets `AutomaticSize` on
  that axis. A number sets the pixel offset.
- `align = "stretch"` sets `ItemLineAlignment.Stretch` and sets the flex of
  the cross axis to `Fill`, so each child fills the cross axis of the
  container. `ItemLineAlignment.Stretch` alone fills only the line, and the
  line is as wide as the widest child.
- A container writes an alignment property only when you set `align` or
  `distribute`.
- All options accept a value, a readable or a `function(use)` body.

Use `width = "fill", maxWidth = 480` for a panel that fills the available
width up to 480 pixels. This applies to Screen, VStack, HStack, ZStack,
ScrollView, Grid, AdaptiveStack, ViewThatFits and ErrorBoundary. The maximum
includes the container's padding. It does not change the height or the chosen
`width` mode. A numeric `width` remains fixed unless a smaller `maxWidth` caps it.
The constraint updates in place when a bound maximum changes. Omit `maxWidth`
to leave the width uncapped. Use a native `UISizeConstraint` instead when you
need minimum sizes or height limits; do not combine it with `maxWidth` on the
same container.

```lua
UI.VStack {
    width = "fill",
    maxWidth = 480,
    UI.Stepper { label = "Laps", value = laps, min = 1, max = 10 },
}
```
