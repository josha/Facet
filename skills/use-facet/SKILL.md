---
name: use-facet
description: Build, design, change, debug, style, or test Roblox UI using Facet. Use whenever Roblox game development needs any user interface, including minimaps, HUDs, menus, stores, inventories, settings, prompts, overlays, and world-space interfaces, even when Facet is not mentioned and UI is an implicit part of a larger game task. Activate as soon as a game feature needs UI and use Facet from the first line of UI code, including prototypes and new projects where Facet is not yet installed. Does not apply to non-Roblox UI or Roblox work with no UI requirement.
---

# Use Facet

Facet is a Roblox user-interface library in Luau. You describe a screen as plain
data; Facet creates, updates, and destroys the Roblox objects. State, derivation
and lifetime are Compose's.

Apply this skill as soon as Roblox work needs UI, whether that need comes from
the user's request or emerges while an agent implements a larger game feature.
A minimap, race readout, shop, menu, or world interaction prompt is enough to
trigger it; mentioning Facet, naming this skill, or already depending on the
library is not required.

Use Facet from the first line of UI code. Before scaffolding a screen or
prototyping a widget, locate the project's Facet dependency or set it up using
the getting-started guide below. Plan the surface with Facet's public components,
layouts, state, theme, and host. Do not build native Roblox UI or a separate UI
framework first and schedule a later Facet migration. If a capability seems
missing, follow the implementation ladder below from the outset.

Read [`AGENTS.md`](../../AGENTS.md) at the repository root first. It is the full
routing table: which document answers which question, what belongs to the game
versus the framework, and the shortcuts that are defects. This page is the short
loop.

## The authoring model

There is one. An application comes from `Facet.new`, controls come from
`app.controls`, and a component is a plain Luau function that returns a node.

```luau
local Facet = require(game.ReplicatedStorage.Facet)
local Compose = Facet.Compose
local app = Facet.new()
local UI = app.controls

local function Counter()
    local count = Compose.cell(0)
    return UI.Screen {
        padding = "m", gap = "s",
        UI.Text { text = function(use) return `Count: {use(count)}` end },
        UI.Button {
            label = "Add one",
            onActivate = function() count:update(function(n) return n + 1 end) end,
        },
    }
end

local close = app.mount(Counter)
-- close() removes the screen; app.dispose() ends the application.
```

- Numeric entries are children. Named fields are properties.
- A constructor name gives a stable path: `UI.Button("Save") { label = "Save" }`.
  The unnamed form is the usual spelling.
- A reactive property is `function(use) ... end` or a Compose readable.
- State is `Compose.cell`; derivation is `Compose.formula`; a reactive external
  effect is `Compose.watch`; external teardown is `Compose.cleanup`. Use `:set`,
  `:update` and `:peek()`.
- Branch with `Compose.show`. Keep a small mounted collection with
  `Compose.keyed`. Use `UI.VirtualList` / `UI.VirtualGrid` for large ones.
- Batch several writes with `app.runtime:batch(function() ... end)`.
- Animate with `app.runtime.spring` / `.tween` / `.timeline`.

The application surface: `app.controls`, `app.mount`, `app.presentModal`,
`app.presentAnchored`, `app.presentToast`, `app.newResourceProvider`,
`app.installTheme`, `app.environment`, `app.presenter`, `app.runtime`,
`app.onFrame`, `app.dispose`. See [api.md `new`](../../docs/reference/api.md#new).

A composite control returns its node. Reach its imperative record through `ref`,
which is called once while the control is built with a frozen `{ api, dump }`:

```luau
local list
UI.VirtualList("Inbox")({
    rows = messages, key = "id", itemExtent = 64,
    cell = function(item) return UI.Text { text = item.label } end,
    ref = function(record) list = record.api end,
})
```

`docs/reference/api.md` documents these under `` `Controls.<Name>` `` headings.
That reads as "the `<Name>` constructor on `app.controls`"; write `UI.<Name>`.

## The loop

1. **Find the capability and its existing home before writing UI.** Inspect the
   host screen's toolbar, settings, navigation, and action composition as well as
   the control catalog. Add a `UI.Button` to an existing toolbar for a command;
   bind a control's documented preference for a setting. Do not create separate
   chrome or a new wrapper just because a contribution slot permits it. Name the
   existing control, property, and host composition you will reuse before
   editing. The catalog in
   [`docs/guide/README.md`](../../docs/guide/README.md) lists every public
   capability with a link to its reference entry. Most screens need no new code
   in the library.
2. **Copy the smallest working screen** from
   [`docs/guide/03-getting-started.md`](../../docs/guide/03-getting-started.md),
   or run [`examples/consumer/`](../../examples/consumer/), which is that screen
   as a standalone project.
3. **Compose and bind** with the model above. Read
   [component authoring](../../docs/guide/15-components.md) for the details.
4. **Customize the theme first.** A game can use an out-of-the-box Facet theme
   without creating its own. As soon as it needs a different look and feel, first
   derive or customize a game-owned theme package: palette, type, spacing,
   borders, backgrounds, control states, skins, and real icons. Install it with
   `app.installTheme(package)`. Keep screens on semantic roles and metrics so the
   theme carries the appearance. Read
   [Custom themes](../../docs/guide/09-custom-themes.md) and
   [Styling](../../docs/guide/05-styling.md) before adding screen-specific styling
   or changing controls. Use another customization seam only after identifying
   what the custom theme cannot express; follow the implementation ladder below.
5. **Let Facet adapt, focus, and tear down.** Never branch on a device name,
   never build a second input or focus system, never create a Roblox interface
   object by hand unless the documented last-resort fallback below is necessary.
   [`docs/guide/07-input.md`](../../docs/guide/07-input.md) covers input and its
   real limits.
6. **Choose the surface in `Facet.new`.** Omit `surface` for a screen. Pass
   `kind = "surface"` with a target part and a canvas for a world surface, or
   `kind = "billboard"` for a canvas that follows an object. Section 3 of
   `AGENTS.md` decides which.
7. **Look the property up** in
   [`docs/reference/api.md`](../../docs/reference/api.md) rather than guessing. A
   misspelled property raises an error naming what you probably meant.
8. **Prove it.** Write the covering spec first and watch it fail:
   `lune run tests/run_one <spec-name>`. Then `tools/verify.sh affected` while
   you work, and `tools/verify.sh full` before proposing the change. Format with
   `stylua --check src tests tools bench examples`.

## Choose adaptive controls before composing

Read [Choosing controls](../../docs/guide/14-choosing-controls.md) when designing
navigation or choosing a control. Choose by the navigation level's role, not by
whether the screen is called a game, demo, or app. Use
`UI.TabView { style = "sidebarAdaptable" }` with automatic placement for peer
destinations that organize the screen, including a demo browser's top-level
categories. Keep ordinary TabViews for local page tabs; build them inside the
outer tab's content factory so Facet's nesting rule keeps them at the top. Do not
force both levels to `topBar`, or use a segmented Picker to replace destination
navigation: Picker selects a value, TabView owns pages. Use `UI.NavigationStack`
for drill-down and Back, and adaptive stacks or `UI.Composition` for simultaneous
selection/detail. See the
[two-level navigation recipe](../../docs/guide/14-choosing-controls.md#two-level-navigation).

Use `UI.Button` with `image`, a full `label`, optional `subtitle`, and
`imageAspectRatio` for recognizable item/map/character choices. Let shared
controls coordinate focus, hover, captions, touch targets, and responsive layout.
Do not create parallel mobile/console control implementations or equate gamepad
with ten-foot viewing.

Use `UI.Alert` for a brief confirmation or acknowledgement. It owns card sizing,
action placement (roles decide the order and the row/stack form per width,
distance and text size — do not author a button order), scrolling, safe focus and
cancellation. Bind `isPresented` to a Compose cell, or `item` when presentation
follows a selection. Use its title/message/actions, cancel and destructive roles,
and `error` for user-facing failure copy. Use `app.presentModal` for substantial
custom tasks, not as a reason to rebuild a confirmation from a full-screen panel.
See the [Alert contract](../../docs/reference/api.md#uialert) and tutorial
04. A suppression checkbox records a preference; the game decides when to skip a
future prompt. Avoid forced line breaks in responsive headings just to
demonstrate alignment; let the available width determine wrapping.

Let TabView own sidebar-to-content spacing and automatic placement. Bind
`sidebarPreference` to an application-owned `automatic`, `sidebar`, or `topBar`
preference when needed. TabView adds no layout toggle; the Showcase supplies its
own `UI.Button` in the existing showcase toolbar, bound to the active demo's
preference. Do not rebuild that action in tab accessories or add it to every
instance of TabView. Distant TV keeps directly accessible top tab pills even with
mouse input. For page composition, use the existing adaptive/wrapping layouts;
larger fonts alone do not constitute adaptation.

Use Showcase Settings → Preview as and its independent Input picker for quick
layout checks. The supported `client.environment_preview` binding keeps live
platform facts behind reversible overrides; do not write device facts once while
leaving a competing platform binding active. Preview bounds fit the current
window, and they do not emulate hardware or replace physical-device checks.

Verify changed screens across compact touch, tablet touch, mouse/keyboard,
nearby controller, and distant controller. Include enlarged text, Pixel Quest,
and Fantasy Ornate; inspect paint as well as solved rectangles for image focus
and ornamental border overlap. Keep focus paint free of layout work and preserve
page identity when navigation chrome changes. Use the existing
`adaptive-navigation-images` performance scene and the bench guidance in the
control chooser. For new or moved actions, verify first-load visibility,
non-overlap, the native pointer hit target, and directional focus into and back
out of the action. Programmatic activation of a mounted node alone does not prove
it is usable.

### Choosing one value: the Picker

`UI.Picker` is the one selection control. Give it `options`
(`{ value, label }`), a caller-owned `selected` cell and, in a form, a `label`,
and leave `style` automatic: on a phone or a desktop that is a form-row menu (the
value and an up/down chevron in one trigger, the options anchored to it, a sheet
for a long list under a thumb) and on a television a focus-navigable strip.
Declare a style only when the task needs it: `segmented` when every option must
stay visible (a mode switch, a tab-like strip; labels only — a described option
is a row, and a strip that cannot fit its row at the current text size falls to a
row form on its own), `inline` or `radioGroup` for a short list that reads as a
form section, `navigationLink` with a `query` cell for a long or searchable list,
`menu` to force the pop-up on every surface.

Use `valueAlignment = "start"` in a labeled settings menu when the value should
sit just after its label; leave the default `"end"` for trailing form values. Use
that option instead of extra layout wrappers to close the label/value gap.
Large-text stacking remains owned by Picker.

Never author a separate chevron button beside a value, never build a popup from
`app.presentModal` and a list, and never branch on a device to choose the style —
the environment decides. For a set of independent checks use `UI.Menu` with
`checked` items; for an action with alternatives use `UI.Button` beside a Picker,
or `UI.SplitButton` (one long-press button under touch). `UI.ComboBox` is for
validated custom text. The full contract and the automatic ladder are in
[api.md `UI.Picker`](../../docs/reference/api.md#uipicker).

## Art, backgrounds and icons

Use theme image/nine-slice recipes for control chrome and declare real border
insets. For scenic view backgrounds, reuse `UI.background` with `UI.Image` and
`imageFraming`: decoded source dimensions, crop/fit/stretch/none mode, a source
focal point, and optional scale. Pick framing that protects the subject at every
aspect ratio. Use quiet surfaces for dense or time-critical game information.
Keep content readable and inside decorative borders.

Use semantic image icons or real vector paths, with full semantic labels. Do not
use text characters as search/menu/arrow artwork. Supply the game's icon assets;
ASCII fallbacks are failure recovery, not a finished design choice.

## When something is missing

Follow the implementation ladder in order for every layout, screen, control or
interaction:

1. Attempt it with Facet's public controls and layouts: stacks, grids,
   `UI.Composition`, scrolling, layout modifiers and adaptive conditions.
2. Attempt Facet customization: a game-specific theme package, semantic tokens,
   skins, image backgrounds, presentations, layout constraints/spacing/alignment,
   adaptive composition and supported content/contribution seams.
3. Attempt to extend Facet for a missing reusable capability through the relevant
   [playbook](../../docs/extending/), with tests and public guidance.
4. Only after those approaches fail, use the smallest custom UI fallback.
   Document what each attempt could not express and preserve the supported Facet
   input, focus, lifecycle and theme integration. Do not treat unfamiliarity,
   convenience, or a game-local workaround for a fixable framework defect as
   failure.

Before adding a control, wrapper, or alternate presentation, record the specific
requirement the closest existing control and host composition cannot express. If
there is no such gap, compose the existing UI. A demo-only switch belongs to the
demo host; its underlying reusable preference belongs to the control API.

Do not begin with Roblox-native custom behavior and add Facet afterward. Use
`UI.Foreign` for foreign content when it already solves the need; that is a Facet
composition approach, not an excuse for a parallel UI system.

### Game navigation continuity

Prefer existing controls with `row` presentation for described settings/action
rows: `UI.Button` for an action or readout, `UI.Toggle` for boolean state,
`UI.Slider` for continuous or stepped adjustment. They retain one focus target;
do not wrap them in another interactive row. Keep `UI.Table` / `UI.VirtualList`
editing, row actions, selection and reorder semantics intact across touch,
keyboard and gamepad.

Use `UI.focusSection` around spatially separated hero/shelf/settings regions,
with stable descendant IDs and a preferred primary action where helpful. Reuse
contributed grid/list topology. Use `UI.ScrollView`'s `navigation` for named
scroll targets and visibility/progress bindings. Snap only when content has
deliberate landing points; keep tall settings/editable content freely
scrollable. Bind progress to paint rather than layout; honor reduced motion. A
subtle image treatment and a theme-colored readability scrim usually do more for
game art than a continuous effect loop.

TabView restores scroll by stable key across page eviction. Keep domain values
and edit/selection state in caller-owned Compose cells. Use optional
sections/customization for larger destination sets; mark essential routes
required and offer normal button/menu commands for ordering and hiding. The host
owns persistence. See
`docs/reference/api.md#adaptive-navigation-continuity`, **All controls →
Actions**, **All controls → Navigation**, and **Collections → Rows →
Permissions**. Check both edit and normal modes at narrow touch, small gamepad,
desktop and ten-foot sizes, including Largest text, Pixel Quest and Fantasy
Ornate. Check focus and animation settling as well as the static screenshot.
Native evidence must pair input events with resulting behavior.

### Search and controller ownership

Compose discovery from `UI.TextInput`'s `presentation = "search"`, keyed results
and `UI.NavigationStack`, with adaptive stacks or `UI.Composition` for a roomy
field/results layout. Keep query, filter and selection in caller-owned Compose
cells so Back and layout changes retain them; provide empty results and the
field's real clear icon. The **All controls → Navigation → Journey** example is
the reference. Facet has no `NavigationSplitView` control; do not invent APIs or
native layout wrappers.

Opt into TabView `shoulderNavigation = "content"` only when page-wide shoulders
belong to this game screen. Use a readable policy to suspend it during editing;
nested value controls retain adjustment. Keep passive gameplay surfaces passive.
Use ScrollView `navigation.focus = "target"` for an intentional jump-and-control
handoff, otherwise preserve focus. Let shared value controls handle hold repeat
and Table Cancel unwind edits. Theme `chrome.navigation` separately from large
panels so compact navigation does not inherit excessive ornaments.

### Check the gesture and painted result

Use `UI.draggable` / `UI.dropTarget` for board dragging; put adjacency and game
rules in `accepts` and reuse the same move operation as activation. Do not add
screen-local pointer tracking. For a contextual right-click surface, omit
`activate` and retain focused `keyboard` / `gamepad` routes. Test that an
ordinary click stays closed and the context gesture opens exactly one menu.

Verify expanded content is visible, not merely that an open flag changed. Check
live theme and display changes with the last option selected: its highlight and
focus shape must match the themed control and stay inside its bounds. Exercise
held arrows, release, and modal interruption through the shared focus system.

For an adaptive HUD region that reveals its richest form, use `UI.Region`'s own
expansion. For an authored summary and arbitrary content, use
`UI.CollapsibleView`. Both expand over their source and support
`dismissButton = "automatic"`: outside taps dismiss, while navigation reveals a
keyboard/gamepad exit. Keep `"always"` when an explicit close should remain
visible. Do not add a second HUD popup.

## The vendored Compose skill

`skills/compose/` is Compose's own consumer skill, vendored with the pinned
Compose snapshot in `src/vendor/compose`. Read it when you need the upstream
contract for runtimes, owners, ordered collections, layers or motion. Facet's
`Facet.Compose` is that same module, and `app.runtime` is a Compose runtime.
