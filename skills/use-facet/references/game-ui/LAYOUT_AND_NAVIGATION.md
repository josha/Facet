# Layout and navigation

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

## Choose the relationship

Use VStack for reading order, HStack for one compact unit, Grid for a small
static arrangement, and Table for shared-attribute comparison. A results
page can contain a bounded Table inside a VStack; they solve different needs.

Screen arranges a vertical page with safe margins. It is not an overlay layer.
Mount Composition directly for a HUD. Ordinary interactive screens use device
chrome; edge-reaching artwork still needs safe text and controls.

## Fit without losing the task

Stacks hug by default. Bound the task before fill collections or wrapped text.
Use a wrapping HStack or AdaptiveStack when a row cannot fit. Do not let a
preview push the decision and its action below the shortest viewport.

Composition ranks competing Regions; lower ranks take precedence. Each form
needs a measurable size and a useful complete meaning. A fill-sized form cannot
describe its intrinsic requirement. Use mayDrop only when an immediate required
action has an equally usable alternative. A compact Menu owns its own action
and must actually open the omitted choices.

ViewThatFits tries alternatives in order and still shows the last if none fit.
Its final form must work at the smallest supported room. It does not decide
which information is safe to remove.

## Navigate deliberately

TabView is for stable peer destinations. NavigationStack is for a meaningful
path into detail. NavigationSplitView is for a collection whose selection
determines related detail, not two unrelated panels.

Keep the title, selected section and Back destination clear. Preserve selection,
drafts and useful scroll position on return. In compact split views, deliberate
selection opens detail and Back returns to the collection. Set pane minimums
from readable content rather than forcing two unusable panes.

NavBar arranges navigation chrome but does not own history. Hiding built-in
chrome requires a complete visible return route. A root page has no Back.
Do not turn every small setting adjustment into another page.

PageView suits a short inspectable sequence; expose an alternative to swiping.
Pagination suits genuinely bounded result pages. StepIndicator describes task
stages, not destinations. ZoomView preserves spatial relationships in a map or
board; keep global actions outside its zoomed content.

Read the selected control's card and props for configuration.
