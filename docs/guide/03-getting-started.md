# 3. Getting started

This chapter mounts a small screen in Studio and in a headless test. Both use
ordinary Compose functions and the same Facet controls.

## 3.1 The pieces, in order

A Facet application has three parts:

1. `Facet.new()` creates the environment, renderer, input system and frame driver.
2. A component function creates Compose state and returns Facet controls.
3. `app.mount(Component)` runs that function and presents its root.

Use `app.controls` for controls and layouts. Use `Facet.Compose` for state,
reactive calculations, ownership, collections and motion primitives.

Component setup runs once per mount. A changed value updates the properties that
read it. It does not run the whole component again.

## 3.2 The smallest screen, headless

The headless path needs a clone of this repository and the pinned toolchain.
Install the tools and fetch the pinned Compose source:

```sh
rokit install
python3 tools/sync_compose.py
```

The repository includes a read-only snapshot of Compose. The dependency script
checks every file against the pinned revision and its hashes. The distributed
Facet model includes the source needed to run in Roblox.

The example below uses the repository's fake target. Save it under `tests/`
and run it with Lune from the repository root. Its explicit host options replace
engine services for the test; normal Studio applications do not need them.

```luau
local Facet = require("../src")
local fake = require("./lib/fake_target")
local Compose = Facet.Compose
local adapter = fake.new()
local input, frame

local app = Facet.new {
    newAdapter = function() return adapter end,
    newInputSystem = function(core)
        input = Facet.newActionSystem(core)
        return input
    end,
    bindEnv = function(env)
        env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
        return function() end
    end,
    connectFrame = function(callback)
        frame = callback
        return function() frame = nil end
    end,
}
local UI = app.controls

local function Counter()
    local count = Compose.cell(0)
    return UI.Screen {
        padding = "m", gap = "s",
        UI.Text {
            text = function(use) return `Count: {use(count)}` end,
        },
        UI.Button {
            label = "Add one",
            onActivate = function()
                count:update(function(n) return n + 1 end)
            end,
        },
    }
end

local close, node = app.mount(Counter)
frame(1 / 60)
input.deviceKey("Return", true)
input.deviceKey("Return", false)
frame(1 / 60)
assert(adapter.node(node.children[1].path).props.text == "Count: 1")
close()
assert(adapter.rootCount() == 0)
app.dispose()
assert(frame == nil)
```

The presenter gives focus to the button. The Return key activates it through the
input system. The frame callback advances motion and applies rendering changes.

## 3.2b Testing your screen

The [fake target](../../tests/lib/fake_target.luau) records nodes, geometry,
properties and input. It ships in the repository, not in the Roblox model.
Clone the repository alongside your game if you need this test instrument.

The [standalone consumer spec](../../tests/consumer_standalone.spec.luau) mounts
the same screen module as the Studio example. It checks input, state, themes,
adaptive layout and cleanup.

| Call | Purpose |
|---|---|
| `adapter.node(path)` | Inspect a node's rectangle, properties and paint. |
| `adapter.paths()` / `adapter.liveCount()` | Inspect the mounted nodes. |
| `adapter.tap(path)` | Activate a control through pointer input. |
| `adapter.pointerDown(x, y, kind)` / `pointerMove` / `pointerUp` | Drive a raw pointer or touch gesture. |
| `adapter.typeText(path, text)` / `commitText(path)` | Enter and commit text. |
| `adapter.setThemePackage(package, themeName)` | Apply a theme package. |
| `adapter.rootCount()` | Check that disposal removed the surfaces. |

Headless checks prove Facet's layout and input decisions. They do not prove
Roblox `StyleSheet` rendering, device behavior or engine performance. Those
checks need Studio evidence.

Keep your game's tests in your own project. Facet imposes no test directory
structure on consumers. Inside this repository, put specs under `tests/` and
register them in `tests/run.luau`. Run one with `lune run tests/run_one <name>`.

## 3.3 Where state lives, and making the screen react

`Compose.cell(value)` stores a value. A property function receives `use`; call
`use(cell)` to subscribe that property to the cell. Use `cell:peek()` for an
untracked read in an event callback.

Use `cell:set(value)` to replace the value. Use `cell:update(function)` to derive
a new value from the current one. A writable cell can also bind directly to a
value control:

```luau
local music = Compose.cell(true)
return UI.Toggle { label = "Music", value = music }
```

Create local state inside the component. Create shared model state outside it
when the value must survive navigation. Multiple screens can read the same cells.

Use `Compose.formula` for a shared derived value. Use `Compose.watch` for a
reactive external effect. Register external resource cleanup with
`Compose.cleanup`. The [component guide](15-components.md) covers these lifetimes.

## 3.4 Wiring inside Roblox Studio

Enable `Workspace.PlayerScriptsUseInputActionSystem` in Studio before testing
input. Facet uses Roblox's Input Action System. The built-in player scripts must
use that system too, so they do not intercept keys outside Facet's input contexts.

The maintained example projects set this property in their Rojo configuration.
Use the repository's pinned Rojo version when building them. See
[Input](07-input.md) for setup and input limits.

### Project mapping (Rojo)

The [standalone project](../../examples/consumer/default.project.json) maps
Facet to `ReplicatedStorage.Facet` and a LocalScript to
`StarterPlayer.StarterPlayerScripts`. It also sets the required Workspace property.
Use that file as a complete starting point.

Fetch Compose before using Rojo with a source checkout:

```sh
python3 tools/sync_compose.py
rojo build examples/consumer/default.project.json -o build/Facet-Consumer.rbxl
```

Open the generated place in Studio and press Play. For a package or model
installation, follow [Without Rojo](08-without-rojo.md), then use the same client
script below.

### The client script

Put this LocalScript under `StarterPlayer.StarterPlayerScripts`:

```luau
local Facet = require(game.ReplicatedStorage:WaitForChild("Facet"))
local Compose = Facet.Compose
local app = Facet.new()
local UI = app.controls

local function Counter()
    local count = Compose.cell(0)
    return UI.Screen {
        padding = "m", gap = "s",
        UI.Text {
            text = function(use) return `Count: {use(count)}` end,
        },
        UI.Button {
            label = "Add one",
            onActivate = function()
                count:update(function(n) return n + 1 end)
            end,
        },
    }
end

local close = app.mount(Counter)
-- Call close() to remove this screen.
-- Call app.dispose() when the application ends.
```

`Facet.new()` connects engine input, environment facts and the frame driver.
Requiring Facet from shared code does not create those client services. They load
when the client creates an application.

Register work that must run each frame with `app.onFrame(callback)`. Inside a
component, pass its returned disconnect function to `Compose.cleanup`. The
callback uses the application's existing frame driver.

## 3.5 Where does semantic state come from?

The counter holds local UI state. A server-owned balance or inventory needs a
model that receives validated server updates. Controls display that model and
send change requests through callbacks. The server decides whether to accept them.

See [Client and server](06-client-server.md) for the replication boundary.

## 3.6 The same screen, as a project you can run

The [standalone consumer](../../examples/consumer/) contains the Rojo mapping,
client script and a reusable screen module. Its headless tests exercise that
module directly. They check mounting, theme changes, button activation, reactive
text, adaptive layout and cleanup.

Read [Components](15-components.md) next for branches, collections and animation.
The [tutorial index](04-tutorial-examples.md) describes the maintained examples.
