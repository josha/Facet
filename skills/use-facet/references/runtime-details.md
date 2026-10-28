# Runtime details

Read this when [runtime essentials](runtime.md) does not cover a case.

## Existing runtimes and type checks

For a plugin or an existing runtime, read `Mounting` first and reuse the
game's Compose instance. In the Facet repository, use
`lute run tools/facet types --files FILE` for a focused check with the pinned
definitions. Keep target errors apart from reported dependency diagnostics.

## Navigation and acceptance

For Back, clone then `table.remove(nextPath)` and set it. Clear the path for an
intentional return to root. Inspect the transition itself, not only its end frame.

The game owns validation. Separate editable intent, pending request and accepted
state. Match replies to the request and current subject; ignore stale replies.
Block duplicate consequential submissions, preserve useful edits on rejection,
and offer retry. Apply canonical server values, which can differ from the submitted
draft; example callbacks that return only success do not model normalization.
Sending a request is not acceptance. Use
`C.cleanup(function() connection:Disconnect() end)` for subscriptions.
Read `Tasks.state`, `Tasks.confirm` or `Sheet.dismissal` for the relevant boundary.

Resolve callback meaning before wiring state. Input `onChange` can request a
value instead of writing the cell; accept the request by updating the model.
An `onCommit` edit boundary is not server acceptance. Other controls report
changes after writing. Use that control's contract, not a shared callback rule.

Use named constructors (`UI.VStack "Details" { ... }`) and annotate reactive
callbacks `function(use: Facet.Use)`. Type nested option lists before passing
them, even a single entry: `local detents: {Facet.SheetDetent} = {"hug"}`;
use `{Facet.OverlayAction}` for overlay actions. Otherwise Luau can widen a
literal to `string` and reject the constructor. Resolve errors at this boundary,
not by casting the whole spec or disabling checking. `Facet.host(app.runtime)`
returns the typed native constructors without a cast.

For an overloaded collection, type the chosen mode, not the union of modes:
`Facet.KeyedTableSpec<Row, string>` for rows with an explicit key. A
`Facet.TableSpec<Row, string>` annotation can lose that distinction at the call.
The pinned checker can also require the exact native boundary type: split-view
factories return `Instance`; a NavBar trailing node can be stored in a
`GuiObject` local. Use these declared boundaries instead of casting the spec.

## Sizing details

| Intended relationship | Configuration |
| --- | --- |
| Bounded paragraph | Parent width; `UI.Text { wrap = true }` |
| Full-width primary button | Parent VStack `align = "stretch"` |
| Equal peer buttons in a row | `UI.fill()` inside each Button |
| Label and trailing value | `UI.Spacer {}` between them in a bounded HStack |
| Vertically centered content in a fixed-height row | HStack `align = "center"`; text alignment acts inside each label |
| Two or three actions change row to column | AdaptiveStack; many short choices wrap in `HStack { wrap = true }` |
| Alternative HUD forms | Stable Region with concrete, measurable forms |
| Large browse area | Bounded VirtualList or VirtualGrid |
| Button with record facts inside its plate | Bounded native `Size`, `label` and `subtitle`; `caption` is an external annotation that reserves no space |

Stacks hug by default. `width`, `height`, `gap`, `padding` and `maxWidth` are
container options; Button and Text do not accept `width`. Use native `Size`
and `AutomaticSize` for explicit leaf sizing. Bound the available space before
using fill. Wrapped Text fills its bounded parent and grows vertically.
Standard spacing steps are `xs`, `s`, `m`, `l`, `xl`; use `0` for no spacing.
Surface styling can supply padding on omitted sides. For a compact fixed-height
plate, set all four sides explicitly; check its text boxes and visible glyphs.
Do not repair overflow by shrinking all text or the whole interface.
A viewport may be zero during mount. Prefer measured forms to viewport arithmetic;
when calculating a size, keep it nonnegative before the first frame.

Keep the action and its terms together. Pin them when readable content still
fits; with large text, a keyboard or short room, let the complete decision
scroll rather than trap controls behind a fixed footer.
In selectable collections, a mouse click selects; double-click or Return
activates. A touch tap activates. Selection must not imply commitment.
Theme tokens own type, spacing, paint and motion; the game owns composition
and art. Set the game's type hierarchy in `themes.define`'s `metrics.typography`,
then use `textRole` on labels. A numeric `textSize` fixes pixels and does not
follow the role's preferred-size adjustment. For example, a typed partial ramp
can strengthen a result without changing control or body text:

```luau
local typography: {[string]: Facet.TypographyPatch} = {
    title = {size = 30}, numeral = {size = 28},
}
```

Pass `metrics = {typography = typography}` in the game's theme definition.
Choose sizes and fonts for its identity and reading distance; these numbers are
not a required style. Read `Tasks.theme` for the full contract. Stage previews
need a camera fitted to the real subject.

Sheet `center` floats; `adaptive` chooses placement from room and input.
`contentInset` pads the body, not the outer margin. Long `hug` content can fill
the room. The exploration example uses a typed fractional detent for short
rooms and `hug` otherwise. Its 0.85 fraction and row actions suit that guide;
they do not guarantee margins or translated-label fit. Sheet's minimum height
still applies. Keep `actions` separate from scrollable `content`; check the body
and footer together at large text. Read `Sheet.layout` and `Sheet.detents`;
do not reposition internal SheetPanel objects or add spacer text.
Sheet width is a themed preset, not a number. Outcome chooses `narrow` for
portrait and `wide` with more room. Below the narrow token's width, the panel
can meet the screen edges; do not promise a floating margin in every viewport.

## Input and adaptation

The HUD Composition is passive; it does not take gameplay navigation. Bind
native InputActions in a game-owned InputContext. A Button's `shortcutHint`
shows an action's hint; it does not connect the action to your callback.
RadialMenu's `holdAction` does subscribe to its supplied InputAction.

Use the same command for a shortcut and its visible control. Gate gameplay
commands while `UI.environment().gameplaySuspended` is true. Use Facet's
owned page or modal behavior for input lifetime; do not emulate it with an
opaque Frame. Read `Tasks.pages` for navigation ownership and `responder`
for controller entry to a passive HUD. Do not bind reserved Escape or Start.

`UI.environment()` exposes camera room, input and access preferences.
Use `UI.environment(taskBody)` for the bounded body after navigation and insets;
do not measure a hugging child that changes size with the chosen form.
Choose layout from room, prompts from actual input, and readability from access
preferences. Keep the same state when these change. Core UI safe insets do not
reserve the movement stick or Jump button. Inspect those controls beside the
HUD on both phone orientations; use the game's known control clearance when
needed (`Tasks.safe-layout`). Convey meaning through text or shape as well as
color. Required information cannot depend on hover or motion. Preserve outcomes
with reduced motion; check focus, large text, translated labels and the on-screen
keyboard through the complete task.

For compact status or occasional commands, use `Region` with `zone = "topbar"`
and `leading = true` or `trailing = true`. Composition follows the live
`GuiService.TopbarInset`, including changing Roblox controls, and lands content
below when it cannot fit. Supply measurable smaller forms and preserve access
to omitted detail. Do not hard-code offsets for microphone or other controls,
or disable Roblox UI to make room. Read `Composition.adaptation` for the contract.

Localize complete labels through the game's translator and give the app that
translator. Disable AutoLocalize for already translated or player-supplied
text. Use actual InputAction hints rather than hard-coded keyboard suffixes.

## Exact contracts

With filesystem access, request one canonical node per invocation:
`lute run tools/facet docs Button.card`, or
`lute run tools/facet docs --search TEXT`. In Studio Edit mode, read the named
StringValue at `ServerStorage.FacetDocs.docs.reference.nodes["Button.card.md"].Value`.
Batch independent known nodes in one bounded, labeled read. Follow a card's links
for advanced options. If generated props contain unresolved placeholders such as
`ValueField` or `ActionField`, use the control’s reference and binding contract;
that output is not a complete schema. Retain answers for the current task; read
implementation source only to resolve a contradiction or reproduce a bug.
