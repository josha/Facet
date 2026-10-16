### ErrorBoundary

<!-- aliases: ErrorBoundary | errorboundary -->

`UI.ErrorBoundary(spec) -> Frame` contains a failure in the region that it
builds. `view()` builds the region. `fallback(failure, retry)` builds the
content that replaces the region after a failure. Both are required.

- A failure in `view` when the boundary mounts, or in a later Compose update
  inside the region, disposes the region and shows the fallback. Siblings
  outside the boundary stay. The code that wrote the cell that caused the
  failure does not see an error.
- The boundary reports each failure once. `onError(failure)` receives it. If you
  do not set `onError`, the factory `onError` option receives it. The
  `FacetError` attribute of the frame holds the failure text.
- Call `retry()` to build the view again. A successful retry clears
  `FacetError`.
- A failure in the fallback is not contained.
- `width` and `height` take `fill`, `hug` or pixels. The default is `hug` on
  both axes.

The boundary uses `Compose.boundary`. A failure outside every boundary stays a
hard error.
