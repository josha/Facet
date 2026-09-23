# Mounting into native targets

Targets are ordinary native Instances owned by the caller's Compose tree. Facet has no render-target adapter interface. Use a ScreenGui, BillboardGui or SurfaceGui and mount controls inside it.

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

For interactive world UI, parent the SurfaceGui under PlayerGui and reference the world part through Adornee. The caller chooses parentage, safe-area/inset properties, resolution and display order. Compose owns constructed Instances and releases them with their mount. Borrow or reference external Instances deliberately; do not destroy game-owned parts when a UI mount ends.

Test target creation/destruction, native bounds, focus and input in Studio. A SurfaceGui is a flat two-dimensional interface placed in the world. This does not add VR, ray, hand or gaze input.

A missing native host feature belongs in Compose's Roblox host. A missing reusable control behavior belongs in Facet. Neither requires reinstating a separate scene or target renderer.
