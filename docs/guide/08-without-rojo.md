# 8. Getting started without Rojo

[Chapter 3](03-getting-started.md) wired Facet into Studio with a Rojo project
file. Rojo is *not* a dependency: nothing in the library requires it, imports it,
or asks whether it is running. Rojo does exactly one job — it turns a folder of
`.luau` files into an `Instance` tree inside your place. If you build directly in
Studio, you need that tree once, by another route, and then you never think about
it again.

This chapter is the no-Rojo route: the one structural rule, five ways to install,
the client script you write by hand, and what you do and do not give up.

## 8.1 The one rule: the instance tree must mirror the file tree

Facet's internal requires are Luau **require-by-string** — `require("@self/core/custom")`
inside `src/init.luau`, `require("../layout/solver")` inside a leaf module. This is
generally available in the engine (no beta flag), and it resolves against the
**instance tree**, not against files. Two consequences decide whether an install
works:

- **A folder that contains an `init.luau` becomes a ModuleScript named after the
  folder**, and the folder's other members become that ModuleScript's children.
  So `src/` does not become a Folder called `src` — it becomes the `Facet`
  **ModuleScript itself**, because `src/init.luau` is the library's entry point.
- **A folder with no `init.luau` becomes a plain Folder**, and each `.luau` file
  inside it becomes a ModuleScript with the `.luau` suffix stripped.

Concretely:

| On disk | In the DataModel |
|---|---|
| `src/init.luau` | `ReplicatedStorage.Facet` — a **ModuleScript** |
| `src/blueprint.luau` | `ReplicatedStorage.Facet.blueprint` — ModuleScript |
| `src/layout/` | `…Facet.layout` — **Folder** (no `init.luau` inside) |
| `src/layout/solver.luau` | `…Facet.layout.solver` — ModuleScript |
| `src/client/screen_target.luau` | `…Facet.client.screen_target` — ModuleScript |

Rename a node, flatten a folder, or leave `init.luau` sitting as a child called
`init` instead of *being* the `Facet` node, and requires fail at load. Every
option below exists to produce this tree without you assembling it by hand.

Put the tree in **`ReplicatedStorage`**. That is what lets a client script reach
it, and what keeps the main table safe to require from shared or server code
(see [chapter 2](02-architecture.md)).

## 8.2 Option A — the official Roblox Package *(recommended)*

Facet is published as one Roblox Package. A package is an ordinary model asset
that keeps a link back to the asset it came from, so every copy knows which
version it is and can be told to take a newer one. That is the closest thing to a
package manager Roblox offers without an external toolchain, and it is the reason
this is the recommended route: with the other options, upgrading means finding
every copy and re-importing it by hand.

**The asset id is pending.** The Facet package asset has not been created yet.
When it exists, its id and its creator are recorded in
`package/facet-package.json`, which is the one place that holds them. The id is
deliberately not part of Facet's Luau interface — no code you write should name
it.

### Installing it

1. In Studio, open the **Toolbox** and go to the **Inventory** tab.
2. Find Facet under **My Packages** and insert it.
3. Move the inserted `Facet` node to `ReplicatedStorage` if it landed elsewhere.
4. Verify `ReplicatedStorage.Facet` is a **ModuleScript**, exactly as in §8.3.

A package copy carries a `PackageLink` child and shows a chain-link symbol in the
Explorer. **Do not delete or move the `PackageLink`.** Doing so turns that copy
back into an ordinary model and it stops being a package.

### Knowing which version you have

Two answers, and they agree:

```lua
print(Facet.VERSION) -- "0.10.0"
```

...and the `Distribution` folder inside the package, whose attributes name the
exact source the artifact was built from: `Version`, `SourceCommit`, and
`SourceHash`. The folder also carries the licence and third-party notice text as
plain values, so the terms travel with the copy. Nothing in it is executable and
nothing in it is part of the runtime interface.

### Taking a new version

A copy that is behind gets a download symbol in the Explorer. Right-click it and
choose **Get Latest Package**. With several copies selected, **Get Latest For
Selected Packages** does them together.

The package's version history is in Package Options → Package Details →
**Versions**, where you can compare versions and restore an older one.

### AutoUpdate is opt-in, and it steps aside for a modified copy

Every copy has its own `PackageLink` with an `AutoUpdate` property, and it is
**false** when a package is created. Turn it on for a copy and the game
periodically checks for a new version while the place is open and takes it.

The moment you edit a copy, `AutoUpdate` on that copy is **disabled and ignored**,
and the copy gets a "modified" icon in the Explorer. A mass update skips modified
copies and reports how many it skipped. So a copy you changed is never silently
overwritten — it is simply left out. (Renaming the root node, moving a root
`GuiObject`, and toggling a root `LayerCollector.Enabled` do not count as
modifications.)

**In a production game, leave `AutoUpdate` off.** Take new versions deliberately
with *Get Latest Package*, read [`CHANGELOG.md`](../../CHANGELOG.md) and
`Facet.DEPRECATIONS`, and test the place before you publish it. Turn `AutoUpdate`
on only where accepting the newest compatible version without looking at it is
genuinely what you want — a prototype, or a place you open and check often.

## 8.3 Option B — drag in the prebuilt model

The repository ships the library as a single model file: **`build/Facet.rbxm`**.
Its root is the `Facet` ModuleScript with the whole tree beneath it.

1. Get `build/Facet.rbxm` onto your machine (download it, or copy it out of a
   checkout — you do not need the rest of the repo).
2. In Studio's Explorer, **right-click `ReplicatedStorage` → Insert from File…**
   and choose `Facet.rbxm`.
3. Verify: `ReplicatedStorage.Facet` must be a **ModuleScript** (not a Folder),
   with `async`, `client`, `controls`, `core`, `env`, `focus`, `input`, `layout`,
   `motion`, `present`, `preview`, `render`, `replication`, `themes`, and
   `tokens` beneath it. All fifteen: the entry module requires every one of them
   at load, so an install missing `motion` or `themes` errors on first require.

That is the whole install. If you instead drag the `.rbxm` file onto the 3D
viewport, Studio parents it to `Workspace` — move it to `ReplicatedStorage` in the
Explorer afterwards.

**Rebuilding the model** (maintainers only): `tools/build_model.sh` regenerates
`build/Facet.rbxm` from `src/`. That script uses Rojo — but only on the machine
that cuts a release. Consumers of the `.rbxm` need nothing installed. Re-run it
whenever `src/` or `Facet.VERSION` changes. The build ignores `**/*.spec.luau`,
so a spec file colocated with source can never ship inside the model (the library
keeps its tests in `tests/`, so today nothing is dropped).

**The model is the library alone.** It carries `src/` and Studio Neutral, the
theme Facet wears out of the box; it does not carry any of the eight optional
theme packages. Each of those is its own model file — `build/themes/<Name>.rbxm`,
built by `tools/build_themes.sh` — and installs the same way: drag it into
`ReplicatedStorage` beside `Facet` and require it. See
[13 — The theme catalog](13-theme-catalog.md) for what each one looks like, one
install call, and what it costs.

## 8.4 Option C — lift the library out of a shipped example place

Every file in `examples/places/*.rbxl` — and `build/Facet-Gallery.rbxl` — already
contains the same `ReplicatedStorage.Facet` tree, because they are built from the
same `src/`.

1. Open any one of them in Studio (File → Open from File…).
2. Select `ReplicatedStorage.Facet`, copy it.
3. Open your own place and paste it into `ReplicatedStorage`.

Use this when you also want a working reference next to your own code: the same
place has the gallery bootstrap in `StarterPlayer.StarterPlayerScripts` and the
tutorial modules in `ReplicatedStorage.FacetExamples`, all of which you can read,
run, and copy from. See [chapter 4](04-tutorial-examples.md) for what each place
demonstrates.

## 8.5 Option D — publish a copy of your own

Option A already gives you a package, so reach for this one only when you need a
copy under your own account: a fork you have patched, or a version pinned for a
team that cannot take upstream updates.

- **As a model.** Right-click `ReplicatedStorage.Facet` → **Save to Roblox…** and
  publish it (private is fine). In any other place, insert it from the Toolbox's
  Inventory tab — it lands in `Workspace`, so move it to `ReplicatedStorage`.
  Upgrading means inserting the new copy and deleting the old one.
- **As your own package.** Right-click → **Convert to Package…**, which gives your
  copy the same *Get Latest Package* flow §8.2 describes, published by you.
  Ownership of a package cannot be transferred afterwards, so choose the account
  or group deliberately at that moment.

Either way, your own UI code stays outside the `Facet` node, so replacing the
library never touches it.

## 8.6 Option E — rebuild the tree by hand *(last resort)*

40 ModuleScripts across 13 folders. Only worth it if you genuinely cannot move a
file into Studio. Follow §8.1 exactly: create the folders, create a ModuleScript
for each `.luau` file with the suffix stripped, and make `src/init.luau`'s
contents the body of the `Facet` ModuleScript itself rather than a child named
`init`. A mistake shows up on first require as an error naming the component it
could not resolve — check that node's name and its parent's class before
suspecting anything else.

## 8.7 The client script, written in Studio

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

local Facet = require(ReplicatedStorage:WaitForChild("Facet"))

-- client-only modules are NOT on the Facet table; require them directly
local host = require(ReplicatedStorage.Facet.client.host)

-- ONE call stands the whole thing up: a core, an environment BOUND to the
-- engine, a render target under PlayerGui, an input system, a presenter — and
-- one PreRender connection driving both halves of the frame.
local h = host.new()
local core, presenter = h.core, h.presenter

local count = core:signal(0)
local label = core:memo(function(use) return `Clicked {use(count)} times` end)

presenter.present(
    Facet.UI.Screen({
        id = "Counter",
        padding = 16, gap = 8,
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
)

-- ...and when this surface goes away, `h.dispose()` takes back the frame
-- connection, the input system, the render target and the environment binding.
```

Press Play. A button appears; clicking, pressing Enter, or pressing gamepad A all
bump the count.

The `game.Loaded:Wait()` guard at the top is not optional and not cosmetic:
require-by-string does **not** wait for a ModuleScript to replicate, so a client
that starts requiring before the DataModel has finished loading can fail on a
child that simply has not arrived yet. `WaitForChild("Facet")` covers only the
top node — the guard covers the rest of the tree.

## 8.8 The one manual step that has nothing to do with Rojo

Tick **`Workspace.PlayerScriptsUseInputActionSystem`** in the Properties panel.
Facet's input layer is built on the Input Action System, the flag is not
scriptable, and with it off your gamepad Activate goes silently dead in any game
that has an avatar. Full story — including why, and how to tell — in
[chapter 7](07-input.md).

> **If the property is not in the Properties panel at all**, your Studio build
> does not expose it: observed 2026-07-21 on Studio `0.730.0.7300790`, where
> neither `Workspace` nor `StarterPlayer` has the member and
> `Enum.PlayerScriptsUseInputActionSystem` does not exist either — the Input
> Action System is a client beta, and the property comes and goes with it. That
> is not fatal to a UI-only place: in exactly that Studio, a freshly installed
> Facet built its `InputContext`/`InputAction` instances and both mouse and
> keyboard Activate worked. The flag governs *coexistence with the legacy control
> scripts* in a game that has an avatar — which is where a dead gamepad A comes
> from. Check for it again before shipping anything gamepad-facing.

## 8.9 What you give up, and what you don't

**You give up nothing at runtime.** Every feature in this guide — reactivity,
layout, focus and navigation, styling, replication adapters, all four input
devices — is in the model you dragged in. There is no Rojo-only code path.

**What you do give up** is workflow, and only workflow:

- **File-based version control of the library.** The tree lives in your `.rbxl`.
  Pin a version by recording `Facet.VERSION` (currently `0.10.0`) somewhere you
  will see it, and check `Facet.DEPRECATIONS` after an upgrade — see
  [ADR-0011](../adr/ADR-0011-semver-and-deprecation.md). On the package route the
  `Distribution` folder's `Version`, `SourceCommit` and `SourceHash` attributes
  answer the same question without a checkout.
- **The headless test suite.** `./run-tests.sh` runs the whole suite under Lune
  with no Roblox process, but it needs the source files. You can clone the
  repository purely to run tests and read source without ever wiring Rojo into
  your place.
- **External-editor authoring of your own UI code.** Studio's script editor does
  type-check Luau, so `--!strict` still earns its keep — but the diff, review, and
  branch workflow is on you.

**Upgrading** is one of two things. On the package route (§8.2) it is *Get Latest
Package*, then press Play. On any other route it is: delete
`ReplicatedStorage.Facet`, insert the new one, press Play. Your UI code sits
outside the node either way and is untouched.

## 8.10 Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Require error naming a module or "could not resolve" a component | The instance tree does not mirror the file tree (§8.1) | Re-insert from `build/Facet.rbxm`; do not rename or flatten nodes |
| `Facet` is a **Folder**, not a ModuleScript | You copied the `src` folder rather than the built model — `init.luau` must *be* the `Facet` node | Use option B or C |
| Requires fail only sometimes, usually on join | Missing the `game.Loaded:Wait()` guard (§8.7) | Add the guard at the top of the client script |
| `attempt to index nil with 'client'` from a server or shared script | `client/*` is client-only by design and never on the public table | Require the adapters from a LocalScript only ([chapter 2](02-architecture.md)) |
| Gamepad A does nothing | `Workspace.PlayerScriptsUseInputActionSystem` is off | §8.8, then [chapter 7](07-input.md) |
| Nothing renders, no errors | nothing is driving the frame | Stand the surface up with `client.host` (§8.7), which connects one `PreRender` and drives `tick(dt)` then `refresh()` |
| It renders but nothing ever animates — a toast never expires, a transition never completes | the motion clock is not advancing: something is calling `presenter.refresh()` without `presenter.tick(dt)` | Same fix. `refresh` re-solves what the frame dirtied; `tick` is what moves the clock every transition, spring and timer rides, and a frozen clock looks exactly like a settled one in a dump |
