#### Techniques

- `swatches`: the `Swatches` grid of 44 by 44 cells, at most 8 in a row. A
  press on a cell proposes its colour. The chosen cell shows `Check`. Each
  cell has the `facet-color-cell` tag and no padding, so its swatch is square.
  A swatch has the `facet-color-swatch` tag and the theme's `radii.control`
  corner. The `Save` cell and the `BrickGrid` cells are the same.
- `spectrum`: the `Plane`, the `StickHint` and the `Hue` slider. The plane is
  two native layers. `Hue` has a white-to-hue UIGradient across. `Value` has
  a black UIGradient that fades in downward. A UIDragDetector on `Surface`
  sets saturation and brightness 1:1. The hue track is a rainbow UIGradient.
- `sliders`: the `Hue`, `Saturation` and `Brightness` sliders. Their labels
  share the width of the widest label, so the three tracks start at one x.
- `brick`: the 128 engine BrickColors in the `BrickGrid`, and the name of the
  chosen brick in `NameField` above the grid.

The thumbs are rings with a white band between two dark lines. The opacity
track shows the colour over a checker. If the preferred input changes during
a drag of the plane, the colour returns to the start of the drag.

On a touch screen, a bubble of the colour shows above the finger during a
drag of the plane or a strip. The plane bubble uses the overlay layer, so it
stays above the finger at the top of the spectrum and can overlap other
controls. It moves beside the finger only when it cannot fit above it within
the screen. On a gamepad, the right stick moves the plane
while `Surface` has the selection. The stick input action sinks the stick, so
a camera does not turn. The D-pad still moves the selection. `StickHint`
shows while the plane has the selection.

The fields commit typed values. `Hex` accepts `#RGB` and `#RRGGBB`. With
`alpha`, it also accepts `#RRGGBBAA`. A hex text that is not legal stays in
the field with its error, and nothing commits. A change of the readout format
never changes the colour. A grey keeps the hue that the player set.

There is no eyedropper, because Roblox cannot read a screen pixel. Put your
own Button beside the well, and call `onChange` with the colour that it
sampled.
