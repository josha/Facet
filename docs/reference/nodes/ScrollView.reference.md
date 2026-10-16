### ScrollView

`UI.ScrollView(spec) -> ScrollingFrame` scrolls its children. It fills its
parent by default. It contains a `UIListLayout` and sets `AutomaticCanvasSize`
and `ScrollingDirection` for its axis. Thus the content fits the scroll window
beside the scroll bar. `axis` is `"y"` (the default), `"x"` or `"xy"`. The
`"x"` axis stacks the children horizontally and, unless you give a `height`,
hugs their height, so a row of chips never clips when they grow at ten feet.
When the row overflows, its automatic height also reserves space for the
native horizontal scroll bar. The scroll bar shows that more choices are
available. An authored size constraint keeps its authority.
When a child passed in the props has a Scale height (`height = "fill"`), the
ScrollView fills its parent's height because a hugging
frame would give that child no height.
On a vertical scroll axis, a direct fill-height vertical stack uses the window
height as its minimum. Its native `AutomaticSize` includes Y, and its
`UIFlexItem` can grow but cannot shrink the stack to hide overflow. Content
that needs more height expands the canvas. A nested scrolling control keeps
its own viewport and scroll range. At a touch scroll boundary, a nested Facet
scrolling control yields the rest of the swipe to the nearest enabled ancestor
that can scroll in that direction. This also applies to virtual collections,
table bodies and overlay content. The inner control becomes available again
when the touch ends. A disabled scroll ancestor blocks the handoff. Mouse wheel
scrolling uses the native engine behavior.
Options: `axis`, `gap`, `padding`,
`align`, `distribute`, `width` and `height`.

The native `Active` property defaults to true, so scrolling input does not
reach 3D controls behind a SurfaceGui. An authored `Active` value takes priority.

An authored initial `CanvasPosition` is retried when native canvas and window
bounds arrive. This also applies to virtual collections. After the engine
accepts the requested offset, later layout changes do not restore it. Touch,
mouse press or mouse wheel input cancels a pending initial request.
