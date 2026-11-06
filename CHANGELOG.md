# Current package

When the theme supplies no art for a standard icon that a control uses for its
own parts (close, the chevrons, checkmark, more, menu, increment, decrement,
search, the status and selection marks, clock and calendar), the icon draws as
native Path2D strokes in its styled tint. A Dialog close button, a disclosure
chevron or a checkbox mark is no longer blank in a game that supplies no icon
art. A Button caption next to an icon now uses the control type role, the same
size as a text-only Button label.

On touch, a Button with no text keeps its plate size. An icon, glyph, image or
circle Button no longer grows to `targetSizes.minimum`. An invisible
`HitTarget` around the plate meets that size instead. An empty `label` is the
same as no label, also when a reactive label changes to `""`. A Button with
text still grows its plate. The touch floor now follows the effective input
(`PreferredInput`), so a touch laptop that the player uses with a mouse has no
floor. A gamepad keeps the floor on text Buttons only.
Controls no longer read layout inside a layout change signal. In a game, the
geometry that controls observe (collection viewports and measured rows,
navigation chrome, pickers, popovers, Button `compactLabel`, level pickers,
focus rings, world markers and grid cells) is read on the next frame. Fast
resizes and scrolls no longer run these reads during the engine's layout pass.
A form, a placement or a title style can update one frame after its bounds
change. Feedback decoration still follows its host in the same frame.

`Facet.DesignStudioKit` is now the read-only form of the Compose design editor
kit type, so a kit built with the Compose design editor has this type.
`Facet.composeDesign` returns `Facet.DesignStudioEditorKit`, whose `edit`
returns the full `Facet.DesignStudioEditor`.
`environment.safeInsets` measures each side from the full screen to the core
UI safe area with `GuiService:GetInsetArea`. On Android, the bottom value now
includes the navigation bar; before, it was always 0. A core script also gets
the status bar, bottom bar, side bar and safe zone sizes. The value follows
orientation changes.

Controls under `CoreGui` move gamepad and keyboard focus through
`GuiService.SelectedCoreObject` when the script can write it. All selection
reads and writes go through one host seam, `ctx.selection`. The
`selection-seam` check rejects a direct `SelectedObject` use in `src`.
Text size comes from a type role. The base `facet-text` rule no longer sets
`TextSize`; each Facet text node carries one `facet-type-<role>` tag, `body`
by default. A Badge label and a ShortcutHint key use `caption`, and the text of
a Chip with leading, trailing or remove content uses `control`. A pixel
`textSize` on Text, Toggle or Picker sets the size with no role tag, so a size
of 14 (the engine default) is no longer replaced by the body size. NavBar
`titleSize` is a type role.

Text fills the width that its parent gives and grows only in height. It still
hugs its words in a horizontal stack, in a parent that hugs its width and at an
explicit position. `AutomaticSize = Enum.AutomaticSize.XY` is the opt-in to hug
everywhere. Collection rows keep the cell's cross-axis size and grow only on
the main axis; `contentOverflow = "grow"` is the opt-in for growth on both
axes. Card titles and captions show at most two lines and end with an
ellipsis, so a long title in a narrow grid cell keeps the card's size.
Theme and factory `icons` entries accept a font glyph
`{ font, codepoint, tintRole? }` beside image content. Each control that takes
an icon name draws the glyph at the short side of the icon box without
`TextScaled`. The glyph follows the image icon state colors and transparency,
and state maps can mix glyph and image entries. `themes.resolveIcon` returns
the content string or the glyph table. `themes.define` rejects a glyph without
a font or with an invalid codepoint. `Facet.IconEntry` and `Facet.IconGlyph`
type the entries.

ScrollView and stack containers accept `maxHeight` beside `maxWidth` through
one native size constraint. `ScrollView { height = "hug", maxHeight = limit }`
grows with short content and caps the window for long content. Compose Design
preserves the limits and their bindings. Horizontal ScrollView keeps room for
its scroll bar within the authored limits.

`Facet.Compose` includes `cubicBezier(x1, y1, x2, y2)` from the Compose pin.
It returns an easing function for Compose motion.

`Facet.review.screens(targets?, options?)` reviews all mounted Sheets or named
screen targets in one client call during Play. It opens and closes each target,
returns one text report and reports common build and runtime errors once.

Facet Design accepts consumer kinds through `DesignContext.extension`, using
Compose Design's library extension contract. `DesignKind`, `DesignResolved`
and `DesignExtension` type the registration and editor builder. `Path.points`
and `RadialMenu.skin` accept whole theme tokens. Inline token expressions in
plain point tables still need Compose Design support.

Menus use a short fade after layout is ready, with separate theme timing for
menus and sheets. Menu overlays share their preparation result, and successful
font preparation is reused when a menu opens again.

A help tooltip no longer breaks a short word across two lines, such as
"Paus / e". Its width rounds the measured text width up to a whole pixel.

Compose Design documents can author more Facet controls without code. A Text
node can own native constraint children such as `UISizeConstraint`. Dialog,
Sheet and DisclosureGroup content fields bind a prepared slot input, so the
control keeps creation and lifetime of lazy content. Sheet `detents`, overlay
`actions` and RowActions `leading` and `trailing` emit typed tables, for
example `{ Facet.SheetDetent }` and `{ Facet.DialogAction }`. Toggle offers the
`button` presentation. Design previews resolve native datatype tokens, for
example a `UDim2` with token components, with fewer allocations.

A named Alert call such as `UI.Alert "Confirm" { ... }` type-checks in strict
consumer code without an explicit `<<unknown>>` instantiation. The generated
Design source for an Alert document now type-checks as emitted.

A `DiegeticScreen` that unmounts while it is presented returns its layers and
their input contexts to the screen. Before, the app UI was destroyed with the
display surface.

A bottom tab bar with a fixed `textSize`, or with `sections`, shows its tab
titles. Before, the title of each tab could have zero width.

A row copied into its own reorderable collection no longer stops the drag with
an error when the pointer is past the last row.

`Grid` with `aspectRatio` sets the cell height from the cell width, as
documented. Before, the cells fitted inside the control height.
Compose Design documents can author more Facet controls without code. A Text
node can own native constraint children such as `UISizeConstraint`. Dialog,
Sheet and DisclosureGroup content fields bind a prepared slot input, so the
control keeps creation and lifetime of lazy content. Sheet `detents`, overlay
`actions` and RowActions `leading` and `trailing` emit typed tables, for
example `{ Facet.SheetDetent }` and `{ Facet.DialogAction }`. Toggle offers the
`button` presentation. Design previews resolve native datatype tokens, for
example a `UDim2` with token components, with fewer allocations.

A named Alert call such as `UI.Alert "Confirm" { ... }` type-checks in strict
consumer code without an explicit `<<unknown>>` instantiation. The generated
Design source for an Alert document now type-checks as emitted.

Named control builders type-check again in strict consumer code. A named call
such as `UI.Menu "Commands"` returns a generic builder, descriptor fields such
as `DialogAction` and `SheetDetent` are read-only, and `Facet.RadialMenuBuilder`
and `Facet.AlertBuilder` type the direct call of `UI.RadialMenu` and
`UI.Alert`.

Theme readers accept shallow-frozen packages without copying them. Native
property observations expose read-only values. Controls share these observations
without treating them as writable cells.

`Facet.controls(runtime)` now loads a control family when code first reads one
of its members. `require(Facet)` and `Facet.controls(runtime)` load 82 Facet
modules instead of 275. A game that uses only `UI.Button` loads 90. An
iteration over the controls object still loads all families. The first call to
`Facet.design()` loads the design kit. The public names and types do not change.

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

`Facet.review` reports design patterns that make a screen look generic, on a
live screen or a saved dump; `facet critique` turns captures and those
findings into a packet for a fresh reviewer. `Facet.themes.define` adds
`report.advice` for a flat type scale and for a display family on only one
type role. `Facet.review` reports `stacked-choices`: short choices stacked one
per row in a wide space; `hollow-plate`, `lopsided-page`, `floating-text` and
`touch-control-overlap` report empty plates, one-sided pages, HUD text on the
world and controls over Jump. `Facet.SkinLayerPatch`, `Facet.ThemeRule` and
`Facet.ThemeRuleProperties` type a theme's `chrome` and `rules` tables.

ScrollView and card Collections keep room for the theme's plate glow and
edge, so plates at the canvas edge are not clipped. `UI.environment()` without
a source returns the app's shared camera environment, also from a property
function that reruns outside an owner. A NavigationStack page that fails to build
reports its error to `onError` or the output. RadialMenu sizes its ring from measured captions, paints bands wider than the
engine's 100-pixel Path2D limit as adjacent strokes so captions stay inside
their wedges, judges a measured caption by its real width and never lets an icon that several items share replace a
label.

The version in `src/init.luau` identifies the source package. A local build does
not publish it. Run `lute run tools/facet package status` for publication and
verification status. See [package operations](package/README.md).

The [verification scope](docs/guide/verification-scope.md) defines evidence
limits. The [evaluation protocol](eval/README.md) defines game comparisons;
`eval/latest` contains the latest saved submissions.
