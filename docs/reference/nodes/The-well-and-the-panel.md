#### The well and the panel

A well with a `label` is a form row. The `Well` button holds `Title`, the
`Swatch`, the `Value` text and `Chevron`. A well without a label is the
swatch alone, 44 by 44 pixels. The `label` attribute of the well names the
colour, for example "Kart paint, #E63946".

The panel opens below the well. If there is not sufficient room below, it
opens above. If neither side has room, it opens beside the well. Otherwise it
takes the larger side, and its `Body` ScrollingFrame scrolls. The panel never
covers the well. On a touch screen narrower than 600 pixels, the panel is a
sheet at the bottom of the screen with a Done button. On a ten-foot screen,
the panel is a sheet at the center of the screen. The `placement` attribute is
`bottom`, `top`, `right`, `left`, `sheet` or `center`. A skinned theme's panel `contentInsets` pad the panel,
and the panel grows by them, so the grid keeps 8 columns inside the art.

The panel holds these parts in order:

1. `Modes`: a `UI.Picker` of the techniques. It is present only with two or
   more modes.
2. `Body`: the `Technique` frame. The Bricks technique mounts on its first
   visit. Each mounted technique stays mounted until the panel closes. The
   inactive techniques are not visible. The frame is as tall as the tallest technique,
   so the panel keeps one height when the tab changes. In a scrolling body,
   an inactive technique reserves at most the height of the body, so a short
   technique has nothing below it to scroll to. The swatch and brick
   grids are centred in the panel.
3. `Opacity`: present only with `alpha`.
4. `Readout`: the `Preview` swatch, the `Format` picker (RGB, HSV and Hex) and
   the fields. The preview is two cells wide and one cell tall, and the format
   picker fills the rest of the row. Each format has a row (`FieldsRGB`,
   `FieldsHSV` or `FieldsHex`) with equal columns and native `HorizontalFlex`.
   Each field has its label above it. The `Hex` field takes the whole row.
   The rows stay mounted; only the selected format is visible. The readout
   reserves the tallest row, so the panel does not move when the format changes.
   On a touch screen, the readout comes before the body, so the finger does not
   cover it.
5. `Actions`: Cancel and Apply, or Done on a sheet.
