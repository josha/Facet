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

- `UI`: the controls.
- `runtime`: the Compose runtime of the app.
- `mount(component, parent?)`: mounts `component()` in a new ScreenGui and
  returns `stop, screenGui`. The default parent is the `parent` option or the
  PlayerGui. The `screen` option of the app sets native ScreenGui properties,
  for example `ScreenInsets`.
- `presentAnchored(component, options)`: shows a popover at `options.source`
  in its own ScreenGui and returns `close, screenGui`.
- `presentToast(component, options?)`: shows a toast and returns
  `{ id, dismiss }`.
- `construct(control, spec)`, `refusal(control, spec)` and `controlNames()`:
  make one control by name, return the error a spec would raise, and list the
  control names.
- `dispose()`: stops every mount. It disposes the runtime when the app made it.

Call `mount` one time. Each screen, HUD element and overlay is a branch of
that tree. A Sheet, Dialog, Popover and Toast present in their own layer from
inside the tree.
