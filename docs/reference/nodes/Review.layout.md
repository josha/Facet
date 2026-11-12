# Review.layout

Review rules for parts that collide or that leave the Facet layout.

| Rule | Finds |
|---|---|
| `overlapping-text` | Two different texts whose glyphs cover each other by a fifth or more of the smaller text. High. A text that is hidden by a clip, or under an opaque plate or image such as the next card of a fanned hand, does not count. |
| `offscreen-text` | A text with less than half of its glyphs on the screen, while the stack that holds it is on the screen. High. A text inside a clip or a scrolling view does not count, and neither does a text whose holder is itself off the screen, such as a panel that waits beside the screen. |
| `covered-text` | A text with half or more of its glyphs under a plate or the paint of an image from another part, such as a banner that is wider than its slot. A cover that hides three or more texts is an overlay and does not count. A stack with a negative `gap` is a fan and does not count. |
| `escaped-text` | A text whose glyphs run past the edge of the plate or the paint of the image that it sits on, or that a clip cuts. A scrolling view does not count as a clip. An image counts only when it is built beside the text, within three levels. A text that still sits inside a larger plate does not count. |
| `native-text` | Three or more texts that are native labels and not `UI.Text`. They miss the type roles of the theme, the text size of the player and the ten-foot scale. |
| `oversized-target` | Buttons that are taller or wider than the scroll view that holds them, so no scroll position shows one whole. One finding for each scroll view, with the count, the size and the room. |

For `floating-text`, an image counts as a plate when its paint is under the
text, or when it covers a quarter of the screen or more, such as a Screen
`ground`.

For an image, the rules use its painted bounds: the smallest rectangle that
holds its pixels of alpha 0.1 or more. `paintRect` on `UI.Image` declares
them. Without it, `review.collect` reads the pixels in Studio, one time for
each asset, and can yield. Studio reads only an image that the Studio user or
the experience owner can load. For other images, and outside Studio, the
rules use the rectangle of the part; declare `paintRect` there. An image with
no such pixel is not a cover or a backing. An image as large as 35% of the
screen is a ground or an overlay whatever its paint.

`review.paintRect(image) -> ImagePaintRect?` reads the painted bounds and the
pixel size of an image in Studio, in the form that `paintRect` takes. It can
yield. It returns nil outside Studio and for an image that Studio cannot
read. The art of a stack `ground` counts as built beside the texts of that
stack, and `escaped-text` always measures those texts against its paint.
The art of a theme skin counts as built in the part that wears the skin.

A text sits on the paint when half or more of its glyphs are over the painted
bounds. `escaped-text` then uses the edge of the paint. A text that is mostly
on the transparent margin, such as a count in the corner of a subject, is
measured against the rectangle. The painted bounds are a rectangle: a hole in
the paint, such as the middle of a frame, counts as paint; look at the
capture. A part that is turned by a quarter turn is read at its turned
rectangle. A part at another angle is not used as a cover or as a backing.

The layers of a ZStack do not make room for each other, and a child that is
wider than its slot in a stack runs over its neighbor. Put the parts that must
not cover each other in one stack.

When a report has medium findings, `text` ends its list with their count and
says what a new interface owes them: a repair, or a noted reason to keep the
design.

Back to [Review](Review.md).
