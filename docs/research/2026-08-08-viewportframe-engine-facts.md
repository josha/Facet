# ViewportFrame engine facts — probe 2026-08-08

For the reference-app stage's engine-content leaf (`UI.Stage`). Probed live in
Studio (empty place, Edit + Play/Client datamodels) per the new-engine-feature
playbook; first-party reference: create.roblox.com `ViewportFrame` /
`WorldModel` class pages (rolling platform — re-verify at adoption).

## Round-trip results (Edit probe, all PASS)

- `ViewportFrame` constructs; is a `GuiObject` (Size/Position/Background*/
  BorderSizePixel/ZIndex all writable; `UICorner` applies and clips the content).
- `CurrentCamera` accepts a `Camera` instance parented inside the frame and
  reads back identical.
- `Ambient`, `LightColor`, `LightDirection` are plain writable properties **on
  the frame instance itself** (authority consequence below).
- `ImageColor3`, `ImageTransparency` writable (tint/fade the rendered content).
- `WorldModel` parents inside the frame; `Model`/`Part` trees parent into it and
  read as descendants of the frame.

## Render probe (Play/Client, PASS with capture `vp-probe-1`)

A 300×300 frame in PlayerGui with a `WorldModel` holding a two-part mannequin
and a `Camera` rendered the rig correctly inside the rounded panel; a live
`Camera.CFrame` write mid-session re-rendered at the new angle with no
re-parenting and no flicker. Background color, `UICorner` radius, and content
clipping all behaved as normal GuiObject chrome.

## Facts that shape the API

1. **Lighting lives on the frame, not on content.** If the content owner set
   `Ambient`/`LightColor`/`LightDirection` directly they would write properties
   on a LuauUI-owned Instance — an authority violation. The adapter therefore
   mediates: the stage handle exposes lighting/camera setters and the authority
   manifest claims those properties for the STAGE seam.
2. **`WorldModel` is the content root.** Content (models, camera targets) is
   engine Instances by nature and client-only; the handle hands the caller a
   content root and owns its lifecycle (created with the node, destroyed with
   it). Headless adapters expose a recording stub with the same shape.
3. **A camera is required for any render**; the adapter creates and owns one and
   exposes `setCamera` (CFrame + FOV) rather than handing the raw camera out.
4. **Rendering cost is real** (each frame is a separate scene render). The leaf
   is for a small number of stable boxes (a preview pane, a hero), not lists of
   live 3D cells; the api doc must say so, like the CanvasGroup cost note.
5. Engine limits not probed here (deferred until a proof hits them): SurfaceGui
   interplay, particle/decal support inside WorldModel, max instance guidance.
   Recorded as open, not assumed.

Probe scripts ran via Studio MCP `execute_luau`; render capture stored with the
stage evidence (`artifacts/swiftui-reference-app-validation/studio/`).

## Addendum (platform review N2, 2026-08-08 close)

`CFrame.lookAt` with a look direction COLLINEAR WITH THE UP VECTOR (e.g. a
top-down camera: `position={0,10,0}, lookAt={0,0,0}`) is a degenerate case the
official CFrame page does not specify; community reports split between "up
switches to the X axis" and NaN components. The shared normalizer refuses only
the coincident case; the collinear-up case is UNGUARDED and belongs to the
follow-on list (framework-fixes.md). A proof needing a top-down stage camera
should offset the eye slightly off-axis until then. The scenario runner's part
placement (`runner.luau` applyStageContent) has the same exposure.
