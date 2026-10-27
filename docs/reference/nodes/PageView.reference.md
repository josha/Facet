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
scrollers so the native ScrollingFrame can handle the swipe. Vertical contacts
stay with the list. The original scroller state returns after release, cancel,
focus loss or owner cleanup. Interactive card content uses the same policy.

`autoAdvanceSeconds = 20` advances to the next page every 20 seconds and wraps
after the last page. Give a readable that returns nil to pause an inactive
carousel. The interval restarts after a manual selection or a pause. Hovering,
holding a contact, or focusing a control inside a page pauses automatic advance.
After release, the pause lasts for `motion.durations.scrollReveal` before the
interval restarts (0.25 seconds in Neutral).
Compose owns the scheduled work and cancels it when PageView ends. Omit the
option for manual navigation only. The interval must be finite and positive.
A retained PageView restores its selected page without animation when its
ancestors become available again. Selection changes while hidden wait until
the page is available. Returning to a page does not reset its selection.

The indicators are a row of dots, one button per page, named by the page id.
The current page's dot is painted in the accent colour. Each dot's accessible
name is `Page n of m`. `indicators = false` hides them.
Use `indicatorPlacement = "overlay"` to place the dots inside the lower edge
of the page. The default is `"footer"`. Overlay dots use compact inline targets,
24 pixels wide and at least 44 pixels high with the default theme. Each target
remains separate. They do not reserve a row below the page. Leave space in page
content for them.

While the selection is on a control in a page, Left and Right (and the D-pad
Left and Right) page back and forward. The selection then moves into the new
page. Up and Down leave the pages.

Facet's horizontal VirtualList owns native scrolling.
The page follows a held touch directly. Snapping waits until all contacts end,
including contacts that start on a child button. A vertical gesture can scroll
the surrounding page. The model selection changes when a page reaches its
boundary. Release moves at most one page from the start page. The start page is
the page nearest the view when the contact starts. During a programmatic scroll,
this page can be different from the selection. A quick flick uses its release
direction. A slow drag past half a page moves in the drag direction. A shorter
drag returns to the start page. Release uses the theme's
`motion.springs.control` spring. A new contact stops that spring at its current
position. Previous, Next, dots and arrow keys use the shared scroll reveal
motion. Reduced motion lands without animation. A new contact cancels a
programmatic scroll. Resize and return from a hidden ancestor restore the
selected page without animation. Keyboard focus moves after the new page
lands, and a page with no interactive child remains a navigation target.
