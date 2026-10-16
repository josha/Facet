### PageView

<!-- aliases: PageView | pageview -->

PageView requires a writable `selection` and `pages` with unique ids and
content factories. It supplies page navigation, indicators, and previous and
next actions. Use it for a sequential set of peer pages. TabView is for named
destinations. NavigationStack is for a drill-down path.

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
