# NavigationStack.motion

A push slides the new page in from the trailing edge. The covered page moves
30 percent to the leading edge and dims. The covered page keeps its full
width, so its controls do not change size. A pop plays the reverse. The popped
page stays until motion completes, without input or selection. While a page
moves, each page borrows the background color of the nearest ancestor whose
`BackgroundTransparency` is less than 1, when one exists, and paints it
opaquely. A separate black shade frame dims the covered page from 0 to 0.1 opacity. The page
content does not change its transparency. At rest, the pages are transparent. A stack that fills its ScreenGui does not
clip the moving pages, so a Screen `surface` stays on the glass while the page
slides. The default motion is a critically damped Compose
spring. `transition = { seconds, ease }` replaces the slide with a crossfade
that uses those Compose tween options.
`transition = false` disables motion. The pages that are present when the
stack mounts show without motion.

When every ancestor has a fully transparent background, transparent page
content can leave the covered page visible during a slide. An image in a sibling ScreenGui does not supply that
ancestor. For a deliberate slide, give the moving page an opaque surface.
For a stationary change over shared scene art, use `transition = false`;
history, Back and focus restoration still work. A crossfade can also show both
sets of content at once, so inspect the middle of the transition.

Set theme `metrics.motion.distances.parallax = 0` to keep covered pages still
while the front page slides. It affects all default stacks in that theme.
See [Tasks.theme](Tasks.theme.md).

`transition = { scale = true }` zooms a plate behind the page, not its text.
See [Custom-transitions](Custom-transitions.md) for `apply` and reduced motion.
