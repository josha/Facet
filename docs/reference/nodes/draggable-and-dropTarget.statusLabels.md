# draggable-and-dropTarget.statusLabels

Keyboard and gamepad pickup also shows an inert carried-item preview. During a
collection reorder it follows the insertion point, and the original cells stay
empty until the move ends. Edit controls are excluded from the preview.
Failed drops return the preview to
the source with theme-timed travel. Accepted drops shrink the preview at the drop position. Both use the shared Travel engine and skip animation under reduced motion.
Only accepted destinations show the native drop highlight; source-only
collections show no insertion marker.
A shared status label shows Copy or Apply for an accepted target, the
rejection reason for a rejected target, and Waiting for confirmation for a pending
drop. Ordinary pointer moves omit Move; armed input retains it. `statusLabels = false`
hides this text without changing validation, highlights or animations.
The label uses native text layout and theme paint. Pending drops keep their
preview and block a second commit until completion or cancellation.

During a grid reorder, arrows and D-pad move the insertion point in both axes.
Across the grid they advance one position; along the scrolling axis they move to
the nearest position in the next row or column. A short last row preserves the
preferred cross-axis position when moving back. Placement comes from Compose, so
resizing the grid uses its current layout. List and table reorders remain linear.
For a collection that also supports transfers, Y switches between positioning
the insertion point and native navigation to another destination. A drops and
B cancels. The status label shows these controller commands.

`dropTarget` spec:

- `label`: optional destination name shown with the accepted operation.
