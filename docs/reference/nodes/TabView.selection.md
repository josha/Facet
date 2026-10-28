# TabView.selection

TabView requires a writable `selection` that names a declared tab. It also
requires `tabs` with unique `{ id, label, content }` entries. Tabs can be a
plain array or a readable. `content` is a factory that returns native content.

A bottom bar (with its `aboveBar` accessory) sets the `FacetInsetBottom`
attribute on its layer while it shows, so a bottom Toast docks above it.

By default, Compose `LayerStack` keeps the visited content
(`retention = "all"`). Use `retention = "top"` to dispose departing pages after
their transition. Keep durable page state in the model.

An automatic placement follows `adaptive.navPlacement` of the TabView's own
size, the preferred input, the display size and ten-foot viewing: a TV takes a
top bar, a compact width a bottom bar in the thumb zone, a short height the
compact bottom bar, a pointer a sidebar, and a roomy touch screen or a gamepad
on a larger display a top bar. A TabView inside another TabView's page keeps a
top bar.

Use `style = "sidebarAdaptable"` for peer destinations. Its selected tab is a
pill, and its top bar is a segmented strip: the tabs hug their labels, centred
on a track. `sidebarPreference` (`"sidebar"` or `"topBar"`) chooses between the
two roomy homes, except on a ten-foot display, which keeps the top bar.
`sidebarExpanded`, a writable boolean cell, is the ten-foot command that
replaces `expandSidebar()` and `collapseSidebar()`: set it to `true` (from a
Menu or a Button) and a distant screen shows the sidebar; ButtonB while the
selection is in that sidebar sets it back to `false` and the top bar returns,
with the selection kept on its tab. A near screen ignores it and follows
`sidebarPreference`. Page Back keeps ButtonB when the selection is in the page.
`placement` sets an explicit choice. `placement = "none"` hides the
bar and gives the page the whole view. A change to `"none"` slides the bar out
over the theme token `motion.durations.tabChrome`, then the page grows. A change
back from `"none"` slides the bar in. Selection, shoulder navigation and
`selection` changes still work; supply your own route to the other tabs, such
as a Menu. `railWidth`,
`sidebarPreference`, `sections`, accessories and
`customization = { order, hidden }` refine the presentation. Required tabs
cannot be hidden.

A sidebar is as wide as its widest tab label plus the tab padding and icon, and
its labels are centred. Before the labels are measured it is 20 percent of the
TabView width, from 200 to 280 pixels. A bound `railWidth` can return `nil`
to restore this default. `railWidth` sets the width and aligns
the labels to the leading edge. The tabs of a top bar are centred in it.

`onChange(id)` reports a user selection. A programmatic selection change does
not look like user input. The control owns scroll and focus restoration and
shoulder navigation.

Use `transition.apply` for a custom page entrance and exit. See
[Custom-transitions](Custom-transitions.md). Default fades keep incoming
content interactive; custom transitions enable it when the presentation rests.
