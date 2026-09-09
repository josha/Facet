# Radial menu implementation and evidence

Implementation of the [agreed design](2026-09-08-radial-menu-design.md).
Public API: [`Controls.RadialMenu`](../reference/api.md#controlsradialmenu).

## Rendering decision, measured 2026-09-08

The native probe used five Path2D arcs with thick strokes around an uncovered
center. Thick strokes form annular sectors with clean radial ends; no hidden
center-colored disc is needed. Each sector uses a bounded number of cubic curve
points, rather than a large collection of small GUI shapes. The ordinary theme
therefore works offline without uploaded wedge assets. Supplied image decoration
remains available through Facet's existing image state-variant and semantic-icon
paths. Image alpha does not determine selection.

Sources inspected: Roblox's [Path2D reference](https://create.roblox.com/docs/reference/engine/classes/Path2D),
[2D paths guide](https://create.roblox.com/docs/ui/2D-paths), and
[Path2DControlPoint reference](https://create.roblox.com/docs/reference/engine/datatypes/Path2DControlPoint).
The supported native thickness tops out at 100 pixels; the control limits its
bands to 96 and chooses a list when a larger readable target is required.

The initial probe was recorded as showing a uniform UIGradient fade on Path2D
and a CanvasGroup limitation. The user's September 8 phone recordings invalidate
that as ordinary-client evidence: surfaces remain opaque while labels fade.
Roblox's [upgraded UI gradients announcement](https://devforum.roblox.com/t/studio-beta-upgraded-ui-gradients/4846594)
identifies Path2D gradient support as a Studio beta. Setting and reading gradient
values is not proof of painted opacity. The radial control now puts each complete
visual in a bounded CanvasGroup, with Path2D inside its own child Frame. It uses
neither Path2D's restricted Transparency property nor beta gradient alpha for
its fade. The new rendered result still needs the unlocked visual check described
below; earlier claims of physical-device animation parity are not carried forward.

## Labels

The agreed upright text is preserved. Curving text glyph by glyph would create a
second typography/layout system with localization, shaping, and accessibility
costs. Instead, label rectangles are checked against both circular edges and
angular seams, with breathing room. Button compact representations and a measured
icon+text ladder select the best readable content. The full accessible action name
is retained and appears outside the ring during preview. A list is chosen before
labels or minimum targets need to be crushed into unsuitable geometry.

## Input and platform adjustments

Selection geometry is independent of artwork. The existing presenter, semantic
action contexts, native capture seam, motion values and focus graph own the
mechanisms. Direction2D now carries continuous stick coordinates through the
existing action binding path; digital stepping remains unchanged. The controller
has an optional mouse-preview callback with an owned detach function.

Roblox reserves physical Escape for its CoreGui menu. Semantic Cancel and gamepad B
navigate back/dismiss; the visible Back/Close affordance remains available to
keyboard and touch. Physical Escape interception is not claimed.

Native GUI input surfaces are rectangular. `centerPassThrough` therefore exposes
the central square inscribed in the transparent circular hole. Both the capture
plane and the presenter's outside-tap catcher use four ordinary rectangles around
that same aperture. Curved corner crescents of the hole still consume input. This
is an explicit geometric limitation, not a claim of alpha-based hit testing. It
keeps every painted wedge from leaking a scene tap. Captured input never passes
through the aperture. `outsideDismiss.passThroughRect` is the shared presenter
seam; other popup behavior is unchanged when it is absent.

## Demo and reproducible checks

Open `examples/places/Facet-Showcase.rbxl`, Play, choose **Quick actions** in the
existing demo picker. Stable demo ID: `radial-menu`; scenario ID: `radial_menu`.
The three tabs are Corner commands, Quick gestures and Character commands.
More options exposes the available image skin, focal movement, center behavior
and center pass-through. The explorer/status responds visibly to actions.

The existing Showcase BindableFunction API now exposes `step` and `report` for
its mounted fixture. Steps include `corner`, `gestures`, `character`, `open`,
`equipment`, `tools`, `lantern`, `stow`, `ready`, `wave`, `back`, `close`, `skin`,
`native`, `move`, `still`, `passThrough`, `centerBack`, `reset`. Allow presenter
frames between steps. A scripted step is semantic scenario evidence, not an
injected touch or physical device gesture.

Targeted checks: `lune run tests/run_one radial_geometry`, `radial_menu`,
`paint_extensions`, `extension_checker`, `gallery_demo_picker`, `overflow_sweep`.
Required tier: `tools/verify.sh full`; distributable: `tools/package.sh build`,
`status`, `verify`; actual places: `tools/build_places.sh`.

The scaffold's obsolete runner insertion anchor is fixed and regression-tested.
The type checker enumerates the current namespace and verifies every declared
entry, instead of imposing a stale hardcoded count. The new control and its pure
geometry helper are registered, including catalog/API, conformance, large-text
fixture, overflow sweep and surface ledger.

## Evidence status

Live evidence and final verification results are recorded under
`artifacts/studio/radial-menu/`. Screenshots were inspected through the native
Studio app in this task. An earlier MCP screenshot call hung and Studio was
restarted; that interrupted call is not verification evidence.

Physical phone touch, physical mouse feel, and a physical controller are not
available in this session. Headless tests and Studio simulation must not be read
as that missing hardware evidence. No assets or package release were published.

## Follow-up visual review

Angular trimming made the outside separator wider than the inside. Native Path2D
now uses endpoints inset by a fixed pixel distance along each nominal boundary
tangent, with parallel butt caps. The geometry regression checks 2px separation
at both edges of 44, 62, and 96px bands. Live portrait Studio confirms the seams.

The character example reserves 82px clearance and requests the theme's large
control height for `ringWidth` (61.6px effective band with the native target floor).
Compact icons retain complete action names in the preview. More options → Separate
character icons demonstrates separate icons around the focal point through
`appearance = "buttons"`. Rotating carousel selection is not implemented; learned
directions remain fixed. Navigation uses rounded 32px ×/‹ visuals with accessible
names and Facet's existing minimum-target expansion.

The device simulator exposed a missing global UIS release notification. The
originating InputObject delivered End correctly. The shared pointer seam now
accepts that release, disconnects capture before callbacks, and deduplicates both
end paths by capture identity. Native tap-to-open, Wave tap-to-close, and a launcher
press-slide-release to Inspect succeeded after the fix. These are mouse-driven
Studio simulations, not evidence from a physical touchscreen.

## Verification follow-up

Native pointer input in the built Showcase selected Wave and dismissed the menu.
Source reads from the built place matched the control, geometry, pointer adapter,
and demo files exactly. A temporary transparent scene-input probe counted zero
center taps by default and one with pass-through enabled; an outside dismissal
did not add a scene tap. The probe is removed after verification.

Native capture froze a moving anchor at exactly the same x/y across an 800ms
sample, and movement resumed after release. A narrow-phone regression then exposed
an overly wide demonstration travel distance; its amplitude now scales with the
scene width so the ring does not oscillate into list presentation. The new test
failed before this adjustment and passed afterward.

Targeted validation: 38 radial-control cases, 6 geometry cases, 14 pointer-seam
cases, 65 large-text matrix cases, 17 render-target contract cases, and the
102-case overflow sweep. These are headless checks. The final full-tier result is
recorded by `artifacts/verify/latest-full.json`, not inferred from these counts.
The compact navigation and interrupted-disposal tests include all core counters
returning to baseline.

Studio evidence includes mouse-driven phone portrait/landscape and tablet
simulation, native keyboard Return, live theme changes, loaded image skins,
hierarchy/completion, transparency, interruptible motion, reduced motion, anchor
capture, and input arbitration. The circular jewel assets are existing Facet
art; all three live image labels reported IsLoaded=true. No asset was uploaded.

The unlocked follow-up pass confirmed the jewel skin and compact x/< navigation.
It exposed list navigation overlapping the scroll panel in landscape: the offset
had been authored beneath a ZStack, which does not position children like Anchor.
The list now has an Anchor positioning parent; a failing-before/passing-after
regression reserves separate navigation and preview space, and the live landscape
view confirms the separation. Physical touchscreen, controller/analog, console,
and player text-preference validation remain distinct from these simulations.
Sending ButtonA through the keyboard simulator did not establish gamepad evidence.

## Content-fit follow-up

The user's requested default is `contentFit = "both"`: paint hugs the content in
both thickness and arc length. `radial`, `angular`, and `none` independently fit
one axis or retain full sectors. Logical sectors and minimum input targets do not
shrink, directions never rotate, and the dead zone/empty compass slots remain.
Theme typography and the existing text measurement service determine the current
text/icon representation; theme spacing pads the fitted shape and reserves native
glyph rounding room. Long labels retain Button's compact policy and full preview.
Separate circular buttons retain their existing geometry. The Showcase's Arc shape
option cycles Hug content, Slim band, Short arcs, and Full arcs.

Live phone inspection confirmed small arc tiles around the character, native tap
into Equipment, and readable Tools/Wear labels. The new geometry test checks all
eight compass directions, and the control tests verify independent fitting modes
and selection outside the fitted paint but inside the unchanged gesture target.

The package status's source drift against the last published release is expected
for these unpublished changes. It is distinct from build drift, source/type-count
drift, and theme-literal drift; publishing is outside this implementation task.

## User-recorded regression pass

The five supplied movies and two photos show the old published build's defects.
They are user-supplied device recordings, not assistant-run physical tests; the
exact device and client version were not supplied. Contact sheets and source
hashes are retained under `artifacts/studio/radial-menu/regressions/`.

The fixes cover:

- Translucent circular surfaces with theme-sensitive contrast outlines.
- Corner navigation at the launcher position; empty character centers use a
  lower-left ring navigation item. The gesture demo uses central Back/Close and
  preserves its five assigned compass directions and three gaps.
- One complete visual per motion group; outgoing labels remain paint-eligible
  while input and focus reject them. Closing freezes the current page through
  retirement. Same-band replacement waits for departing visuals; retained
  ancestors stay visible during expansion. Interrupted zero-opacity rows cannot
  block subsequent pages.
- Art and label placement through an Anchor inside the compositor. The first
  native measurement found a 1.5px icon-to-jewel-center offset. After the fix,
  menu/search/flag each measure 0.5px on both axes (odd/even pixel rounding).
- Uniform inner/outer paint radii per level in slim-band mode.
- Launcher activation-echo suppression in both radial and list modes; the held
  capture source stays mounted invisibly rather than covering list rows.
- `gestureSelection = "direction"` projects drags onto the deepest visible ring
  after its dead zone and preserves radial presentation in cramped space. The
  public default remains finite `"bounded"` selection.

Automated regressions test the release/Activated sequence, geometry retention,
shared visual lifetime, sequential replacement, interruption, ancestor stability,
center alignment, navigation placement, and long direction drags. The unlocked
Studio visual/ordinary-client animation check and publication are pending at this
checkpoint. Numeric Studio runtime readings are not presented as pixel evidence.


The unlocked visual follow-up found a further native stroke defect: Path2D
thickness does not follow its containing UIScale, clipping a contracting arc.
The control now scales its stroke explicitly; a regression fails before the fix
and passes afterward. A slowed and frozen Studio frame confirms a smooth arc
with content still present. The test clock is temporary Studio-only instrumentation
and must be restored before publication.


## September 9 follow-up: navigation, outlines and final-frame motion

The second device report supersedes the earlier sequential replacement fade.
Replacement now crossfades concurrently: wedges unfold angularly from the pressed
sector with aligned circular edges, while separate buttons travel from its region.
Existing keyed springs keep their progress on interruption. Closing continues to
contract and fade the complete glyph/surface visual together.

List fallback has one Back/Close above its scroll area, with no synthetic navigation
row or central control. Short wedges use a closed perimeter with both radial end
caps. `buttonSurface = "none"` (menu default or item override) suppresses separate
buttons' native plate and border for image/icon-only presentation. The Jewel demo
opts into it. All four existing `preset` corners are exposed by the demo selector.
The new choosing-controls guide and AGENTS route explain when radial actions fit,
when linear controls are preferable, and which configuration to start with.

The supplied September 9 pop recording was inspected frame by frame. A native
Studio trace then reproduced a ~1px final-frame shift when the adapter destroyed
UIScale and reset AnchorPoint at explicit scale 1. Keeping that explicit scale on
the same pivot reduced the sampled final handoff to <0.01px; clearing the transform
still releases the scale instance. Both before/after traces are in
`artifacts/studio/radial-menu/sep9/`. This is Studio simulator evidence; the supplied
physical recording demonstrates the defect, not physical confirmation of the fix.

Targeted control, geometry, scale-lifetime and presentation checks precede the
final build/package/full verification. The final statuses and source identities
are recorded in `artifacts/studio/radial-menu/sep9/validation.json`. Any Studio test
clock is temporary and must be removed before publishing the rebuilt Showcase.

## Final handoff and custom images

Focal launchers now share the menu exit clock instead of waiting for retirement.
Lists fade their rows before that same clock reveals the launcher. Regression
coverage includes every center policy and reopening during exit.

Content fitting measures navigation's themed image square and raw compact
images' rendered rectangles. Raw images reserve a square at the current theme's
icon size; their button has no text padding that could stretch the image.
The shared chrome path now paints an explicitly supplied image even when the
composite suppresses its themed plate; it does not borrow a plate shadow. Native
Studio probes caught and verified this distinction, with eight images visible
at the measured 20×20 size for both preferred and responsive image forms.
Pixel Quest, Compact Pointer, and Glossy Touch use the shared search image.

Final evidence is in `artifacts/studio/radial-menu/final-handoff/`. Studio emulator
checks and native frame traces are simulated evidence, not physical-device proof.
