### worldAnchor

<!-- aliases: worldAnchor | worldanchor -->

`UI.worldAnchor(options) -> { anchor, dispose }` projects a world object to a
screen anchor for a `RadialMenu` `anchor` or a `WorldMarker`. It reads the camera on
each `RunService.Heartbeat`. It creates no Instances.

| Option | Meaning and default |
|---|---|
| `target` | Required. A `BasePart`, a `Model` or a `Player`, or a readable of one. A `Player` resolves its current `Character`. A nil value makes the anchor invisible until the target comes back. |
| `padding` | A fraction from 0 to 1 of the measured radius. The default is 0.15. |
| `offscreen` | `"hide"` (the default) or `"retain"`. `"retain"` projects the center for a marker, also in a direction past the viewport for a target behind the camera. A retained anchor has `onscreen` and `clearance = 0`. |
| `occlusion` | `false` by default. When `true`, one `Workspace:Raycast` from the camera to the target center hides a target behind another object. |
| `camera` | A `Camera` or a readable of one. The default is the workspace camera. |

`anchor` is a readable `{ x, y, clearance, visible, onscreen?, occluded? }` in
viewport pixels. `x` and `y` are the center of the projected bounding box.
`clearance` encloses the eight projected corners, times `1 + padding`. A
missing, removed, empty, offscreen or near-plane target has `visible = false`,
and an open `RadialMenu` closes. An unknown option, a padding out of range and
a missing target are errors before the frame hook starts. `dispose()` sets
`visible = false` and disconnects the hook. The owner that creates the binding
also disposes it.

The game owns the `ProximityPrompt`, the proximity rules and the server checks.
Open the menu from the prompt:

```luau
local function CrateActions(crate, prompt, actions)
	local binding = UI.worldAnchor({ target = crate })
	local open = Compose.cell(false)
	local triggered = prompt.Triggered:Connect(function()
		open:set(true)
	end)
	Compose.cleanup(function()
		triggered:Disconnect()
	end)
	return UI.RadialMenu "CrateActions" {
		items = actions,
		anchor = binding.anchor,
		isPresented = open,
		launcher = false,
	}
end
```
