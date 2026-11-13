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

## From a native habit to Facet

| Native habit | Use |
| --- | --- |
| `Frame` with a `UIListLayout` | `UI.VStack` or `UI.HStack` with `gap`, `padding`, `align` and `distribute` |
| A row that must become a column | `UI.AdaptiveStack`, or `HStack { wrap = true }` for many short items |
| `UIGridLayout` or computed cell positions | `UI.Grid`, or `UI.VirtualGrid` with `minColumnWidth` for a long collection that scrolls |
| Children layered with `AnchorPoint` and `Position` | `UI.ZStack` with `alignH` and `alignV` |
| A block pinned to the bottom or the far side | `UI.Spacer {}` or `UI.fill()` in a bounded stack |
| `ImageLabel` with a computed `Size` | `UI.Image` with `width`, `height` and `aspectRatio` (`"fill"` or pixels, bound to the room when needed), `scaleMode`, `shape` and `tint`; native image properties still apply |
| A separate ScreenGui for a full-screen backdrop | `UI.Screen { ground = UI.Image { ... } }`, or a `UI.ZStack` of images for layers |
| A transparent `ImageButton` or `TextButton` over art | `UI.Button { appearance = "bare", name = ..., face }`: the Button has the size of its face, Facet draws focus and keeps the touch target |
| Objects placed in a scene by coordinates | Layers of a `ZStack`, each a filling stack that aligns its own content; a negative `gap` for overlap; `Rotation` on a face |
| `TextLabel` | `UI.Text` with a `textRole`; `UI.Label` for an icon with a value |
| A count or status pill; a mark on a corner | `UI.Badge`; `UI.badged(host, value)` |
| A plate image behind a group | `surface = "panel"` with theme `chrome.panel` art |
| A label on one piece of art, such as a note, a card or a sign | A stack with `ground = UI.Image { image = ..., scaleMode = ..., paintRect = ... }`: the art fills the stack and the padding starts at its paint |
| A thin frame as a rule | `UI.Divider` |
| Pixel tables chosen by screen size | `AdaptiveStack`, `ViewThatFits`, or one `UI.environment()` class |
| `TweenService` | Theme motion with `UI.countUp`, `UI.follow`, `UI.sequence`, `UI.shake`, `Flash` and `Travel` |
| `UserInputService` key checks | An `InputAction` with the Button's `shortcutHint` |


Put `table.unpack(rows)` last in a constructor; before other entries Luau keeps
only its first value. In a `Stage` where the player chooses colors, keep
`Ambient` and `LightColor` near white.

## First screen with native art

The runnable [Proof Press example](../assets/native-direction.luau) is one
first screen built from native type and shapes, with no uploaded assets. Read
it for the wiring of a theme and for the layers of a screen: a ground that
reaches the glass, a lead that takes its size from the room, the controls on
a rail, and a short wide form with the lead beside the controls. It is one
composition for one task, a letterpress shop with one large proof. It is not
a layout for other screens, and a quiet interface has other answers; the
[settings example](../examples/settings.luau) is a plain form.
In Studio, read the full example in one call:

```luau
return game.ServerStorage.FacetDocs.skills["use-facet"].assets["native-direction.luau"].Value
```

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

[Runtime details](runtime-details.md#sizing-details) covers scaled text
bounds, painted bounds under a clip, image skins and the size of a TextInput.

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

`suspendGameplay` is an option of the app, not of a surface:
`Facet.app({ name = "Game", theme = theme, suspendGameplay = true })`. It
applies to modal surfaces and a nonempty NavigationStack path; it does not
suspend gameplay for a root Screen alone.
While one is open, Facet turns off the touch controls and
`UI.environment().gameplaySuspended` is true. Derive the game's own input
from it. Do not turn the touch controls or an input context on and off by
hand for a page that an owner can present. For a dedicated full-screen app,
read [runtime details](runtime-details.md#input-and-adaptation). A
full-viewport ground is noninteractive paint behind the safe-area content;
the Screen's `ground` option makes it reach the glass, as
[finish](finish.md#the-ground) shows.

Facet owns the selection of a surface that it presents. A Sheet, a Dialog
and a NavigationStack page select their entry control when they open: the
control that `initialFocus` names, else the first usable one. They skip
disabled and hidden controls, and they return the selection to the opener
when they close. Read `Selection.SelectedObject` for the contract. A panel
that the game shows and hides itself gets no entry control and no return.
Present it through NavigationStack, a modal or `UI.focusSection`. Do not select "the first
button" by a search of the descendants: `Visible` is true on a disabled
button and on a button under a hidden ancestor, and the engine then holds
the selection on a control that cannot act. Write `GuiService.SelectedObject`
yourself in one case: conditional content removes the focused control, and
you move the selection to a named control that survives. Keep pointer and
touch users free from unsolicited focus claims.

To check controller focus in Studio, switch the device preview to a console.
Injected arrow keys stand for the D-pad and Return stands for the A button.
When nothing is selected, `GuiService:Select(playerGui)` stands for the first
press. Read `GuiService.SelectedObject` after each move: it is a control that
can act, the next move leaves it, and Return activates it. An injected
`ButtonA` does not activate the selection. Check the entry, one move, an
activation and the return for each kind of surface. The first injected key
after a change of device can clear the selection, so send one key before you
select.

A page whose builder errors shows "This page could not be displayed." and
warns with the page id and the error in the output; read the output after
each Play.

## Exact contracts

In Studio, read a node at
`ServerStorage.FacetDocs.docs.reference.nodes["Button.card.md"].Value`; with a
shell, `lute run tools/facet docs Button.card`. Batch independent reads and
reuse answers while they remain current. [Runtime details](runtime-details.md)
covers Sheets, overloaded collections, the top bar, localization and the type
checker.
