# Mounting.Facet.app

<!-- aliases: Facet.app | app -->

`Facet.app(options?)` is the short path to a screen. It uses only the public
pieces below. It adds no service, solver, scene or render target.

```luau
local Facet = require(game.ReplicatedStorage.Facet)
local app = Facet.app()
local UI = app.UI

app.mount(function()
    return UI.Screen {
        UI.Button { label = "Continue", onActivate = function() print("Continue") end },
    }
end)
script.Destroying:Connect(app.dispose)
```

The app has these fields:
