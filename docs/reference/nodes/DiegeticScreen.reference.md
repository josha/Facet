# DiegeticScreen

`UI.DiegeticScreen` returns a Folder. Place it under PlayerGui beside the
existing ScreenGui layers. It uses the same Compose runtime and application
instances. It does not mount another application.

| Option | Contract |
| --- | --- |
| `layers` | Existing ScreenGui layers. First is the primary application. Include its full-screen backdrop. Facet also moves its associated Composition top-bar layers. |
| `isPresented` | Writable boolean cell. True enters the world surface. False reverses the current shot. |
| `scene` | Named factory returning a Compose-owned Instance. Compose mounts it in Workspace for the presentation lifetime. |
| `surface` | CFrame value or reactive source for the front face of the display. Local negative Z points out of the screen. |
| `bounds` | Positive Vector2 physical display bounds. The fixed logical canvas fits inside them without stretching. |
| `camera` | CFrame value or reactive source for the room camera at the end of entry. |
| `fieldOfView` | Vertical field of view, default 48 degrees. Must be between zero and 180. |
| `motion` | Theme motion role, default `move`. Reduced motion uses the end pose directly. |
| `onUnavailable` | Optional callback with a failure reason. The interface returns to its original screen hosts. |

The surface uses native SurfaceGui input and a queryable display part. Tapping
the display reverses the shot. While pulled back, the display is a return target;
it does not accept application actions until it fills the screen again.

The canvas retains each source layer's ScreenInsets and DisplayOrder. Its size
is fixed through a shot. A viewport size change safely returns to screen mode.
The original Camera is restored unless another owner has replaced the camera.
Application state and source instances survive entry, reversal and return.
VR entry is unavailable until a comfort presentation is supplied.

The scene and camera framing belong to the consumer. SurfaceGui, Camera,
GuiService:GetInsetArea and Compose portal, spring, settled and scheduler own
the native rendering, ownership, motion and readiness mechanisms.
