# Table.sort

When `sort` changes, Table returns the body to the top. If a selected row is
in the new order, Table scrolls the minimum distance to show the whole row.
With multiple selected rows, Table uses the first selected row in the new
order. VirtualList, VirtualGrid and Outline keep their native anchor policy.

`from`, `key` and `columns` define the rows. `key` has the same forms as for
VirtualList. A column has:

- `id` and `label`,
- an optional pixel `width` (otherwise flex),
- `align = "start"`, `"center"` or `"end"` for the heading and value text,
- `minWidth` (48) and `maxWidth` (1e6),
- `resizable` and `sortable` (both true),
- `value(item)` or `render(current, placement, key)`,
- `wrap = false` to truncate, or `wrap = true` to allow wrapping. Without
  `wrap`, the input policy selects wrapping,
- `detailRender(current, placement, key)` for an interactive value in Details.

A column collapses only when it has a numeric `priority`. Larger values
collapse first. The first column always stays visible. A flexible first
column gets space for its full text before other flexible columns get extra
space. Selection, reorder and row action columns keep their fixed widths.
The other columns keep their `minWidth`. Columns without a numeric priority stay visible; a narrow table
can scroll sideways. This minimum also applies under touch and
gamepad input. A Popover shows collapsed and natively truncated values through
the row's icon-only `status.info` button, named "Show details". Row commands
keep their separate `more` (…) button. The cell
state stays retained. `detailRender` receives the same item, placement and key
as `render`. Keep durable value state in the model and share it between the
cell and Details. Without `detailRender`, Details shows the full text value.
The header band spans the whole row, edit controls
included, and shows a hairline divider between headings; the headings sit over
their columns. With a persistent vertical scrollbar, the header background
continues over the scrollbar gutter to align the outside edges. Resize
requests use layout pixels even when an ancestor scales the table.
