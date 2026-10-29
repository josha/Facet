# Custom-transitions.zoom

`zoom` is a number above 0 and at most 1. The page content itself grows from
`zoom` to full size around its center while it fades in, and a leaving page
shrinks back while it fades out, on `easing.zoomScale` and
`durations.zoomPresent`. The content sits in a Frame named `TransitionContent`
with a UIScale named `TransitionZoom`. In a NavigationSplitView only the detail
pane zooms; the sidebar fades. Measure layout that must not change during the
zoom with `environment.layoutSize` ([layoutSize](layoutSize.md)). You cannot use `zoom` with `apply`.

Back to [Custom transitions](Custom-transitions.md).
