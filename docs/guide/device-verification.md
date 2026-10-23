# Device verification

The engine double checks Facet policy, bindings and cleanup. It does not prove
native layout, glyph paint, hit testing, IME or physical-device performance.
Use live Studio evidence for engine behavior and physical devices for hardware
claims. See [verification scope](verification-scope.md).

## Exercise complete tasks

Check wide and compact room, both phone orientations, pointer, keyboard, touch
and gamepad. Include larger text, reduced motion, theme changes, modal Back,
scroll access, focus restoration and an open viewport change. Inspect gameplay
behind the UI. Idle surfaces must settle without moving targets.

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

For physical input, use Studio MCP user input or the live runner's documented
interactive path. Setting SelectedObject alone does not prove traversal, and
calling a callback does not prove hit testing.

## Record the result

Record source revision, device, starting state, player action, observed result,
errors and supporting captures. Recheck a repaired state and adjacent layouts.
A screenshot does not establish operation; a passing subset is not full evidence.
Keep generated reports in artifacts, not dated guide chapters.
