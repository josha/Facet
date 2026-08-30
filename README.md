# Facet

Facet is a user-interface library for Roblox, written entirely in Luau. You hand
it a plain-data description of the screen you want, and it decides which real
objects to create, when to change them, and when to destroy them — you never write
`Instance.new("Frame")` or set a `Position` by hand.

Layout, state, focus, and adaptation are ordinary Luau, so a test can check them
exactly without a running engine. A thin adapter edge turns the result into real
Roblox user interface through the engine's own scrolling, styling, and input. One
description adapts from a phone to a console without a per-device branch, and every
control it ships is reachable by pointer, touch, keyboard, and gamepad.

Facet has its own reactive core. It depends on no third-party user-interface or
reactivity library at runtime.

## What it runs on

Facet draws **client-side** user interface. Its surfaces are Roblox screens, and
there are three places a solved screen can land:

- **A screen** — a `ScreenGui` on the player's display. This is the default, and
  what every guide chapter assumes.
- **A billboard** — the same flat screen following an object in the world.
- **A world-fixed surface** — the same flat, two-dimensional screen on a
  `SurfaceGui` attached to a part, which a player walks up to and uses.

That last one is a flat screen in the world and nothing more. Facet has no
declarative three-dimensional layout, no virtual-reality mode, and no ray, hand, or
gaze input path.

The main library table is safe to require from server or shared code. The modules
that create Roblox objects, read the real input device, and read the real viewport
are client-only and are required directly from `src/client/`.

## What the evidence covers

Two instruments produce Facet's recorded evidence, and it is worth knowing what
each cannot see.

- **The headless suite.** Thousands of cases run under Lune with no Roblox
  process. They prove Facet's own decisions — layout arithmetic, focus, state,
  adaptation, teardown — exactly and repeatably. They cannot see engine frame work,
  paint cost, or anything about a real device.
- **Roblox Studio checks.** A Play session with a simulated device proves the
  integrated adapter's real objects, connections, and frame work **on the host
  machine you ran it on**. It cannot see a low-end processor, memory pressure,
  thermals, or battery.

**The physical-device evidence classes are declared and empty.** Facet records
three of them — a desktop retail client, the weakest supported Android phone, and
a console — and each currently carries zero rows rather than being omitted.
Device performance budgets are marked as unmeasured and are reported as skipped on
every run. So: do not describe Facet as proven on low-end phones, consoles, or
televisions. [Guide 11](docs/guide/11-device-verification.md) is the full account,
including which numbers may be compared with which.

## Installing

### The official Roblox Package (recommended if you work in Studio)

Facet is published as one Roblox Package: a model asset that remembers where its
copies live, so a new version reaches every place with one command instead of a
manual re-import.

**The asset id is pending.** The asset has not been created yet. When it exists,
its id and creator are recorded in `package/facet-package.json`, which is the one
place to look. The id is deliberately not part of Facet's Luau interface.

1. In Studio, open the Toolbox and find the package under **Inventory**.
2. Drag it in, then move it to `ReplicatedStorage` if it landed elsewhere.
3. Confirm `ReplicatedStorage.Facet` is a `ModuleScript`, not a `Folder`.

**Updating.** An out-of-date copy is marked in the Explorer. Right-click it and
choose **Get Latest Package**. To check which version you have, read
`Facet.VERSION`, or read the `Distribution` folder inside the package, whose
`Version`, `SourceCommit`, and `SourceHash` attributes identify the exact source it
was built from.

**AutoUpdate is opt-in, and it stops for a modified copy.** Every copy has its own
`PackageLink` with an `AutoUpdate` property that is false when the package is
created. Turning it on lets that copy take the newest version. The moment you edit
a copy, its `AutoUpdate` is disabled and ignored, and mass updates skip it and
report it as skipped — a modified copy is never silently overwritten.

**For a production game, prefer reviewed updates.** Leave `AutoUpdate` off, take
new versions deliberately with **Get Latest Package**, and test before you publish
the place. Turn `AutoUpdate` on only where accepting the newest compatible version
without looking is what you actually want.

### Git and Rojo

Clone the repository and map `src/` into your place with
[Rojo](https://rojo.space/). A project file needs two things:

```json
{
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": { "Facet": { "$path": "path/to/Facet/src" } },
    "Workspace": { "$properties": { "PlayerScriptsUseInputActionSystem": "Enabled" } }
  }
}
```

`examples/consumer/default.project.json` is a complete, runnable version of that.
Rojo 7.7.0 or newer is required, because earlier builds do not know the workspace
property Facet's input layer needs.

### A source copy

Copy `src/` into your own repository and map it the same way. Facet's internal
requires are relative, so the same source runs headless under Lune and mounted in
Roblox with no changes. Record `Facet.VERSION` somewhere you will see it, so you
know what you have.

### The built model file

`build/Facet.rbxm` is the whole library as one file whose root is the `Facet`
`ModuleScript`. In Studio, right-click `ReplicatedStorage` and choose **Insert from
File**. Maintainers regenerate it with `tools/build_model.sh`.
[Guide 8](docs/guide/08-without-rojo.md) covers this route, the one structural
rule it depends on, and what a no-Rojo workflow costs.

## The five-minute screen

One `LocalScript` under `StarterPlayer.StarterPlayerScripts`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Facet = require(ReplicatedStorage:WaitForChild("Facet"))
-- the client-only modules are not on the Facet table; require them directly
local host = require(ReplicatedStorage.Facet.client.host)

-- one call stands up a core, a bound environment, a render target, an input
-- system and a presenter, and drives both halves of the frame
local h = host.new()
local core, presenter = h.core, h.presenter

local count = core:signal(0)
local label = core:memo(function(use)
    return `Clicked {use(count)} times`
end)

presenter.present(Facet.UI.Screen({
    id = "Counter",
    padding = "m",
    gap = "s",
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
}))
```

Passing the memo as `text` is the whole reactivity rule: a readable value makes
that property reactive, a plain value does not. Press Play, and clicking, pressing
Enter, or pressing gamepad A all bump the count.

**One checkbox first.** Tick `Workspace.PlayerScriptsUseInputActionSystem` in
Studio's Properties panel, or declare it in your project file as the snippet above
does. Facet's input layer is built on Roblox's Input Action System, and with the
property off, Roblox's own scripts hold some keys where no Facet binding can reach
them. [Guide 3](docs/guide/03-getting-started.md) explains this in full.

The same screen as a standalone, runnable Rojo project is
[`examples/consumer/`](examples/consumer/), and a headless spec mounts that exact
screen and proves it works.

## Examples

- **[`examples/consumer/`](examples/consumer/)** — the smallest complete project.
  One theme, one adaptive screen, one signal, one teardown.
- **`examples/gallery/`** — the showcase place: a picker that switches between
  every demo and every shipped theme on the device in your hand. Build it with
  `rojo build examples/gallery.project.json -o build/Facet-Gallery.rbxl`.
- **`examples/gallery/examples/`** — the tutorial programs the guide teaches,
  smallest first.
- **`examples/reference/`** — complete reference applications, each built from
  nothing but the public surface.

## Documentation

| Document | What it is |
|---|---|
| [`docs/guide/README.md`](docs/guide/README.md) | **Start here.** The guide, in reading order, written for a Roblox developer who has never seen this repository. It carries the capability catalog: every public capability, one line each, linked to its reference entry. |
| [`docs/guide/14-choosing-a-ui-library.md`](docs/guide/14-choosing-a-ui-library.md) | Optional: a comparison of Facet with React Luau, Fusion and Vide, for a creator choosing a UI library. |
| [`docs/reference/api.md`](docs/reference/api.md) | The exhaustive reference — every property, default, callback, and return value. |
| [`docs/reference/constitution.md`](docs/reference/constitution.md) | The rules anything added to this repository has to follow. |
| [`docs/MAINTAINERS.md`](docs/MAINTAINERS.md) | Where a change goes, and what proves it. |
| [`docs/extending/`](docs/extending/) | One playbook per kind of addition: a control, a primitive, a theme, a skinned control, an engine feature, a render target, a platform mode. |
| [`CHANGELOG.md`](CHANGELOG.md) | What changed in each version, and every behavior change riding the unreleased one. |
| [`AGENTS.md`](AGENTS.md) | The routing table for an automated coding agent working with Facet. |

## Development

```sh
rokit install                        # the pinned toolchain: Rojo, luau-lsp, Lune, StyLua
tools/verify.sh affected             # the smallest safe set for what you changed
tools/verify.sh fast                 # the inner-loop tier
tools/verify.sh full                 # every deterministic check, exactly once
tools/verify.sh release              # full, plus the build, package and evidence producers
```

The suite also runs the way it always has, and a single spec file is the loop to
work in:

```sh
./run-tests.sh                       # the complete suite
./run-tests.sh --fast                # the same list minus the slowest files
lune run tests/run_one <spec-name>   # one spec file
```

Builds and the distributable package:

```sh
tools/build_model.sh                 # build/Facet.rbxm, the library as one model file
tools/build_themes.sh                # build/themes/<Name>.rbxm, one per reference theme
tools/package.sh build               # the package artifact and its manifest
tools/package.sh status              # does the built artifact still match the source?
tools/package.sh verify              # rebuild, inspect the tree, run the consumer check
tools/doctor.sh                      # the toolchain and the library invariants
```

`tools/package.sh build`, `status`, and `verify` are offline. Creating or
publishing the asset requires an explicit confirmation flag and a credential that
is never stored in this repository; [`package/README.md`](package/README.md) is
the reference.

## Versioning and compatibility

Facet follows semantic versioning, and the policy is
[`CONTRIBUTING.md` §6](CONTRIBUTING.md#6-versioning-and-deprecation). The version lives in one
place, `src/init.luau`, and is readable as `Facet.VERSION` — currently `0.10.0`.

While Facet is pre-1.0, a minor version may change public behavior. Nothing public
disappears without an entry in `Facet.DEPRECATIONS` naming its replacement and the
earliest version that may remove it. [`CHANGELOG.md`](CHANGELOG.md) records what
changed and when.

Check `Facet.DEPRECATIONS` after any upgrade.

## Contributing, security, and license

- [`CONTRIBUTING.md`](CONTRIBUTING.md) — setup, where a change goes, the four
  verification tiers, and what a good change looks like.
- [`SECURITY.md`](SECURITY.md) — report a vulnerability privately, through
  GitHub's private vulnerability reporting on this repository.
- [`LICENSE`](LICENSE) — the MIT License.
  [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) lists everything in this
  repository that somebody else wrote, with the notice it carries.
