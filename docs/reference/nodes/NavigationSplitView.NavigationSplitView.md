# NavigationSplitView.NavigationSplitView

Use `NavigationSplitView` for two related panes. Set `axis = "x"` (the default)
for side-by-side panes or `axis = "y"` for panes stacked top/bottom. Layouts
with enough room on that axis show both panes with a resize divider. Compact
layouts and ten-foot layouts show one pane with
Back and Show detail controls. A gamepad at near viewing distance can use both
panes.

```luau
local first: "sidebar" | "detail" = "sidebar"
local column = Compose.cell(first)
local width = Compose.cell(360)
UI.NavigationSplitView {
    preferredCompactColumn = column,
    sidebarWidth = width,
    sidebar = function() return UI.Button { label = "File" } end,
    detail = function() return UI.Button { label = "Linked file" } end,
    detailLabel = "Linked view",
    backLabel = "Files",
}
```

`sidebar` and `detail` take an Instance or a function that returns an Instance.
Both panes keep their mounted content when the layout collapses or expands.
`detailVisible` defaults to true. Set it to false to remove the detail pane and
let the sidebar fill the control. Keep durable detail state in the model.

`preferredCompactColumn` is an optional writable cell with `"sidebar"` or
`"detail"`. It defaults to `"sidebar"`. Back writes `"sidebar"`; Show detail
writes `"detail"`. Set it to `"detail"` when a selection opens the detail pane.
`backLabel` defaults to `"Back"`; `detailLabel` defaults to `"Show detail"`.

`sidebarWidth` is an optional writable number cell in logical pixels. Its
default is 360. `minSidebarWidth` defaults to 240, `maxSidebarWidth` to 600,
`minDetailWidth` to 320. The available width can reduce the sidebar width.
By default, the control collapses only when both minimum widths and the divider
no longer fit. Set `compactWidth` to collapse at a larger width. Width limits
must be positive finite numbers.

For `axis = "y"`, use `sidebarHeight` instead of `sidebarWidth`. Its default is
240. `minSidebarHeight` defaults to 120, `maxSidebarHeight` to 600,
`minDetailHeight` to 120. Set `compactHeight` to collapse before the minimum
heights and divider no longer fit. These height options follow the same rules
as the width options. The sidebar is the top pane; detail is the
bottom pane. The axis is fixed when the control is constructed.

```luau
UI.NavigationSplitView {
    axis = "y",
    sidebarHeight = Compose.cell(240),
    sidebar = files,
    detail = inbox,
    detailLabel = "Inbox",
}
```
