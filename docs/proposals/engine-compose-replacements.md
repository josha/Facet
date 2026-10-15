# Engine and Compose replacement census

This census covers the code read for the Table sort fix. It has 11 replacement
candidates. Only item 11 has the same behavior with the current APIs and needs
no geometry change. The other items are follow-ups, not approved deletions.

Source ranges refer to this branch after the Table fix and the input
subscription replacement. Estimates are net source lines that a replacement
could remove. They exclude tests and documentation. They are estimates, not
measured savings. Items are in decreasing estimate order. For equal estimates,
lower risk comes first. Do not add estimates for overlapping source ranges.

The Compose pin is `1836eaaa4da1e39046d9a3176be768890cf50731`. The snapshot
does not include the consumer reference. I read the available
[consumer reference](https://github.com/voidmeld/compose/blob/main/.agents/skills/compose/references/api.md),
its linked [API](https://github.com/voidmeld/compose/blob/main/docs/api.md), and
the pinned source cited below. The pinned source controls these findings.

## Candidates

### 1. Sequence event scheduling: about 100 lines, high risk

Source: [effect_sequence.luau](../../src/ui/effect_sequence.luau), lines 31–161.
`compile` builds serial and parallel phases, orders equal-time events, and
`advance` runs callbacks and samples. It already uses `runtime.timeline` as
its clock.

Checked [TweenService](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/TweenService.yaml),
then Compose `runtime.timeline`, `runtime.tween`, owners and scopes.
[Timeline options](../../src/vendor/compose/core/animation/timeline.luau),
lines 11–31, provide time, repeats, seek and pause. They do not provide nested
phases or ordered callbacks. TweenService changes Instance properties; the
Facet sequence also calls consumer functions. A direct substitution changes
callback order, cancellation during callbacks and zero-duration behavior.
Use proposal A before removing this code. The estimate keeps theme token
resolution and the public Facet adapter.

### 2. Instance focus candidate traversal: about 80 lines, high risk

Source: [selection.luau](../../src/ui/selection.luau), lines 34–95 and 129–278.
Facet walks visible descendants, sorts document and selection order, chooses
the current modal scope, and implements Tab traversal and entry selection.

Checked [GuiService](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/GuiService.yaml),
[GuiObject](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/GuiObject.yaml)
`SelectionGroup`, `SelectionOrder` and `NextSelection*`, then Compose
`createFocusScope` and `focusNeighbor`. The native APIs cover selection and
directional links. Compose covers keyed candidates and navigation. Neither
collects this Instance tree with Facet's modal and document-order policy.
Keep the policy; consider an engine-specific Compose candidate adapter.
Risk is high because Tab order, hidden ancestors, text focus and nested modal
entry can change. This is not a claim that the native selection engine must
be replaced. See proposal B.

### 3. Geometry observation queue: about 70 lines, high risk

Source: [geometry_observation.luau](../../src/ui/geometry_observation.luau),
lines 6–126. A shared queue reads all geometry before it publishes cells.
It also samples derived properties before paint and cancels deferred work.

Checked `Instance:GetPropertyChangedSignal`, `RunService.PreRender`,
`GuiObject.AbsoluteSize`, `TextLabel.TextBounds`, then Compose cells,
`reactor:batch` and the host observation capability. The pinned
[Roblox host](../../src/vendor/compose/roblox/host.luau), lines 165–193,
observes property signals. It does not supply the shared read-before-publish
frame sample. A signal-only substitution can miss derived changes. The
existing native collection spec explicitly checks changes with no signal.
Move the general sampling mechanism upstream before replacing it; see
proposal C. Risk is high because the publication phase can change layout
and introduce feedback.

### 4. Fade child transfer and warm-up: about 65 lines, high risk

Source: [context_native.luau](../../src/ui/context_native.luau), lines 105–269.
Facet creates a CanvasGroup only when needed, transfers children, preserves
selection during transfer, waits for a frame and returns children on cleanup.

Checked [CanvasGroup](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/CanvasGroup.yaml),
`UIGradient` and `UIStroke`, then Compose `show`, `presence`, portals and
owners. CanvasGroup already provides the group paint operation. It always
clips descendants. A permanent CanvasGroup would remove transfer and warm-up
code, but can change clipping, automatic size, textures and selection.
Compose presence retains a subtree; it does not make the existing Frame a
CanvasGroup or remove that clipping rule. Test persistent groups in Studio
before making this change. Keep the public Frame contract.

### 5. Directive child ordering adapter: about 60 lines, high risk

Source: [layout_kit.luau](../../src/ui/layout_kit.luau), lines 246–338.
`kit.ordered` wraps a mount point, tracks inserted nodes, preserves authored
LayoutOrder values, and assigns separate number ranges to directive children.

Checked `UIListLayout.SortOrder` and `GuiObject.LayoutOrder`, then Compose
`keyed`, `indexes`, fragments and `MountPoint.moveTo`. The native layout sorts
numbers; it does not allocate number ranges for several directive siblings.
Compose owns keyed identity and movement, but the adapter also combines
authored order with directive order. Dropping the wrapper can interleave
unrelated siblings. Move only this general range mechanism upstream; see
proposal D. Risk is high for mixed static and dynamic children.

### 6. Overlay geometry readiness: about 50 lines, medium risk

Source: [rest.luau](../../src/ui/rest.luau), lines 14–85, and
[nav_overlay_presence.luau](../../src/ui/nav_overlay_presence.luau),
lines 96–145. Facet waits for repeated geometry, font readiness and visibility,
then holds measured extents during an appearance transition.

Checked `AutomaticSize`, `TextBounds` and `RunService.PreRender`, then
Compose `presence`, cells, formulas and timelines. Native geometry supplies
the facts. Presence supplies departure retention, as shown in
[presence.luau](../../src/vendor/compose/core/structure/presence.luau),
lines 13–31 and 76–105. Neither API reports that all layout and fonts are ready.
Proposal C could remove the sampling and restart lifecycle. Keep the overlay's
decision about when to show content. Risk is medium because an early ready
result can reveal a zero-size or moving panel.

### 7. Scroll child minimum height repair: about 40 lines, high risk

Source: [layout.luau](../../src/ui/layout.luau), lines 331–415.
The Scroll path derives a minimum height, adds a UISizeConstraint and briefly
turns off AutomaticSize when the viewport shrinks. It restores CanvasPosition
after the engine has another frame to lay out the child.

Checked [UISizeConstraint](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/UISizeConstraint.yaml),
[UIFlexItem](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/UIFlexItem.yaml),
`UIListLayout` flex sizing and `AutomaticSize`, then Compose formulas and frame
subscriptions. The engine supplies constraints and flex. The extra frame
repair preserves the authored size and scroll position during shrink.
Remove only the repair if Studio proves the constraint alone is sufficient.
Risk is high for nested vertical flex content and viewport shrink.

### 8. Released spring lifecycle: about 35 lines, medium risk

Source: [settle.luau](../../src/ui/settle.luau), lines 21–77.
Facet starts a spring with release velocity, stops it at a crossing for a
critically damped spring, and publishes nil when the motion ends.

Checked TweenService and `UIDragDetector`, then Compose `runtime.spring`,
`createSpringState`, `stepSpring` and `springAtRest`. Facet already uses the
Compose integrator; it does not have a second spring solver.
[spring.luau](../../src/vendor/compose/core/animation/spring.luau), lines 61–77,
uses a distance-relative rest tolerance. Facet uses absolute position and
velocity thresholds and a crossing rule. Replacing the lifecycle with a
standard spring changes release behavior. A future controlled spring API
would need initial velocity, restart, stop and a completion readable.
Risk is medium for Sheet release and collection snap. Do not change theme
timing to make the two results look similar.

### 9. Measured scroll canvas: about 20 lines, medium risk

Source: [measured_scroll.luau](../../src/ui/measured_scroll.luau), lines 27–63.
Facet uses an automatically sized flow in a large measurement frame, rounds
the measured height and writes CanvasSize.

Checked [ScrollingFrame](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/ScrollingFrame.yaml)
`AutomaticCanvasSize`, `AbsoluteCanvasSize` and `AbsoluteWindowSize`, then
Compose formulas and property observation. AutomaticCanvasSize can derive a
canvas from children. Here the measurement parent has a deliberate height of
100000 and the reported flow uses layout units. A direct switch can include
that measurement parent in the canvas and change scale and rounding behavior.
Replace the measurement hierarchy as one change, with Studio checks for hug
width, wrapped text, UIScale and shrinking content. Risk is medium.

### 10. Shared property subscription lifetime: about 15 lines, medium risk

Source: [context_observe.luau](../../src/ui/context_observe.luau), lines 77–176.
Facet holds one cell and subscription per Instance and property, counts users,
and removes the entry at the last release.

Checked property change signals, then Compose `createSharedResource`, owners
and cells. Compose already supplies acquisition and last-release cleanup.
The map could hold acquisition functions instead of records with user counts.
Keep the SelectedObject touch policy, PreferredInput withholding, selection
hooks and preview values. These change the value, not just its lifetime.
Risk is medium because synchronous re-acquisition and selection callbacks must
retain their order. A focused lifetime test must cover two owners and a last
release followed by a new acquisition before this change is safe.

### 11. Focus ring event ownership: 3 lines removed, low risk, implemented

Source before replacement: [environment.luau](../../src/ui/environment.luau),
lines 77–80. Current source: line 77.

Checked `UserInputService.LastInputTypeChanged` and `GetLastInputType`, then
Compose `runtime.connect` and `owner.own`. Native Connect supplies the event;
Compose owns the same unsubscribe. The pinned implementation in
[runtime/init.luau](../../src/vendor/compose/core/runtime/init.luau),
lines 443–471, registers the host unsubscribe with the active owner.
There is no behavior difference. The callback, initial input sample and
native event stay the same. The existing owner assertion makes the owner
requirement explicit. Risk is low because only subscription custody changes.

The new case in [native_environment.verify.luau](../../tests/native_environment.verify.luau)
passed before and after replacement. It checks initial keyboard visibility,
pointer, touch and gamepad changes, one extra subscription and release on
unmount. The source changes from four lines to one line.

## APIs already in use and boundaries

These checks do not add more deletion estimates.

| Area and source | APIs checked | Result and behavior boundary |
| --- | --- | --- |
| [layout_kit.luau](../../src/ui/layout_kit.luau), lines 78–108 and 154–242; [layout.luau](../../src/ui/layout.luau), lines 436–493 and 848–879 | UIListLayout, UIGridLayout, UIFlexItem, UIPadding; Compose bindings | Already native. Token and alignment conversion is Facet policy. No second general layout solver was found in these ranges. |
| [media_text.luau](../../src/ui/media_text.luau), lines 47–82 and 236–258 | TextBounds, TextFits, TextScaled, UITextSizeConstraint, TextService:GetTextBoundsAsync; Compose cells | Text size bounds already use a native constraint. Middle truncation retains both ends; TextTruncate.AtEnd and SplitWord do not. Keep this policy. Native text measurement can replace a hidden probe only after styled font and text results match. |
| [nav_notice.luau](../../src/ui/nav_notice.luau), lines 192–235 | TextService:GetTextBoundsAsync, TextBounds, AutomaticSize; Compose watch | Already uses native measurement. The ticket rejects stale async results; removing it can apply old text geometry. |
| [scrolling.luau](../../src/ui/scrolling.luau), lines 21–127 | CanvasPosition, AbsoluteCanvasSize, AbsoluteWindowSize, TweenService; Compose animation | Already native scrolling and tweening. Ancestor reveal and reduced-motion policy remain. The checked ScrollingFrame reference has no ScrollToTop method. Top uses CanvasPosition.Y = 0. |
| [scroll_chain.luau](../../src/ui/scroll_chain.luau), lines 96–188 | ScrollingFrame.ScrollingEnabled, ScrollingDirection, ElasticBehavior; Compose owner cleanup | Native scrolling does not specify this cross-ancestor gesture handoff policy. Do not remove it based on ElasticBehavior alone. Requires real nested touch scrolling evidence. |
| [collections.luau](../../src/ui/collections.luau), lines 125–147 and 294–320; [collection_table.luau](../../src/ui/collection_table.luau), lines 345–371 | CanvasPosition; Compose OrderedCollection controls and desiredOffset | Compose already owns placement, extent and anchoring. Table now chooses its own sort policy through setOffset. VirtualList, VirtualGrid and Outline retain anchoring. See proposal E. |
| [slider.luau](../../src/ui/slider.luau), lines 476–536 and 639–659; [drag_session.luau](../../src/ui/drag_session.luau), lines 845–886 | UIDragDetector axis, limits and CustomOffset; Compose cells | Slider already uses detectors. Range value validation and commit policy remain. Drag edge autoscroll also supports custom target.scroll callbacks; it is not an automatic detector replacement. |
| [context_actions.luau](../../src/ui/context_actions.luau), lines 306–313 and 402–421 | InputContext, InputAction; Compose ownership | Native action construction is already present. No replacement claim is made for the rest of this module. |
| [theme_stylesheet.luau](../../src/ui/theme_stylesheet.luau), lines 306–390 | StyleSheet, StyleRule:SetProperties, SetPropertyTransitions; Compose keyed and watch | Already uses native style rules and transitions. Caches avoid repeated writes. Removing them can restart transitions; no safe deletion is claimed. |
| [media_path.luau](../../src/ui/media_path.luau), lines 23–80 | Path2D:SetControlPoints; Compose watch | Already uses the native path renderer. Point conversion and theme tags remain. There is no polyline renderer to delete here. |
| [nav_stack.luau](../../src/ui/nav_stack.luau), lines 66–103 and 149–210 | CanvasGroup; Compose LayerStack, presence and springs | LayerStack already retains pages. The leaving entry supports pop animation and selection handoff. Presence alone does not supply stack role or history policy. |

`UIAspectRatioConstraint` was also checked in the engine reference. It fixes a
ratio; it does not replace content measurement, column priority or text fit.
Compose cells, formulas, owner scopes, portals, keyed structure and inspect
were checked as public mechanisms. Inspect reports state and lifetimes; it
does not schedule layout or replace a control's state policy.

## Upstream proposals

These are API sketches, not APIs available in the pin. No upstream code or
dependency snapshot is changed by this census.

### A. Owner-bound sequence tracks

Motivation: a timeline reports time but consumers still compile serial and
parallel callbacks. Stable equal-time ordering and reentrant cancellation are
general mechanisms.

API sketch: `runtime.sequence({ steps = { { seconds, delay, ease, sample,
onStart, onEnd, parallel } }, onCompleted })` returns `play`, `cancel`,
`finish`, `running` and `completed`. Callbacks run under the captured owner.
Cancel or replay inside a callback invalidates the remaining events of that
run. Zero-duration phases have a defined event order.

Facet would delete the phase compiler and event dispatcher from
`effect_sequence.luau`. Its adapter would resolve theme token names to seconds
and easings and apply reduced-motion policy.

### B. Native Instance candidates for focus scopes

Motivation: Compose focus scopes accept candidates, but native UI consumers
must collect visible, selectable descendants and track the root lifetime.

API sketch: `Roblox.focusCandidates(runtime, root, { order = "document",
include, boundary }) -> Readable<{ GuiObject }>` feeds `createFocusScope`.
The adapter must define hidden ancestor rules, stable equal-order ties and
when changes to descendants publish. It must not create another scene graph.

Facet would delete repeated Instance candidate collection and ordering in
`selection.luau`. It would retain modal choice, responder policy and native
GuiService selection. Adoption needs Tab and gamepad tests in Studio.

### C. Frame-coherent host observations

Motivation: property signals and derived engine geometry do not always publish
together. Several consumers need one read phase followed by one cell batch.

API sketch: `runtime.observeFrame(node, properties, { phase = "beforePaint" })`
returns readables. One shared host subscription reads all registered values,
then publishes them in one reactor batch. An optional `runtime.whenStable`
accepts a sample and readiness predicate, with restart and disposal support.
The host selects PreRender; core does not import Roblox.

Facet would delete the queue in `geometry_observation.luau` and the general
frame and restart lifecycle in `rest.luau`. It would retain font and overlay
readiness predicates. Missing-signal, disposal, no-frame and same-frame
cross-property cases are required before adoption.

### D. Ordered native child ranges

Motivation: keyed structure orders one population. Several adjacent dynamic
populations also need stable native LayoutOrder ranges.

API sketch: a Roblox mount option `childOrder = { range, authored = "relative" }`
assigns native order while preserving authored offsets inside each range.
Insert, move, remove and late LayoutOrder changes must have defined results.
The native UIListLayout still performs layout.

Facet would delete the directive slot, stamp and property listener tables in
`layout_kit.ordered`. It would retain control-specific placement callbacks.
Do not change the current authored-offset rule as part of the move.

### E. Collection reveal and explicit reflow policy

Motivation: OrderedCollection has index and placement queries, but no operation
that requests the minimum offset to reveal a key. The pinned
[ordered-collection.luau](../../src/vendor/compose/core/structure/ordered-collection.luau),
lines 319–340 and 392–405, provides aligned index offsets and anchor movement.
A sort owner must coordinate a request with the new order.

API sketch: `controls.revealKey(key, { align = "nearest" })` requests an
offset after the next order update. A separate optional
`reflow = "anchor" | "offset"` selects whether a permutation keeps the first
visible key or the numeric offset. The default must remain `"anchor"`.
Insertion and removal rules must be explicit. Do not make all permutations
reset automatically: VirtualList documents anchor retention.

Facet could delete Table's key-order readiness scan and selected-row offset
calculation. Table would still choose top versus selected row on a sort.
This proposal is not needed to ship the current Table fix.

## Integration evidence still needed

Run the playlist Table in Studio at wide and compact sizes. Sort from the top
with no selection, with one selection and with several selections. Check the
first row, the whole selected row, the scrollbar thumb, horizontal scroll and
an ancestor UIScale. Check a selected row that is removed or hidden by a tree
branch. Check long wrapped rows and a row taller than the viewport; a row
taller than the viewport cannot be fully visible.

For the subscription replacement, switch keyboard, mouse, touch and gamepad
while the focus ring is mounted. Unmount and remount it. Check selection
visibility and cleanup. The native double checks policy and ownership, not
real device input.

Do not apply the geometry, focus or motion follow-ups until their behavior
differences have a regression spec and live Studio evidence. No Studio run was
made for this work.
