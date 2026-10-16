### Grid

`UI.Grid(spec) -> Frame` puts its children in a `UIGridLayout`. `columns` is
required. It must be a whole number, 1 or more. The grid divides its width into
that number of cells. Each cell gets its share of the gaps, rounded up to a
whole pixel, so a full row always fits the width. `gap` spaces the cells on both axes, and `rowGap`
replaces the vertical space. `cellHeight` is the cell height in pixels. The
default is the regular control height of the theme package. `aspectRatio` adds
a `UIAspectRatioConstraint` to the grid layout, which sets the cell height
from the cell width. `align` (`start`, `center` or `end`) aligns the cells
horizontally. The grid fills the width and hugs the height by default.
`flow = "column"` fills each column from top to bottom before the next column.
The grid keeps `columns` columns and sets the rows from the number of children,
so a new child moves the others to keep the columns even. The default is
`flow = "row"`.
