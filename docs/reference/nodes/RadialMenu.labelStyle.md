# RadialMenu.labelStyle

An item on the ring shows its icon or its label, never both. It shows the
icon when its `labelStyle` is `icon`, its `compactLabel.prefer` is set, or it
is a `buttons` item with an `icon`. It also uses an available icon when the
complete label and its padding do not fit the content box after `contentFit`.
Otherwise it shows the label. Hold a touch on an icon, or point at it with
the mouse, to show the complete label. The list fallback shows both. A ring also uses the list form when it cannot
fit the complete caption of an action that has no icon.

`contentFit` defaults to `"radial"`. It fits the ring thickness to the content
and keeps the full angular span of each sector. Use `"both"` to fit both the
thickness and angular span, `"angular"` to fit only the span, or `"none"` to
keep the full sector shape.

`ringWidth` is a number of pixels or a theme width: `narrow`, `regular` or
`wide` (`controls.radial.narrow`, `.regular` and `.wide`). Each ring is at
least that thick and grows until every item's label or icon box fits, with
`space.s` around it, at the item's direction. The box is estimated from theme
metrics, not measured: the label is its character count times 0.6 of
`typography.control.size` wide and one control line tall, and an icon is
`iconSize` square. Set `iconSize` on the menu to draw icon-only items at that
size instead of the theme control icon size. An icon never grows past the
square that fits in its sector, so give large icons room with `ringWidth`. The ring is never thinner than `targetSizes.minimum`, is
thick enough for each wedge to be one touch target wide, and is never wider
than the room. A level that replaces its parent (`navigation = "replace"`)
keeps items at the same
distance from the centre. The same items and theme always give the same ring.

Where Back and Close sit depends on the preset, `center` and the room:
