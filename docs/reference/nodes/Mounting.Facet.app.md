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
  in its own ScreenGui and returns `close, screenGui`. Repeated `close()` calls
  are safe. See the option routes below.
- `presentToast(component, options?)`: shows a toast and returns
  `{ id, dismiss }`. `dismiss()` returns true on its first dismissal and false
  after the toast has retired.
- `construct(control, spec)`: builds an uppercase-named constructor inside
  the current Compose owner. It does not invoke helpers such as `environment`.
- `refusal(control, spec)`: tries construction in a temporary owner and returns
  the error text, or nil on success. Construction can run factories and refs;
  this is not a pure game-state validator. An unknown control name throws.
- `controlNames()`: returns sorted names of all `UI` bindings, including
  helpers. Not every returned name is accepted by `construct`.
- `dispose()`: stops every mount. It disposes the runtime when the app made it.

Imperative presenters call `component(UI)` inside their owned content. Their
types are `Facet.AnchoredOptions` and `Facet.ToastOptions`:

- `AnchoredOptions` requires `source`. `edge`, `align`, `gap`, `crossOffset`,
  `tail`, `maxWidth` and `maxHeight` position the panel; `modal`, `cancelPolicy`
  and `onDismiss` control interruption. Follow [Popover](Popover.reference.md)
  for source, placement and dismissal meanings. The app accepts presentation
  changes and releases this ScreenGui when dismissed.
- `ToastOptions` takes `key`, `priority`, `duration`, `readFloor`, `position`,
  `width`, `fade` and `onDismiss`. Follow [Toast](Toast.reference.md) for
  scheduling, timing and dismissal meanings. The returned `{ id, dismiss }`
  is a handle, not a GuiObject or a game reward receipt.

These helpers create app-owned layers; they do not require another app.
Keep a handle only as long as its task needs it, then close or dismiss it.

Call `mount` one time. Each screen, HUD element and overlay is a branch of
that tree. A Sheet, Dialog, Popover and Toast present in their own layer from
inside the tree.

The app provides `app.UI` to mounted components and presented content.
`Facet.controls(app.runtime)` without options returns that same object inside
those components and their descendant Compose owners. For a direct Compose
mount, use `UI.provide(body)`. See the [API reference](../api.md).

Task recipes include standalone bootstraps. When combining them, reuse their
component bodies inside this mount, with the same UI, model, commands and
localization source. Do not create another app for each recipe.
