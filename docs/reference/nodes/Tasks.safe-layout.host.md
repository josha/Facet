# Tasks.safe-layout.host

Declare the capture area of a host movement control outside TouchGui.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local C = Facet.Compose
local reservations = C.cell<<{ Facet.TouchReservation }>>({})
local app = Facet.app({ touchReservations = reservations })
app.mount(function()
  local UI = app.UI
  local Host = app.runtime.constructors
  local capture = Host.Frame {
    Size = UDim2.fromOffset(140, 140),
    Position = UDim2.new(0, 12, 1, -152),
    BackgroundTransparency = 1,
  }
  reservations:set({ capture })
  C.cleanup(function() reservations:set({}) end)
  return Host.Frame { Size = UDim2.fromScale(1, 1), capture,
    UI.Composition "HUD" {
      UI.Region "Prompt" { zone = "bottomRight", rank = 1,
        UI.Button { label = "Interact" },
      },
    },
  }
end)
script.Destroying:Connect(app.dispose)
```

The example reserves a bottom-left capture frame with sample dimensions.
The host supplies movement input and its visible control. Keep that control
outside the safe surface it reserves.

Set `touchReservations` in Facet.app or Facet.controls options. Each
`Facet.TouchReservation` accepts a GuiObject, a Rect, or a bound value that
returns either type or nil. The list also accepts a bound value.
For a reactive Rect, pass `{ captureRect }` where `captureRect` is a
`C.cell<<Rect?>>(nil)`. Set the cell to the current capture Rect, or nil to
remove it. Set the list to `{}` to remove all host declarations.

Rects use GuiObject.AbsolutePosition UI pixel coordinates. Reserve the
whole input area. GuiObjects follow bounds, ancestor visibility, ScreenGui
Enabled and ancestry within the same PlayerGui. Rects remain until removed.
Both require TouchEnabled, independently of TouchGui and TouchControlsEnabled.
Native and host areas share the bottom band and update on resize or removal.
No extra ScreenGui is added.

- [Safe layout](Tasks.safe-layout.md)
