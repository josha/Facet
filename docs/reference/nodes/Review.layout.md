# Review.layout

Review rules for parts that collide or that leave the Facet layout.

| Rule | Finds |
|---|---|
| `overlapping-text` | Two different texts whose glyphs cover each other by a fifth or more of the smaller text. High. A text hidden by a clip, or under an opaque plate or image, does not count. |
| `offscreen-text` | A text with less than half of its glyphs on the screen, while the stack that holds it is on the screen. High. A text inside a clip or a scrolling view does not count, and neither does a text whose holder is off the screen. |
| `cut-at-edge` | A text (high) or a control (medium) that crosses the edge of the screen by 4 pixels or more, outside a clip. A plate (medium) counts when the edge cuts 15 percent or more of it along an axis where it is at most half the screen, also when its text stays on the screen. |
| `touching-controls` | A control whose stroke or shadow, drawn outside its box, reaches the control beside it. Medium. |
| `collapsed-text` | A text that is 0 pixels wide inside a holder that is on the screen. High. Its holder hugs its content, and the content waits for a width from the holder. A text in a part that is closed to no size does not count. |
| `covered-control` | A control with a tenth to nine tenths of its box under a plate or an image of another part that is drawn above it. Medium. A control under a modal, wholly under a part, in a scrolling view or in a fan does not count, and neither does a cover smaller than half of the control. |
| `covered-text` | A text with half or more of its glyphs under a plate or the paint of an image from another part. An overlay that hides three or more texts and a fan (a stack with a negative `gap`) do not count. |
| `escaped-text` | A text whose glyphs run past the edge of the plate, the outlined box (a visible stroke on a box without fill) or the paint of the image that it sits on, or that a clip cuts. A scrolling view does not count as a clip. An image counts only when it is built beside the text, within three levels. A text that still sits inside a larger plate does not count. |
| `native-text` | Three or more texts that are native labels and not `UI.Text`. They miss the type roles of the theme, the text size of the player and the ten-foot scale. |
| `oversized-target` | Buttons taller or wider than the scroll view that holds them, so no scroll position shows one whole. One finding for each scroll view. |

For `floating-text`, an image counts as a plate when its paint is under the
text, or when it covers a quarter of the screen or more, such as a Screen
`ground`.

For an image, the rules use its painted bounds. See
[Review.paint](Review.paint.md).

When a report has medium findings, `text` ends its list with their count and
says what a new interface owes them: a repair, or a noted reason to keep the
design.

Back to [Review](Review.md).
