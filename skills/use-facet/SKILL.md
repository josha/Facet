---
name: use-facet
description: Use when building, changing, debugging, styling, or testing Roblox user interface with the Facet library.
---

# Use Facet

Facet is a Roblox user-interface library in Luau. You describe a screen as plain
data; Facet creates, updates, and destroys the Roblox objects.

Read [`AGENTS.md`](../../AGENTS.md) at the repository root first. It is the full
routing table: which document answers which question, what belongs to the game
versus the framework, and the shortcuts that are defects. This page is only the
short loop.

## The loop

1. **Find the capability before writing one.** The catalog in
   [`docs/guide/README.md`](../../docs/guide/README.md) lists every public
   capability with a link to its reference entry. Most screens need no new code in
   the library.
2. **Copy the smallest working screen** from
   [`docs/guide/03-getting-started.md`](../../docs/guide/03-getting-started.md),
   or run [`examples/consumer/`](../../examples/consumer/), which is that screen as
   a standalone project.
3. **Compose and bind.** Layout from `Facet.UI.*`, controls from
   `Facet.Controls.<Name>(core, spec)`, state in signals and memos from
   `Facet.newCore()`. Pass a signal as a property to make that property reactive.
4. **Give the game its own theme.** Derive/customize a package to match the
   game art: palette, type, borders, control states and real icons. Use semantic
   roles and metrics in screens. Read [Custom themes](../../docs/guide/09-custom-themes.md)
   before choosing the look; retain a stock look only when it fits the game.
   [`docs/guide/05-styling.md`](../../docs/guide/05-styling.md) is the chapter.
5. **Let Facet adapt, focus, and tear down.** Never branch on a device name, never
   build a second input or focus system, never create a Roblox interface object by
   hand unless the documented last-resort fallback below is necessary.
   [`docs/guide/07-input.md`](../../docs/guide/07-input.md) covers input and
   its real limits.
6. **Stand the surface up with `client.host.new()`**, which drives both halves of
   the frame. Choosing a screen, a billboard, or a world-fixed surface is section 3
   of `AGENTS.md`.
7. **Look the property up** in
   [`docs/reference/api.md`](../../docs/reference/api.md) rather than guessing. A
   misspelled property raises an error naming what you probably meant.
8. **Prove it.** Write the covering spec first and watch it fail:
   `lune run tests/run_one <spec-name>`. Then `tools/verify.sh affected` while you
   work, and `tools/verify.sh full` before proposing the change. Format with
   `stylua --check src tests tools bench examples`.

## Choose adaptive controls before composing

Read [Choosing controls](../../docs/guide/14-choosing-controls.md) when designing
navigation or choosing a control. Use `TabView.style = "sidebarAdaptable"` for
peer app destinations, ordinary tabs for in-game categories, NavigationStack for
drill-down, and adaptive stacks or Composition for simultaneous selection/detail. Use
`Controls.Button` with `image`, a full `label`, optional `subtitle`, and
`imageAspectRatio` for recognizable item/map/character choices. Let shared
controls coordinate focus, hover, captions, touch targets, and responsive layout.
Do not create parallel mobile/console control implementations or equate gamepad
with ten-foot viewing.

Use `Controls.Alert` for a brief confirmation/acknowledgement; call its
`present(presenter)` method. It owns card sizing, action placement (roles decide
the order and the row/stack form per width, distance and text size — do not
author a button order), scrolling, safe focus and cancellation. Use `presentModal` for substantial custom tasks,
not as a reason to rebuild a confirmation from a full-screen panel. See the
[Alert contract](../../docs/reference/api.md#controlsalert) and tutorial 04.
Use its title/message/actions and cancel/destructive roles, `isPresented` or `item`
binding when presentation follows game state, and `error` for user-facing failure
copy. Use a real `icon` or critical severity where appropriate. A suppression
checkbox records a preference; the game decides when to skip a future prompt.
Avoid forced line breaks in responsive headings just to demonstrate alignment;
let the available width determine wrapping.
Let TabView own sidebar-to-content spacing and automatic placement; its optional
nearby sidebar toggle is a user preference. Distant TV keeps directly accessible
top tab pills even with mouse input. For page composition, use the existing
adaptive/wrapping layouts; larger fonts alone do not constitute adaptation.

Verify changed screens across compact touch, tablet touch, mouse/keyboard,
nearby controller, and distant controller. Include enlarged text, Pixel Quest,
and Fantasy Ornate; inspect paint as well as solved rectangles for image focus
and ornamental border overlap. Keep focus paint free of layout work and preserve
page identity when navigation chrome changes. Use the existing
`adaptive-navigation-images` performance scene and the bench guidance in the
control chooser; compare with Vide only on an equivalent supported workload.

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

Follow the implementation ladder in order for every layout, screen, control or interaction:

1. Attempt it with Facet's public controls and layouts: stacks, grids, Composition, scrolling,
   layout modifiers and adaptive conditions.
2. Attempt Facet customization: a game-specific theme/StyleSheet, semantic tokens,
   skins, image backgrounds, presentations, layout constraints/spacing/alignment,
   adaptive composition and supported content/contribution seams.
3. Attempt to extend Facet for a missing reusable capability through the relevant
   [`playbook`](../../docs/extending/), with tests and public guidance.
4. Only after those approaches fail, use the smallest custom UI fallback. Document
   what each attempt could not express and preserve the supported Facet input,
   focus, lifecycle and theme integration. Do not treat unfamiliarity, convenience,
   or a game-local workaround for a fixable framework defect as failure.

Do not begin with Roblox-native custom behavior and add Facet afterward. Use the
public native-content seam for foreign content when it already solves the need;
that is a Facet composition approach, not an excuse for a parallel UI system.

### Game navigation continuity

Prefer existing controls with `row` presentation for described settings/action rows:
Button for an action/readout, Toggle for boolean state, Slider for continuous or
stepped adjustment. They retain one focus target; do not wrap them in another
interactive row. Keep Table/VirtualList editing, row actions, selection and reorder
semantics intact across touch, keyboard and gamepad.

Use `UI.focusSection` around spatially separated hero/shelf/settings regions, with
stable descendant IDs and a preferred primary action where helpful. Reuse contributed
grid/list topology. Use `UI.ScrollView.navigation` for named scroll targets and
visibility/progress bindings. Snap only when content has deliberate landing points;
keep tall settings/editable content freely scrollable. Bind progress to paint rather
than layout; honor reduced motion. A subtle image treatment and a theme-colored
readability scrim usually do more for game art than a continuous effect loop.

TabView restores scroll by stable key across page eviction. Keep domain values and
edit/selection state in owner-held signals. Use optional sections/customization for
larger destination sets; mark essential routes required and offer normal button/menu
commands for ordering and hiding. The host owns persistence. See
`docs/reference/api.md#adaptive-navigation-continuity` and the Actions and menus,
Tabs, nested, and row-capabilities Showcase demos. Check both edit and normal modes
at narrow touch, small gamepad, desktop and ten-foot sizes, including Largest text,
Pixel Quest and Fantasy Ornate. Check focus and animation settling as well as the
static screenshot. Native evidence must pair input events with resulting behavior.

### Search and controller ownership

Compose discovery from TextInput's `presentation = "search"`, keyed results and
NavigationStack, with adaptive stacks or Composition for a roomy field/results
layout. Keep query/filter/selection in caller-owned signals so Back and layout
changes retain them; provide empty results and the field's real clear icon. The
Navigation flow Showcase is the reference. Facet has no `NavigationSplitView`
control; do not invent APIs or native layout wrappers.

Opt into TabView `shoulderNavigation = "content"` only when page-wide shoulders
belong to this game screen. Use a readable policy to suspend it during editing;
nested value controls retain adjustment. Keep passive gameplay surfaces passive.
Use ScrollView `navigation.focus = "target"` for an intentional jump-and-control
handoff, otherwise preserve focus. Let shared value controls handle hold repeat
and Table Cancel unwind edits. Theme `chrome.navigation` separately from large
panels so compact navigation does not inherit excessive ornaments.
