# ADR-0021 — The future spatial seam: contracts only

**Status:** Accepted (2026-07-26) · **Stage:** roadmap Step 4 (`cross-platform-proof`)
**Requirement:** UI-SPATIAL-001
**Supersedes nothing.** Extends ADR-0003 (world-target deferral) with the contracts
that deferral left undefined.

## Context

LuauUI targets Roblox, and Roblox has spatial surfaces: `SurfaceGui` in the world,
`VRService`, user-frame tracking, a GUI-input frame and a laser-pointer mode. A future
game may want a menu on a garage wall or a HUD a player points at with a controller
ray.

Two failure modes were available here, and both are expensive:

1. **Build nothing.** Adding spatial input later then means touching every control,
   because a control that only understands `{ x, y }` cannot be handed a ray without a
   signature change, and a framework with no presentation-space fact has nowhere to put
   "this surface is on a wall" except a device-name branch at screen level.
2. **Build a stub and call it support.** A preview profile that loads, an adapter that
   constructs instances, a `vr = true` flag — none of which has met a headset — reads
   to a consumer as a supported platform. That is the worse mistake, because it is
   discovered by a player rather than by a test.

## Decision

Ship the **seam**, not the feature, and make the absence of the feature checkable.

### 1. Presentation is a fact, not a device name

`presentationSpace ∈ { "screen", "billboard", "world" }` joins the environment facts,
defaulting to `"screen"`. The derived `presentationProfile` answers the two questions a
policy actually asks: `flat` (a billboard is still a flat pixel canvas — it just lives
in the world) and `world` (the narrow case only a future world target answers yes to).
An unrecognized value clamps to `"screen"`; a broken platform fact must not silently
put a menu in the world.

Rejected: a `vr` boolean. A phone, desktop, console and headset may all expose several
interaction methods at once, and "VR" is not one replacement for pointer, touch,
keyboard or gamepad.

### 2. Spatial pointing is one more capability

`capabilities.spatialPointer` feeds `interactionClasses.spatialPointer`. Nothing sets
it today; it defaults false. A spatial session may have a controller ray, a tracked
hand, a gaze and a gamepad live simultaneously, so the class set gains a member — it
does not gain a mode. Adding the ray must not remove the gamepad, and the spec asserts
exactly that.

### 3. Spatial data is optional payload beside the 2D fields

`LuauUI.spatial` defines `{ hit?, ray?, pose?, handedness, phase, target?, distance? }`
and attaches it to the existing normalized pointer position as `pos.spatial`. `pos.x`
and `pos.y` keep meaning what they mean. A handler written before this ADR keeps
working — proven by mounting a real Button through the real renderer, driving it once
flat and once with a ray, and observing both.

Three deliberate restrictions:

- **`distance` is derived**, from pose and hit, never accepted from the platform. A
  platform reporting a distance that disagrees with its own geometry would be
  reporting two different things.
- **`pose` carries position and an optional forward vector, not a transform.** A
  rotation convention LuauUI has not measured on hardware would be an invented
  semantic.
- **`normalize` never errors.** Hostile or partial data degrades to a well-formed
  value or to `nil`: a zero-length direction drops the ray rather than dividing by
  zero, `NaN`/infinite coordinates are not positions, unknown vocabulary values fall
  back, and an event with no spatial content returns `nil` rather than pretending to
  be spatially targeted. A broken future adapter must not be able to take a screen
  down.

### 4. The world render target is declared with its unanswered questions

`target_contract.FUTURE.surface` names `SurfaceGui`, states `not implemented`, and
carries the ten questions a Studio and physical spike must answer before an adapter is
written: canvas mapping, adornee lifetime, local ownership, clipping, stylesheet
resolution, pointer/ray coordinates, focus legibility, occlusion, teardown, and
per-frame cost. The contract checker does not know about it, no adapter file exists,
and `LuauUI.newSurfaceTarget` is absent — all three asserted.

The questions are the deliverable. Guessing at any of them produces an adapter that
looks correct and is not.

### 5. A support claim has a named, unmet gate

`docs/extending/new-platform-mode.md` carries the gate table: focus, hover, occlusion,
comfort, cancellation, performance — every row `PENDING_PHYSICAL`, none closable by an
emulator, a preview profile or a headless test. A suite case greps the shipped guide,
API reference and source for VR-support phrasings and fails the build if one appears.

## Consequences

- Adding spatial input later is an adapter change plus a capability fact. No control
  signature changes; no screen gains a headset branch.
- The framework can be asked "do you support VR?" and answer with a table rather than
  a feeling.
- The cost is a small amount of currently-unused surface: one environment fact, one
  derived policy, one capability flag, one pure module and one declaration table. That
  is the price of the seam, and it is paid once.
- **Nothing here is spatial support.** The honest statement is: *LuauUI has an
  extension seam for spatial UI.*
