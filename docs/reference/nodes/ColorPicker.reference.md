### ColorPicker

`UI.ColorPicker(spec)` returns a Frame. The player uses it to choose any
colour, for example the paint of a kart. For a few named colours, use
`UI.Picker`. A fixed palette also fits `modes = { "swatches" }`.

```luau
local paint = Compose.cell(Color3.fromRGB(230, 57, 70))
UI.ColorPicker "KartPaint" {
    label = "Kart paint",
    value = paint,
    onChange = function(color)
        paint:set(color)
    end,
    onCommit = function(color)
        print("save", color)
    end,
}
```

- `value`: a Color3, or a readable of one. It is `nil` only with
  `allowEmpty = true`. Then the plate has a cross and the text is
  `placeholder`.
- `onChange(color)`: receives each proposal. It is necessary unless `value` is
  a writable cell or `readOnly` is true. With `allowEmpty`, a discarded draft
  that opened empty proposes `nil`.
- `onCommit(color)`: runs once at the end of each gesture.
- `alpha` and `onAlphaChange(alpha)`: an opacity from 0 to 1. They add the
  `Opacity` slider, and the text becomes `#RRGGBBAA`.
- `modes`: the techniques in tab order. Each is `swatches`, `spectrum`,
  `sliders` or `brick`. The default is all four. Without `BrickColor` in the
  controls' `types`, the default is the first three. Set it at construction.
  With `brick`, a colour that is a BrickColor is named by that brick, for
  example "Kart paint, Really red".
- `swatches`: a list of Color3 values or `{ color, label? }` items, or a
  readable of one. The label or the hex text is the key of an item. Without
  it, the control shows a generated grid of 48 colours.
- `onSaveSwatch(color)` and `onRemoveSwatch({ color, label?, key })`: saved
  colours. See below.
- `style`: `automatic` (the default) or `inline`. Set it at construction.
  `automatic` is a well that opens a panel. `inline` shows the panel in place.
- `draft`: adds Cancel and Apply.
- `isPresented`, `onPresentedChange(next)` and `onDismiss(reason)`: the open
  state of the panel. The reason is `activate`, `outside`, `cancel`,
  `anchorLost` or `apply`. Without `isPresented`, the control keeps its own
  open state.
- `enabled` and `readOnly`: booleans or readables. A disabled well keeps its
  colour and does not open.
- The field chrome keys: `label`, `requiredMark`, `hint`, `errorText`,
  `controlSize`, `appearance` and `corners`. See
  [Field chrome](Field-chrome.md).

A value that is not legal at construction causes an error. A value that
becomes illegal later is not painted. The control keeps the last legal colour
and adds a line to the `diagnostics` attribute.

Open:

- [Proposals-and-commits](Proposals-and-commits.md)
- [Saved-colours](Saved-colours.md)
- [Techniques](Techniques.md)
- [The-well-and-the-panel](The-well-and-the-panel.md)
