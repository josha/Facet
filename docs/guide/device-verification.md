# Device verification

The engine double checks Facet policy, bindings and cleanup. It does not prove
native layout, glyph paint, hit testing, IME or physical-device performance.
Use live Studio evidence for engine behavior and physical devices for hardware
claims. See [verification scope](verification-scope.md).

## Choose cases from independent constraints

Width, height, physical readability, input and player preferences can change
independently. Test combinations that expose different failure modes; one
phone preset and one desktop preset do not cover them.

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

## Record the result

Record source revision, device, viewport, input, viewing distance, player
preferences, starting state, player action, observed result, errors and
supporting captures. Distinguish automated assertions, observed Studio behavior
and physical-device observations. If a device was not tested, name that gap
instead of inferring a pass from its resolution or input profile.

Recheck a repaired state and adjacent layouts. A screenshot does not establish
operation; a passing subset is not full evidence. Keep generated reports in
artifacts, not dated guide chapters.
