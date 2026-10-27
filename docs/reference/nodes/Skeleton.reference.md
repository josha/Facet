# Skeleton

Skeleton.reference option values and behavior.

The parent owns loading state and replaces or removes the placeholder when
loading finishes. Shimmer follows the theme motion preference; the Compose
owner releases its animation when the placeholder unmounts. Provide a visible
loading label when the task needs one. A Skeleton does not report an error
or an accepted result.

| Control | Main contract |
|---|---|
| `Skeleton` | A loading placeholder with a configurable form and line count. `corners` rounds a box or a line: `square`, a number of pixels, `control` (or `rounded`) and `panel` for the radii of the theme, or `pill`. A circle refuses `corners`. |
