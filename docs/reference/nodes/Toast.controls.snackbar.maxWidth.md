# Toast.controls.snackbar.maxWidth

One row shows and up to eight wait. Readable time pauses while the row is
hovered or selected, or while a modal is open. Queued time does not count.
The row uses `controls.snackbar.maxWidth`, bounded by the layer, and docks
16 pixels above the app's reserved bottom chrome (a TabView bottom bar, an
affixed Notice; its own reservation does not count). The action
moves below long text. Arrival never takes the selection, and one Down from
the control that had it reaches the row. Cancel (Escape or the B button) on a
selected row proposes or retires with `cancel` and returns the selection to
the content, also when the caller refuses. The Down link from the control that had the selection lasts
until the selection moves anywhere else; an action toast still stays until it
is closed when it has no `duration`, as the snackbar did. A visible row sets the
`FacetInsetBottom` attribute on its layer until it has slid out, so a bottom
stack of display-only toasts docks above it. The row is a Frame named `Snack`
at `ZIndex` 60. It slides up and fades in to enter, and slides down and fades
out to leave. A leaving row cannot be interacted with. Under reduced motion it
arrives and leaves at once. There is no swipe.

The anchor carries `ToastVisible` and `ToastQueued` attributes.

`app.presentToast(component, options?) -> { id, dismiss() }` shows
`component(app.UI)` as a toast in the app's toast ScreenGui (named from
`name`, `FacetToasts` by default), which all its toasts share, so they stack
and queue together. `options` takes the keys
above except `message` and `content`. `dismiss()` retires it with `manual`
and returns false when it has already gone. The toast's mount stops when it
retires.
