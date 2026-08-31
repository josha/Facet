# 3. Getting started

This chapter builds the smallest useful screen and wires it two ways: first as a
headless test (no Roblox needed), then inside Roblox Studio. Working through both
shows exactly which pieces are engine-free and which live only on the client.

## 3.1 The pieces, in order

Every Facet screen is assembled from the same short sequence:

1. **A core** — the reactive runtime. `Facet.newCore()`.
2. **An environment** — the per-device facts. `Facet.newEnvironment(core)`.
3. **An action system** — the input pipeline. `Facet.newActionSystem(core)`.
4. **A render-target adapter** — where output goes. The real screen on the
   client; a fake recorder in a test.
5. **A presenter** — owns screens on top of all of the above.
   `Facet.newPresenter(core, env, adapter, actionSystem)`.
6. **A blueprint**, handed to `presenter.present(...)`.

## 3.2 The smallest screen, headless

The headless path needs no Roblox process. Instead of the real render target you
supply a **fake adapter** — a plain table implementing the adapter interface,
here doing nothing but counting the nodes it is asked to create. This is exactly
how `tests/smoke.spec.luau` proves the whole library wires together.

```lua
local Facet = require("../src") -- relative require: runs under Lune

local core   = Facet.newCore()
local env    = Facet.newEnvironment(core)
local system = Facet.newActionSystem(core)

-- a blueprint: a screen with one button
local screen = Facet.UI.Screen({
    id = "S",
    children = {
        Facet.UI.Button({ id = "Go", label = "Go" }),
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

local presenter = Facet.newPresenter(core, env, adapter, system)
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

## 3.2b Testing your screen

The adapter above is a teaching toy: it counts nodes and does nothing else. It
cannot press a button, read a rectangle back, or wear a theme, so it can prove
that a screen mounts and nothing more.

**The real headless instrument is `tests/lib/fake_target.luau`.** It implements
the same adapter contract the client target implements, and it records the tree:
every node, every rectangle, every property write. It also drives input, which is
the half that matters — a test that cannot press the button is testing the
blueprint, not the screen.

The canonical worked example is
[`tests/consumer_standalone.spec.luau`](../../tests/consumer_standalone.spec.luau),
which mounts [`examples/consumer/`](../../examples/consumer/) and proves it end to
end. Read that file next; it is short, and it is the shape to copy.

The verbs you will reach for first:

| Call | What it does |
|---|---|
| `adapter.node(path)` | one node: its `rect`, its `props`, its resolved paint |
| `adapter.paths()` / `adapter.liveCount()` | everything currently on the target |
| `adapter.tap(path)` | activate a control the way a pointer would |
| `adapter.pointerDown(x, y, kind)` / `pointerMove` / `pointerUp` | a raw gesture, including touch |
| `adapter.driveDragStart` / `driveDragContinue` / `driveDragEnd` | a drag through the native detector seam |
| `adapter.typeText(path, s)` / `commitText(path)` | text entry |
| `adapter.setThemePackage(package, themeName)` | commit a theme and repaint |
| `adapter.rootCount()` | what is left after teardown — the leak check |

A test drives the frame by hand. `presenter.refresh()` applies what the frame
dirtied; `presenter.tick(dt)` advances the motion clock. Both, in that order, are
what a real frame does.

> **The fake target ships in the repository, not in the library.** It lives under
> `tests/`, so a clone has it and the built `build/Facet.rbxm` and the Roblox
> Package do not — they carry `src/` and nothing else. If you installed Facet as
> a Package or a model file and you want headless tests, clone the repository
> alongside your game and point Lune at it.

**What a headless theme test does and does not prove.** Committing a package
through `adapter.setThemePackage` exercises the metric half — the resolved
snapshot, the re-solve, and every geometry consequence — and the **fallback**
paint arm, where the palette is written property by property. It does not
exercise Roblox `StyleSheet` paint, which needs a running engine; that is a
Studio claim, and `controller.inspect().mode` is what reports which arm is live.

## 3.3 Where state lives, and making the screen react

The screen above is static. To make it *do* something, give it semantic state as
a signal and read that signal from the blueprint.

```lua
local core = Facet.newCore()

-- semantic state: a label the button will change
local count = core:signal(0)

-- a memo derives display text from the count; it recomputes only when count changes
local label = core:memo(function(use)
    return `Clicked {use(count)} times`
end)

local screen = Facet.UI.Screen({
    id = "Counter",
    padding = "m",
    gap = "s",
    children = {
        Facet.UI.Text({ id = "Label", text = label }),  -- a signal/memo as a prop = reactive
        Facet.UI.Button({
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
prop value, Facet subscribes to it: whenever the memo changes, the text node is
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

> ### ⚠️ One checkbox first: Facet requires the Input Action System
>
> Before any of the code below, open the **Workspace** in Studio's Explorer and
> tick **`PlayerScriptsUseInputActionSystem`** in the Properties panel (category
> *Behavior*). Roblox describes it as controlling "whether the built-in player
> scripts are updated to use the Input Action System"
> ([`Workspace` API reference](https://create.roblox.com/docs/reference/engine/classes/Workspace)).
>
> **The shipped example places already carry it** — it is declared in every
> `examples/*.project.json`, so a `rojo build` bakes it in and a rebuild cannot
> silently undo it. That needs Rojo **7.7.0 or newer**: 7.7.0-rc.1's reflection
> database does not know the property and fails the build with *"Unknown
> property"*. `rokit.toml` pins it; run `rojo` through rokit rather than a
> `/usr/local/bin` copy.
>
> Facet's input layer is built entirely on the Input Action System and never
> reaches into `ContextActionService`. Roblox's *own* scripts do, and with this
> box unticked they hold keys outside the Input Action System, where no Facet
> binding can reach
> them: the default camera keeps `Left`/`Right` (bound as `RbxCameraKeypress` at
> priority 2000, sinking), and the legacy control scripts keep gamepad
> `ButtonA`. Screens built on this page still *render* perfectly — the input
> just silently never arrives, which is the hard part to diagnose later.
>
> Do it once per place. It is not scriptable and not Rojo-syncable, so no code
> here — Facet's included — can set it or check it for you; it is genuinely a
> human checkbox. The whole story, including why a higher priority number is not
> an alternative, is [chapter 7](07-input.md).

The Studio path swaps the fake adapter for the real one and adds the two other
client-only adapters (real device facts, real input). The complete, working
reference is `examples/gallery/client/init.client.luau`; here is its shape.

### Project mapping (Rojo)

> **Not using Rojo?** Rojo is not a dependency — it only turns the source folder
> into an `Instance` tree. [Chapter 8](08-without-rojo.md) covers the same setup
> with no external toolchain: insert the official Roblox Package (the recommended
> route, and the one that can take a new version with *Get Latest Package*), or
> drag in the prebuilt `build/Facet.rbxm`, then skip to
> [§3.4 The client script](#the-client-script), which is identical either way.

Facet is placed under `ReplicatedStorage` and the client script under
`StarterPlayerScripts`. The example project file
`examples/gallery.project.json` does exactly this:

```json
{
  "name": "Facet-Gallery",
  "globIgnorePaths": ["**/*.spec.luau"],
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": {
      "Facet": { "$path": "../src" }
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
and `"$path": "../src"` maps the whole library folder to a `ReplicatedStorage.Facet`
`Instance`. The library's internal requires are relative, so the *same* source
runs headless under Lune and mounted under Rojo with no changes.

### The client script

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Facet = require(ReplicatedStorage:WaitForChild("Facet"))

-- the client-only modules are NOT on the Facet table; require them directly
local host = require(ReplicatedStorage.Facet.client.host)

-- ONE call stands the whole thing up: a core, an environment BOUND to the
-- engine, a render target under PlayerGui, an input system, a presenter — and
-- one PreRender connection driving both halves of the frame.
local h = host.new()
local core, presenter = h.core, h.presenter

local count = core:signal(0)
local label = core:memo(function(use) return `Clicked {use(count)} times` end)

local screen = Facet.UI.Screen({
    id = "Counter",
    padding = "m", gap = "s",
    children = {
        Facet.UI.Text({ id = "Label", text = label }),
        Facet.UI.Button({
            id = "Bump",
            label = "Bump",
            onActivate = function()
                count:set(count:get() + 1)
            end,
        }),
    },
})

presenter.present(screen)

-- ...and when this surface goes away, `h.dispose()` takes back the frame
-- connection and unbinds the environment.
```

The three differences from the headless version are the only differences that
ever matter between test and production:

1. **The client-only require.** `host` comes from `src/client/*`, *not* from the
   `Facet` table, and neither do the four modules it composes (`screen_target`,
   `roblox_env`, `roblox_input`, and the render target's collaborators). Keeping
   them off the public table is what lets server and shared code `require` the
   main library safely — none of the engine-touching code is pulled in unless a
   client explicitly asks for it. You can still build the pieces by hand (see
   [api.md §Client entry points](../reference/api.md#client-entry-points)); the
   host is what those steps compose to, in the order they have to happen.
2. **The environment is BOUND.** `host.new` calls `roblox_env.bind(env)` for
   you, which connects the environment's fact keys to real engine values and
   keeps them live. In the headless test the environment just used its defaults.
3. **The per-frame `tick(dt)` + `refresh()`, which the host owns.** As explained
   in [chapter 2](02-architecture.md), changes accumulate in a dirty queue and are
   applied when `refresh()` runs. **`tick(dt)` is the other half and it is not
   optional**: it is what advances the presenter's motion clock, so transitions,
   toast expiry and every spring or timer on that clock only move on frames you
   tick. A surface that drives `refresh` alone paints correctly and never
   animates — and nothing reports it, because a frozen clock and a settled one
   look identical. (This guide taught a hand-rolled `refresh`-only loop until
   2026-08-17, and three shipped surfaces in Rascal Rally had frozen motion
   because of it. The host exists so the lesson cannot be copied out of this page
   again.) In a test you call both manually — `presenter.tick(1/60)` to advance
   time, `presenter.refresh()` after changing state — then inspect the result.

**Per-frame work of your own** — polling a model, stepping a game clock — goes on
`presenter.onTick(fn)`, which returns its own unsubscribe. It runs on the same
frame, after the motion step, so it reads this frame's settled values and
whatever it writes is solved before the frame ends. A second `RunService`
connection is the thing to avoid: the audit that produced the host found thirteen
game modules driving three different signals for what is conceptually one UI
frame.

## 3.5 Where does *semantic* state come from?

In these examples `count` is a local signal — fine for self-contained UI state.
When the value is owned by the server (a coin balance, an inventory), you do not
hold it in a bare signal; you hold it in a **replication adapter** whose signal
you read the same way. That is the subject of [chapter 6](06-client-server.md).
The blueprint and its control-local `onActivate` behavior do not change — only where the signal's
value originates.

## 3.6 The same screen, as a project you can run

Everything above is in [`examples/consumer/`](../../examples/consumer/) as a
complete standalone project: a Rojo project file that maps the library and sets
the workspace property from §3.4, a client script, and the screen itself as one
module. Build it, press Play, then change it.

```sh
rojo build examples/consumer/default.project.json -o build/Facet-Consumer.rbxl
```

That same screen module is mounted headlessly by
`tests/consumer_standalone.spec.luau`, which proves it mounts, wears a theme,
answers a button press, repaints when a signal changes, re-solves when the
viewport or the preferred text size changes, and leaves nothing behind when it is
disposed. So the example cannot drift away from the library without a test going
red.

Next: [chapter 4](04-tutorial-examples.md) walks the eight example programs. If
you build directly in Studio without a file sync, read
[chapter 8](08-without-rojo.md) first — it replaces the Rojo project mapping
above with a one-file install and lists the traps of a hand-built instance tree.
