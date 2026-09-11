# 14. Choosing controls

Choose the control from the player's task, then adapt its presentation to the
available space and input facts. Use this decision guide when building a screen
without a designer specifying every control. The [capability catalog](README.md)
and [API reference](../reference/api.md) define the available public surfaces.

## Start with the task

| Player's task | Start with | Reason |
|---|---|---|
| Perform one primary action | `UI.Button` | Keep the action visible and directly reachable. |
| Choose a few familiar contextual commands without losing sight of a character or object | `Controls.RadialMenu` | Directional choices surround the focal point and support tap or a single marking gesture. |
| Keep a compact set of occasional commands at a screen edge | `Controls.RadialMenu` with a corner preset | A small launcher opens inward and returns to the same corner. |
| Read many commands, unfamiliar names, or long descriptions | `Controls.Menu` or a labeled list | Reading and scanning need predictable linear space. A radial menu should not become a dense inventory. |
| Keep frequently used actions visible | Buttons in a toolbar/stack | Avoid making players open a menu for every repeated action. |
| Choose one value from a list | `Controls.Picker` (leave `style` automatic) | One control, every surface: a form-row menu on a phone or a desktop, a focus-navigable strip on a television. Declare `segmented` only when every option must stay visible (a mode switch), `navigationLink` for a long or searchable list. |
| Choose a persistent value | Picker, Toggle, or Slider as appropriate | Expose the current value and its alternatives. Use a radial check action only when it belongs in a contextual command set. |
| Run one action with alternatives | `Controls.Button` beside a `Picker`, or `Controls.SplitButton` | The split joins a chevron segment to the button under a pointer and becomes one long-press button under touch; when the alternatives must be discoverable on a phone, a Picker beside the Button says them out loud. |
| Browse inventory, compare items, or search a large collection | Grid/list/table with filtering | Item discovery and comparison need more content than directional quick actions. |
| Switch peer destinations such as Garage, Races, and Settings | `Controls.TabView` | Use `style = "sidebarAdaptable"` for automatic sidebar/top/bottom navigation. |
| Choose a visually recognizable vehicle, character, map, or item | `Controls.Button` with `image`, `label`, and optional `subtitle` in a grid/rail | One focus target coordinates artwork highlight and persistent captions. |
| Navigate destinations or complete a multi-step form | `Controls.NavigationStack` and explicit destinations | A command hierarchy is not a substitute for a page flow. |
| Confirm a consequential action | `Controls.Alert` | A fast gesture must not bypass the application's confirmation requirement. |

A useful starting range for radial commands is three to eight familiar actions
per level, with short labels or recognizable icons. This is design guidance, not
an API limit. Prefer a shallow hierarchy. If a task is dominated by reading,
comparison, or frequent traversal of deep branches, choose a linear surface.

## Adapt the presentation to the task

Use `TabView.style = "sidebarAdaptable"` for peer destinations in a lobby,
collection browser, or management screen. Tablets start with tabs and a visible
sidebar toggle as an optional preference; mouse windows start with a sidebar.
Distant screens show top tab pills, independently of pointer or gamepad input.
Switching destinations does not change the navigation home. Nearby compact
screens retain bottom tabs. TabView owns the sidebar-to-page gap; pages own
their internal padding.
Nearby top/sidebar switches retain the navigation controls and scroll host.
For custom responsive layouts, bind `AdaptiveStack.axis` and `ScrollView.axis`
to the layout condition instead of rebuilding identical content in two branches.
Use `When` for genuinely different content or interaction structure.
Keep ordinary TabView styling for short in-game categories and nested tabs. Use
NavigationStack for drill-down and Back; use adaptive stacks or Composition when selection
and its detail should remain visible together. These layouts describe different
tasks and should not be interchanged merely to copy a streaming-app screenshot.

Use `Controls.Alert` for a brief confirmation or acknowledgement with one to three
choices. Supply the title, message and semantic action roles, then call
`alert.present(presenter)`. The shared component owns content-sized centering,
wrapping actions, constrained scrolling, safe initial focus and cancellation.
Use a game theme/StyleSheet to customize its appearance. A full-screen `Screen`
with a vertical button stack is not a confirmation recipe. Reserve an authored
`presentModal` surface for a substantial editor or multi-step task.

Viewing distance changes layout policy as well as typography: top navigation and
lower content density apply to Distant TV with mouse/keyboard too. It does not
reinterpret every fixed VStack as a different composition. Author responsive
relationships with AdaptiveStack, wrapping rows, grids or Composition: for example,
put showroom and setup side by side when `conditions.isWide` is true and in sequence
otherwise. Keep the same controls mounted. A nearby handheld controller retains
compact layouts; changing input alone does not turn it into a television.

Use image Buttons for choices recognized by their artwork. Always retain a full
semantic `label`; use `subtitle` for short supporting information. Let the grid
or rail offer the card's width, and supply the artwork's intended aspect ratio.
The Button owns focus/hover treatment and clearance. Do not scale its parent
cell, draw a separate focusable caption, hide the only label until hover, or
position captions over an ornamental border. For stat comparison use structured
list/table rows; for immediate gameplay commands prefer a direct button or radial
menu. Long descriptions belong in detail content, not a tiny image card.

Keep automatic control presentation unless the task requires an explicit form.
A Picker's automatic style is the menu family under touch and a pointer (one
integrated trigger, the options anchored to it, a sheet for a long list) and a
segmented or inline strip on a television or under a nearby gamepad with a
short list; a handheld's compact screen folds a long list into the menu. A
screen that must show every option declares `style = "segmented"`; nothing on
a phone should show a separate chevron cell beside a value unless a screen
declared it.
Menus use one panel for compact widths, touch, and gamepad; mouse menus can
cascade where space permits. Sliders expose one adjustable focus target, while
pointer/touch retain direct manipulation. Do not replace these with a second
controller-only UI. A connected controller does not imply a distant display:
respect `viewingDistance` independently of current input.

For every changed screen, check compact touch, roomy touch, mouse/keyboard,
nearby gamepad, and ten-foot gamepad, including live input/size changes. Exercise
Back, focus restoration, disabled/busy states, and radial menus where used.
Include Pixel Quest and Fantasy Ornate with enlarged text: check both content
containment and the painted borders/focus envelope in Studio. Never shrink text,
remove decorative insets, or silence overflow diagnostics to force a screenshot.

For performance, reuse the existing bench harness. The
`adaptive-navigation-images` scene covers a 24-card inventory, idle frames,
image focus, and sidebar changes. Focus must remain paint-only and moving
navigation chrome must not rebuild its page. Compare equivalent workloads with
FacetBench/Vide only when both adapters implement the same work; its generic
inventory workload is not evidence of adaptive-control feature parity.

## Choose radial options deliberately

| Context | Starting options |
|---|---|
| Around a character or selected object | `preset = "donut"`, `anchor = binding.anchor` from `client.world_anchor`, `center = "empty"`, `follow = "idle"`. The binding’s `padding` is a relative fraction (default 0.15). Use the menu’s theme-based `clearance` for an optional minimum opening. A plain projected anchor still works for UI content. |
| Proximity prompt on a nearby item | Bind `client.world_anchor` to the item, use `launcher = false`, and call `api.open()` from the prompt. Keep domain actions and server validation in the game. |
| Compact arc tiles around icons | Default `contentFit = "both"`; this fits thickness and arc length to measured content. |
| A continuous slim band | `contentFit = "radial"`; every control at a level shares the same inner/outer radii. |
| Short arcs with deeper plates | `contentFit = "angular"`; both circular edges and both end caps have borders. |
| A full segmented dial | `contentFit = "none"`; logical sectors fill the whole band with constant-width separators. |
| Separate round or illustrated commands | `appearance = "buttons"`; use `buttonSurface = "none"` for art/icon-only buttons. Supply `compactLabel.image` for a whole image button or `skin.item`/item `decoration` for background art beneath a label. |
| Corner shortcuts | One of `top-left`, `top-right`, `bottom-left`, `bottom-right` in `preset`; all open inward. Choose the corner from the screen's occupied regions, not a hardcoded device name. |
| Learned marking gestures or joystick directions | `distribution = "compass"`, explicit stable `slot`s, and `gestureSelection = "direction"`. The latter preserves radial selection when the painted ring is partly clipped. |
| Commands primarily selected by direct taps | Default `gestureSelection = "bounded"`; retain the accessible list fallback when readable radial targets cannot fit. |
| Children should retain their parent as visible context | Parent `navigation = "expand"`, with `expansion = "fan"` for local children or `"ring"` for a complete outer level. Fitting may replace the visible level while retaining Back. |
| Space is limited or the child set replaces the current task | `navigation = "replace"`; children crossfade and unfold from the pressed parent region. Mix replacement and expansion per parent as needed. |

Keep full accessible labels even when preferring icons. Use Button's existing
`compactLabel` policy or `labelStyle = "both"` for responsive icon/text content.
Text remains upright inside a measured safe rectangle; Facet does not bend glyphs
along an arc. The candidate preview gives the full name outside the ring.
Do not shrink text or hit targets to force a dense menu into a narrow viewport.
Facet first pulls the ring inward and reduces surplus button/band size before
choosing a list. Provide compact icons or short labels for small landscape
surfaces, and reserve explicit `clearance` only for space the focal object needs.
Minimum touch sizes and explicit clearance are preserved during fitting.

## Navigation and completion

Use `center = "back"` when a central navigation button is useful. Use `"empty"`
or passive `"content"` around an object; Back/Close then belongs in the ring.
Corner Back/Close replaces the launcher, and list fallback has one navigation
control above the list. Leave `centerPassThrough` off unless touching the focal
scene through the hole is an intentional part of the game. Its exact rectangular
aperture is documented in the [API](../reference/api.md#controlsradialmenu).

Commands close by default. Checks/radio selections stay open. Set per-item
`completion` to `"stay"`, `"back"`, `"root"`, or `"close"` to match the player's
next likely action. For example, keep a lantern toggle open, return to the gear
root after equipping a tool, and dismiss after waving. Gameplay callbacks run
immediately and never wait for the visual exit.

Use the same menu for mouse, touch, keyboard, and gamepad. Tap-to-open must remain
available alongside press-slide-release; do not require a gesture as the only
route. Verify preferred text size, reduced motion/transparency, safe areas,
orientation changes, and interruption. Studio virtual input and headless tests
are simulated evidence; physical touch/controller claims require device testing.
The Showcase's **Quick actions** demonstrates these choices. See the
[input guide](07-input.md#radial-quick-actions) and
[device verification guide](11-device-verification.md).

## Actions around world objects

Use `client.world_anchor` when the commands act on a visible Part, Model, or
avatar and keeping that target in view helps the player choose: inspect or take
an item, equip a dropped tool, or interact with a teammate. The menu remains a
screen overlay whose opening follows projected bounds; it is not a 3D panel.
For one primary action, keep a direct proximity prompt. Use a corner menu for
global shortcuts, a labeled list for reading-heavy choices, and `surface_target`
for a panel physically attached to a world surface.

A proximity prompt should open a menu with `launcher = false`; observe
`api.isVisible` to keep that prompt hidden through the menu's exit, then restore
it. Own the binding, prompt connection, and menu in the same lifetime and dispose
them together. Use `follow = "idle"` to track the object between gestures while
keeping selection stable. An unavailable or off-screen target dismisses the menu.
The [world-anchor API](../reference/api.md#clientworld_anchor) documents the binding;
the Showcase Item scene demonstrates this prompt flow.

For a world target, reserve the measured object bounds before fitting the ring.
Use a specific part when a whole model includes irrelevant accessories or large
invisible parts. Do not cap the measured opening just to force a ring onto a phone;
allow the accessible list fallback, or explicitly choose directional gestures.
The anchor does not test whether another world object obscures the target.

Use `badge` for a tab or picker count: its row reserves label/count space and wraps on a narrow offer. Avoid positioning a count image over navigation text. Use the theme palette’s `onAccent` tint for custom text on an accent selection plate.

### Rows, sections and returning to a destination

Use the `row` presentation of Button, Toggle and Slider for game settings,
equipment details and action lists that need descriptions or trailing values. Keep
one semantic control per row; do not nest a second focusable button around a toggle
or slider. Keep Table/VirtualList for actual collections, including editing,
selection, row actions and reordering. A TV presentation should increase readability
without flattening those editing semantics into a streaming catalog.

Wrap a hero action group, a shelf, or a settings column in `UI.focusSection` when
empty space between regions makes directional entry unclear. Give primary actions
stable IDs and, where useful, a preferred section entry. Preserve the grid and
collection's own navigation; do not author a second per-device neighbor map.

Use ScrollView's `navigation` for named jump actions, deliberate shelf snapping,
and visibility-driven artwork. Avoid snap for long prose, tall settings groups or
editable collections that require free scrolling. A jump changes the scroll position;
use `focus = "target"` only when arriving should transfer control to the target
region. The default preserves focus. Use normalized progress for
subtle paint-only artwork treatment and honor reduced motion. Prefer a themed
readability gradient over moving text or expensive continuous background effects.

Use TabView sections/customization only when a game has enough persistent
destinations to benefit from organization. Mark essential play/exit/settings routes
required as appropriate. Offer reorder and show/hide commands through normal buttons
or menus so they remain usable on touch and gamepad. Store preferences in game-owned
state. TabView restores scroll by key across lazy page eviction; keep editing,
selection and domain values in owner-held signals as before.

### Implementation order for game UI

For layouts as well as controls, try existing Facet stacks, grids, Composition,
scrolling, layout modifiers and adaptive conditions first. Then use its
theme/StyleSheet, spacing, constraints, alignment, skin, background, presentation
and content customization. If those cannot express
a reusable need, attempt a Facet extension with the appropriate playbook and tests.
Only after all three approaches fail should a game build custom UI; document the
specific limitations and keep that fallback small and integrated through supported
focus, input, theme and lifecycle seams. Starting with native Roblox behavior out
of convenience skips the design contract. A supported Facet foreign-content host
is still composition and should be considered before a custom system.
