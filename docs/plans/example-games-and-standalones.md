# Game tutorials and standalone example polish

**Date:** 2026-08-15
**Status:** Planned after the release-candidate review and before public-repository
preparation.

## Purpose

Make the three tutorial games feel understandable and complete in play. Make the
sensory-feedback demo useful as soon as it opens. Add one interactive Facet surface
inside the 3D world. Turn a small, curated part of the showcase into standalone places
that teach important Facet ideas through believable game screens. Remove obsolete
example material after proving that nothing still uses it.

This is a product pass, not a gallery rewrite. Reuse the exact tutorial and scenario
modules that the showcase runs. Do not fork a second implementation for a standalone
place.

## Authority and release-review boundary

Examples own game rules, content, deterministic fixtures, teaching copy, and declared
composition. Facet owns reusable layout, focus, input, adaptation, accessibility,
theme, motion, transition, resource, and lifecycle behavior. Create a responsibility
ledger before editing. Fix a framework defect or missing general mechanism in Facet,
then make the example consume its public API. Do not hide a framework need in an
example-only tween, geometry loop, input branch, or raw GUI helper.

Step 13 has already reviewed the release candidate. Prefer example-only changes except
for the required, already-declared `SurfaceGui` render-target seam. If this stage
changes Facet source, public behavior, assets, or contracts, update every affected
Rascal Rally caller and contract test, rerun the affected Step 13 review rows and
gates, and refresh the frozen release evidence. Documentation and examples must
continue to pass Step 13's product-language and clear-writing guards.

Register `example-games-and-standalones` before implementation with honest pending
checks. Extend existing example, place-build, device-matrix, artifact, and gate tools.
Do not recreate them.

## Five-letter word game

Replace the hand-picked tutorial vocabulary with a real, local five-letter English
dictionary. Use a redistribution-compatible source and record its URL, version or
content hash, license, transformations, and generated-file command. Do not copy a
proprietary game's word lists or depend on a network request at runtime.

Prefer the versioned SCOWL/English Speller Database American-English source and carry
its required notices; it is designed to generate redistributable spelling lists under
BSD-compatible terms. If the current release or selected data has different terms,
record the conflict and use another clearly compatible source instead.

Keep two sets:

- a broad accepted-guess set containing thousands of normalized five-letter words;
- a smaller reviewed solution set containing familiar words suitable for players.

Normalize once at build time. Runtime validation must be deterministic and fast.
Measure source/build size and lookup cost. Test representative common words across the
alphabet, inflections present in the source policy, obvious nonwords, every solution,
and dictionary provenance/drift. Remove the phrase “tutorial word list.” A rejected
guess should say plainly that the game does not recognize the word.

At startup, all thirty board cells must be visibly present under every shipped theme.
Each empty cell needs persistent chrome or a placeholder; the active row and next
letter position need a clear non-color-only cue. Filled and scored letters must remain
readable at all preferred text sizes. Preserve correct two-pass duplicate scoring,
keyboard evidence, win/loss, deterministic restart, and all supported input paths.
Play common guesses that the old tiny list rejected.

## Crossword tile game

Replace “put every rack tile into any empty box” with one clear, finite word-building
loop. Use a small crossword-style board and the shared example dictionary:

1. The first turn must cross the highlighted center cell.
2. A turn places rack tiles in one contiguous row or column.
3. Later turns connect to at least one committed tile.
4. **Submit word** validates the complete line, commits it, scores it, and refills the
   rack from a deterministic bag.
5. **Undo turn** returns uncommitted tiles to the rack.
6. Invalid placement or word explains the exact problem and preserves recoverable
   state.
7. A visible goal and bounded turn count produce win/loss, summary, and restart.

Show legal next cells, selected tile, uncommitted versus committed letters, current
word, score, goal, and turns. Give the player an obvious first action and a guaranteed
opening move. Keep board and rack navigation natural for pointer/touch, keyboard, and
gamepad. Put shared word data and pure word validation in one example-domain module;
do not put crossword rules in Facet.

Test placement direction, gaps, center/connectivity, crossing consistency, dictionary
accept/reject, commit, undo, scoring, refill, end states, reset, rapid input, and
teardown. Play at least one win and each major refusal in Studio.

## Match-3 motion

Keep deterministic board logic, legal-opening guarantees, async-image recovery, and
multi-input play. Give every tile a stable identity so motion represents the same tile
moving rather than a picture changing inside a fixed cell.

A successful action must visibly sequence:

1. the two selected tiles move to their proposed positions;
2. an invalid swap returns them to their original positions with feedback;
3. a valid match marks and removes the matched tiles;
4. surviving tiles drop into their new rows;
5. new tiles enter from above or through a clear bounded appearance transition; and
6. cascades repeat the match, removal, drop, and refill sequence before input unlocks.

Use public `presenter.withAnimation` for surviving keyed movement and the public
structural-transition system for insertion/removal. Use the framework's clock or
completion seam for the resolution state machine. Do not use `TweenService`, frame
loops, arbitrary `task.wait`, raw instance offsets, or a second animation system.
Queue or refuse input visibly while resolving so rapid actions cannot corrupt state.

Under reduced motion, preserve ordering, feedback, final state, and total game rules,
but remove decorative travel and long chained flashes. Do not replace removed travel
with another busy effect. Bound simultaneous moving/flashing tiles. Test intermediate
motion evidence as well as endpoints, stable identity, interruption/reset, cascades,
no lingering records, full/reduced parity, and unchanged deterministic replays.

## Sensory-feedback demo

Move the haptics control panel to the top of the scroll content, directly after the
title and short introduction and before the controls it affects. The enabled toggle,
its status, and the short explanation must be inside the initial viewport without
scrolling on the automated compact portrait, short landscape, desktop, and ten-foot
profiles, including Largest text. Prove this from rendered order and geometry, not
source order alone.

The demo's haptics toggle starts on at every fresh mount. This is a demo choice, not a
change to Facet's game-opt-in haptics contract: the example explicitly requests and
installs the adapter so pressing a sample control can demonstrate the feature
immediately. If the host refuses haptics or support cannot be determined, leave the
requested toggle on and report that result accurately. Never claim that a player felt
a vibration when Roblox cannot expose that fact. Rewrite any “switch below” or
“default off” demo copy so this distinction is clear.

Turn the main lesson into four clearly labeled, playable comparisons that use the
Step 13 public API:

1. **Press:** an ordinary control with no local override demonstrates the built-in
   contact waveform when the primary action goes down.
2. **Release:** the same interaction makes its distinct built-in release phase clear
   when a valid press ends. A canceled press must show the documented silent or cancel
   outcome instead of pretending that activation succeeded.
3. **Selection:** a real discrete choice or value control demonstrates the built-in
   selection tick only when its selected value changes. Passive hover and a no-op
   choice must not fire it.
4. **Custom:** one control uses Facet's documented public override/profile seam to
   play an obviously distinct, bounded custom waveform. The example must not construct
   `HapticEffect` directly or reach into adapter internals.

Use visible pressed/released/selected/custom state and a bounded event history so a
player can understand which phase was requested without reading source and automated
Studio proof can observe it without feeling the device. Show the active profile and
whether each row uses a built-in default or the example's custom override. Do not
confuse a visible request with proof that the motor fired. Keep the existing semantic
feedback examples when they teach a different concept, but remove redundant map tables
or copy that makes the four primary interactions hard to find.

Turning the toggle off must detach and dispose the adapter and its effects. Turning it
on again must install exactly one working adapter. Reopening or rebuilding the example
must restore the on default; scenario changes and teardown must leave no adapter,
effect, connection, or stale state. Add failing tests first for the initial value and
install attempt, top-of-page geometry, honest requested/refused/undetermined states,
the exact Step 13 default waveform/profile identities, press-before-release order,
selection only on change, canceled/no-op silence, a distinct custom profile, off/on
cycles, remount, and cleanup. Exercise every comparison through pointer/touch proxy,
keyboard, and gamepad without duplicate pulses. Preserve separate tests that prove the
Facet library does not enable haptics until a game opts in.

Play a fresh launch and the off/on cycle in Studio with pointer/touch proxy, keyboard,
and gamepad. Capture the first viewport with the toggle visibly on. Studio may prove
the request, adapter, effect assignment, and status; actual physical sensation remains
a named device-verification item.

## World terminal: two-dimensional UI on a 3D surface

Add an **Outpost Power Terminal** to the showcase and emit it as its own standalone
place. The player walks to a physical console, uses it to allocate a limited power
budget among a door, beacon, and workshop, applies a valid allocation, and sees nearby
world objects respond. Give the player a clear objective, constrained choices, exact
validation feedback, success, reset, and exit. The terminal should feel like a small
piece of a real game, not a render-target diagnostic with buttons.

This is ordinary two-dimensional Facet rendered by a `SurfaceGui`. It is not the
declarative Part/Model layout considered in Step 12, and it is not VR, ray, hand, or
gaze support. Reuse the same declarative terminal-content module in the showcase and
standalone hosts. Example code owns the power-allocation rules and world fixture.
Facet owns the reusable world-surface render target, layout, styling, input, focus,
motion, and teardown behavior.

Follow `docs/extending/new-render-target.md`, `ADR-0003`, `ADR-0021`, and the open
questions in `target_contract.FUTURE.surface`. Run the required Studio spike before
publishing an adapter. If the spike succeeds, add one public client-side
`surface_target` adapter by reusing the existing target/root-factory seam; do not add a
second renderer or put `SurfaceGui` branches in controls. Replace the obsolete
“not implemented” declaration and update the ADR, API, constitution, guide, extension
playbook, registration, boundary, property-parity, conformance, and performance truth.

The first supported policy is a fixed virtual-pixel canvas with explicit face,
resolution, maximum distance, and `AlwaysOnTop = false` unless evidence requires a
different value. The `SurfaceGui` must be client-owned under `PlayerGui`, point its
`Adornee` at the replicated console part, and require the part to remain queryable.
Set `presentationSpace = "world"`; feed the solver the exact canvas rectangle. Prove
native StyleSheet/theme resolution, clipping, text measurement, focus visuals,
legibility, occlusion, pointer coordinates, and every optional adapter capability.
Implement a capability correctly or remove it with its named degradation; never let a
screen-capability method appear to work when its coordinate space is wrong.

Use a Roblox `ProximityPrompt` on an Attachment as the native, cross-input walk-up
invitation. Triggering it engages one Facet responder/focus scope. Direct pointer and
touch activation must work on the physical screen. Keyboard and gamepad then use the
same semantic Input Action System actions and logical focus as screen UI. Do not bind
hardware through ContextActionService or UserInputService in the example. Cancel,
the terminal's Exit control, leaving prompt range/line of sight, character removal,
adornee streaming/removal, switching showcase scenarios, and teardown must resign the
surface, cancel in-flight input, restore gameplay control, and leak nothing. Repeated
trigger/cancel and input hot-switching must be safe.

The UI remains per-player and client-owned. Applying power changes shared world state,
so send domain intent to the server; validate values, authority, rate, and current
player-to-console distance there before changing replicated objects. Never replicate
the UI tree or trust a client-side proximity check.

Studio proof must include the positive `PlayerGui + Adornee + CanQuery` topology and
negative controls for wrong parenting and a non-queryable adornee; pointer, touch
proxy, keyboard, and gamepad entry/use/exit; default and oblique camera angles;
near/far, occluded, streamed/removed, death, and scenario-switch lifecycles; two
materially different themes; Full/Reduced motion if the terminal animates; normal and
Largest text; server refusal of invalid/stale/distant commands; and bounded cost versus the same
showcase at idle. Do not turn Studio emulation into a physical-device or VR claim.

Add a plain-language guide recipe for “put Facet on a part players can use.” Explain
the client `SurfaceGui` topology, native walk-up prompt, responder handoff, shared
world-state server validation, canvas/theme choices, teardown, supported inputs, and
the exact limits (flat world-fixed UI, not declarative Parts or VR). Link the public
adapter API and this example; do not make readers reconstruct the recipe from an ADR.

## Curated standalone places

Keep the seven tutorial places because the guide teaches them. Remove the superseded
plain settings demo if the new shared standalone chrome covers its purpose. Select a
small showcase subset using these required capability families:

- adaptive controls and input paradigms;
- row actions or another platform-dependent interaction;
- `withAnimation` and reduced motion;
- one realistic large virtualized collection;
- one async-resource/loading-and-recovery screen;
- one large-text or narrow-layout adaptation screen; and
- the required Outpost Power Terminal on a real `SurfaceGui` world target.

Prefer one place that teaches more than one related feature. Five to seven curated
**existing** showcase standalones plus the required world terminal is the target (six
to eight total), not one place per scenario. Record why each chosen place is uniquely
useful and why each unchosen scenario remains showcase-only. A
standalone should feel like a small screen from a real game first and a diagnostic
fixture second. It must show a title, the player goal or task, a discoverable first
action, visible success/failure feedback, reset, and a short optional “What this
shows” explanation. Remove test-only jargon and raw counters from the player surface
unless the number is the lesson.

Each standalone imports the same module and metadata as the showcase. Add a checked-in
manifest that drives the showcase registry, presentation target and world-fixture
metadata, standalone project generation, build outputs, documentation, and drift
tests. Do not maintain parallel lists. Emit local, self-contained `.rbxl` files that
the owner can open and publish manually. Do not publish, upload, attach universe IDs,
or require Rojo at play time.

## Theme and motion controls

Every tutorial and curated standalone place must expose the existing theme picker with
the public reference themes mapped into the place. A theme change must update palette,
type, metrics, and applicable chrome without remounting or losing game state.

Every place with decorative or informational motion must expose the shared Full /
Reduced control and write the same `reducedMotion` environment fact as the showcase.
Reuse the showcase settings model and chrome/reservation rules; do not copy them into
each place. The controls must remain reachable without covering the example on small
portrait, short landscape, ten-foot, or Largest-text layouts. Their focus scope must
not trap or steal focus from the example.

## Cleanup

Inventory every example source, generated place, project file, registry entry, test,
guide link, build output, and artifact reference. Delete an old item only when it is
superseded and no tutorial, showcase, standalone, test, gate, document, or build uses
it. Preserve evidence outside the public branch when provenance requires it. Remove
stale generated `.rbxl` outputs, lock files, temporary projects, and dead registry
entries. Prove the manifest rejects an orphaned or missing output.

## Studio proof and gate

Play the three games to completion and use the world terminal through its real
walk-up, engagement, task, and exit loop. Automate the canonical Studio device matrix
for each changed tutorial and each curated standalone. Cover
pointer, hardware keyboard, on-screen pointer/touch proxy, focus navigation, and
gamepad where automation supports them. Do not label emulation as physical touch or
console proof.

Capture neutral and a materially different theme, Full and Reduced where applicable,
normal and Largest text, compact portrait/landscape, desktop, and ten-foot. Pair images
with state, focus, geometry, theme, motion records, mount identity, and Studio output.
Verify clean teardown and no overlapping chrome.

The gate passes only when:

- common dictionary words play, all word cells are visible, and the full word-game
  loop works;
- the tile game has a clear valid strategy, refusals, completion, and restart;
- match-3 shows swap, invalid return, match removal, gravity, refill, and cascades in
  Full motion and preserves outcomes under Reduced;
- the sensory demo opens with haptics requested on and its toggle/status visible at
  the top without scrolling; its visible interactions demonstrate the real built-in
  press, release, and selection defaults plus one public-API custom waveform; off/on,
  remount, capability reporting, phase timing, no-duplicate behavior, and teardown
  pass while Facet's library-level opt-in contract remains unchanged;
- the same Outpost Power Terminal content works through the real client-owned
  `SurfaceGui` target in the showcase and standalone, all target-checklist rows have
  evidence, and gameplay control is restored on every exit/lifecycle path;
- every declared standalone rebuilds and opens from the one manifest with shared
  theme/motion controls;
- the dead-example audit has no unexplained item;
- relevant focused/full suites, prior example gates, Step 13 guards, and any affected
  Rascal Rally checks pass; and
- an independent phase-gate reviewer plays the touched loops and resolves every
  requirement finding.

Store evidence under `artifacts/example-games-and-standalones/`. Physical device
confirmation may remain precisely pending. Report exact commands, results, captures,
artifacts, deletions, and pending rows.
