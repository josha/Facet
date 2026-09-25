# Mounting into native targets

Targets are ordinary native Instances in the Compose tree of the caller. Facet
has no render-target adapter interface. Use a ScreenGui, BillboardGui or
SurfaceGui, and mount controls inside it.

```luau
local playerGui = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local function Terminal()
    return Host.SurfaceGui {
        Adornee = Compose.static(terminalPart),
        Face = Enum.NormalId.Front,
        CanvasSize = Vector2.new(1024, 768),
        SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
        Active = true,
        UI.Button { label = "Open manifest", onActivate = openManifest },
    }
end
local stop = runtime.mount(Terminal, playerGui)
```

For interactive world UI, parent the SurfaceGui under PlayerGui. Reference the
world part through `Adornee`.

- The caller chooses the parentage, the safe-area and inset properties, the
  resolution and the display order.
- Compose owns the Instances that it makes. It releases them with their mount.
- Borrow or reference external Instances deliberately. Do not destroy
  game-owned parts when a UI mount ends.

In Studio, test target creation and destruction, native bounds, focus and
input. A SurfaceGui is a flat two-dimensional interface in the world. It does
not add VR, ray, hand or gaze input.

A missing native host feature belongs in the Compose Roblox host. A missing
reusable control behavior belongs in Facet. Neither one needs a separate scene
or target renderer.
