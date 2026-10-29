# DiegeticScreen

`UI.DiegeticScreen` returns a Folder. Place it under PlayerGui beside the
existing ScreenGui layers. It uses the same Compose runtime and application
instances. It does not mount another application.

| Option | Contract |
| --- | --- |
| `layers` | Existing ScreenGui layers. First is the primary application. Include its full-screen backdrop. Facet also moves its associated Composition top-bar layers. |
| `isPresented` | Writable boolean cell. True enters the world surface. False reverses the current shot. |
| `scene` | Named factory returning a Compose-owned Instance. Compose mounts it in Workspace for the presentation lifetime. |
| `retainScene` | Optional. When `true`, Compose mounts the scene with the DiegeticScreen and keeps it in Workspace while `isPresented` is false. Entry and return then do not build the scene again. Default `false`. |
| `surface` | CFrame value or reactive source for the front face of the display. Local negative Z points out of the screen. |
| `bounds` | Positive Vector2 physical display bounds. The fixed logical canvas fits inside them without stretching. |
| `camera` | CFrame value or reactive source for the room camera. After entry settles, CurrentCamera follows this value with CameraType Scriptable. Use `UI.cameraRig(...).camera` for bounded camera input and presets. |
| `fieldOfView` | Vertical field of view, default 48 degrees. Must be between zero and 180. |
| `motion` | Theme motion role, default `move`. Reduced motion uses the end pose directly. |
| `onUnavailable` | Optional callback with a failure reason. The interface returns to its original screen hosts. |
| `interactive` | Optional. When `true`, presses on the tablet reach the live app's controls, and the screen returns only when the game sets `isPresented` to false. The surface is hosted beside the first layer so that it receives input. The canvas maps u = 0 to the plate's local +X on its Front face, which is the engine's SurfaceGui mapping; account for it when you project a canvas point into the world. Default `false`: a press anywhere on the tablet returns to the screen. That return target is not a gamepad or keyboard selection stop, so focus stays with the game's own controls. |

The surface uses native SurfaceGui input and a queryable display part. By default,
tapping the display reverses the shot. With `interactive = true`, the display
accepts application actions while presented. Frame the room camera so that the
room is visible around the display. An enabled cameraRig receives pointer input
over empty room space and yields to input over the application surface.

The entry motion starts only after the surface layout is stable for two frames
with steady frame times, or after the theme `motion.restLimit` time. A frame
that takes more than twice as long as the frame before it restarts this wait.
The motion starts at the matched pose, so a slow frame after the surface
transfer does not move the camera.

The canvas retains each source layer's ScreenInsets and DisplayOrder. Its size
is fixed through a shot. A viewport size change safely returns to screen mode.
The original Camera is restored unless another owner has replaced the camera.
Application state and source instances survive entry, reversal and return.
VR entry is unavailable until a comfort presentation is supplied.

The scene and camera framing belong to the consumer. SurfaceGui, Camera,
GuiService:GetInsetArea and Compose portal, spring, settled and scheduler own
the native rendering, ownership, motion and readiness mechanisms.

Use [cameraRig](cameraRig.reference.md) to orbit, pan and zoom in the room.
Bind its `enabled` option to the camera task and pass its `camera` value here.
Use `interactive = true` with an explicit return command when the surface has
camera reset and preset controls.
