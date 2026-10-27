# World drag and drop

`UI.draggable(source, spec)` accepts a GuiObject, BasePart, or Model.
For a BasePart or Model, set `spec.world`. All parts in the source must be
anchored. Facet moves the held object. The game owns its accepted placement.

`Facet.WorldDragOptions` has these fields:

- `plane`: a CFrame. Its position and UpVector define the drag plane.
- `lift`: an optional distance in studs. Default `0`. Pickup raises the source
  along the plane normal. Timing uses `motion.durations.pressLift` and the
  theme's `present` easing.
- `focusTarget`: a required GuiObject. Use a labelled Button for pickup by
  keyboard, gamepad, touch, or an accessibility tool.
- `hitArea`: an optional GuiObject, such as a SurfaceGui `focusTarget` over
  the source. A press on it that moves past the drag threshold starts the
  drag. A shorter press stays a tap.
- `maxActivationDistance`: an optional native DragDetector distance. The engine
  default applies when this is absent.

  The engine measures it from the character. Without a character, Facet
  starts pointer pickup from its own raycast.

Facet creates a local DragDetector with `TranslatePlane`, `Custom` response,
and `Everybody` permission. This detector recognizes pointer pickup and release.
Facet intersects the pointer ray with the authored plane to preserve its contact
offset. `Geometric` and `Physical` response cannot own Facet's snap, pending drop,
and return presentation. Detector permission permits local input only. The game
must validate durable moves on the server.

A world target uses the existing `UI.dropTarget`. Set `worldPlacement` to a
CFrame or readable CFrame. This is the source pivot at that destination.
An accepted hover snaps the held object there, with lift. A native Highlight
shows the accepted target. The first raycast hit must belong to a target.
The held source is excluded from that raycast. Other parts and blocking UI
keep their normal occlusion behavior.

Return or A on the pickup button starts an armed session. Native selection
chooses a target's `focusTarget`. Return or A places the object. A tap or click
on the target button uses the same drop command. Escape or B cancels.
Use native selection links to define the route between buttons.

`DropInfo.source` can now be a GuiObject, BasePart, or Model.
`DropInfo.worldPlacement` contains the target transform when supplied.
Payload, operation, mode, validation, pending completion, and all callbacks use
the same shared session as 2D drag and drop. One `onDrop` handler can accept both.
Set the target's `placement` to a `Facet.SpatialPlacement` or readable placement
to supply the same `info.placement` used by SpatialGrid. Keep logical placement
in the game model. Use `worldPlacement` for its world presentation.

```luau
local tileId = "rack-tile"
local boardPlane = CFrame.new(0, 1, 0)
local cellPlacement = CFrame.new(4, 1, 0)
local tile = Host.Part { Anchored = true, CFrame = boardPlane }
local cell = Host.Part { Anchored = true, CFrame = CFrame.new(4, 0, 0) }
local function place(payload, info)
    if payload == tileId and info.worldPlacement then
        tile:PivotTo(info.worldPlacement)
        return true
    end
    return false
end
local pickup = UI.Button { label = "Pick up tile" }
local destination = UI.Button { label = "Place in cell" }
UI.draggable(tile, {
    payload = tileId,
    world = { plane = boardPlane, lift = 0.5, focusTarget = pickup },
})
UI.dropTarget(cell, {
    focusTarget = destination,
    worldPlacement = cellPlacement,
    onDrop = place,
})
```

Landing and cancel return use the theme's `travel` duration and easing.
`limited` or `none` motion, including the engine's reduced motion preference,
applies placement immediately and suppresses lift. Owner disposal cancels the
session, restores a returning source, and releases its resources.

World pickup claims its InputObject through `UI.gestureArbiter`. The binding
accepts an Instance surface. A camera controller must respect the shared claim.
Facet does not replace Roblox camera scripts.
