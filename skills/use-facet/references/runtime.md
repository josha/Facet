# Runtime essentials

Use the installed Facet module and reuse the application's runtime. Keep the
task's pages and overlays in the same mount. For a plugin or existing host, read `Mounting` and
[runtime details](runtime-details.md) before choosing the mount target.
Edit persistent source; Play-only edits are not the delivered change.

For a new game direction, give the first task its authored `theme`. Set the
type families, weights and sizes in `metrics.typography`. Give the most
important text a role that leads, such as the `title` specimen in this
letterpress example. Let body copy and secondary facts support it. Use
`appearance = "emphasis"` for the main commitment and let the theme's
`control` role size its label. Here `pullProof` is the task's action.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local C = Facet.Compose
local app = Facet.app({ name = "ProofPress", theme = theme })
local UI = app.UI
app.mount(function()
    return UI.Screen "Workshop" {
        surface = "surface",
        UI.VStack "Proof" {
            surface = "panel", width = "fill", maxWidth = 520, padding = "m", gap = "s",
            UI.Text { text = "Pack my box.", textSize = "title", wrap = true },
            UI.Text { text = "Ultramarine on warm paper", textSize = "caption" },
            UI.Button { label = "Pull a proof", appearance = "emphasis", onActivate = pullProof },
        },
    }
end)
script.Destroying:Connect(app.dispose)
```

Use `app.UI` in the app's own code. A portable component can call
`Facet.controls(runtime)` inside the mount and inherit the provided controls.
Calling it before the mount creates separate controls, without the app's theme
metrics and skin. The native stylesheet may still color those controls.

Build the whole interface from Facet: stacks, `ZStack` and `Grid` for
arrangement, `UI.Image` for art, `UI.Text` for labels, and Facet controls for
input, navigation, collections and overlays. `local Host = app.runtime.constructors`
is for what Facet has no construct for, such as a `UIPadding` or
`UISizeConstraint` child, an `InputAction` or world content. Host children go
in the parent's positional list; a Compose-owned object passed as `Parent`
needs `C.static(object)`. Build controls only inside the mount function or a
component it calls.

## First screen with native art

For a game direction that can be expressed in native type and shapes, see the
runnable [Proof Press recipe](../assets/native-direction.luau).
It shows one theme applied to live type, paper, a choice and a primary action,
with no uploaded assets. It teaches the wiring for a small type-led task; it
is not a quality target or a panel template. [Finish](finish.md) lists the
theme values, fonts and ground treatments that carry a game's own direction.
In Studio, read the full example in one call:

```luau
return game.ServerStorage.FacetDocs.skills["use-facet"].assets["native-direction.luau"].Value
```

Mount the representative task with its authored theme before repeating the
screen treatment. Inspect the action and the selected choice with focus on it
and on its peer. Check the result at a wide and constrained supported viewport.

## State and commands

`C.cell(value)` owns state. Read it with `use(cell)` in property functions and
`cell:peek()` in callbacks; write with `set` or `update`. Derive with
`C.formula(function(use) ... end)`, branch with `C.show(condition, builder)`
and clean up subscriptions with `C.cleanup(function() connection:Disconnect() end)`.
`C.switch(source, { [key] = builder }, fallback)` picks one branch by value.
`C.keyed({ from = list, key = function(value, index) return value.id end, render = function(value, index, key) ... end })`
builds one child for each list entry and keeps it while its key stays; `value`
and `index` arrive as readables. `C.watch(function(use) ... end)` runs a side
effect when the values that it reads change.
Keep durable selection and drafts outside disposable pages and recycled rows.

NavigationStack keeps pages by entry identity. Push and pop a shallow copy of
the path:

```luau
local nextPath = table.clone(path:peek())
table.insert(nextPath, { id = "Shop" })
path:set(nextPath)
```

The server owns validation. Keep the draft, the pending request and the
accepted state apart; sending a request is not acceptance. Block duplicate
submissions, keep edits on rejection, offer retry and apply the server's
values. An input's `onChange` can request a value instead of writing the cell.

## Types

Use named constructors (`UI.VStack "Details" { ... }`) and annotate reactive
callbacks `function(use: Facet.Use)`. Type option lists before you pass them,
even with one entry: `local actions: { Facet.DialogAction } = { ... }`.
Otherwise Luau widens a literal to `string` and rejects the constructor. Fix
the type at that boundary; do not cast the whole spec.

## Sizing

| Intended relationship | Configuration |
| --- | --- |
| Bounded paragraph | Parent width; `UI.Text { wrap = true }` |
| Title in a fixed-width cell | Omit `Size`; Text fills the cell and grows in height. Add `lines = 2` or `truncate = "end"` for long titles |
| Full-width button | Parent VStack `align = "stretch"`, or `Size = UDim2.new(1, 0, 0, 0)` |
| Full-width text input | Omit `Size`; TextInput fills its parent width and supplies its own height |
| Equal peer buttons in a row | `UI.fill()` inside each Button in an `HStack { width = "fill" }`; a bounded row moves a button down when they do not fit |
| Label and trailing value | `UI.Spacer {}` between them in a bounded HStack |
| Wrapped text beside a badge or value | `UI.fill()` inside the wrapped Text; a Spacer cannot shrink a wrapped Text, which spans the row |
| Two or three actions that may turn into a column | AdaptiveStack |
| Many short choices | `HStack { width = "fill", wrap = true }`; a wrapping row without a width hugs its children and never wraps |
| A page body | The task body in [game screens](game-screens.md) |
| A scrolling body below a header | Bound the parent height and put `UI.fill()` inside the body; `height = "fill"` alone requests the full parent height, not the space remaining below siblings |

Stacks hug by default. A bounded HStack wraps its children rather than letting them spill; `wrap = false` keeps one line. `width`, `height`, `gap`, `padding` and `maxWidth` are
container options; Button, Text and TextInput take native `Size`. Text fills a
parent with a defined width and hugs inside a hugging stack or a row;
`AutomaticSize = Enum.AutomaticSize.XY` makes it hug everywhere. Bound the
space before you use fill. Spacing steps are `xs`, `s`, `m`, `l` and `xl`. Do
not repair overflow by shrinking all text.

Scaling a fixed desktop canvas with `UIScale` does not reflow its columns.
It can shrink targets and text below their usable sizes while a header or
minimum-sized control still overlaps. Use the bounded task area's width and
height to choose a fitting composition; preserve the input target size and
text preference in that form. Art can scale within its allocated area.

Check rendered text bounds after applying device and text scaling. Adjacent
labels can overlap even when their assigned rectangles looked large enough
at desktop scale. Use the mounted safe area's dimensions and the controls'
actual minimum sizes; an authored height can be smaller than the rendered
touch target. When the content cannot fit, change its grouping or presentation
instead of stacking fixed offsets past the edge. Check the scroll window as well as its contents: its bottom
must fit the available area, and the final item and exit must be reachable.
Check painted bounds too: an outer stroke, shadow or focus ring can extend
beyond `AbsoluteSize` and be cut off by a clipping ancestor. Leave room for
that paint, or use an inset treatment; do not disable necessary clipping.
For an image skin, fit the live label inside its usable painted area.
Transparent margins, content insets and shaped edges can leave less room than
the control rectangle. Recompose an action row when its labels and padding
cannot fit; a label touching the border is not a successful fit.

A plain TextInput honors an explicit native `Size`. A zero Y scale and offset
give it zero height; the auto-sized Button example does not apply to it. Omit
`Size` for the normal field, or supply a positive height for a fixed-size field.
After changing field sizing, click or tap the field and type into it. A direct
`CaptureFocus()` call is useful for diagnosis, but does not test whether the
user can reach the field. If pointer input fails, inspect the field's bounds,
clipping and overlays before testing its submission logic.

## Input

Bind game commands as native InputActions in a game-owned InputContext. A
Button's `shortcutHint` shows an action's binding; it does not connect it.
Gate gameplay commands while `UI.environment().gameplaySuspended` is true. Do
not bind Escape or gamepad Start. Facet activates the focused control with
Space and Return, so do not bind those keys to a game command as well. `UI.environment()` gives the viewport size,
the primary input and `thumbTarget`; choose layout from room and prompts from
the actual input. Call it once at the top of a screen function
(`local env = UI.environment()`) and read `use(env.viewportWidth)` in
property functions.

`suspendGameplay = true` applies to modal surfaces and a nonempty
NavigationStack path; it does not suspend gameplay for a root Screen alone.
For a dedicated full-screen app, the host must own gameplay input and native
touch-control visibility for that app's lifetime. A Screen correctly reserves
space for visible movement controls, which can leave little room on a short
phone. Use the existing page or modal lifecycle when it fits; otherwise gate
the host controls and restore their previous state when the app closes.
Read `Factory-options.keyboardNavigation` and `Tasks.safe-layout` for the
contracts. Do not remove safe insets to cover still-active movement controls.
A full-viewport ground is noninteractive paint behind the safe-area content;
the Screen's `ground` option makes it reach the glass, as
[finish](finish.md#the-ground) shows. Inspect the outer edges on a phone and a television.

When conditional content removes the focused action, transfer selection to a
useful surviving control. Use NavigationStack or `UI.focusSection` ownership
where it fits; read `Selection.SelectedObject` for native restoration. Test
the next directional input and the return action after acceptance. A successful
activation can still leave selection on a removed object. Keep pointer and
touch users free from unsolicited focus claims.

A page whose builder errors shows "This page could not be displayed." and
warns with the page id and the error in the output; read the output after
each Play.

Verify required engine APIs from the project's normal script context. A Studio
command or plugin can have permissions that the game script does not. After
an access setting changes, start a fresh Play session and exercise the actual
success path; a successful privileged probe does not establish that it works.

## Exact contracts

In Studio, read a node at
`ServerStorage.FacetDocs.docs.reference.nodes["Button.card.md"].Value`; with a
shell, `lute run tools/facet docs Button.card`. Read a card when the needed
contract is unclear or the example does not cover it. Batch independent reads
and reuse answers while they remain current. [Runtime details](runtime-details.md) covers Sheets, overloaded
collections, the top bar, localization and the type checker.
