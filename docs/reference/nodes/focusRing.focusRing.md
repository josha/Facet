# focusRing.focusRing

`UI.focusRing(playerGui) -> Frame` sets `PlayerGui.SelectionImageObject` to
one selection object that the engine draws on the selected control, so the
engine owns where the focus is and when it moves. The theme package supplies
the look in its `chrome.focus` recipe (see [Themes](Themes.md)). The look shows
after keyboard or gamepad input, or when the effective input is a gamepad, and
hides after mouse or touch input. Call it inside a component and put the
returned Frame (an invisible paint probe) in the ScreenGui that holds the
StyleSheet link. `app.mount` does this for you; `app({ focusRing = false })`
leaves the PlayerGui's selection object to the game. Several apps share the one
engine selection object: the latest mounted look is drawn, unmounting gives
the previous look back, and the last unmount restores the object the game had
before.

The look takes the shape of the selected control: the control's own
`UICorner` (a `corners = "pill"` Button, a Slider thumb), a pill for a Chip, a
circle for a circle Button, and otherwise the theme's `radii.control`. A
recipe with `corner = "square"` or `corner = "pill"` keeps that shape
everywhere. The colour is the recipe `color`, or `accent`. A selected object
with a number attribute `FacetFocusHeight` gets a look that many times its own
height, measured down from its top edge (a Card uses this to ring the whole
card from its body). A selected object with a string attribute
`FacetFocusPart` (a path of child names such as `"Track/Thumb"`, where `..`
steps to the parent) gets the look on that part instead, sized to it and shaped
by its `UICorner`; a Slider uses this so the look stays on its thumb while the
whole Slider is the stop, and a framed TextInput or Search points its text box
at the whole field (`".."` up to the plate), so the look covers the search icon,
prefix, suffix and Clear button too. A field with step buttons keeps the look
on its text box, since each step button is its own stop. The
part's place and size are kept as shares of the selected object, so a parent
`UIScale` moves and sizes the look with the part. A part that is itself rotated
relative to the selected object gets an unrotated look around its unrotated box.
Known limit: when the selected object itself is rotated, the engine turns the
look with it about the look's own centre, so a look on a part off the object's
centre sits beside the part.
