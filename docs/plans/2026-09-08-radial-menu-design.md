# Radial menu design and implementation brief

Status: ready for implementation after a collaborative design conversation on
2026-09-08. No runtime implementation was made during that conversation.

## Purpose and agreed scope

Add a public `Facet.Controls.RadialMenu` control for quick commands and contextual
hierarchies. It must support touch, mouse, keyboard, and gamepad from its first
release, through Facet's existing input, focus, presentation, layout, motion,
and theme authorities. Consumers should not assemble their own radial input
system. Keep domain actions and selection state owned by the consumer.

These choices were explicitly requested or accepted by the user:

- Quarter-circle corner menus, full circles, and donuts with adjustable empty
  centers around characters or other focal points.
- Both separate buttons positioned along an arc and connected wedge appearances.
- Nested rings/fans, replacement navigation, and combinations of the two. Each
  submenu can override an inherited menu-level navigation default.
- A phone launcher supporting both a single press-slide-release gesture and
  tap-to-open followed by individual taps.
- Both evenly distributed items and fixed compass slots. Use fixed compass slots
  for the five-action phone shortcut demo.
- Center behavior chosen by the app: back one level, reset to root, dismiss,
  contextual content, or an empty opening.
- Per-item completion behavior: remain open, return one level, reset to root,
  or dismiss the entire menu.
- A focal menu follows its anchor while idle and freezes during a selection
  gesture by default. Following policy is configurable. The empty center blocks
  scene input by default; pass-through is configurable.
- Pleasant, restrained, Apple-like motion on appearance, highlighting, selection,
  submenu transitions, and dismissal; complete native-theme and image-skin support.
- Incorporate the result into the built Showcase place, including a useful demo.

The detailed interaction defaults below are design recommendations supplied with
this brief, rather than separate user decisions. Implement them unless repository
or live interaction evidence warrants a documented adjustment. Do not reopen the
agreed choices merely to ask routine implementation questions.

## Geometry and appearance

Treat geometry, appearance, navigation, and selection behavior as independent
choices on one control. Prefer a small set of presets and measured theme metrics
over a large public API of arbitrary geometry knobs.

Support all four corners with a 90-degree inward arc and safe-area-aware launcher
placement. Full circles and donuts share the same angular model; the latter
reserve configurable center clearance. Separate buttons and connected wedges
use the same logical sectors. An outer submenu may occupy a partial fan around
its selected parent, or a complete concentric ring. A fan may spread wider than
its parent sector to preserve usable targets. Keep text upright.

Even distribution follows stable authored order. Fixed-slot placement uses eight
compass directions, with stable item IDs and explicitly assigned slots; empty
slots do not select an adjacent action. Do not redistribute actions when one is
disabled, unavailable, or hidden during an open interaction. Validate conflicting
slot assignments. Keep geometry fixed for a captured gesture.

Define hit regions mathematically from angle and radius, independently of image
alpha and rectangular artwork bounds. Direct taps must hit the intended sector
or button, including a real center hole. Gestural selection should tolerate
overshooting the painted ring through a documented finite capture region, and
use a central dead zone plus boundary hysteresis. Decorative gaps may be bridged
by logical sectors; unassigned compass slots remain intentionally empty.

Fit before capture: account for safe areas, reserved showcase chrome, minimum
targets, theme metrics, preferred text size, and available space. Never silently
rotate learned directions. If another ring cannot fit, replace the current level
while preserving the logical path and Back behavior. If even one radial level
cannot fit legibly, use a documented accessible list/sheet fallback via existing
Facet mechanisms. Freeze the resolved presentation during a gesture. On a major
viewport change that invalidates capture, cancel safely before reflowing.

## Opening, selecting, and cancelling

Touch and pointer use the same fundamental state machine:

1. Pressing the launcher begins visual opening immediately, without a required
   long-press delay, and captures that specific pointer/touch.
2. Releasing without meaningful movement leaves the menu latched open.
3. Moving beyond the dead zone highlights a candidate and displays its readable
   label clear of the finger. Highlighting never executes an action.
4. Releasing over a valid enabled candidate commits exactly once.
5. Moving back into the dead zone after a drag, then releasing, cancels without
   executing. A gesture that opened a closed menu dismisses on cancellation; a
   gesture begun inside an already latched menu leaves that menu open.
6. Release in an empty slot or outside the gesture capture region does not
   execute an action. Losing input capture, focus, or the target cancels safely.

In the latched menu, individual taps/clicks select normally. Pointer hover can
preview/highlight, but does not automatically open a branch or fire an action.
Selecting a parent opens its children and leaves the menu open for a fresh
selection. Do not let the release that opens children also activate one of them.
Continuous multi-level marking gestures are out of scope for this first release.

Disabled items retain position and explain unavailability where useful. Recheck
eligibility at commit. Handle reactive removal/disabling of the selected item,
trigger, or ancestor safely, restoring the nearest valid navigation context.
Release capture and make retiring controls non-interactive before callbacks can
open another surface or dispose this control. Do not defer gameplay actions until
an exit animation finishes. Callback dispatch and input must never double-fire.

Do not pause the game implicitly. Coordinate with the presenter's responder and
input arbitration mechanisms. A second touch must not steal the selecting finger;
unrelated gameplay touches remain governed by existing surface policy.

## Hierarchy and completion

Maintain one logical navigation path across all visual presentations:

- **Replace:** replace the current level's items, preserving the parent context.
- **Expand:** retain ancestor levels, highlight the selected parent, and append
  its children as an outer fan/ring. Only one active branch exists at each depth.
- **Mixed:** for example Equipment replaces root, and Tools then opens an outer
  fan. Back returns to the immediately preceding logical level and restores its
  visual state; Home clears the full path and all outer rings.

Retain a short context label/breadcrumb without forcing text into the center
hole. Focus returns to the parent item when backing out. Choosing a sibling
closes the old descendant branch. Avoid an arbitrary semantic nesting limit;
bound visible growth through fitting and replacement rather than tiny rings.

Selection completion is independent of hierarchy appearance. Provide a menu
default and per-item override for stay, back, root, and close. Back at root
dismisses; root at root remains at root. Reuse current Menu action/check/radio
semantics where practical: commands close by default, check/radio selections stay
by default. Document precedence and callback ordering; do not introduce a second
incompatible menu data model without a concrete reason. Linear dividers need not
become selectable radial items; reject unsupported shapes clearly.

The center can perform Back, Home, or Close, or display passive contextual content
or nothing. Its glyph and accessible label must match its behavior at the current
depth. Escape/gamepad B consistently navigates back one level and dismisses at
root, independent of the center setting. Supply a visible touch-accessible
Back/Close affordance outside the hole when the center cannot supply it. A tap
outside the menu dismisses all levels and is consumed rather than also clicking
the underlying scene. The central dead zone is not a center-button activation
when the pointer merely travels through it during a drag.

## Input parity and focal anchors

- Mouse: ordinary click/hover plus press-drag-release from the launcher.
- Touch: ordinary tap plus captured press-slide-release, with readable candidate
  feedback and optional existing sensory-feedback cues.
- Keyboard: spatial arrow navigation, deterministic Tab traversal to every item
  and navigation affordance, Enter/Space activation, Escape back/dismiss.
- Gamepad: analog direction highlights, A commits, B backs/dismisses; D-pad
  navigation reaches every item and level. Offer held-trigger release-to-select
  through a semantic consumer binding, without hardcoding a game's trigger.
  Stick return to neutral alone never commits. Account for dead zone and
  hysteresis, and document how the active ring is chosen.

Analog input and digital traversal must share the logical focus/selection
authority. Every outer-ring item remains reachable without precise analog input.
Preserve focus on input-class changes and restore trigger focus on dismissal.

Support a screen/UI anchor and a projected focal anchor through the appropriate
existing public target/presentation seams. A character ring is a 2D overlay, not
a claim of 3D layout, VR, or world-space interaction. Keep target-specific world
knowledge in the consumer. Default to following the anchor while idle, freezing
its solved center and geometry on pointer capture or active analog selection,
then resuming smoothly once idle. An always-follow option is allowed. If a target
disappears or goes off-screen, safely dismiss rather than leaving orphaned input.

The hole is visually transparent. By default it consumes scene taps without
selecting an item; an explicit pass-through option allows uncaptured taps to reach
the scene. Pass-through must not leak an already captured selection gesture or
disable Back/Dismiss. Verify this against real presentation/input behavior.

## Motion and theming

Use Facet's motion authority, preserving position/velocity when transitions are
interrupted. The menu must feel responsive even during its opening animation.
Starting tuning ranges, not claimed Apple specifications:

- Open: a small radial expansion with opacity, settling in roughly 180–240 ms.
- Highlight/press: immediate state feedback, about 80–120 ms of subtle emphasis.
- Expand: children move a short distance outward from the parent region, roughly
  180–240 ms, keeping the selected ancestor visually stable.
- Replace: short crossfade/radial translation, roughly 140–200 ms, retaining context.
- Commit/dismiss: clear selected feedback followed by a short inward fade, roughly
  120–180 ms; execute the action immediately, independent of the animation.

Avoid large overshoot, spinning labels, mandatory waits, and long item staggers.
Reduced motion preserves selection, hierarchy, and completion feedback through
short fades or immediate changes. Honor reduced-transparency and contrast rules.

Theme the launcher, center, ring/sector/button surfaces, separators, icon and
label treatments, focus, hover, pressed, disabled, selected/check states,
submenus, shadows, geometry metrics, and motion through existing authorities.
Native StyleSheets own eligible paint; use documented framework paths for
properties the engine cannot style. Do not promise that unsupported engine
objects suddenly accept stylesheet rules.

Support supplied Roblox image assets for surface/state skins and semantic icons,
including shared backgrounds and per-segment/button decoration. Preserve native
readable labels and geometric hit regions. Follow existing theme vs explicit
local override precedence; handle live theme swaps and missing assets cleanly.
Keep the ordinary theme functional without an uploaded custom skin. Use legitimate
existing assets or newly authored assets for the demonstration, never copy the
reference images as production assets or invent asset IDs. Publishing/uploading
new assets is a separate external operation if credentials or permission are needed.

First prove the rendering seam: the current `UI.Path`/`Path2D` implementation is
stroke-only, with documented clipping and opacity limitations. Do not assume it
can fill annular wedges or fade like a normal GuiObject. Inspect the current
engine and repository capabilities, compare a bounded native geometry approach
with existing supported image decoration, and demonstrate filled, themeable
sectors and a real hole live. Add only the minimum missing primitive/adapter
capability through Facet's extension playbooks. Avoid excessive tiny primitives,
per-frame instance churn, and a custom renderer or input system in the demo.

## Showcase: Quick actions

Add one curated, hands-on **Quick actions** demo in the existing Showcase place.
Use a small character/focal scene with a clear purpose and visible action results.
Offer three understandable examples/tabs rather than displaying every control
variant simultaneously on a phone:

1. **Corner commands:** a quarter-circle launcher with distinct circular buttons;
   a compact menu for contextual actions. Demonstrate a child menu replacing items.
2. **Quick gestures:** five stable compass actions such as Wave (up), Cheer
   (upper-right), Point (right), Sit (lower-left), and Inspect (left). Initially
   teach both tap-to-open and slide-to-select. Show the selected action in the
   scene/status, not only an internal event counter. Preserve the three empty slots.
3. **Character commands:** a visible character/focal point inside a transparent
   donut; Equipment replaces items, Tools expands outward. Include a stay-open
   toggle, a return-one-level action, a root-reset action, and a closing command
   with understandable outcomes. Let the focal point move to demonstrate follow
   and freeze, and provide a small advanced section for the configurable policies.

Prove native styling and an actual available image skin, plus live theme switching
through the Showcase's existing picker. Include reduced-motion and large-text
checks using established facilities. Keep technical diagnostics in the laboratory
or scripted scenario reports, not in the primary user flow. Maintain existing
stable demo IDs and regression fixtures. Follow the current showcase curation
document and control registration/scaffold workflow. Rebuild the real
`examples/places/Facet-Showcase.rbxl` through the repository's documented builder;
merely adding an unregistered scenario or producing a separate browser mockup
does not satisfy showcase integration.

## Implementation path and proof

Start at `AGENTS.md`, `CONTRIBUTING.md`, `docs/MAINTAINERS.md`, and
`docs/reference/constitution.md`. Read the new-control and, if needed,
new-engine-feature/new-primitive/theme extension playbooks. Inspect current Menu,
anchored surfaces, gesture capture, input contributions, focus graph, motion,
skin recipes, and path-shape code before selecting seams. Follow current source
over stale assumptions in this brief. No new dependency or broad rewrite is
justified by this feature alone.

Use `Facet.Controls.RadialMenu(core, spec)` and the established control return,
reactive state, disposal, diagnostics, and registration conventions. Exact property
names are the implementer's responsibility; keep them coherent with current
Facet. Reuse shared Menu semantics where they actually fit, retaining existing
Menu behavior. Do not force radial geometry through its linear sheet adaptation.

Write meaningful failing behavioral tests first, using the repository's existing
world/input fixtures. Cover sector geometry and boundaries; all corner placements;
donut hit exclusion and configurable pass-through; stable compass gaps; direct and
gesture activation/cancellation; touch ownership; input loss; all four input
classes through real dispatch; mixed navigation and focus restoration; each
completion policy; reactive disabling/removal; callback-triggered disposal;
safe-area/large-text fitting; moving anchors; theme swaps; reduced motion; and
interrupted transitions with complete cleanup. Avoid tests that only invoke the
callback directly or mirror a private helper implementation.

Run affected checks during implementation and the required full verification tier
before declaring completion. Follow current repository instructions for formatting,
documentation, conformance registration, theme/overflow/large-text sweeps, builds,
and package rebuild/status. Update the API reference, guide capability catalog,
input/style documentation where needed, and changelog. Build and check the
distributable package locally; do not publish a release.

Perform live Roblox Studio verification of real rendering, animation, sector hit
behavior, hierarchy, input paths, game-input arbitration, skins, device-size
adaptation, and teardown. Record evidence using the established scenario workflow.
Distinguish headless proof, Studio simulation, and physical-device validation;
never claim a physical phone/controller was tested if unavailable. If a specific
live check or asset operation is blocked, complete all independent work, report
the exact gap and reproduction steps, and do not label that gap verified.

Completion means an integrated public control, registered useful showcase demo,
rebuilt place/package artifacts as required, updated docs, passing required
checks, and recorded live evidence or explicitly named unavoidable proof gaps.
The final report should identify the control API, how to open the demo, tests and
live checks performed, artifact locations, and remaining material limitations.

## Visual references

These are design references, not licensed production art:

- Corner buttons: https://i.pinimg.com/736x/84/1a/cf/841acf786cc7a5a77ab36d3da363077c.jpg
- Concentric segments: https://i.pinimg.com/1200x/3d/0b/38/3d0b387a35fb069a2964ee38cd6daec2.jpg
- Outer button fan: https://i.pinimg.com/736x/c2/64/db/c264dba1f2fb5b2bf38f7e99cbf4b83e.jpg
- Game menu discussion: https://champicky.com/2022/01/21/radial-menus-in-video-games/
