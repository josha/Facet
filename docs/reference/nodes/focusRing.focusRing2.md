# focusRing.focusRing2

focusRing.focusRing2 contract and option values.

At ten feet the look is larger: a ring is twice as thick, its contrasting
halo is as thick as the ring, the pulse fades less, brackets, art outsets and
slices are 1.5 times, a glow blurs 1.6 times and is more opaque, and the whole
look stands 3 pixels off the control, so it lifts clear of the control's own
edge. The theme tokens in `metrics.controls.focusRing` set these values:
`ringWeight` and `bracketWeight` (the stroke when the recipe has no
`thickness`), `bracketArm`, `blur`, `haloRatio`, `pulseFraction`,
`glowOpacity` and `glowPulseFraction`, and for ten feet `tenFootGap`,
`tenFootStrokeScale`, `tenFootBracketScale`, `tenFootOutsetScale`,
`tenFootSliceScale`, `tenFootBlurScale`, `tenFootGlowScale`,
`tenFootHaloRatio` and `tenFootPulseFraction`. A ring is drawn just outside the control at every distance,
so it never covers a label that runs to the control's edge.

A keyboard or gamepad selection inside a ScrollingFrame scrolls it so the
selected control and some room on each side are in view, so the engine can
always reach the next control (the pre-0.12 keep-visible rule). The room is
the control's height, but never more than half the space the control leaves in
the window, so a tall control stays fully in view. In a ScrollingFrame that
scrolls only on X, such as a segmented Picker strip, the same rule also keeps
room on the left and the right, from the control's width. Facet does this for every
app that observes the selection, with or without `focusRing`; it reads
`UserInputService:GetLastInputType()`, so a mouse or touch selection does not
scroll.

A value control is one stop; its look is drawn on its value part through
`FacetFocusPart` (a Slider's thumb or track, a range Slider's adjusted
handle). Each segment of a segmented Picker is its own selected object. A game control that needs its own look
sets `SelectionImageObject` on that control; the engine then draws that
object for it. Facet also omits its theme glow for that control, including
when the override changes while the control has focus.
