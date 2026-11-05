### ScrollView

<!-- aliases: ScrollView | scrollview -->

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
`align`, `distribute`, `width`, `height`, `maxWidth` and `maxHeight`.

Set `height = "hug"` with `maxHeight` to grow the window with its content up
to a limit, then scroll the remaining content. An empty window has zero height
unless padding, a native minimum size or other authored properties add space.
The maximum dimensions accept bound finite numbers of pixels, zero or more.
An omitted maximum leaves that axis unbounded. Facet uses one native
`UISizeConstraint` for both limits and keeps `AutomaticSize` and
`AutomaticCanvasSize`. A maximum does not change the default fill sizing.
Set the cap from the room available in the parent when it must follow a device
resize. Use content with a natural height on the hugging axis.

For example, this panel fills its parent width up to 360 pixels and hugs rows
up to 240 pixels high. These limits assume that much room is available:

```luau
UI.ScrollView "Rows" {
    width = "fill", height = "hug", maxWidth = 360, maxHeight = 240,
    gap = "s",
    table.unpack(rows),
}
```

A ScrollingFrame clips its canvas. When the theme's panel or control plates
draw past their bounds, through a `chrome` shadow or a theme rule's `UIStroke`,
the ScrollView adds that reach to its padding on every side, so a plate at the
canvas edge keeps its glow and edge. A Collection of cards does the same. The
neutral theme draws nothing past its plates and adds no padding.

The native `Active` property defaults to true, so scrolling input does not
reach 3D controls behind a SurfaceGui. An authored `Active` value takes priority.

An authored initial `CanvasPosition` is retried when native canvas and window
bounds arrive. This also applies to virtual collections. After the engine
accepts the requested offset, later layout changes do not restore it. Touch,
mouse press or mouse wheel input cancels a pending initial request.

A ScrollView is a gamepad selection stop only while it holds no visible
selectable descendant, so a directional move from a control inside it goes to
the next control. A ScrollView of read-only content stays selectable so a
gamepad can scroll it. An authored `Selectable` overrides this.
