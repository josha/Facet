# Collections.placement

<!-- aliases: CollectionPlacement | Facet.CollectionPlacement -->

`CollectionPlacement` describes a collection slot's layout geometry, not an
Instance or a screen rectangle. `render(current, placement, key)` receives a
readable placement; use it reactively as measurements/order change.

| Field | Meaning |
| --- | --- |
| `index`, `row`, `column` | One-based slot, layout row and column. |
| `offset`, `size` | Main-axis start offset and row extent. A grid row uses its largest item extent. |
| `crossOffset`, `crossSize` | Cross-axis start offset and cell extent. |

Offsets start at zero in the collection content's layout coordinates; extents
and offsets use layout pixels, not absolute screen pixels after UIScale.
The main axis follows `direction`. These values do not include a conversion
to native screen position or the grid's outer padding.

Pass a retained table as `controls` to VirtualList/VirtualGrid. During mount
Compose fills these optional methods:

- `indexOfKey(key) -> number?`: current one-based index, nil if absent.
- `placementOf(index) -> CollectionPlacement`: current geometry snapshot.
  Supply a valid current index; retain neither its index nor its snapshot as
  a reactive record across sorting, filtering or measurements.
- `offsetOf(index, align?, size?) -> number`: desired main-axis scroll offset.
  `align` is `"start"` (default), `"center"` or `"end"`; `size` is the viewport's
  main-axis extent in the same layout units (default 0). The result is clamped
  between zero and content extent minus viewport extent. This calculates an
  offset; it does not scroll by itself.

Read methods from the retained table when calling: a `follow` change can
replace the underlying OrderedCollection. Use handles only during its mounted
lifetime. Fields are not a disposal signal and are not promised to be cleared. This geometry is
distinct from SpatialPlacement footprints and drag/drop insertion slots.
See [collection options](VirtualList-and-VirtualGrid.mode.md).
