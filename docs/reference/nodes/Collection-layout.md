# Collection layout

Use this pattern when a user selects a record and needs its preview, facts and
action together. The [collection/detail recipe](Tasks.collection-detail.md)
keeps two bounded panes at wide sizes. NavigationSplitView retains both panes
and shows one step with Back when they cannot fit.

## Bound the task body

Give the page a bounded height. Put navigation above the split view and add
`UI.fill()` to the split view so native UIListLayout and UIFlexItem allocate
only the remaining height. A hugging page can grow beyond the viewport.
A fill preview inside a VStack does not bound text or facts below it.

Keep long content in the detail's ScrollView. Its viewport fills the detail
pane; its canvas holds preview, facts, terms and action in that order. The
page and list do not scroll with it. Keep search and Filters access together;
put many filters in another step that shares the query model.

## Use the available height

The recipe assumes a small preview and short terms. For a short container,
put the preview beside the facts and action when both remain readable.
[Tasks.inspect](Tasks.inspect.md) shows the native fill allocation for this
relationship. Measure the bounded detail with `UI.environment(detail)` after
navigation and safe padding. Use both height and width when selecting a form.

A preview must have a bounded parent and fill it. Use Stage for a selected 3D
subject and bind the scene to the same selection as its facts and action.
Use visible labeled swatches when choosing colors. Keep price, affordability,
pending state and the accepted result with the action. Do not replace these
with an icon alone.

This is a design pattern, not a required screen structure. A text-led archive
can use a title and document excerpt as its subject. A quiet inventory can use
small thumbnails without an accent on every row. A plugin inspector uses its
existing dock widget bounds and host navigation. A brief text settings page
with no collection does not need a split view or a preview.

Check entry, long text, selection, Back and rotation. Confirm that the detail
viewport stays inside the page and its last action is reachable by scrolling.
Use real input and captures to verify engine layout and activation.
