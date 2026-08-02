# 8. Getting started without Rojo

[Chapter 3](03-getting-started.md) wired LuauUI into Studio with a Rojo project
file. Rojo is *not* a dependency: nothing in the library requires it, imports it,
or asks whether it is running. Rojo does exactly one job — it turns a folder of
`.luau` files into an `Instance` tree inside your place. If you build directly in
Studio, you need that tree once, by another route, and then you never think about
it again.

This chapter is the no-Rojo route: the one structural rule, four ways to install,
the client script you write by hand, and what you do and do not give up.

## 8.1 The one rule: the instance tree must mirror the file tree

LuauUI's internal requires are Luau **require-by-string** — `require("@self/core/custom")`
inside `src/init.luau`, `require("../layout/solver")` inside a leaf module. This is
generally available in the engine (no beta flag), and it resolves against the
**instance tree**, not against files. Two consequences decide whether an install
works:

- **A folder that contains an `init.luau` becomes a ModuleScript named after the
  folder**, and the folder's other members become that ModuleScript's children.
  So `src/` does not become a Folder called `src` — it becomes the `LuauUI`
  **ModuleScript itself**, because `src/init.luau` is the library's entry point.
- **A folder with no `init.luau` becomes a plain Folder**, and each `.luau` file
  inside it becomes a ModuleScript with the `.luau` suffix stripped.

Concretely:

| On disk | In the DataModel |
|---|---|
| `src/init.luau` | `ReplicatedStorage.LuauUI` — a **ModuleScript** |
| `src/blueprint.luau` | `ReplicatedStorage.LuauUI.blueprint` — ModuleScript |
| `src/layout/` | `…LuauUI.layout` — **Folder** (no `init.luau` inside) |
| `src/layout/solver.luau` | `…LuauUI.layout.solver` — ModuleScript |
| `src/client/screen_target.luau` | `…LuauUI.client.screen_target` — ModuleScript |

Rename a node, flatten a folder, or leave `init.luau` sitting as a child called
`init` instead of *being* the `LuauUI` node, and requires fail at load. Every
option below exists to produce this tree without you assembling it by hand.

Put the tree in **`ReplicatedStorage`**. That is what lets a client script reach
it, and what keeps the main table safe to require from shared or server code
(see [chapter 2](02-architecture.md)).

## 8.2 Option A — drag in the prebuilt model *(recommended)*

The repository ships the library as a single model file: **`build/LuauUI.rbxm`**.
Its root is the `LuauUI` ModuleScript with the whole tree beneath it.

1. Get `build/LuauUI.rbxm` onto your machine (download it, or copy it out of a
   checkout — you do not need the rest of the repo).
2. In Studio's Explorer, **right-click `ReplicatedStorage` → Insert from File…**
   and choose `LuauUI.rbxm`.
3. Verify: `ReplicatedStorage.LuauUI` must be a **ModuleScript** (not a Folder),
   with `async`, `client`, `controls`, `core`, `env`, `focus`, `input`, `layout`,
   `present`, `preview`, `render`, `replication`, and `tokens` beneath it.

That is the whole install. If you instead drag the `.rbxm` file onto the 3D
viewport, Studio parents it to `Workspace` — move it to `ReplicatedStorage` in the
Explorer afterwards.

**Rebuilding the model** (maintainers only): `tools/build_model.sh` regenerates
`build/LuauUI.rbxm` from `src/`. That script uses Rojo — but only on the machine
that cuts a release. Consumers of the `.rbxm` need nothing installed. Re-run it
whenever `src/` or `LuauUI.VERSION` changes. The build ignores `**/*.spec.luau`,
so a spec file colocated with source can never ship inside the model (the library
keeps its tests in `tests/`, so today nothing is dropped).

## 8.3 Option B — lift the library out of a shipped example place

Every file in `examples/places/*.rbxl` — and `build/LuauUI-Gallery.rbxl` — already
contains the same `ReplicatedStorage.LuauUI` tree, because they are built from the
same `src/`.

1. Open any one of them in Studio (File → Open from File…).
2. Select `ReplicatedStorage.LuauUI`, copy it.
3. Open your own place and paste it into `ReplicatedStorage`.

Use this when you also want a working reference next to your own code: the same
place has the gallery bootstrap in `StarterPlayer.StarterPlayerScripts` and the
tutorial modules in `ReplicatedStorage.LuauUIExamples`, all of which you can read,
run, and copy from. See [chapter 4](04-tutorial-examples.md) for what each place
demonstrates.

## 8.4 Option C — publish it once, reuse it everywhere

If you maintain several places, upload the library to your own inventory instead
of re-importing a file each time.

- **As a model.** Right-click `ReplicatedStorage.LuauUI` → **Save to Roblox…** and
  publish it (private is fine). In any other place, insert it from the Toolbox's
  Inventory tab — it lands in `Workspace`, so move it to `ReplicatedStorage`.
  Upgrading means inserting the new copy and deleting the old one.
- **As a Package.** Right-click → **Convert to Package…**. A package remembers
  where its copies live, so when you publish a new version of the library you can
  pull it into each place with *Get Latest Package* instead of a manual
  re-import. This is the closest thing to a package manager available without an
  external toolchain, and it is the better choice if more than one place depends
  on LuauUI.

Either way, your own UI code stays outside the `LuauUI` node, so replacing the
library never touches it.

## 8.5 Option D — rebuild the tree by hand *(last resort)*

40 ModuleScripts across 13 folders. Only worth it if you genuinely cannot move a
file into Studio. Follow §8.1 exactly: create the folders, create a ModuleScript
for each `.luau` file with the suffix stripped, and make `src/init.luau`'s
contents the body of the `LuauUI` ModuleScript itself rather than a child named
`init`. A mistake shows up on first require as an error naming the component it
could not resolve — check that node's name and its parent's class before
suspecting anything else.

## 8.6 The client script, written in Studio

Nothing about the client script is Rojo-specific — this is the same script as
[§3.4](03-getting-started.md#34-wiring-inside-roblox-studio), typed into the
Studio script editor instead of synced from disk. Create a **LocalScript** under
`StarterPlayer.StarterPlayerScripts` (name it whatever you like) and paste:

```lua
-- string requires do NOT wait for replication: gate on the DataModel being
-- loaded before requiring anything out of ReplicatedStorage
if not game:IsLoaded() then
    game.Loaded:Wait()
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LuauUI = require(ReplicatedStorage:WaitForChild("LuauUI"))

-- client-only adapters are NOT on the LuauUI table; require them directly
local screen_target = require(ReplicatedStorage.LuauUI.client.screen_target)
local roblox_env    = require(ReplicatedStorage.LuauUI.client.roblox_env)
local roblox_input  = require(ReplicatedStorage.LuauUI.client.roblox_input)

local core    = LuauUI.newCore()
local env     = LuauUI.newEnvironment(core)
local unbind  = roblox_env.bind(env)
local adapter = screen_target.new()
local system  = roblox_input.newSystem(core)
local presenter = LuauUI.newPresenter(core, env, adapter, system)

local count = core:signal(0)
local label = core:memo(function(use) return `Clicked {use(count)} times` end)

presenter.present(
    LuauUI.UI.Screen({
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
)

RunService.Heartbeat:Connect(function()
    presenter.refresh()
end)
```

Press Play. A button appears; clicking, pressing Enter, or pressing gamepad A all
bump the count.

The `game.Loaded:Wait()` guard at the top is not optional and not cosmetic:
require-by-string does **not** wait for a ModuleScript to replicate, so a client
that starts requiring before the DataModel has finished loading can fail on a
child that simply has not arrived yet. `WaitForChild("LuauUI")` covers only the
top node — the guard covers the rest of the tree.

## 8.7 The one manual step that has nothing to do with Rojo

Tick **`Workspace.PlayerScriptsUseInputActionSystem`** in the Properties panel.
LuauUI's input layer is built on the Input Action System, the flag is not
scriptable, and with it off your gamepad Activate goes silently dead in any game
that has an avatar. Full story — including why, and how to tell — in
[chapter 7](07-input.md).

> **If the property is not in the Properties panel at all**, your Studio build
> does not expose it: observed 2026-07-21 on Studio `0.730.0.7300790`, where
> neither `Workspace` nor `StarterPlayer` has the member and
> `Enum.PlayerScriptsUseInputActionSystem` does not exist either — the Input
> Action System is a client beta, and the property comes and goes with it. That
> is not fatal to a UI-only place: in exactly that Studio, a freshly installed
> LuauUI built its `InputContext`/`InputAction` instances and both mouse and
> keyboard Activate worked. The flag governs *coexistence with the legacy control
> scripts* in a game that has an avatar — which is where a dead gamepad A comes
> from. Check for it again before shipping anything gamepad-facing.

## 8.8 What you give up, and what you don't

**You give up nothing at runtime.** Every feature in this guide — reactivity,
layout, focus and navigation, styling, replication adapters, all four input
devices — is in the model you dragged in. There is no Rojo-only code path.

**What you do give up** is workflow, and only workflow:

- **File-based version control of the library.** The tree lives in your `.rbxl`.
  Pin a version by recording `LuauUI.VERSION` (currently `0.7.0`) somewhere you
  will see it, and check `LuauUI.DEPRECATIONS` after an upgrade — see
  [ADR-0011](../adr/ADR-0011-semver-and-deprecation.md).
- **The headless test suite.** `./run-tests.sh` runs the whole suite under Lune
  with no Roblox process, but it needs the source files. You can clone the
  repository purely to run tests and read source without ever wiring Rojo into
  your place.
- **External-editor authoring of your own UI code.** Studio's script editor does
  type-check Luau, so `--!strict` still earns its keep — but the diff, review, and
  branch workflow is on you.

**Upgrading** is: delete `ReplicatedStorage.LuauUI`, insert the new one (or *Get
Latest Package*), press Play. Your UI code is outside the node and is untouched.

## 8.9 Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Require error naming a module or "could not resolve" a component | The instance tree does not mirror the file tree (§8.1) | Re-insert from `build/LuauUI.rbxm`; do not rename or flatten nodes |
| `LuauUI` is a **Folder**, not a ModuleScript | You copied the `src` folder rather than the built model — `init.luau` must *be* the `LuauUI` node | Use option A or B |
| Requires fail only sometimes, usually on join | Missing the `game.Loaded:Wait()` guard (§8.6) | Add the guard at the top of the client script |
| `attempt to index nil with 'client'` from a server or shared script | `client/*` is client-only by design and never on the public table | Require the adapters from a LocalScript only ([chapter 2](02-architecture.md)) |
| `core.fusion_adapter` fails to require | It is a Phase-0 bake-off artifact that reaches outside `src/` for `vendor/Fusion`, which the model does not ship | Don't require it — `LuauUI.newCore()` is the supported core |
| Gamepad A does nothing | `Workspace.PlayerScriptsUseInputActionSystem` is off | §8.7, then [chapter 7](07-input.md) |
| Nothing renders, no errors | `presenter.refresh()` is never called | Connect it to `RunService.Heartbeat` (§8.6) |
