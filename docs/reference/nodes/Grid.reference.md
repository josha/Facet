### Grid

<!-- aliases: Grid | grid -->

`UI.Grid(spec) -> Frame` puts its children in a `UIGridLayout`. `columns` is
a whole number, 1 or more. The grid divides its width into
that number of cells. `minCellWidth` is a pixel width that scales with the
display. With it, the grid shows as many columns as fit at that width or more,
and `columns` is optional and is the most columns. Use it for tiles in a
panel whose width you do not know. A Grid needs `columns` or `minCellWidth`. Each cell gets its share of the gaps, rounded up to a
whole pixel, so a full row always fits the width. `gap` spaces the cells on both axes, and `rowGap`
replaces the vertical space. `cellHeight` is the cell height in pixels. The
default is the regular control height of the theme package. A grid that sets no
`cellHeight` and no `aspectRatio` gives each cell the height of its tallest
Card or hugging stack, and at least the control height, so its children do
not overlap. A grid of Buttons keeps the control height. A child is as wide as its cell: the
grid turns off the horizontal hug of a child, so its content wraps or
truncates and does not go past the cell. `aspectRatio` adds
a `UIAspectRatioConstraint` to the grid layout, which sets the cell height
from the cell width. `align` (`start`, `center` or `end`) aligns the cells
horizontally. The grid fills the width and hugs the height by default.
`flow = "column"` fills each column from top to bottom before the next column.
The grid keeps `columns` columns and sets the rows from the number of children,
so a new child moves the others to keep the columns even. The default is
`flow = "row"`.
