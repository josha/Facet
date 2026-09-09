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
| Choose a persistent value | Picker, Toggle, Slider, or RadioGroup as appropriate | Expose the current value and its alternatives. Use a radial check action only when it belongs in a contextual command set. |
| Browse inventory, compare items, or search a large collection | Grid/list/table with filtering | Item discovery and comparison need more content than directional quick actions. |
| Navigate destinations or complete a multi-step form | `Controls.NavigationStack` and explicit destinations | A command hierarchy is not a substitute for a page flow. |
| Confirm a consequential action | The existing confirmation dialog flow | A fast gesture must not bypass the application's confirmation requirement. |

A useful starting range for radial commands is three to eight familiar actions
per level, with short labels or recognizable icons. This is design guidance, not
an API limit. Prefer a shallow hierarchy. If a task is dominated by reading,
comparison, or frequent traversal of deep branches, choose a linear surface.

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
