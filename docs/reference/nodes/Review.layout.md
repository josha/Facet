# Review.layout

Review rules for parts that collide or that leave the Facet layout.

| Rule | Finds |
|---|---|
| `overlapping-text` | Two different texts whose glyphs cover each other by a fifth or more of the smaller text. High. A text that is hidden by a clip, or under an opaque plate or image such as the next card of a fanned hand, does not count. |
| `covered-text` | A text with half or more of its glyphs under a plate or an image from another part, such as a banner that is wider than its slot. A cover that hides three or more texts is an overlay and does not count. A stack with a negative `gap` is a fan and does not count. |
| `escaped-text` | A text whose glyphs run past the edge of the plate or the image that it sits on, or that a clip cuts. A scrolling view does not count as a clip. An image counts only when it is built beside the text, within three levels. A text that still sits inside a larger plate does not count. |
| `native-text` | Three or more texts that are native labels and not `UI.Text`. They miss the type roles of the theme, the text size of the player and the ten-foot scale. |

For `floating-text`, an image that covers a quarter of the screen or more,
such as a Screen `ground`, counts as a plate.

The rules read the rectangle of each part. They do not read pixels. A label
on the transparent margin of an image, or over the edge of a shape that is
painted inside its image, is not found; look at the capture. A part that is
turned by a quarter turn is read at its turned rectangle. A part at another
angle is not used as a cover or as a backing.

The layers of a ZStack do not make room for each other, and a child that is
wider than its slot in a stack runs over its neighbor. Put the parts that must
not cover each other in one stack.

Back to [Review](Review.md).
