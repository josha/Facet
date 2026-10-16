# Sheet.drag

Native drag detection resizes the sheet. The grabber detector starts a drag at
once. A second detector on the panel starts a drag only after 6 pixels, or 14
pixels on touch. A release goes to the detent nearest to the released height
plus 0.15 seconds of its velocity. A hold before the release has no velocity.
Below the lowest detent the whole sheet moves down instead of getting shorter,
so the header, the body and the pinned actions move together. A drag below 70
percent of the lowest detent dismisses the sheet, and the exit slide starts
where the drag left it. Past the
limits the drag resists. `interactiveDismissDisabled` holds the sheet near its
lowest detent and blocks Back and the backdrop. An outside detent change
during a drag ends the drag. Only one drag runs at a time.

The grabber sits on the edge that the sheet came from. A bottom or center
sheet has a horizontal bar at the top. A side sheet from the right has a
vertical bar on its left edge, and a side sheet from the left has one on its
right edge. The grabber sits in its own gutter at that edge, just inside the inner edge
of the theme's panel art (`contentInsets`), centred along the edge. The
content reserves only the gutter, 20 pixels plus an 8 pixel gap, on that side
and keeps equal padding on the other sides. Sheet adds its normal content
spacing inside the theme's panel art insets. The header, body and actions use
this same boundary, including when `contentInset = "none"` removes the body's
extra padding. On a side sheet,
a drag of the grabber toward the sheet's edge moves the whole sheet. A release
past a third of the width, or faster than 600 pixels a second, closes it.
Otherwise it slides back.
