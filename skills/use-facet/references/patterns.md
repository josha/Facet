# Compose for the decision

Choose the leading task pattern and give it the game's own visual character.
Shared type and paint do not require a shared page layout.

| Player task | Composition and interaction | Starting point |
| --- | --- | --- |
| Act while playing | World leads. Brief status at a safe edge; frequent actions within reach; optional commands disclosed. | [Exploration](../examples/exploration.luau), Composition and Region |
| Enter an activity | World or selected character leads. One primary route, a small secondary group, occasional tasks behind a named menu. | Composition, Menu, NavigationStack |
| Switch peer destinations | Persistent rail beside task-specific content when switching is frequent; adaptive bar or disclosed form in less room. | TabView `sidebarAdaptable`; [navigation](advanced-surfaces.md#navigation) |
| Give a brief command | Spatial menu for learned directions, or a bounded readable list near its source. Return after the accepted choice. | RadialMenu, Menu, Popover; [commands](advanced-surfaces.md#disclosure-and-commands) |
| Browse and inspect | Collection beside a recognizable selected subject and decisive facts; separate commitment. Narrow room uses a complete detail step with Back. | [Collection](../examples/collection.luau), [inspection](../examples/inspection.luau), NavigationSplitView, Stage |
| Compare alternatives | Align shared attributes and units. Show tradeoffs and unavailable values; selection does not commit. | Table; inspection for subject/decision allocation |
| Edit preferences | Immediate application or explicit Save. A saved draft needs preview, accepted values, rejection recovery and dirty-exit handling. | [Settings](../examples/settings.luau), Toggle, Picker, Slider, TextInput |
| Read a result | Outcome, accepted gains, then useful progression. Continue returns to the activity. A claim is a separate request. | [Outcome](../examples/outcome.luau), ProgressView, DisclosureGroup, Table |
| Learn an action | Callout near a live target; modal for focused reading. Separate lesson navigation from gameplay commands. | Callout.card, Sheet.layout; exploration guide |
| Coordinate with others | Shared goal and accepted readiness lead. Separate each player's choice from the group result. | Vote, Avatar, ProgressView; Tasks.state |

## Choose the layout relationship

| Relationship | Use | When room shrinks |
| --- | --- | --- |
| Sequential reading or distinct form sections | VStack; HStack within a related section | Wrap and grow prose; scroll a bounded body |
| Short status or action row | HStack; AdaptiveStack when order can become a column | Reflow related items together; keep priority |
| Records with attributes to compare | Table with stable keys and meaningful columns | Keep decisive columns; optional detail preserves the selected record |
| Visual peers identified by shape | Grid for a small fixed arrangement; VirtualGrid for an interactive collection | Reduce columns from readable cell width and target size |
| Records in rows | VirtualList; Outline for parent/child relationships | Preserve keys, selection and scroll context |
| Subject with contextual layers | ZStack for shared bounds; Composition/Region for screen regions | Reserve input clearance; use complete smaller forms |
| Collection and selected detail | NavigationSplitView | Detail step with Back instead of squeezed columns |

A settings form can be a VStack of sections with aligned rows. A leaderboard
needs shared columns; independent HStacks do not share column sizing. An object
inventory can use visual cells and a Table for comparing their statistics.

Bound available space before using fill. Two fill-width children in a hugging
HStack do not divide a row; use `fill`'s native flex contract within a bound.
HStack `align = "center"` centers children vertically, while text alignment acts
inside each label. AdaptiveStack changes an axis, not priority. Grid does not
infer a new column count. Read the chosen constructor's sizing contract.

## Give groups a deliberate footprint

Position, child alignment and control width are separate. A bottom-right Region
can still contain a leading-aligned VStack. Use `align = "end"` for hugging
children at the right edge, or `align = "stretch"` inside a bounded group for
common width. Do not let label length alone define equal-role action shapes.
Group by task before choosing alignment.

Allocate hands for simultaneous touch actions; steering may belong opposite
acceleration and braking. Pointer/controller can need prompts instead of a
permanent touch pad. Preserve hold, release, cancel and simultaneous input.

Choose the surface bound from content, target size, localization and viewing
distance; the viewport supplies the limit. Full-width rows are useful inside
a sensible list, but a few words do not require a viewport-wide popup. A table
or comparison may need most of the screen.

Inspect generated fallback forms: ring/list, sidebar/bar, split/detail and
floating panel/scrolling task. If public options cannot correct a poor fallback,
record the library gap. Do not shrink text, disable accessibility or modify
private children to hide it.

## Transfer a complete example

Art should show the actual subject's distinguishing shape, condition or variation.
Fit the camera and allocate enough space to see the difference. When art supplies
no decision or identity, let comparison or outcome lead.

Inspection measures the bounded detail body, bounds the wide subject/decision
group, and uses a complete narrow step. Keep its State table across page builds
to retain selection and the compact step. Mount its page through NavigationStack
(`Tasks.pages`) for input and focus ownership; Screen alone supplies layout.
For searchable catalogs, start with [collection](../examples/collection.luau):
call `createModel()` once, pass readable records and `inspect(id)`/`close()`
callbacks to `build`. Each record has `id`, `name`, `category`, visible `facts`
and numeric `value` for cost sort. Keep units in facts. The native filter route
keeps browse mounted; do not replace it with an expanding chrome stack. Search
clear changes only the query; Reset search and filters also restores type/sort.
The caller owns the detail route and game commitment.

Settings takes accepted values and `save(draft, complete)`. The game must settle
that callback with real acceptance/rejection and apply the result. Outcome takes
already accepted data; it neither grants rewards nor implements a claim request.
All examples need the new game's callbacks and visual identity.

Keep durable models outside disposable pages, and separate unrelated scroll
positions. Back goes one level; Close leaves the task. Test restoration of focus
and gameplay. When compact steps become wide panes, give shared facts one
visible owner instead of joining two complete compact documents.

Use a strong focal element, an obvious next action and quieter support.
Simultaneous gameplay can need an action group. Remove repeated headings and
state. Align related edges; use spacing to express relationships. A floating
panel needs outer space and bottom padding; a docked sheet can meet its edge;
a full task can use the screen. Preserve world visibility when it serves the task.

Copy `examples` and `assets` as sibling folders. Inspection requires
`script.Parent.Parent.assets["relic-art"]`; map their parent into the Roblox tree.
Art fabrication need not enter the layout-reading context.
