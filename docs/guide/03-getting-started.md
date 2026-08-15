# 3. Getting started

This chapter builds the smallest useful screen and wires it two ways: first as a
headless test (no Roblox needed), then inside Roblox Studio. Working through both
shows exactly which pieces are engine-free and which live only on the client.

## 3.1 The pieces, in order

Every LuauUI screen is assembled from the same short sequence:

1. **A core** — the reactive runtime. `LuauUI.newCore()`.
2. **An environment** — the per-device facts. `LuauUI.newEnvironment(core)`.
3. **An action system** — the input pipeline. `LuauUI.newActionSystem(core)`.
4. **A render-target adapter** — where output goes. The real screen on the
   client; a fake recorder in a test.
5. **A presenter** — owns screens on top of all of the above.
   `LuauUI.newPresenter(core, env, adapter, actionSystem)`.
6. **A blueprint**, handed to `presenter.present(...)`.

## 3.2 The smallest screen, headless

The headless path needs no Roblox process. Instead of the real render target you
supply a **fake adapter** — a plain table implementing the adapter interface,
here doing nothing but counting the nodes it is asked to create. This is exactly
how `tests/smoke.spec.luau` proves the whole library wires together.

```lua
local LuauUI = require("../src") -- relative require: runs under Lune

local core   = LuauUI.newCore()
local env    = LuauUI.newEnvironment(core)
local system = LuauUI.newActionSystem(core)

-- a blueprint: a screen with one button
local screen = LuauUI.UI.Screen({
    id = "S",
    children = {
        LuauUI.UI.Button({ id = "Go", label = "Go" }),
    },
})

-- a do-nothing render target that records how many nodes were created
local created = 0
local adapter = {
    createRoot   = function() return {} end,
    create       = function() created += 1; return {} end,
    setRect      = function() end,
    setProp      = function() end,
    remove       = function() end,
    destroyRoot  = function() end,
}

local presenter = LuauUI.newPresenter(core, env, adapter, system)
presenter.present(screen)

assert(created == 2)                                 -- the Screen and the Button
assert(presenter.focus.focused:get() == "/S/Go")    -- focus landed on the button
```

Two things to notice:

- **The adapter interface is tiny.** The six functions above are the minimum. The
  real client adapter implements the same six plus a few optional extras (focus
  visuals, tap handlers). Because the interface is small, headless tests can
  fully drive a screen.
- **Focus was assigned for free.** The presenter walked the mounted tree, found
  the one focusable control, built a focus scope, and set focus to it. The path
  `"/S/Go"` is the node's identity: the screen `id` `"S"`, then the button `id`
  `"Go"`.

## 3.3 Where state lives, and making the screen react

The screen above is static. To make it *do* something, give it semantic state as
a signal and read that signal from the blueprint.

```lua
local core = LuauUI.newCore()

-- semantic state: a label the button will change
local count = core:signal(0)

-- a memo derives display text from the count; it recomputes only when count changes
local label = core:memo(function(use)
    return `Clicked {use(count)} times`
end)

local screen = LuauUI.UI.Screen({
    id = "Counter",
    padding = 16,
    gap = 8,
    children = {
        LuauUI.UI.Text({ id = "Label", text = label }),  -- a signal/memo as a prop = reactive
        LuauUI.UI.Button({
            id = "Bump",
            label = "Bump",
            onActivate = function()
                count:set(count:get() + 1)
            end,
        }),
    },
})
```

The important line is `text = label`. When you pass a **signal or memo** as a
prop value, LuauUI subscribes to it: whenever the memo changes, the text node is
marked dirty and repainted on the next refresh. When you pass a **plain value**
(like `label = "Bump"`), it is fixed for the life of the node. That is the entire
rule for making a prop reactive — hand it a readable value instead of a constant.

The button's app behavior belongs on the button. The presenter still turns touch,
mouse, keyboard, and gamepad input into the same semantic Activate event, but you do
not need a screen-wide path router for ordinary controls:

```lua
presenter.present(screen)
```

The `onActivate` function in the blueprint changes semantic state; the label follows.
A screen-wide presenter override still exists for advanced routing and compatibility,
but the control-local form is easier to compose and is the default taught here.

You never touch the text node. You change `count`; the memo recomputes; the text
prop is dirtied; the next `refresh()` repaints it. That is the declarative loop
end to end.

## 3.4 Wiring inside Roblox Studio

> ### ⚠️ One checkbox first: LuauUI requires the Input Action System
>
> Before any of the code below, open the **Workspace** in Studio's Explorer and
> **A REBUILT PLACE LOSES IT, EVERY TIME.** `rojo build` cannot write this
> property — it is absent from rojo 7.7.0-rc.1's reflection database, and adding
> it to a `.project.json` fails the build outright with *"Unknown property
> Workspace.PlayerScriptsUseInputActionSystem"* (measured 2026-08-15; the same
> gap Rascal Rally's `docs/DEBUG_PLACE.md` records for its Server-Authority
> prerequisites). So it cannot be checked in, and every freshly built `.rbxl`
> starts without it. Tick it by hand after each rebuild, or the arrow keys are
> silently dead in that copy while every screen still renders perfectly.
>
> tick **`PlayerScriptsUseInputActionSystem`** in the Properties panel (category
> *Behavior*). Roblox describes it as controlling "whether the built-in player
> scripts are updated to use the Input Action System"
> ([`Workspace` API reference](https://create.roblox.com/docs/reference/engine/classes/Workspace)).
>
> LuauUI's input layer is built entirely on the Input Action System and never
> reaches into `ContextActionService`. Roblox's *own* scripts do, and with this
> box unticked they hold keys outside IAS where no LuauUI binding can reach
> them: the default camera keeps `Left`/`Right` (bound as `RbxCameraKeypress` at
> priority 2000, sinking), and the legacy control scripts keep gamepad
> `ButtonA`. Screens built on this page still *render* perfectly — the input
> just silently never arrives, which is the hard part to diagnose later.
>
> Do it once per place. It is not scriptable and not Rojo-syncable, so no code
> here — LuauUI's included — can set it or check it for you; it is genuinely a
> human checkbox. The whole story, including why a higher priority number is not
> an alternative, is [chapter 7](07-input.md).

The Studio path swaps the fake adapter for the real one and adds the two other
client-only adapters (real device facts, real input). The complete, working
reference is `examples/gallery/client/init.client.luau`; here is its shape.

### Project mapping (Rojo)

> **Not using Rojo?** Rojo is not a dependency — it only turns the source folder
> into an `Instance` tree. [Chapter 8](08-without-rojo.md) covers the same setup
> with no external toolchain: drag in the prebuilt `build/LuauUI.rbxm` (or lift
> the library out of an example place) and skip to
> [§3.4 The client script](#the-client-script), which is identical either way.

LuauUI is placed under `ReplicatedStorage` and the client script under
`StarterPlayerScripts`. The example project file
`examples/gallery.project.json` does exactly this:

```json
{
  "name": "LuauUI-Gallery",
  "globIgnorePaths": ["**/*.spec.luau"],
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": {
      "LuauUI": { "$path": "../src" }
    },
    "StarterPlayer": {
      "StarterPlayerScripts": {
        "Gallery": { "$path": "gallery/client" }
      }
    }
  }
}
```

Note `globIgnorePaths` drops the `*.spec.luau` test files from the synced build,
and `"$path": "../src"` maps the whole library folder to a `ReplicatedStorage.LuauUI`
`Instance`. The library's internal requires are relative, so the *same* source
runs headless under Lune and mounted under Rojo with no changes.

### The client script

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LuauUI = require(ReplicatedStorage:WaitForChild("LuauUI"))

-- the client-only adapters are NOT on the LuauUI table; require them directly
local screen_target = require(ReplicatedStorage.LuauUI.client.screen_target)
local roblox_env    = require(ReplicatedStorage.LuauUI.client.roblox_env)
local roblox_input  = require(ReplicatedStorage.LuauUI.client.roblox_input)

local core   = LuauUI.newCore()
local env    = LuauUI.newEnvironment(core)
local unbind = roblox_env.bind(env)          -- pushes real screen size / input type into env
local adapter = screen_target.new()          -- renders under PlayerGui with real Instances
local system  = roblox_input.newSystem(core) -- maps actions onto the engine input system
local presenter = LuauUI.newPresenter(core, env, adapter, system)

local count = core:signal(0)
local label = core:memo(function(use) return `Clicked {use(count)} times` end)

local screen = LuauUI.UI.Screen({
    id = "Counter",
    padding = 16, gap = 8,
    children = {
        LuauUI.UI.Text({ id = "Label", text = label }),
        LuauUI.UI.Button({
            id = "Bump",
            label = "Bump",
            onActivate = function()
                count:set(count:get() + 1)
            end,
        }),
    },
})

presenter.present(screen)

-- drive one refresh per frame: this is what pushes dirty changes to the screen
RunService.Heartbeat:Connect(function()
    presenter.refresh()
end)
```

The three differences from the headless version are the only differences that
ever matter between test and production:

1. **The client-only requires.** `screen_target`, `roblox_env`, and
   `roblox_input` come from `src/client/*`, *not* from the `LuauUI` table. Keeping
   them off the public table is what lets server and shared code `require` the
   main library safely — none of the engine-touching code is pulled in unless a
   client explicitly asks for it.
2. **`roblox_env.bind(env)`** connects the environment's fact keys to real engine
   values and keeps them live (it returns an unbind function to disconnect
   later). In the headless test the environment just used its defaults.
3. **The per-frame `refresh()`.** As explained in
   [chapter 2](02-architecture.md), changes accumulate in a dirty queue and are
   applied when `refresh()` runs. On the client you call it once per frame from
   `Heartbeat`. In a test you call it manually after changing state, then inspect
   the result.

## 3.5 Where does *semantic* state come from?

In these examples `count` is a local signal — fine for self-contained UI state.
When the value is owned by the server (a coin balance, an inventory), you do not
hold it in a bare signal; you hold it in a **replication adapter** whose signal
you read the same way. That is the subject of [chapter 6](06-client-server.md).
The blueprint and its control-local `onActivate` behavior do not change — only where the signal's
value originates.

Next: [chapter 4](04-tutorial-examples.md) walks the eight example programs. If
you build directly in Studio without a file sync, read
[chapter 8](08-without-rojo.md) first — it replaces the Rojo project mapping
above with a one-file install and lists the traps of a hand-built instance tree.
