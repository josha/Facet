# Compose for the decision

Choose the leading task pattern and express the game's character through subject
scale, type, shape and composition. Shared paint alone does not establish identity.

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

Choose the surface bound from content, targets, localization and viewing distance;
the viewport supplies the limit. Use surplus room deliberately:

| Task needs | Use the extra room for |
| --- | --- |
| A few choices or a brief decision | Center the complete bounded task, including title and actions |
| Inspection or customization | Enlarge the useful subject beside a readable decision column |
| A task connected to gameplay | A bounded panel that retains useful world context |
| Dense comparison or editing | A full task with aligned columns or useful working space |

A content `maxWidth` inside an opaque full-screen surface does not bound the
composition. Align its navigation, body and actions together. Empty space should
separate groups or frame a subject, not leave the task stranded on one side.

If public options cannot correct a poor fallback, record the library gap.
Do not shrink text, disable accessibility or modify private children to hide it.

## Transfer a complete example

Fit the art's camera and scale to reveal shape, condition or variation;
otherwise let comparison or outcome lead.

For products or equipment, use [collection](../examples/collection.luau).
Use the game's theme and subjects; [Riverbank](../assets/riverbank-theme.luau)
demonstrates one identity. Call `createModel()` once, pass records
and `inspect(id)`/`close()` callbacks to `build`. A record has `id`, `name`,
`category`, useful `facts`, numeric `value` for cost sort and optional `price`
with its unit, plus optional `ownership` text. Keep price out of facts when separate. Inspect opens detail
without spending; search clear changes only the query, while Reset also restores
type/sort. The native filter route keeps browse mounted.

In the caller's detail destination, call `buildDetail(app, record, state,
callbacks)`: `record` is a readable Record; state has readable `accepted`, `busy`
and `message`; callbacks are `commit(id)` and `back()`. The game owns requests,
rejection/retry and accepted ownership. The larger subject and emphasis action
make commitment distinct from catalogue Inspect. Both builders accept an optional
fifth argument, `renderSubject(app, readableRecord) -> GuiObject`. Supply the game's
image or model there; omission uses Riverbank's native subjects. Pass `false` for
records whose useful identity is textual; this removes the art allocation.
Keep names, decisive facts, price and ownership outside the art so missing images
do not remove the decision. The renderer creates a fresh Compose-owned object
with reactive record bindings; it must not reuse a cached instance.
Mount Exploration's gameplay
HUD in the stack's root with the same app/theme. Its Field kit opens the temporary
guide; a child task correctly suspends those gameplay commands.

Inspection demonstrates a selected subject in an archive; Collection demonstrates
visual product browsing. Keep Inspection's State table across builds. Mount task pages through
NavigationStack (`Tasks.pages`) for input/focus ownership; Screen supplies layout.

Settings takes accepted values and `save(draft, complete)`. The game must settle
that callback with real acceptance/rejection and apply the result. Outcome takes
already accepted data; it neither grants rewards nor implements a claim request.
All examples need the new game's callbacks and visual identity.

Keep models outside disposable pages and unrelated scroll positions separate.
Back goes one level; Close leaves the task. Test restored focus/gameplay.
When compact steps become wide panes, give shared facts one visible owner.

Copy `examples` and `assets` as sibling folders and map their parent into Roblox.
The examples require their theme and subject-art modules.
Art fabrication need not enter the layout-reading context.
