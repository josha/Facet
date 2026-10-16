### scrollTo and scrollToVisible

<!-- aliases: scrollTo and scrollToVisible | scrollto-and-scrolltovisible -->

`UI.scrollTo(frame, position, options?) -> boolean` moves a native
`ScrollingFrame` to a position. `position` is `"top"`, `"bottom"`, a `Vector2`
or `{ x?, y? }`. An omitted axis keeps its value. The canvas limits clamp the
position: from 0 to `AbsoluteCanvasSize - AbsoluteWindowSize`. The result is
`false` when the frame does not move.

`UI.scrollToVisible(node, rect?, options?) -> boolean` brings a `GuiObject`
into view. It walks every `ScrollingFrame` ancestor from the inside out. Each
one moves the minimum distance that shows the node, or the `{ x, y, w, h }`
rectangle relative to the node. A node taller or wider than the window aligns
to its start. A frame moves only on the axes that its `ScrollingDirection`
permits. The result is `false` when no frame moves or the node has no scroll
ancestor.

Both calls tween `CanvasPosition` with `TweenService` for 0.25 seconds. A new
call cancels the tween that runs on the same frame. The move is instant when
`options.animated` is `false` or when the motion level is not `"normal"`. Call them from an event, for
example a button that goes back to the top of a page.
