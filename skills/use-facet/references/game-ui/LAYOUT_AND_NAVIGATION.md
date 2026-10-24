# Layout and navigation

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

Navigation connects surfaces into a flow.  Layout arranges one surface around its decision.  Settle navigation first: the route decides what each surface must contain and where it returns.

## Navigate deliberately

Choose the navigation model from the relationship between places:

| Relationship | Control |
| --- | --- |
| Stable peer destinations that players revisit | TabView |
| A meaningful path into detail, with a return | NavigationStack |
| A collection whose selection decides the detail beside it | NavigationSplitView |
| A short sequence to inspect in order | PageView, with an alternative to swiping |
| Bounded pages of results | Pagination |
| Stages of one task, not destinations | StepIndicator |
| A map or board whose spatial relationships matter | ZoomView, with global actions outside the zoomed content |

Keep the player oriented.  Show the title, the selected section and where Back leads.  Return to the same selection, draft and useful scroll position.  Keep actions in a stable order across arrangements, so players can use what they learned.  Do not turn every small setting into another page.

Every exit says where it leads.  A root page has no Back, and Close returns to play.  Back returns one step, and when a destination has two levels, Back carries the name of where it goes.  A compact split view inside a destination, for example, has Close for play and a Back named after its collection.  Two controls named Back never lead to different places.

Facet:

- NavigationStack's writable `path` owns the route, and TabView's writable `selection` owns the peer destination.  Both use Compose LayerStack for page lifetime.  Keep durable values outside the pages even when visited pages stay mounted; TabView can dispose departing pages with `retention = "top"`.  Use Compose branches for changing content inside a page, not a second route history or another app mount.
- NavigationSplitView keeps both panes when it changes arrangement.  Bind its `preferredCompactColumn` and set it to `"detail"` when an activation opens the selected object; Back writes `"sidebar"`.  In compact room, a deliberate activation opens the detail and Back returns to the collection.  A directional focus move does not replace the collection.
- Set the split view's pane minimums from readable content.  `minSidebarWidth`, `minDetailWidth` and `compactWidth` express the room the content needs, and `axis = "y"` has equivalent height options.  Two unusable panes are worse than one complete pane.
- NavBar arranges navigation chrome but does not own history.  When you hide the built-in chrome, provide a complete visible return route.

## Arrange the surface

Organize the information around what the player compares and does.  Keep the facts of one decision together, and separate unrelated tasks before you add panels.  The same task can take a different arrangement when the room changes, but its identity, commitment and return route stay clear.

Each stack has one job:

- VStack sets reading order.
- HStack holds one compact unit on a line.
- Grid holds a small static arrangement.
- ZStack layers art, readouts and effects.
- Table compares shared attributes.

A results page can hold a bounded Table inside a VStack, because the two solve different needs.

Screen arranges a vertical page inside safe margins.  It is not an overlay layer.  Mount a Composition directly for a HUD.  Screen's default `chrome = "device"` clears the device safe area, the top bar and the overscan.  Art can reach the edges, but text and controls stay inside.

## Fit the room

Stacks hug their content by default.  Give the task a bound before you add fill collections or wrapped text:

- `width = "fill"` takes the parent's width, and `UI.fill()` takes the room left beside siblings.
- `maxWidth` keeps a reading or decision area comfortable in a wide viewport.
- A wrapping HStack (`wrap = true`) lets peer items use several rows.
- AdaptiveStack changes one group between a row and a column and keeps the same children mounted.
- ScrollView holds content that can grow beyond a bounded viewport.

Allocate room to the required decision first.  Optional art, introductory copy and secondary facts yield before the action and the exit.  Keep the selected object's commitment outside a long browsing collection, and never let a preview push it below the shortest viewport.

For a small grid of peer cards whose content sets the surface height, use VirtualGrid with `minColumnWidth`, `mode = "all"` and `hug = true`.  Its container sets the columns and the shared row width.  Keep a large catalog in a bounded scrolling collection instead.  Read `VirtualList-and-VirtualGrid.sizing` and `VirtualList-and-VirtualGrid.mode` for the exact sizing contract.

Adapt to the containing surface, including its height.  `UI.environment(source)` reads a native container's room; the camera viewport is not the width of a nested panel.  Prefer native layout and controls that measure their own room.  Input and viewing distance are separate: a near player with a gamepad can still use two readable panes.

Composition ranks competing Regions, and lower ranks take precedence.  Each form needs a measurable size and a complete meaning on its own; a fill-sized form cannot describe what it needs.  Use `mayDrop` only when an immediate required action has an equally usable alternative.  A compact Menu owns its own action and opens every choice it replaces.

ViewThatFits tries alternatives in order and shows the last one when none fit, so the last one must work in the smallest supported room.  It does not decide which information is safe to remove.  Give each candidate an intrinsic or fixed size; a fill-width candidate always passes the width check.  Candidates are separate mounted trees, so shared values belong in the model, and each candidate creates its own Instances.

## Check

Open the task from play, enter detail, change the viewport while it is open, return and open it again.  Check the shortest room with long labels and the on-screen keyboard.  Test the page and its body together, because their headers and safe margins share the same limited height.  Confirm that the task keeps its state and that focus, scroll position and gameplay input return to useful places.

Read `Tasks.pages` for the destination and its input lifetime, then `Tasks.collection-detail` or `Tasks.tabs` for its body.  Read `Layout-options`, `fill`, `AdaptiveStack.reference`, `ViewThatFits.reference` and the chosen navigation control's contract for exact configuration.
