# Sheet.layout

- `placement`: `automatic` (the default, the bottom edge), `adaptive`,
  `bottom`, `center` or `side`. On a ten-foot screen `automatic` and
  `adaptive` centre the sheet, and they dock it again when the screen is near. `adaptive` docks the sheet at the side edge
  when the room is 600 pixels wide or more, a mouse is available and touch is
  not. Otherwise it uses the bottom edge. It changes live with the room and
  the input. The `FacetPlacement` attribute of `SheetPanel` holds the result.
  A side sheet docks to `edge` (`left` or `right`, default `right`). `edge`
  also applies to `adaptive`. Its detents stay vertical. It slides in from its edge and leaves
  toward it. Under reduced motion it arrives and leaves at once.
- `width`: `automatic`, `narrow` or `wide`. These are the Dialog widths:
  `controls.alert.maxWidth`, `controls.popup.panelWidth` and
  `controls.dialog.wideWidth`. The safe room bounds each one.
- `header`: absent shows `title`. An Instance or a factory replaces the title.
  `false` removes the title row.
- `hero`: `{ image | content, aspectRatio | height, scaleMode?, background?,
  sticky? }`. A sticky hero stays pinned above the body. Otherwise it scrolls
  with the body. With `header = false`, the close control sits over the hero
  as an `inverse` button, so it reads on any art. Hero `content` is inset 16
  pixels from the sides and 12 from the bottom.
- `actions`: a list of `{ id, label, role?, enabled?, busy?, onActivate }`.
  They stay pinned below the body and never close the sheet. `actionLayout`
  is `automatic`, `row` or `stacked`. Cancel runs an enabled `role = "cancel"`
  action first.
- `contentInset`: `standard` (8 pixels) or `none`. It changes only the body
  padding.
- `scrollPolicy`: `always` (the default) keeps the body scrolling at every
  height. `atLargestDetent` stops the body scroll below the tallest detent.
- `closeButton`: absent, `true`, `false`, or a string or readable label.
  Absent shows an icon-only Close button in the trailing corner of the
  header when interactive dismissal is enabled. This also applies when a
  grabber is visible. Its
  accessible name is `Close`, and its target is 44 pixels. `true` always shows
  that icon button. A label shows a text button with that label. `false` shows
  none; Back, Escape and the backdrop still close the sheet.

When the pinned regions and a short body do not fit the panel, every region
moves into one scrolling column named `Room`. Thus each action stays
reachable. The on-screen keyboard height comes off the room, and the panel
sits above the keyboard.
