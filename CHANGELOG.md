# Current package

In a compact `NavigationSplitView` with a `transition`, the closing pane keeps
its size and screen position until its motion ends. A tab bar placement or a
header that changes with the push no longer reflows the closing pane.

A new theme token, `motion.frameLimit` (0 by default, off), lets a game absorb
a slow mount frame on a device. When it is above 0, the first frame of a
navigation transition adds at most `motion.frameLimit` seconds to its clock, and
the `motion.restLimit` readiness fallback starts after the first frame with
layout. Later frames run in real time. Keep it at 0 in fixtures that advance one
large step and expect the motion to finish.

A `TabView` placement change to `"none"` slides the bar out over the new theme
token `motion.durations.tabChrome` (0.3 seconds), and the content grows when the
bar is gone. A change back slides the bar in. A push that hides the tab bar no
longer removes it before the push motion starts.

A slot collection again creates new slot nodes before item watches that look
them up in the same settle. Compose 147835f keeps an equal-cut-off formula's
consumers in propagation order.

When the destination of `UI.Travel` changes to a node at the same position and
size as the content, the content lands in the new destination at once. It does
not start a flight. A tile that a reserved-slot preview moved into an empty slot
thus stays visible in place when the drop gives it that slot.

In a collection with `slots`, an accepted payload from another source now
parts the items at `info.insertion` while it hovers. The items between the
insertion and the nearest empty reserved slot move one slot toward that empty
slot. The items return when the payload leaves. The landing of a drop with
`travel` uses the same slot. Each node from `slotControls.nodeOfKey` follows the
displayed position of its item, so content that you place on a slot node moves
with the item.

A DiegeticScreen waits for a slow first room frame instead of returning to the
screen. A heavy scene that takes longer than `motion.restLimit` to settle now
enters the room.

A reorderable collection row with a `drag` `previewScale` now lifts when you
press it with a mouse or touch, as `UI.draggable` does. The lift uses the
`motion.durations.pressLift` theme token. The row settles when you release it
without movement. When a drag starts, the drag preview continues the lift.

In a collection with `slots`, an external payload whose first key names an
occupied slot now opens a gap at `info.insertion`. Only a key with an empty
reserved slot returns the payload to that slot.

A palette-only theme swap does no control work. Controls ignore a package change
that differs only in palettes. A StyleSheet writes only the color tokens that
changed and applies only the rules that changed. Compiled rules are shared by
every StyleSheet for the same frozen package. A swap across 200 buttons costs
about 15 us instead of about 950 us in the engine double.

Collection rows write LayoutOrder, Position and Size only when they change.
Text that a function supplies is written only when the result changes.

The `transition.scale` zoom no longer scales the page content, so text does not
step between sizes during motion. The content fades in at full size. A plate in
the color of the nearest opaque ancestor grows behind it. The plate and its
`TransitionScale` UIScale exist only during motion. Without an opaque ancestor,
and in a Sheet, the zoom is a fade. `scale = true` starts the plate at the
theme value `motion.materialize.zoom` (0.92 in Facet Neutral). The zoom uses
the new theme tokens `motion.durations.zoomPresent` (0.3 seconds),
`motion.easing.zoomFade` (`outCubic`) for opacity and `motion.easing.zoomScale`
(`outSine`) for the plate, so the fade leads. In a compact NavigationSplitView,
only the pane that opens zooms. The pane that closes only fades.

Auto-localization stays on for text that the author gives as a plain string,
also when a control reads it through a function. Only `UI.Text` and `UI.Badge`
text that the author binds to a readable or a function turns it off.

Unwrapped text given as a fixed string builds its font-metric size floor when
its text first changes or when the engine reports that the text does not fit.
Until then it uses the native automatic size. Bound text keeps its floor from
the start.

A negative pixel width or height, such as a computed extent before the first
measure, resolves to 0 instead of raising.

Text labels leave their first layout to the engine and read their geometry from
the `Changed` signal. Text floors apply directly from text, style and
measurement events instead of through watches. A bound Badge caption is
computed once per change.

Bound text, given as a readable or a function, sets `AutoLocalize` to false
unless you set it. Engine auto-localization of each change costs about 15 µs.
Text floors build without `Compose.show` or a separate measurement watch, and
text labels observe their geometry by signal instead of by a poll each frame.
A NavigationStack without transitions shows each page in a plain frame after it
is ready. `lute run tools/facet build studio-bench` builds a Studio place that
times the comparison workloads natively.

Facet pins Compose `d6592f9`, which allocates less per watch, shared
resource and observation. Text layout reruns only its measurement when text
changes, caches native measurements, and builds measurement parameters on
demand.

World drag sources use `UI.draggable` with `world` options and the shared drop
session. World targets supply `worldPlacement` through `DropInfo`. See
[world drag and drop](docs/reference/nodes/draggable-and-dropTarget.world.md).

`Facet.Compose` now includes `Compose.map` from Compose d74f653.
`Compose.map(source, transform)` returns a body that transforms the value of one
cell or formula. A property bound to it updates without dependency tracking.

## 0.12.0

Facet provides Roblox UI controls built on Compose and native engine APIs.
Use the [API reference](docs/reference/api.md) for public contracts and the
[architecture](docs/guide/architecture.md) for ownership and engine integration.
Use the [game UI design guide](skills/use-facet/references/GAME_UI_DESIGN_GUIDE.md)
for composition, input, and device decisions.

The version in `src/init.luau` identifies the source package. A local build does
not publish it. Run `lute run tools/facet package status` for publication and
verification status. See [package operations](package/README.md).

The [verification scope](docs/guide/verification-scope.md) defines evidence
limits. The [evaluation protocol](eval/README.md) defines game comparisons;
`eval/latest` contains the latest saved submissions.
