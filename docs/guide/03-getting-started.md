# 3. Getting started

This chapter builds the smallest useful screen and wires it two ways: first as a
headless test (no Roblox needed), then inside Roblox Studio. Working through both
shows exactly which pieces are engine-free and which live only on the client.

## 3.1 The pieces, in order

For a Roblox application, start with three pieces:

1. **A component** — `Facet.component(function(ui) ... end)` describes a view once per mount.
2. **State and recipes** — `ui.state` holds local values; property functions read them.
3. **A host** — `client.host.new()` supplies the environment, renderer, input and presenter. Present the component with `h.presenter.present(Counter {})`.

Use `local UI = Facet.View`. Numeric children keep their declared order. Facet owns
component state, controls and subscriptions until unmount. A changed property
updates that property; it does not run the whole component again.

The headless setup below assembles the host's underlying pieces explicitly so a
test can supply a recording adapter. That setup is an integration boundary, not
boilerplate to repeat in every screen. See [component authoring](15-components.md)
for collections, memos, effects and animation.

## 3.2 The smallest screen, headless

The headless path needs no Roblox process. Instead of the real render target you
supply a **fake adapter**: a plain table that implements the adapter interface.
The one below does nothing but count the nodes it is asked to create. This is exactly
how `tests/smoke.spec.luau` proves the whole library wires together.

```lua
local Facet = require("../src") -- relative require: runs under Lune
local UI = Facet.View

local core   = Facet.newCore()
local env    = Facet.newEnvironment(core)
local system = Facet.newActionSystem(core)

local Hello = Facet.component(function(ui)
    local count, setCount = ui.state(0)
    return UI.Screen {
        id = "S",
        UI.Button {
            id = "Go", label = function() return `Go ({count()})` end,
            onActivate = function() setCount(function(n) return n + 1 end) end,
        },
    }
end)

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
local handle = presenter.present(Hello {})

assert(created == 3)                              -- Screen, Button, Label
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

**Where your spec lives.** In **your own project**, next to the screen it
covers. Run it from your own Lune entry point: a file that requires each of your
specs and then runs them. That is all `tests/run.luau` is. Facet imposes no
layout on you.

Inside **this repository** the rule is narrower. It matters if you are
contributing rather than consuming. `lune run tests/run_one <name>` resolves
`tests/<name>.spec` and nothing else, so a spec lives directly under `tests/`.
Every spec file must also be registered in `tests/run.luau`. An unregistered spec
is a silent zero, and the registration checker fails a run that has one.

**What a headless theme test does and does not prove.** Committing a package
through `adapter.setThemePackage` exercises two things. The first is the metric
half: the resolved snapshot, the re-solve, and every geometry consequence. The
second is the **fallback** paint arm, where the palette is written property by
property. It does not
exercise Roblox `StyleSheet` paint, which needs a running engine; that is a
Studio claim, and `controller.inspect().mode` is what reports which arm is live.

## 3.3 Where state lives, and making the screen react

Keep temporary interface state inside its component. Give a changing property a
function that reads the state; give a control a callback that changes it.

```luau
local UI = Facet.View
local Counter = Facet.component(function(ui)
    local count, setCount = ui.state(0)
    return UI.Screen {
        id = "Counter", padding = "m", gap = "s",
        UI.Text { id = "Label", text = function() return `Clicked {count()} times` end },
        UI.Button {
            id = "Bump", label = "Bump",
            onActivate = function() setCount(function(n) return n + 1 end) end,
        },
    }
end)
local handle = presenter.present(Counter {})
```

`count()` reads the current value. `setCount` changes it. Facet tracks reads made
by the `text` recipe and updates the label after a write. A literal property stays
fixed. Use `ui.memo` for expensive or shared calculations; this short label needs
only a function. Use `ui.watch` for an external reaction, not to copy a value into
another property.

Component setup runs once per mount. Dismissing the handle releases its local
state and bindings. State that must survive navigation belongs in your model;
borrow a Core readable with `ui.read(model.coins)`. Never use `:get()` inside a
reactive recipe: that read is untracked.

Touch, mouse, keyboard and gamepad all reach `onActivate`. Commands belong in
callbacks, including commands that must run when a value has not changed.

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
> reaches into `ContextActionService`. Roblox's *own* scripts do. With this
> box unticked they hold keys outside the Input Action System, where no Facet
> binding can reach them. The default camera keeps `Left`/`Right` (bound as `RbxCameraKeypress` at
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

> **Not using Rojo?** Rojo is not a dependency. It only turns the source folder
> into an `Instance` tree. [Chapter 8](08-without-rojo.md) covers the same setup
> with no external toolchain. Insert the official Roblox Package — the
> recommended route, and the one that can take a new version with *Get Latest
> Package* — or drag in the prebuilt `build/Facet.rbxm`. Then skip to
> [§3.4 The client script](#the-client-script), which is identical either way.

Facet and its client-context bootstrap Script are placed under `ReplicatedStorage`. The example project file
`examples/gallery.project.json` does exactly this:

```json
{
  "name": "Facet-Gallery",
  "emitLegacyScripts": false,
  "globIgnorePaths": ["**/*.spec.luau"],
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": {
      "Facet": { "$path": "../src" },
      "Gallery": { "$path": "gallery/client" }
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
local UI = Facet.View
local Counter = Facet.component(function(ui)
    local count, setCount = ui.state(0)
    return UI.Screen {
        id = "Counter", padding = "m", gap = "s",
        UI.Text { id = "Label", text = function() return `Clicked {count()} times` end },
        UI.Button {
            id = "Bump", label = "Bump",
            onActivate = function() setCount(function(n) return n + 1 end) end,
        },
    }
end)

local handle = h.presenter.present(Counter {})
-- At the application's lifetime boundary:
-- h.presenter.dismiss(handle)
-- h.dispose()
```

The three differences from the headless version are the only differences that
ever matter between test and production:

1. **The client-only require.** `host` comes from `src/client/*`, *not* from the
   `Facet` table, and neither do the four modules it composes (`screen_target`,
   `roblox_env`, `roblox_input`, and the render target's collaborators). Keeping
   them off the public table lets server and shared code `require` the main
   library safely. Nothing engine-touching loads unless a client asks for it. You can still build the pieces by hand (see
   [api.md §Client entry points](../reference/api.md#client-entry-points)); the
   host is what those steps compose to, in the order they have to happen.
2. **The environment is BOUND.** `host.new` calls `roblox_env.bind(env)` for
   you, which connects the environment's fact keys to real engine values and
   keeps them live. In the headless test the environment just used its defaults.
3. **The per-frame `tick(dt)` + `refresh()`, which the host owns.** As explained
   in [chapter 2](02-architecture.md), changes accumulate in a dirty queue and are
   applied when `refresh()` runs. **`tick(dt)` is the other half, and it is not
   optional.** It advances the presenter's motion clock. Transitions, toast
   expiry and every spring or timer on that clock move only on frames you
   tick. A surface that drives `refresh` alone paints correctly and never
   animates — and nothing reports it, because a frozen clock and a settled one
   look identical. (This is not hypothetical. An earlier version of this
   guide taught a hand-rolled `refresh`-only loop, and three shipped surfaces in
   a production game had frozen motion because of it. The host exists so that
   loop cannot be copied out of this page again.) In a test you call both by
   hand: `presenter.tick(1/60)` to advance time, then `presenter.refresh()` after
   changing state. Inspect the result afterwards.

**Per-frame work of your own** — polling a model, stepping a game clock — goes on
`presenter.onTick(fn)`, which returns its own unsubscribe. It runs on the same
frame, after the motion step, so it reads this frame's settled values and
whatever it writes is solved before the frame ends. A second `RunService`
connection is the thing to avoid: the audit that produced the host found thirteen
game modules driving three different signals for what is conceptually one UI
frame.

## 3.5 Where does *semantic* state come from?

In these examples `count` is a local signal — fine for self-contained UI state.
When the server owns the value — a coin balance, an inventory — do not hold it
in a bare signal. Hold it in a **replication adapter**, whose signal you read the
same way. That is the subject of [chapter 6](06-client-server.md).
The blueprint and its control-local `onActivate` behavior do not change — only where the signal's
value originates.

## 3.6 The same screen, as a project you can run

Everything above is in [`examples/consumer/`](../../examples/consumer/) as a
complete standalone project. It has three parts: a Rojo project file that maps
the library and sets the workspace property from §3.4, a client script, and the
screen itself as one module. Build it, press Play, then change it.

```sh
rojo build examples/consumer/default.project.json -o build/Facet-Consumer.rbxl
```

`tests/consumer_standalone.spec.luau` mounts that same screen module headlessly.
It proves six things:

- the screen mounts;
- it wears a theme;
- it answers a button press;
- it repaints when a signal changes;
- it re-solves when the viewport or the preferred text size changes; and
- it leaves nothing behind when it is disposed.

So the example cannot drift away from the library without a test going red.

Next: [chapter 4](04-tutorial-examples.md) walks the eight example programs.
Read [chapter 8](08-without-rojo.md) first if you build directly in Studio with
no file sync. It replaces the Rojo project mapping above with a one-file install,
and lists the traps of a hand-built instance tree.
