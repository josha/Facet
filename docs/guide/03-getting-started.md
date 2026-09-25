# Getting started

1. Put the Facet package in ReplicatedStorage.
2. Set `Workspace.PlayerScriptsUseInputActionSystem` to true in the place.
3. Make a LocalScript in StarterPlayerScripts with this content.

```luau
local Facet = require(game.ReplicatedStorage:WaitForChild("Facet"))
local Compose = Facet.Compose
local app = Facet.app({ name = "Counter" })
local UI = app.UI

local function Counter()
    local count = Compose.cell(0)
    return UI.Screen {
        gap = "s",
        UI.Text {
            text = function(use) return `Clicked {use(count)} times` end,
        },
        UI.Button {
            label = "Add one",
            onActivate = function() count:update(function(n) return n + 1 end) end,
        },
    }
end

app.mount(Counter)
script.Destroying:Connect(app.dispose)
```

## What the script does

- `Facet.app()` makes a Compose Roblox runtime and the controls for it.
  `app.UI` is the table of control constructors.
- `app.mount(Counter)` runs the component and mounts its result into a
  ScreenGui in PlayerGui. The ScreenGui also holds a StyleSheet and a StyleLink
  to it. It returns a stop function.
- `UI.Screen` fills the ScreenGui and pads its content by the `m` spacing
  step. `gap = "s"` puts the `s` step between the children. See
  [Layout](../reference/api.md#layout).
- `app.dispose` stops the mounts and disposes the runtime.
- To use a theme package, give it one time: `Facet.app({ theme = package })`.
  The controls and the StyleSheet both use it. See [Styling](05-styling.md).

`Facet.app` uses only public pieces: `Facet.Roblox.createRuntime`,
`Facet.controls`, `Facet.themes.createStyleSheet`, `runtime.mount` and a
StyleLink. When you need a different root, use these pieces directly. See
[Mounting](../reference/api.md#mounting).

## Test a screen without Studio

You can mount a screen headlessly with Lune. This path needs a clone of this
repository and the pinned toolchain. Run `rokit install` from the repository
root.

The repository has a fake native engine in
[`tests/lib/native_engine.luau`](../../tests/lib/native_engine.luau). It makes
objects that act like Roblox Instances: properties, children, `FindFirstChild`
and events that a test can fire. It is not part of the Roblox package.

Save this script as `tests/counter.luau` and run
`lune run tests/counter.luau` from the repository root.

```luau
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose

local engine = engineLib.new()
local playerGui = engine.new("Folder")
local app = Facet.app({
    runtime = Facet.Roblox.createRuntime(engine),
    types = engine.types,
    parent = playerGui,
})
local UI = app.UI

local function Counter()
    local count = Compose.cell(0)
    return UI.Screen "Counter" {
        UI.Text "Count" {
            text = function(use) return `Count: {use(count)}` end,
        },
        UI.Button "Add" {
            label = "Add one",
            onActivate = function()
                count:update(function(n) return n + 1 end)
            end,
        },
    }
end

local stop, gui = app.mount(Counter)
local screen = gui:FindFirstChild("Counter")
screen:FindFirstChild("Add").Activated.fire()
assert(screen:FindFirstChild("Count").Text == "Count: 1")
stop()
assert(#playerGui:GetChildren() == 0)
app.dispose()
app.runtime:dispose()
```

- `engineLib.new()` makes the fake engine. Give it to
  `Facet.Roblox.createRuntime`, and give that runtime to `Facet.app`.
- The app needs `types = engine.types`, because Lune does not have the Roblox
  datatypes as globals.
- Lune has no PlayerGui. Give a `parent`.
- `app.mount` returns the stop function and the ScreenGui.
- The app does not dispose a runtime that you give. Call `runtime:dispose()`
  after `app.dispose()`.
- The fake engine refuses a property that the Roblox class does not have, as
  Roblox does. A misspelled native property, such as `Sise`, stops the test
  with an error.
- `Activated.fire()` sends the event that a click or a gamepad press sends.

The [standalone consumer test](../../tests/native_gallery.spec.luau) mounts the
screen module of `examples/consumer` in the same way.

A headless test proves state, events, structure and cleanup. It does not prove
native layout, `StyleSheet` paint, text measurement, device input or engine
performance. Those need a Studio check.

Inside this repository, put a spec under `tests/` and run it with
`lune run tests/run_one <name>`.

## Using Facet in a game that already uses Compose

`Facet.Compose` is a pinned copy of Compose. If your game requires its own
Compose, the game and Facet must use the same Compose instance. Two instances
make two reactive graphs, two schedulers and two owner trees. A control then
does not reliably update when your cell changes, and its cleanup does not
belong to your owner.

Bind Facet to your Compose one time. Use the bound table everywhere:

```luau
local Compose = require(game.ReplicatedStorage.Packages.Compose.core)
local ComposeRoblox = require(game.ReplicatedStorage.Packages.Compose.roblox)
local Facet = require(game.ReplicatedStorage.Packages.Facet).bind(Compose, ComposeRoblox)

local app = Facet.app()
local UI = app.UI
local enabled = Compose.cell(false)
app.mount(function()
    return UI.Screen {
        UI.Toggle { value = enabled, label = "Music" },
    }
end)
```

- Give the core module and the Roblox module from the same Compose copy.
- `app` of the bound table makes its runtime with that Roblox module. If you
  make the runtime yourself, use that Roblox module and give the runtime to
  `Facet.app({ runtime = runtime })`.
- The Facet tests use the commit in `Facet.COMPOSE_COMMIT`. Facet supports a
  later commit when it keeps the functions that Facet uses. `bind` stops with an
  error that names a missing function.
- When a runtime or a cell from a different Compose instance reaches a control,
  the control stops with an error that names the control. The error tells you
  to use `Facet.bind`.

The [API reference](../reference/api.md#your-own-compose) gives the full
contract.

## Cleanup

Use Compose cleanup for external subscriptions that a component makes. The stop
function from `app.mount` releases its component. `app.dispose()` releases every
mount of the app and the runtime that the app made. A runtime that you give to
the app stays yours. Call `runtime:dispose()` on it after `app.dispose()`.

The runtime methods `dispose` and `batch` use a colon: `runtime:dispose()`. The
fields of the app use a dot: `app.mount`, `app.dispose`. See
[Call style](../reference/api.md#call-style).

You can make persistent model cells outside the mounted component. See
[Components](15-components.md) for state and ownership.
