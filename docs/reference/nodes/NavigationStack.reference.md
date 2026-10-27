### NavigationStack

<!-- aliases: NavigationStack | navigationstack -->

Supply writable `path`, `root` and `destinations`. Path is an array of
`{ id, value }` entries. `root` and each `destinations[id]` are
`{ title, content }`. Destination content receives the entry.

- To push, append an entry.
- To pop, remove the last entry.

Preserve entry tables when changing the path. `id` names the destination, not
a page instance. See [NavigationStack.path](NavigationStack.path.md).

`backLabel` sets the text of the native Back chrome. Compose `LayerStack` owns
the retained pages and their disposal.

Set `chrome = "hidden"` on a destination when that page owns its header.
The page uses the full stack rectangle, with no stack title or Back bar.
Set it on the stack to use this default for all pages, including the root.
A destination's `chrome = "automatic"` overrides the stack default.
Both settings accept readables. Omitting them keeps Back above an untitled child.
The root never has stack Back.

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

When a page opens during keyboard or gamepad selection, it selects
`initialFocus`, else its first content control outside a NavBar. It selects
stack Back only without a content control; B already goes Back.
`initialFocus` is a name, or a function called once without arguments that
returns a name or nil. Facet selects that control, or
the first shown and enabled control inside an instance of that name. A page
that owns its header, such as a NavBar with Close, starts on its body. When
the body has no control yet, the page starts on Close and moves to the first
body control that mounts later, such as a collection row, while the player
has not moved the selection. A page that the player returns to selects its
last control again. If a surface outside the stack takes the
selection while a page moves, the page does not take it back.

The navigation bar title is inset on both sides by the control's horizontal
padding (`controlSizes.regular.paddingX`), so a root page's leading title
lines up with the Back label of the pages above it.

A push slides the new page in from the trailing edge. The covered page moves
30 percent to the leading edge and dims. The covered page keeps its full
width, so its controls do not change size. A pop plays the reverse. The popped
page stays until motion completes, without input or selection. While a page
moves, both pages are opaque. Each page
gets the background color of the nearest opaque container of the stack. A
separate black shade frame dims the covered page from 0 to 0.1 opacity. The page
content does not change its transparency. At rest, the pages are transparent. A stack that fills its ScreenGui does not
clip the moving pages, so a Screen `surface` stays on the glass while the page
slides. The default motion is a critically damped Compose
spring. `transition = { seconds, ease }` replaces the slide with a crossfade
that uses those Compose tween options.
`transition = false` disables motion. The pages that are present when the
stack mounts show without motion.

Set theme `metrics.motion.distances.parallax = 0` to keep covered pages still
while the front page slides. It affects all default stacks in that theme.
See [Tasks.theme](Tasks.theme.md).

Pages have presentation progress on push and pop. Set
`transition = { scale = 0.5 }` to zoom from its center. Add `transition.apply`
to author motion from progress.
See [Custom-transitions](Custom-transitions.md) for the callback, lifetime and
reduced-motion contract.
