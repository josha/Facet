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
real Roblox engine in a Studio playtest. Verify registers the cases, runs them
and makes the report. The engine does the layout, the text
measurement and the selection. The harness reads `AbsolutePosition`,
`AbsoluteSize`, `TextBounds` and `GuiService.SelectedObject`.

The live place has the modules in `ReplicatedStorage.FacetLive`. Each module
in `tools/studio/live/suites` is one suite. A suite returns a list of cases. A
case has an `id`, the parity `contracts` that it proves and a `run(t)`
function. An interactive case has `setup(t)` and named `steps` in place of
`run`. The `t` object gives these helpers:

- `t.mount(build, options)` mounts a fixture with its own runtime, controls
  and StyleSheet. The options are `theme`, `size` (a Vector2 or a readable)
  `frames`, `motionLevel` and `environment`.
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

### Appearance continuity

`motion_continuity` samples rendered frames during entrance, including the
first visible frame and the settled result. It exercises Alert, Dialog, Menu,
Popover, Callout, Help, Sheet, CollapsibleView and Toast with normal, limited
and no motion, wide and narrow viewports, gamepad input and large-display
layout. It includes long copy, larger explicit text and a Largest environment
preview. The preview does not change the engine's native text preference;
repeat the suite with that preference set in Studio for native accessibility
evidence.

Visible text must exist throughout the sample and keep its final text bounds
and box size within one pixel. Text positions must stay within half a
pixel, relative to the panel for deliberately sliding surfaces. The negative
control includes a one-pixel translation with unchanged text bounds.
A vertical scrollbar that disappears at rest
fails the case. Toasts must also stay within their presentation width and
fit their text. Closing checks require theme shadows to fade with the panel,
including the final frames after its paint becomes transparent. The suite must sample text, so an empty or missing panel cannot
pass. Add appearing controls and new wrapping or scrolling fixtures here when
changing presentation code. A final screenshot alone cannot catch these bugs.

Panels keep their content at its settled layout size while their outer box
animates. Animating a text ancestor's `UIScale` can round glyph sizes during
the transition. Native `AutomaticSize` and Compose bindings still own layout;
the shared presentation helper holds only the measured box during motion.

These checks catch layout changes and scrollbar flashes, not every paint or
rasterization defect. Keep a visual pass for theme paint and device rendering.

`table_resize` compares resized large headings with freshly created native
text, including shrinking and widening columns under display scaling. It also
checks that the header band reaches the outer scrollbar edge.

### Run the suites

Run `lute run tools/lute/studio_live.luau SUITE... [--only TEXT] [--tag NAME]
[--deadline SECONDS]` in the worktree. The command does these steps for each
suite:

1. It builds `build/Facet-Live.rbxlx` from the gallery, the live modules and
   the vendored Verify source.
2. Verify starts a new Studio process with a copy of that place and starts a
   playtest. The command does not use a Studio that is open.
3. The suite runs in the Client data model. Each check is one Verify step.
4. Verify returns the report and stops that Studio process.

The command saves each report as `artifacts/studio-live/<suite>-<tag>.json`.
The default tag is `launched`. Use a tag that names the viewport and the text
size, for example `portrait-largest`. The `--only` option selects cases by id.
The command exits with 1 when a case does not pass or an attachment is
refused.

Each case attaches its measurements as `notes.json`. The command writes the
attachments of a case in `artifacts/studio-live/<suite>-<tag>/<case id>/`. A
case saves other JSON with `live.save(name, json, dir)`. The command writes
an attachment with the directory `atlas` in `tests/fixtures/focus_atlas`. It
writes an attachment with the directory `live` in `artifacts/studio-live`.

The suites `needs_live_input` and `native_mechanisms_input` have interactive
cases, and `native_mechanisms_input` covers engine mechanisms that have no
headless oracle.

A new Studio process has no Controller Emulator. Thus the gamepad suites
(`focus_walk`, `focus_opened`, `gamepad_walk`, `haptics_verify`) need a Studio
that you control:

1. Run `lute run tools/lute/studio_live.luau --place`. Open
   `build/Facet-Live.rbxlx` in Studio.
2. Turn on the Controller Emulator.
3. Get the id of that Studio from the `list_roblox_studios` tool of the Studio
   Model Context Protocol (MCP) server.
4. Run the command with `--studio ID`. Verify starts the playtest in that
   Studio, runs the suite and stops the playtest. It does not close Studio.

An interactive case needs real input between its steps. Use a Studio that you
control:

1. Run `lute run tools/lute/studio_live.luau --place`. Open
   `build/Facet-Live.rbxlx` in Studio and start the playtest.
2. Run `require(game.ReplicatedStorage.FacetLive).begin(suite, id)` in the
   Client data model.
3. Send the input with the Studio input tools.
4. Run `step(name)` for each step of the case.
5. Run `finish()`. It returns the Verify report as JSON.

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

### Send real gamepad input

Turn on the Controller Emulator (the Virtual Controller check box of the
device emulator bar). The emulator maps keys to the pad: W/A/S/D are the left
stick up/left/down/right, and 1/2/3/4 are D-pad up/left/down/right. Then
`live.press({ "DPadDown", "ButtonA" })` in the Client data model sends real
`Gamepad1` input. It uses `UserInputService:CreateVirtualInput()` and the
emulator key map: DPadDown, DPadLeft, DPadRight, ButtonA, ButtonB, ButtonX,
ButtonY, ButtonL1, ButtonL2 and the left stick's `StickUp`, `StickLeft`,
`StickDown` and `StickRight`. Arrow keys are sent by their key code names
(`Up`, `Down`, `Left`, `Right`). Between the steps of an interactive case,
call `live.press` in place of the Studio input tools. The result records the
delivered input in `notes.deliveredInput` and the selection after each press
in `notes.pressedSelections`.

- DPadUp cannot be sent through VirtualInput. The emulator maps it to the key
  1, and VirtualInput refuses that key. Post the key to Studio's process with
  the `pad_key` helper in `tools/studio/capture/`; its usage text lists the key
  codes for the D-pad and the left stick. Studio does not need to be in front,
  but the game view must have the keyboard focus: until one real click lands
  in the game view, Studio drops every posted key. `pid_click` on an empty
  spot of the game view gives it.
  The engine moves the stick selection by a different geometry than the D-pad,
  so `StickUp` can choose another neighbour than D-pad Up.
- Before any capture or posted input, check the desktop session with the
  `session_locked` helper there. It must print `locked: 0` or `locked: no-key`.
  A locked session drops posted input while window captures keep working.
- To click Studio's own UI (for example the Virtual Controller check box), take
  the coordinates from a capture of the Studio window only (the `window_id`
  helper gives the window id), and click with the `pid_click` helper, in
  screen points. Studio ignores clicks posted to its process, so the helper
  sends a real click and refuses unless Studio is in front. Never capture the
  whole screen.
- While the Controller Emulator is on it takes every keyboard key, mapped or
  not: arrow keys, Return and text never reach the game. Turn it off for a
  keyboard pass.
- Do not send the keys U and Q. They are ButtonStart and ButtonSelect. They
  open the Roblox menu or take the keyboard focus, and after that VirtualInput
  refuses every key until the playtest restarts.

### Run the focus walk

The `focus_walk` live suite opens every Showcase page (and every tab of a
tabbed fixture), rests every ScrollingFrame at the top, and records a focus
atlas: each stop's rectangle, links, value-control axis, and the chain of
SelectionGroups and ScrollingFrames around it. It then selects each stop and
presses DPadDown, DPadLeft and DPadRight, and the stick in four directions,
recording where the engine moved the selection and the scroll offsets at the
moment of the press. Options go in `shared.FacetFocusWalk`:

- `only`: a substring of the page name;
- `up`: seconds to wait for D-pad Up per stop. The wait is the Verify step
  `focus-upstream`. A loop that posts key 1 with `pad_key` while that step is
  in progress supplies the presses;
- `keys = true`: the arrow-key pass instead (Controller Emulator off), saved
  beside the atlas as `<page>--keys.json`;
- `stick = false`: skip the stick pass;
- `device`: a Showcase device preview (`tv`, `phone`); its atlases get the
  device name as a prefix.

Each atlas is an attachment with the directory `atlas`, and the command
writes it in `tests/fixtures/focus_atlas`. The headless spec
`native_focus_walk` replays each atlas through `UI.focusQuery` with the recorded
scroll offsets and fails on an unreachable stop, a dead end, or a D-pad or
arrow move where the engine and the query disagree. A known engine difference
is listed in `divergences.json` with its fact id from the input guide.
`FACET_FOCUS_ATLAS` points the spec at another atlas directory, and
`FACET_FOCUS_WALK_REPORT` names a directory for a JSON report per failing page.

### Walk opened controls

The `focus_opened` live suite opens a list of controls (menus and a submenu,
a menu shown as a sheet, CollapsibleView, DisclosureGroup, Sheets, Popover,
Dialog, Alert, the date and colour pickers, Callout, RadialMenu and the
Showcase demo panel) with A, waits for the selection to enter, walks every new
stop (D-pad, D-pad Up through the `pad_key` stream, stick), and closes with B
until the surface is gone. Each case checks that the selection entered, every
item is reachable, no move lands on the page behind, the surface closed and
the selection returned to the control that opened it. `shared.FacetFocusOpened
= { keys = true }` runs the same cases with Return, Escape and the arrows
(Controller Emulator off). Each report is an attachment with the name `focus-opened-<case>`
in the live artifacts.

### Limits of the harness

- Studio input tools send D-pad key codes as keyboard input. Engine
  selection does not move for them. Use `live.press` with the Controller
  Emulator for the D-pad path.
- Studio does not play haptic motors. The harness proves that a control
  requests the effect. A physical phone or gamepad must confirm the output.
- A horizontal drag from the Studio input tools can arrive as a tap. Confirm a
  swipe with a real pointer or touch drag. The mouse moves of the input tools
  do not fire `InputChanged` while a button is held, so a `UIDragDetector`
  does not start.
- The input tools and VirtualInput refuse Tab and Escape, because the core
  interface owns them. The input tools also send `ButtonA` as keyboard input,
  and engine activation does not use it. `live.press` sends a real `ButtonA`.
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
