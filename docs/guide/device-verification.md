# Device verification

The engine double checks Facet policy, bindings and cleanup. It does not prove
native layout, glyph paint, hit testing, IME or physical-device performance.
Use live Studio evidence for engine behavior and physical devices for hardware
claims. See [verification scope](verification-scope.md).

## Choose cases from independent constraints

Width, height, physical readability, input and player preferences can change
independently. Test combinations that expose different failure modes; one
phone preset and one desktop preset do not cover them.

Choose supported contexts from the brief and product configuration. Phone
support includes both orientations unless the product deliberately restricts
them. A test brief that samples only landscape leaves portrait unverified;
it does not establish an orientation restriction in the product.

For a new multi-device composition, declare the minimum supported usable width
and height for each orientation. Follow the [minimum-viewport procedure](../../skills/use-facet/references/compact-compositions.md#verify-the-minimum-viewport)
for choosing limits, measuring the safe rectangle, testing complete painted
bounds and proving routes by input. An unspecified range needs provisional
tests at the smallest available phone preset in both orientations, plus a
notched case when its insets impose different constraints. A larger preset
does not stand in for a smaller supported viewport.

Inspect a wide view and these minimum
narrow and short layouts in the first runtime prototype, before
extending the screen's routes. Portrait and landscape expose different limits;
there is no single phone viewport that proves both. Record the mounted safe
area after insets and control scaling.
Check actual button and text bounds: minimum touch targets can exceed authored
heights. Include focus strokes, selection marks and clipping ancestors. A
visible, clickable center does not prove the whole action fits. If scrolling
is intended, reveal and activate the complete target through real input.
Recompose content that cannot fit instead of compressing a fixed stack.

| Context | Evidence to collect |
| --- | --- |
| Wide desktop with pointer, keyboard only, then gamepad | Useful comparison detail, complete command routes, stable task during input changes |
| Narrow and short windows | Actions, consequences and exits remain reachable; headers do not consume the decision area |
| Touch in both phone orientations | Thumb reach, movement-control clearance, target spacing and scroll versus drag |
| High-resolution handheld at normal holding distance | Text and glyph readability, short-height fit, controller access and on-screen keyboard behavior |
| Television at intended viewing distance | Readable focus and text over gameplay, safe edges and complete navigation |

For example, use a ROG Ally when it is a supported target. Record the actual
display, viewport, scaling and input configuration. A desktop window with the
same pixel dimensions tests available room; it does not reproduce the physical
screen size, grip or viewing distance. A gamepad profile does not establish
television or handheld readability.

Cross the constrained cases with the largest supported text preference, long
localized content and reduced motion. Check bright and busy gameplay as well
as quiet backgrounds. Keep theme, input and device settings available during
the review. Use Facet environment previews for controlled comparisons; they
do not change the physical input device or prove hardware behavior.

Check each materially different layout state the task uses, not only its
opening screen. For example, confirmation terms and accepted feedback can
need more room than a choice list. At larger text, check labels, painted edges,
target sizes and reachable exits in each supported phone orientation. Rotate
the open task and verify that the selection, draft and next action remain usable.

## Exercise complete tasks

Start from gameplay and complete the player's task without explaining the
intended route. Observe whether the player finds the entry, understands the
current state, chooses an action, recognizes its accepted result and returns.
Record hesitation, repeated navigation, wrong activations and recovery as
well as outright failures. A technically reachable command can still be hard
to discover or costly to use.

Use real input for the first press after spawn, HUD entry, scrolling, text
editing, nested Back and return focus. Check canceled and rejected work,
disabled or removed targets, and a controller-only path to settings. Open the
on-screen keyboard and verify that the field, error and completion route stay
reachable. Calling a callback does not establish any of these routes.

While the task is open, change input, viewport and text preference. Disconnect
and reconnect the controller. Preserve drafts, object identity and a usable
exit. A held input or layout change must not activate a new target. Check that
UI input does not also reach gameplay and that gameplay input returns when
the task ends. Inspect the game behind the UI; idle surfaces must settle
without moving targets.

Exercise platform shortcuts while a full-screen game menu is open. Check for
unrelated player lists, movement controls or other platform UI covering its
choices. The game may temporarily hide a specific optional CoreGui surface
that conflicts with that task. Preserve its previous enabled state and restore
it when the menu is disposed. Keep useful platform UI available; do not hide
all CoreGui as a default design fix.

Watch the middle of each changed transition, not only its settled screens.
Check forward, Back and interruption for doubled text or subjects, exposed
covered pages, clipped paint and moving action targets. Confirm that the motion
fits the change: entering a deeper page can justify a slide; accepting an action
does not by itself require one. Repeat with reduced motion.

Compare the main action's bounds before activation and after pending, error
and success feedback appears. Within the same task, added or wrapped status
text should not move the action. Check the longest supported message and text
scale without clipping the feedback. Keep the pointer in place and test the
controller focus through the transition. A replacement command needs a fresh
activation; holding or releasing the previous input must not activate it.

Maximize the owned Studio on one monitor and verify its actual camera viewport.
A responding Model Context Protocol (MCP) session with a tiny viewport is not ready. Verify
rendered frames and input before recording a run.

## Run live cases

Use the existing Verify-backed suites in `tools/studio/live/suites`.
Discover commands and suite names through the CLI rather than copying an old
list of cases:

```sh
lute run tools/facet studio live --help
```

For a corrected case in an already built place:

```sh
lute run tools/facet studio live classb_collections --studio STUDIO_ID --device none --tag review --cases-from-tree --only fill-column-floors-and-hit-order
```

`--cases-from-tree` updates cases only. It does not replace Facet or example
modules in the open place. Rebuild when those modules change. Reports identify
whether case source came from the working tree or the place. Use `--device keep`
when preserving an attached gamepad device profile.

Suites declare contracts and assertions. Interactive cases use setup and named
steps. The fixture reads native bounds, text and selected objects; it records
measurements separately from assertions. Fixture sizing can emulate room
without changing the camera; use the actual device profile when testing input.

For native input paths, use Studio MCP user input or the live runner's documented
interactive path. Setting SelectedObject alone does not prove traversal, and
calling a callback does not prove hit testing.

For emulated gamepad input, open Studio's Controller Emulator and use its
displayed keyboard mappings. Confirm that the client receives gamepad input
and that selection, activation and return work. Plain Tab, arrow and Return
navigation checks the keyboard path; it does not prove the virtual controller
path. Device Simulator alone changes the device preview, not the input source.

Record the input the client actually receives. An attached virtual controller
can remain the preferred input after switching to a desktop or phone preview.
Test pointer and touch delivery as well as the controller, and verify that
changing input preserves the task. Do not infer the active input from a device
label or assume the virtual controller always uses the first gamepad slot.

## Record the result

Record source revision, device, viewport, input, viewing distance, player
preferences, starting state, player action, observed result, errors and
supporting captures. Distinguish automated assertions, observed Studio behavior
and physical-device observations. If a device was not tested, name that gap
instead of inferring a pass from its resolution or input profile.

Recheck a repaired state and adjacent layouts. Associate each capture and input
result with the source it tested; a late patch does not inherit an earlier
visual pass. Retain earlier evidence for unaffected states and name any gaps.
A screenshot does not establish operation; a passing subset is not full evidence.
Keep generated reports in artifacts, not dated guide chapters.
