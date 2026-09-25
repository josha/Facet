# Device verification

## What a headless run proves

A headless native engine double verifies bindings, event cleanup and control
policy. It does not run engine layout, hit testing, text shaping, IME or input
routing. Claims about those behaviors need evidence from live Roblox Studio or
from a physical device.

## What to exercise

Build and run the actual gallery and the virtual monitors. Exercise:

- compact and wide sizes,
- keyboard and gamepad selection,
- pointer and touch controls,
- preferred text size,
- reduced motion,
- theme switching,
- modal Back and focus restoration.

For the virtual monitors, also exercise:

- spatial and flat switching,
- Discover sorting and scanning,
- Avatar scene controls,
- streaming Chat while you scroll.

## What to record

Record the build revision, the scenario, the observed interactions and the
engine errors. Keep benchmark evidence and live evidence separate. A pre-cutover
screenshot or a passing subset does not prove the behavior of this
architecture.

The [verification scope](18-verification-scope.md) lists the live evidence
that is still outstanding.

## Live assertion harness

`tools/studio/live` is a set of Luau modules. They run assertions against the
real Roblox engine in a Studio playtest. The engine does the layout, the text
measurement and the selection. The harness reads `AbsolutePosition`,
`AbsoluteSize`, `TextBounds` and `GuiService.SelectedObject`, and it writes a
JSON result.

The studio sync puts the modules in `ReplicatedStorage.FacetLive`. Each module
in `tools/studio/live/suites` is one suite. A suite returns a list of cases. A
case has an `id`, the parity `contracts` that it proves and a `run(t)`
function. An interactive case has `setup(t)` and named `steps` in place of
`run`. The `t` object gives these helpers:

- `t.mount(build, options)` mounts a fixture with its own runtime, controls
  and StyleSheet. The options are `theme`, `size` (a Vector2 or a readable)
  and `frames`.
- `t.check`, `t.near`, `t.inside` and `t.fits` record assertions.
- `t.note` records a measurement that is not an assertion.
- `t.themes` lists every theme package that builds.
- `t.scenario(name)` and `t.context(...)` mount a gallery scenario.
- `t.gallery({ size, demo })` mounts the whole gallery shell in the fixture.
- `t.stable(node)` waits until the rectangle of the node stops changing.
- `t.offenders(root, bounds)` lists the visible objects that cross the bounds
  sideways or vertically, and the text that is drawn outside its box. It
  uses only the part of each object that its clipping ancestors show.

When you give `size`, the fixture is the screen. The controls get a viewport
of that size, and `overlayParent` is a frame of that size. Thus alerts,
callouts, menus and adaptive rules use the fixture and not the camera. Give
`emulate = false` to keep the camera viewport.

### Run the suites

1. In the worktree, run `lune run tools/lune/studio_sync.luau`. It serves the
   sources and saves results on port 8642.
2. Stop the playtest. In the Edit data model, run `tools/studio/inject.luau`.
3. Start the playtest. In the Server data model, run
   `require(game.ReplicatedStorage.FacetLive.relay).start("http://127.0.0.1:8642")`.
4. In the Client data model, run
   `require(game.ReplicatedStorage.FacetLive).record("<tag>")`.

`record` runs the `layout_geometry`, `gallery` and `needs_live` suites. It
saves each result as `artifacts/studio-live/<suite>-<tag>.json` and returns a
summary. Use a tag that names the viewport and the text size, for example
`portrait-largest`. `run(suite, options)` runs one suite and returns the JSON.
The `only` option selects cases by id. The other suites are `primitives`,
`needs_live_b`, `needs_live_c` and `native_mechanisms`. The suites
`needs_live_input` and `native_mechanisms_input` have interactive cases, and
`native_mechanisms_input` covers engine mechanisms that have no headless
oracle.

An interactive case needs real input between its steps:

1. Run `begin(suite, id)` in the Client data model.
2. Send the input with the Studio input tools.
3. Run `step(name)` for each step of the case.
4. Run `finish(tag)` to save the result.

### Set the device and the text size

Use the Device Emulator for the viewport and the orientation. In the Client
data model, `StudioDeviceSimulatorService` also sets the device from a
script:

- `SetDeviceAsync(id)` selects a device, for example `iphone_14`, `xbox`,
  `ps5` or `generic_handheld_720`.
- `SetResolutionAsync(width, height)` sets the viewport of the device.
- `SetOrientationAsync(Enum.ScreenOrientation.Portrait)` turns the device.
- `StopSimulationAsync()` stops the emulation. Then the viewport follows the
  size of the Studio window.

Scripts cannot write `GuiService.PreferredTextSize`. To test the largest text size, open the
Roblox menu in the playtest and set Settings > Text size to Largest. The
result records the viewport, the safe inset, the preferred text size and the
source stamp.

### Limits of the harness

- Studio input tools send D-pad key codes as keyboard input. Engine
  selection does not move for them. Use the arrow keys for the native
  selection path, and record the D-pad path as a device check.
- Studio does not play haptic motors. The harness proves that a control
  requests the effect. A physical phone or gamepad must confirm the output.
- A horizontal drag from the Studio input tools can arrive as a tap. Confirm a
  swipe with a real pointer or touch drag. The mouse moves of the input tools
  do not fire `InputChanged` while a button is held, so a `UIDragDetector`
  does not start.
- The input tools refuse Tab and Escape, because the core interface owns
  them. They also send `ButtonA` as keyboard input, and engine activation does
  not use it.
- While a `GuiButton` has the selection, the engine uses Return for the native
  activation of that button. No `InputAction` that binds Return fires, also
  with a modifier key.
- The input tools cannot open the Roblox menu, so a live run cannot change the
  text size. Record the Largest text size on a device or in a session where a
  person opens the menu.
- After `SetDeviceAsync`, `UserInputService.PreferredInput` can change some
  frames later. `t.device` waits until the preferred input is steady, and a
  case can pass `input` to wait for one value.

### Engine behavior found by the harness

- A read of `AbsolutePosition` in the same frame as a reparent or a scroll
  can return the old value. The engine can then correct the value without a
  change signal. The affixed Notice reservation and the menu landing row read
  the geometry again on the next `Heartbeat`.
- The height of an automatic-size label is limited by the nearest ancestor
  that does not grow on that axis. In a scroller, that is the window and not
  the canvas. A long label in a chain of automatic-size frames inside a
  scroller is thus cut at the window height. Put the content in a frame with
  a fixed, very tall height, and set the canvas from the measured content.
- A text size that is scaled from a measured width can be 1 px too wide for
  some words. Read `TextFits` after the engine draws the text, and step the
  size down while it is false.
- A 12 px error line next to a 16 px mark is the caption line height, not a
  stale height. The mark height follows the line.
- After a style sheet sets the text size, a label can keep its old height,
  and `TextBounds` can change with no change signal. Read the size again on
  later frames, and change the `Size` for one frame to measure it again.
- The engine hit-tests a rotated object in its unrotated box.
- The Studio mouse input tools take points in the same space as
  `AbsolutePosition`. Do not add `GuiService:GetGuiInset()`.
