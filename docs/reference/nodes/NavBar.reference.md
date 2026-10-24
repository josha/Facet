### NavBar

<!-- aliases: NavBar | navbar -->

`UI.NavBar` returns the bar Frame: `{ onBack?, backLabel?, title?, titleSize?, leading?, center?, trailing?, gap?, padding?, surface? }`.

`UI.NavBar` returns the bar Frame: `{ onBack?, backLabel?, title?, titleSize?,
leading?, center?, trailing?, gap?, padding?, surface? }`. `surface` paints a
background plate: `surface`, `panel` or `pane`, the theme roles of the same
names.

The first row holds Back, `leading` and a `center` that fills the remaining
width. Without `center`, the title shows on one line and truncates. `trailing`
is one GuiObject. Put a cluster in a Frame. The title and the trailing node
stay on one row when the full title fits beside the trailing node. When the
full title does not fit, the trailing node moves to a second row. If the
trailing cluster is wider than the bar, it scrolls horizontally. Its first
action stays inside the bar, and later actions are available by scrolling. Without a
title, the bar uses `controls.popup.panelWidth` as the minimum center width. The
center is not rebuilt, so a search field keeps its text. Back shows the
`chevron.leading` icon beside its word, half a `space.xs` apart, in the
content colour with no plate (`utility`), and a `space.s` gap keeps the title
away from it. NavigationStack's Back and the Back row of a sheet menu are the
same control. `gap` and `padding` are pixels or `space` metric
names.

`onBack` is a function, or a writable boolean cell. With a cell, Back and its
gap show only while the cell is `true`, and Back writes `false`. Use a cell
when another control owns Back, such as the `compactBack` cell of a
NavigationSplitView. A hidden Back does not take room from the title.
