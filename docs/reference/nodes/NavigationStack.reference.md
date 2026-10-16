### NavigationStack

<!-- aliases: NavigationStack | navigationstack -->

NavigationStack requires a writable `path`, `root` and `destinations`. The path
is an array of `{ id, value }` entries. `root` and each `destinations[id]` are
`{ title, content }`. Destination content receives the entry.

- To push, append an entry.
- To pop, remove the last entry.

`backLabel` sets the text of the native Back chrome. Compose `LayerStack` owns
the retained pages and their disposal.

Set `chrome = "hidden"` on a destination when that page owns its header.
The page uses the full stack rectangle, with no stack title or Back bar.
Set it on the stack to use this default for all pages, including the root.
A destination's `chrome = "automatic"` overrides the stack default.
Both settings can be readables. An absent option keeps the current behaviour,
including the Back bar above an untitled child page. The root never has a
stack Back command.

Hidden chrome keeps route history, page motion, Escape, gamepad B and selection
restoration. On touch, a one-finger right swipe from the left edge goes
Back. The edge is `metrics.controls.navigationBack.swipeEdge` (24 layout units
in the neutral theme). A captured drag does not trigger this Back gesture.
Give the page a visible Back button that removes the last entry from `path`,
so mouse and touch players also have a clear command. Do not replace the stack
with a separate route or transition owner.

```lua
destinations.match = {
    chrome = "hidden",
    content = matchPage,
}
```

The navigation bar title is inset on both sides by the control's horizontal
padding (`controlSizes.regular.paddingX`), so a root page's leading title
lines up with the Back label of the pages above it.

A push slides the new page in from the trailing edge. The covered page moves
30 percent to the leading edge and dims. The covered page keeps its full
width, so its controls do not change size. A pop plays the reverse. The popped
page stays until its motion completes. It cannot be interacted with, and it
cannot hold the selection. While a page moves, both pages are opaque. Each page
gets the background color of the nearest opaque container of the stack. A
separate black shade frame dims the covered page from 0 to 0.1 opacity. The page
content does not change its transparency. At rest, the pages are transparent. The default motion is a critically damped Compose
spring. `transition = { seconds, ease }` replaces the slide with a crossfade
that uses those Compose tween options.
`transition = false` disables motion. The pages that are present when the
stack mounts show without motion.
