# A rect read at pointer-down is a lie by the next frame — and the wrong SPACE from the start

**Found:** 2026-07-29, from a device report (iPhone 15 Pro, gallery example 02 under
Pixel Quest): *"When I go to edit mode and pick up a row, it doesn't always appear
under my finger — the picked up chip moves up as I scroll down."*

Table's reorder drag did its whole pointer→table mapping against rects captured
**once**, in `onPointerDown`, from the lookup the renderer handed authored pointer
handlers:

```lua
rowDrag = { bodyTop = bodyRect.y, bodyRel = bodyRect.y - rootRect.y, rootRect = rootRect }
-- ...every move, for the rest of the gesture:
ghostY:set(pos.y - rowDrag.rootRect.y - 13)
```

Two independent mistakes, either one enough to break it, both live at once:

**1. Wrong space.** `pos` always arrives in WINDOW space. That lookup was
`controller.rectOf` — the SOLVED rect, which inside a scroll host is CANVAS space
(the engine shifts it by `CanvasPosition`). The shipped example makes the page the
scroller and the Table a **block** (`scrolls = false`), so the table root's solved
rect never moves while the page does. Every ghost/drop-line/drop-verdict was off by
the page's scroll offset.

**2. Stale.** Even in the right space, a rect read at pickup describes where the
table **was**. On touch, the very gesture that drags the ≡ handle also pans the
ancestor `ScrollingFrame` — so the table travels underneath a live capture, every
frame, by design.

The arithmetic makes the double-count visible. With ghost painted at
`rootScreen + ghostY` and `ghostY = pos.y - rootSolved`, the chip lands at
`pos.y - scroll`. In the recording the finger moved up ~117px while the page
scrolled ~120px, and the chip moved ~237px — twice the content, exactly as
predicted.

**Rules:**

- A rect that will be compared against a POINTER is `screenRectOf`, never `rectOf`.
  The renderer now hands authored `onPointerDown/Move/Up` that lookup, so the
  handler cannot get this wrong by default.
- **Ask the lookup again every move.** Store the *closure*, never its answer. Keep
  the pickup-frame rects only as the fallback for a path that stops resolving
  mid-drag.
- Rects used as pure DIFFERENCES (Table's resize guide: `cellRect.x - rootRect.x`)
  or for `w`/`h` alone are space-agnostic — the shift is common to both terms.

**Why it survived a green suite:** every drag test put the table at the screen root.
Nothing was inside a scroll host, so canvas space and window space were the same
number and both bugs were invisible. The regression rows
(`tests/table_input.spec.luau` §5) put a block Table inside a `ScrollView`, scroll
the page mid-drag, and assert against `controller.screenRectOf` — i.e. where the
node is actually painted.

**Prior art in this repo, ignored:** `VirtualList`'s `hostScreenRect()` already
preferred `screenRectOf` and already re-read it per move, with a comment saying "the
same correction Table's reorder makes". Table did not make it. And ESC-2 in
`artifacts/sponsor-framework-gaps/responsibility-ledger.md` had already named the
exact defect — deferred on "no current consumer drags mid-slide", which weighed the
presentation half of the shift and never asked about the scroll half.

See also:
- `docs/lessons/proxy-surfaces-must-speak-the-registry-coordinate-space.md` — the
  same family: two coordinate spaces that agree until they don't.
- `docs/lessons/a-scroll-container-clips-to-itself.md`
