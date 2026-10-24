# Layout and navigation

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

## Choose the relationship

Organize the information around what the player must compare and do. Keep
facts used in one decision together. Separate unrelated tasks before adding
panels. The same task can use a different arrangement when space changes,
but its identity, commitment and return route must remain clear.

Choose the body from the decision before writing a shared page helper:

| Player task | Body relationship | Starting controls |
| --- | --- | --- |
| Inspect one object | Prominent subject beside decisive facts and action | Stage, bounded stacks |
| Browse and inspect | Candidates beside selected detail, then a detail step when compact | NavigationSplitView, VirtualList or VirtualGrid |
| Compare shared attributes | Aligned values with a clear selected candidate | Table |
| Edit related values | Labeled groups with current values, consequences and save state | VStack, the appropriate input controls |
| Review a result | Personal outcome first, accepted gains next, comparison after | Stacks, a bounded Table when needed |

Share navigation, input lifetime and visual roles. Let the body choose its own
layout and scrolling boundary. Do not make a helper wrap every destination in
the same scrolling text column. A short choice can fit its content; an inspector
can use available room for the subject. On a wide surface, extra room should
support comparison or inspection, or remain deliberate space around a bounded task.

Use VStack for reading order, HStack for one compact unit and Grid for a small
static arrangement. These containers arrange a chosen relationship; they do not
choose the relationship for the player.

Screen arranges a vertical page with safe margins. It is not an overlay layer.
Mount Composition directly for a HUD. Ordinary interactive screens use device
chrome; edge-reaching artwork still needs safe text and controls.

## Fit without losing the task

Stacks hug by default. Bound the task before fill collections or wrapped text.
On a container, `width = "fill"` spans the parent. A `UI.fill()` child shares
remaining space along its parent stack's main axis. Text and Button do not take
container options such as `width`; use parent stretch or explicit native sizing.
Read `Layout-options` and `Text.card` before sharing a sizing helper.
Use `maxWidth` to keep a reading or decision area
comfortable in a wide viewport. Use a wrapping HStack (`wrap = true`) when
peer items can use several rows. Use AdaptiveStack when one group should
change between a row and a column. It keeps the same children mounted.

Allocate room to the required decision first. Let optional art, introductory
copy and secondary facts yield before the action and exit. Use ScrollView
for content that can extend beyond a bounded viewport. Keep a selected
object's commitment outside a long browsing collection. Do not let a preview
push that commitment below the shortest viewport.

For a small peer-card grid whose content sets the surface height, use
VirtualGrid with `minColumnWidth`, `mode = "all"` and `hug = true`.
Its container sets the columns and shared row width. Keep a large catalog
in a bounded scrolling collection instead. Read `VirtualList-and-VirtualGrid.sizing`
and `VirtualList-and-VirtualGrid.mode` for the exact sizing contract.

Adapt to the containing surface, including its height. `UI.environment(source)`
can read a native container's room; a camera viewport is not the width of a
nested panel. Prefer native layout and controls that measure their own room.
Input and viewing distance are separate: a near gamepad player can still use
two readable panes. See [input](INPUT_FOCUS_AND_ACCESS.md) for those decisions.

Composition ranks competing Regions; lower ranks take precedence. Each form
needs a measurable size and a useful complete meaning. A fill-sized form cannot
describe its intrinsic requirement. Use mayDrop only when an immediate required
action has an equally usable alternative. A compact Menu owns its own action
and must actually open the omitted choices.

ViewThatFits tries alternatives in order and still shows the last if none fit.
Its final form must work at the smallest supported room. It does not decide
which information is safe to remove. Give candidates an intrinsic or fixed
size; a fill-width candidate always passes the width check. Candidates are
separate mounted trees, so shared values belong in the model. Create a new
Instance for each candidate rather than parenting the same Instance twice.

## Navigate deliberately

TabView is for stable peer destinations. NavigationStack is for a meaningful
path into detail. NavigationSplitView is for a collection whose selection
determines related detail, not two unrelated panels.

Keep the title, selected section and Back destination clear. Preserve selection,
drafts and useful scroll position on return. In compact split views, deliberate
activation opens detail and Back returns to the collection. A directional
focus move should not unexpectedly replace the collection. Set pane minimums
from readable content rather than forcing two unusable panes. Keep actions in
a stable order across arrangements so players can use what they learned.

NavigationSplitView retains both panes when it changes arrangement. Bind its
`preferredCompactColumn` and set it to `"detail"` when an activation opens the
selected object. Back writes `"sidebar"`. `minSidebarWidth`, `minDetailWidth`
and `compactWidth` express the room needed by the content; `axis = "y"` has
equivalent height options. Use the installed contract for those options.

NavigationStack's writable `path` owns the route. TabView's writable
`selection` owns the peer destination. Both use Compose LayerStack for page
lifetime. Keep durable values outside pages even when visited pages are
retained; TabView can dispose departing pages with `retention = "top"`.
Use Compose branches for changing content inside a page, not a second route
history or an extra application mount.

NavBar arranges navigation chrome but does not own history. Hiding built-in
chrome requires a complete visible return route. A root page has no Back.
Do not turn every small setting adjustment into another page.

When a destination contains compact split navigation, use Close to return to
gameplay and label the inner Back with its collection name. Two controls named
Back must not lead to different places. Test the composed page and body together;
their headers and safe margins consume the same limited height.

PageView suits a short inspectable sequence; expose an alternative to swiping.
Pagination suits genuinely bounded result pages. StepIndicator describes task
stages, not destinations. ZoomView preserves spatial relationships in a map or
board; keep global actions outside its zoomed content.

## Check the connected route

Open the task from gameplay, enter detail, change the viewport while it is
open, return and reopen. Check the shortest room with long labels and the
on-screen keyboard. Confirm that the task keeps its state and that focus,
scroll position and gameplay input return to useful places.

Read `Tasks.pages` for the destination and input lifetime, then
`Tasks.collection-detail` or `Tasks.tabs` for its body. Read
`Layout-options`, `fill`, `AdaptiveStack.reference`, `ViewThatFits.reference`
and the chosen navigation control's contract for exact configuration.
