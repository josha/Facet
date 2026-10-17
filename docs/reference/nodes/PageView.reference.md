### PageView

<!-- aliases: PageView | pageview -->

PageView requires a writable `selection` and `pages` with unique ids and
content factories. It supplies page navigation, indicators, and previous and
next actions. Use it for a sequential set of peer pages. TabView is for named
destinations. NavigationStack is for a drill-down path.

`scrollWheel = true` opts into native mouse-wheel paging. It is off by default
so a PageView can sit inside a vertically scrolling page. This option can be
bound. Touch swipes, indicators and keyboard navigation remain available.

A horizontal touch inside a page temporarily releases input from enclosing
scrollers so the native page layout can handle the swipe. Vertical contacts
stay with the list. The original scroller state returns after release, cancel,
focus loss or owner cleanup. Interactive card content uses the same policy.

`autoAdvanceSeconds = 20` advances to the next page every20 seconds and wraps
after the last page. Give a readable that returns nil to pause an inactive
carousel. The interval restarts after a manual selection or a pause. Hovering,
holding a contact, or focusing a control inside a page pauses automatic advance.
Compose owns the scheduled work and cancels it when PageView ends. Omit the
option for manual navigation only. The interval must be finite and positive.
A retained PageView restores its selected page without animation when its
ancestors become available again. Selection changes while hidden wait until
the page is available. Returning to a page does not reset its selection.

The indicators are a row of dots, one button per page, named by the page id.
The current page's dot is painted in the accent colour. Each dot's accessible
name is `Page n of m`. `indicators = false` hides them.

While the selection is on a control in a page, Left and Right (and the D-pad
Left and Right) page back and forward. The selection then moves into the new
page. Up and Down leave the pages.

The native `UIPageLayout` moves between pages over 0.3 seconds, Cubic Out, with
no overshoot, for Previous, Next, a dot and the arrow keys. A swipe released
faster than 1200 pixels a second settles with Quint Out (`styles.fling`)
instead, which decelerates harder and never overshoots.
