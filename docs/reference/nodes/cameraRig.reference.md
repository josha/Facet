# cameraRig

`UI.cameraRig(options: Facet.CameraRigOptions) -> Facet.CameraRig` creates a
camera rig in the current Compose owner. It owns local camera state and input
subscriptions. Set `DiegeticScreen.camera = rig.camera`, or bind another native
Camera's `CFrame` to `rig.camera`. The rig does not replace CurrentCamera.

| Option | Contract |
| --- | --- |
| `inputRoot` | PlayerGui for native input contexts and GUI hit tests. |
| `initial` | `Facet.CameraPose`: `focus: Vector3`, `yaw`, `pitch` and `distance`. Angles use radians. Yaw zero places the camera on local +Z. Positive pitch raises it. |
| `focusBounds` | `{ min: Vector3, max: Vector3 }` in world coordinates. Pan and focus targets stay inside this box. |
| `distanceBounds` | Vector2 with positive minimum and maximum distance. |
| `yawBounds` | Optional Vector2 minimum and maximum yaw. Default `[-pi, pi]`. |
| `pitchBounds` | Optional Vector2 minimum and maximum pitch. Default `[-pi/2 + 0.01, pi/2 - 0.01]`. Bounds must exclude the poles. |
| `presets` | Optional table of named CameraPose targets. Targets are copied and clamped at creation. |
| `enabled` | Optional boolean input. Default true. Bind it to the lifetime of the camera task. |
| `blocked` | Optional boolean input. True blocks input. Use this for a game's custom world drag. Native DragDetector and Facet drags block input automatically. |
| `inertia`, `smoothing` | Optional booleans. Default false. Inertia continues pointer motion after release. Smoothing uses a Compose spring for command input and travel. Direct manipulation stays attached to the pointer. |
| `orbitSensitivity` | Radians per pointer pixel. Default 0.005. |
| `panSensitivity` | World units per pointer pixel. Default 0.01. Pan follows camera yaw and world up. |
| `orbitSpeed` | Radians per second for keys and right stick. Default 1.5. |
| `zoomSpeed` | Distance per second for keys and triggers, and distance per wheel step. Default 8. |

Bounds and speeds must be finite and ordered. Speeds must be positive. All
initial values, targets, input and spring output are clamped to these bounds.

The handle exposes:

- `camera`: a readable CFrame value.
- `state`: a readable CameraPose with the current rendered pose.
- `focus`: a writable Vector3 value. A write clears the preset and travels to
  the clamped focus. Reads report the target focus; `state.focus` reports travel.
- `preset`: a writable `string?` value. Set a name to travel to that preset.
  Manual input clears it. Setting nil clears the name without starting a trip.
- `reset()`: clears the preset and travels to the initial pose.

One finger drag orbits. Pinch changes distance. Two finger drag pans. Mouse
right drag or left drag on empty space orbits; the wheel changes distance.
Arrow keys and WASD orbit. Plus and minus change distance. The right stick
orbits; R2 zooms in and L2 zooms out. The game must supply visible reset and
preset commands, such as Buttons.

Processed input, GUI hits, GUI selection, text editing, Facet gesture contacts,
Facet drag sessions and active world DragDetectors block camera input. The
rig cancels held input on disable, window focus loss or gamepad disconnect.
Hits on a SurfaceGui block pointer input, including its passive content.
Empty room space remains available while an interactive DiegeticScreen is presented.
The native InputContext uses priority 250 and sinks its commands while enabled.
The game owns other gameplay contexts and must disable them for this task.

Travel uses `motion.durations.cameraTravel` and `motion.easing.travel`.
Inertia uses `motion.durations.cameraInertia`. Smoothing uses
`motion.springs.camera`. Every built-in theme inherits these tokens.
Limited motion, none motion and the engine reduced motion preference disable
inertia and cut travel to its target.

Use the [camera rig example](cameraRig.example.md) to connect a room.

See [DiegeticScreen](DiegeticScreen.reference.md) for camera ownership and the
world surface lifetime.
