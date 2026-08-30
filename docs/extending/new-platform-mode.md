# Playbook: adding a platform capability or interaction mode

Audience: an agent or developer with no prior repository context.

**Facet does not currently support VR.** The worked future case in this playbook is
spatial UI, and nothing in it is a support claim. What Facet has, as of roadmap Step
4, is the *seam*: presentation-space facts, an optional spatial payload on normalized
events, and a declared-but-unimplemented world render target. The gate below is what a
support claim would first have to pass, and none of it has been run.

Read [`../reference/constitution.md`](../reference/constitution.md) first — the
rules your addition must follow.

The gate table below governs this work. No platform-support claim is made without
the physical run its row names.

## The spatial gate — what exists, and what a support claim would cost

This table is the falsifier. Without it, "we support VR" is a sentence nobody can
check. Every row is `PENDING_PHYSICAL` and stays that way until the named hardware
run happens; no emulator, preview profile or headless test can close one.

| Gate | The question | What exists today | Status |
|---|---|---|---|
| Contracts | Can spatial input and world surfaces be added without rewriting screens? | `presentationSpace` fact + `presentationProfile` policy; `Facet.spatial` optional event payload; `capabilities.spatialPointer`; `target_contract.FUTURE.surface`, now shipped as `surface_target` — a FLAT world surface, which is not a spatial claim | **Shipped** (contracts, plus one flat world target) |
| Focus | Does logical focus stay coherent when the pointing device is a ray or a hand that can leave the surface entirely? | Facet's focus graph is device-agnostic and untested against a spatial pointer | PENDING_PHYSICAL |
| Hover | Is hover distinguishable from selection at arm's length, and does it stay stable under natural hand tremor? | hover is pointer-class-gated and has no spatial notion | PENDING_PHYSICAL |
| Occlusion | What does a control do when its surface is behind geometry, edge-on, or off-view? | measured for a FLAT surface under an ordinary pointer: geometry in front blocks input, and `AlwaysOnTop = true` defeats that, which is why `surface_target` pins it false. Undefined for a spatial pointer, which is what this row asks | PENDING_PHYSICAL |
| Comfort | Does the surface hold a stable frame rate, and is text legible at the distance and angle it is actually viewed from? | Roblox's own VR guidance makes stable frame rate a comfort requirement; Facet has no spatial frame measurement at all | PENDING_PHYSICAL |
| Cancellation | If a ray, hand, controller or headset disappears mid-interaction, does the interaction carry or cancel cleanly, without wedging or losing committed data? | the hot-switch/carry-cancel model exists for pointer/touch/keyboard/gamepad and has never seen a spatial class | PENDING_PHYSICAL |
| Performance | What does a world surface cost per frame at production node counts on the supported hardware? | a world target now exists (`surface_target`) and its per-frame cost is one of its own named open questions; nothing has been measured on spatial hardware | PENDING_PHYSICAL |

Until every row above is closed on named hardware, the honest statement is: *Facet
has an extension seam for spatial UI.* Anything stronger is unearned. Nothing in
this repository is a claim of VR support, and no shipped document may become one.

## Design rule

Do not add a screen-level branch named after a device when the real requirement is
available space, viewing distance, presentation space, or an input capability.

A phone, desktop, console, and headset may all expose several interaction methods at
once. “VR” is not one replacement for pointer, touch, keyboard, or gamepad. A spatial
session may have a controller ray, tracked hand, gaze emphasis, and gamepad
simultaneously. The environment records the capabilities; standard controls keep
consuming semantic actions.

Ordinary controls should not need to know a headset model. If a control needs a new
fact or event shape, add the reusable fact or event. If UI must materialize in a new
Roblox container, follow
[`new-render-target.md`](new-render-target.md) rather than putting target-specific
Instance code into controls.

## The four extension seams

1. **Environment facts and derived policy** —
   `src/env/environment.luau` receives observable facts from
   `src/client/roblox_env.luau`. Layout and presentation consume derived space,
   distance, accessibility, and capability policy.
2. **Semantic actions** — `src/input/actions.luau` and
   `src/client/roblox_input.luau` map device input to Activate, Cancel, Navigate,
   Adjust, Drag, or a deliberately added semantic action. Responder priority and
   sinking still decide ownership.
3. **Normalized event geometry** — interactions that need more than a semantic
   button press may carry optional two-dimensional position, three-dimensional hit,
   selection ray, device/hand pose, handedness, phase, and target. Existing
   two-dimensional callbacks must remain valid when those fields are absent.
4. **Render target** — screen, billboard, and a future world-surface target decide
   where the same solved tree creates Roblox UI. A `SurfaceGui` target is a target
   addition, not a new copy of every control.

## Steps

### 1. Define the supported experience before adding facts

Write concrete use cases and acceptance cases. For spatial UI, distinguish:

- a familiar flat menu shown in a headset;
- a world-fixed or object-fixed two-dimensional surface;
- a surface selected by a ray or tracked hand;
- true three-dimensional content, which may be outside Facet's two-dimensional
  layout model.

Name what remains out of scope. A preview profile or adapter stub is not proof that
any of these experiences works on hardware.

### 2. Add capability facts, not a single `vr` switch

Start with failing environment tests. Add only facts a policy actually consumes, for
example:

- presentation space such as flat screen, billboard, or world surface;
- viewing distance or target-size policy;
- available spatial pointer, controller ray, tracked hand, gaze emphasis, gamepad,
  keyboard, touch, or pointer;
- target geometry and occlusion/comfort facts supplied by the host.

Keep safe defaults and clamp malformed platform data. Extend the existing live
interaction-class set instead of replacing it with one `preferredInput = "VRHands"`
value. A primary value may choose hint emphasis, but it never removes another live
and usable interaction method.

### 3. Map device input to existing semantic actions

Bind the new device signals in the Roblox input adapter. Activate remains Activate
whether it came from a click, tap, gamepad button, ray trigger, or deliberate hand
selection. Add a new semantic action only when a named product behavior cannot be
expressed by the existing vocabulary.

Preserve responder ownership, priority, cancellation, and hot-switch rules. Prove
what happens if a ray, hand, controller, or headset disappears during an active
interaction: carry or cancel cleanly, never wedge or lose committed data.

### 4. Add spatial event data only where behavior needs it

A normal Button activation should not force every consumer to handle a ray. Dragging,
placing, or targeting may need the extended normalized event. Keep the value plain and
headlessly constructible so tests can drive the same policy without Roblox hardware.

At the adapter edge, begin with current Roblox services such as `VRService` and
device/user-frame APIs. Capability-probe APIs and record the engine build used. Do not
invent pose, handedness, targeting, or cancellation semantics that a Studio and
physical-device spike has not established.

### 5. Add a render target separately when needed

Use the render-target playbook for a `SurfaceGui` or another native container. Prove
pixel/canvas mapping, adornee lifetime, local ownership, clipping, stylesheets,
pointer/ray coordinates, focus visuals, teardown, and behavior when the target leaves
the world or becomes occluded.

The existing BillboardGui target is reused for billboard requirements. Do not create
a second billboard path merely because the input device is spatial.

### 6. Add preview and headless conformance without overstating them

Add a provisional profile to `src/preview/device_profiles.luau` and
`bench/perf_profiles.luau` only when it represents specified facts and geometry.
Run the normal layout, target-size, focus, reduced-motion, lifecycle, and performance
scenes over it. Label the artifact simulated/headless. It is useful for catching
policy regressions and does not close the physical-device gate.

### 7. Close the physical comfort and performance gate

On supported hardware, verify target acquisition, reach, hover/focus distinction,
text readability, occlusion, cancellation, controller/hand changes, responder return
to gameplay, and the supported world/screen targets. Record input-to-visible behavior,
frame time, Instances, memory, and the device/engine/game build.

Roblox's VR guidance treats stable frame rate as a comfort requirement on untethered
headsets. Set the budget from the supported device and experience target. Do not infer
it from the desktop Lune benchmark or Studio emulation.

### 8. Update docs and gates

Update the guide and API reference, add the platform/capability profile to the
conformance matrix, and run the full test, registration, boundary, inclusion, and
performance gates. Evidence must distinguish headless, Studio-emulated, and physical
runs.

If hardware is unavailable, finish the facts, pure policy, adapter capability probe,
test driver, and exact physical procedure, then leave the result explicitly pending.
Never turn “stub loads” or “preview renders” into a support claim.

Official sources for the spatial case:
[Roblox `VRService`](https://create.roblox.com/docs/reference/engine/classes/VRService),
[Roblox VR guidance](https://create.roblox.com/docs/production/publishing/vr-guidelines),
and [Roblox UI render spaces](https://create.roblox.com/docs/ui).
