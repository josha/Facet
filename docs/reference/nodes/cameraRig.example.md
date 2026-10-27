# cameraRig example

Create the rig inside a Compose component. Use its camera value for the room.
The game supplies PlayerGui, UI, Host and Compose from its app.

```luau
local isPresented = Compose.cell(false)
local applicationLayer = Host.ScreenGui "Application" {
    UI.Text { text = "Room camera" },
}
local function Room(): Model
    return Host.Model "Room" {
        Host.Part "Table" { Anchored = true, Size = Vector3.new(3, 0.2, 2) },
    }
end
local rig = UI.cameraRig {
    inputRoot = playerGui,
    initial = { focus = Vector3.new(0, 2, 0), yaw = 0, pitch = 0.2, distance = 10 },
    focusBounds = { min = Vector3.new(-4, 0, -4), max = Vector3.new(4, 4, 4) },
    distanceBounds = Vector2.new(3, 16),
    enabled = isPresented,
    presets = {
        room = { focus = Vector3.new(0, 2, 0), yaw = 0, pitch = 0.2, distance = 10 },
        table = { focus = Vector3.new(2, 1, 0), yaw = 0.4, pitch = 0.3, distance = 4 },
    },
}
local presentation = UI.DiegeticScreen {
    layers = { applicationLayer }, isPresented = isPresented,
    scene = Room, surface = CFrame.new(0, 2, 0),
    bounds = Vector2.new(4, 2.5), camera = rig.camera, interactive = true,
}
```

See [cameraRig](cameraRig.reference.md) for options and input ownership.
