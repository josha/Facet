# TabView.indicator

A tab can have `indicator`, a StatusIndicator spec `{ form?, status?, count?,
max? }`. It shows in that tab's own button. The whole-control `indicator` is a
different setting. A tab with `enabled = false` stays in the strip, but no
route selects it: a press, shoulder navigation and the collapsed menu skip or
refuse it. A malformed tab indicator causes an error that names `indicator`.

A tab with an `icon` and a `badge` shows the badge on the icon's top corner.
When the tab also shows its label, the gap between the icon and the label
grows to hold the half of the badge that sticks out past the icon. Thus the
badge never covers the label.

`textSize` defaults to `fit`. In a bottom bar each tab gets an equal share of
the width, and its words shrink from the `control` type size toward the
`caption` size to fit that share before the engine truncates them. The control
measures the words at the control size. A number or a readable number sets a
fixed size. Bottom tab captions stay inside their allocated space beside
or below the icon. A label that cannot fit uses the native end ellipsis.

`labelPlacement = "belowIcon"` puts the label below the icon in a bottom bar.
The bar reserves the icon, one text line, the theme gap and vertical padding.
Tabs keep equal targets and the badge stays at the icon's corner. The default,
`"besideIcon"`, keeps the horizontal presentation. A sidebar or top bar keeps
its horizontal presentation. Use `belowIcon` for phone destination tabs.

`track = "floating"` gives a bottom bar side and bottom margins, an opaque
track and its own corner radius. In a sidebar it gives the rail side, top and
bottom margins. The tabs use the track's rectangle. Page content and bottom
Toast reservations include the bottom margin. `track = "automatic"` or an
absent option keeps the existing layout. The floating track height is a minimum:
larger text can increase it so the icon and label fit.

`indicator = "mark"` removes the selected button fill. In a bottom bar it
shows a small mark above the icon. `indicatorPlacement = "belowIcon"` moves
it below the icon; `"aboveIcon"` is the default. `"inset"` puts the selection
inside the tab target. A sidebar always uses an inset selection. A tab without
an icon also uses the inset selection. Top bars keep their underline.
`indicator = "none"` still hides the selection paint.

The following numeric theme metrics are in `metrics.controls`. Lengths are
layout units. A radius of zero gives square corners.
