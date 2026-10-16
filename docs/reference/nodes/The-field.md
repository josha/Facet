#### The field

The field is the `Field` plate in the field chrome. When the preferred input
is keyboard and mouse, the field holds a native TextBox named `Entry`.
Otherwise, it holds a button named `Show`. The calendar button `Open` is 44
pixels wide, inside the plate at its trailing edge, with no plate of its own.
The plate is 44 pixels tall, or the `controlSize` height. `Entry`, `Show` and
`Open` take the plate's full height, so no part paints outside it at any
size. `Show` and `Open` fill the plate from edge to edge, share its corners,
and the plate clips their hover and press highlights. `Show` reads in the
`body` text role, the same as `Entry`.

`Entry` takes the numeric form of the locale when focus leaves it. A year has
four digits. A typed range is two dates with " – " or " - " between them. If
the text is not a date, or the day is not available, the text stays. The field
shows the error in the message line and adds the `facet-invalid` tag to the
plate. Nothing commits. An empty text proposes an empty value.

The panel opens below the field, aligned to its leading edge. If there is not
sufficient room below, the panel opens above the field. The panel stays 8
pixels from the screen edges. The `CalendarSurface` ScrollingFrame holds the
calendar. A skinned theme's panel carve (`chrome.panel.contentInsets`) is added
around the calendar, so the art never covers it. The surface is never taller
than the screen, so a tall calendar scrolls. On a touch screen narrower than 600 pixels, the
panel is a sheet at the bottom of the screen with a Done button. On a ten-foot
screen, the panel is a sheet at the center of the screen. The panel is a native
modal. A tap outside the panel, B or Escape closes it. When it closes, the
selection returns to the control that had it before.
