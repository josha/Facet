# Facet

Facet is a user-interface library for Roblox, written in Luau. Compose supplies
the authoring model and manages reactive updates and lifetimes. Facet adds
controls, layout, themes, adaptation and input.

Layout, focus and adaptation run in Luau and can be tested without Roblox Studio.
Client adapters create Roblox objects and connect scrolling, styling and input.
The same screen adapts to available space and input capabilities.

Use Compose cells, functions, collections and motion with Facet controls.
Facet does not require IDs for ordinary controls.

## A small working screen

After [installing Facet](#installing), put this in a LocalScript under
`StarterPlayer.StarterPlayerScripts`:

```lua
local Facet = require(game.ReplicatedStorage:WaitForChild("Facet"))
local Compose = Facet.Compose
local app = Facet.new()
local UI = app.controls

local function Counter()
    local count = Compose.cell(0)
    return UI.Screen {
        padding = "m", gap = "s",
        UI.Text {
            text = function(use) return `Clicked {use(count)} times` end,
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
```

Compose tracks `use(count)` and updates the bound property when the cell changes.
A component is an ordinary function. Facet supplies the controls, layout, styling,
input and frame driver. `close()` removes the screen and releases its owned
resources; `app.dispose()` closes the application, including any remaining screens.
Anonymous controls need no IDs. Changing collections use Compose's stable keys.
`app.environment` supplies adaptive facts; `app.onFrame(callback)` subscribes to
the host frame driver and returns a cleanup function. Inside a component, pass
that function to `Compose.cleanup` to release it on unmount.

Enable `Workspace.PlayerScriptsUseInputActionSystem` in Studio or your Rojo
project. The button works with pointer, touch, keyboard and gamepad. See
[getting started](docs/guide/03-getting-started.md) for setup and
[components](docs/guide/15-components.md) for state, collections and animation.

## What it runs on

Facet draws **client-side** user interface. Its surfaces are Roblox screens, and
there are three places a solved screen can land:

- **A screen** — a `ScreenGui` on the player's display. This is the default, and
  what every guide chapter assumes.
- **A billboard** — the same flat screen following an object in the world.
- **A world-fixed surface** — the same flat, two-dimensional screen on a
  `SurfaceGui` attached to a part, which a player walks up to and uses.

World-fixed surfaces remain two-dimensional interfaces. For embedded 3D, place a
`UI.Stage` and mount scene content into `controller.stageHost(path).contentRoot()`.
The same Compose model can also drive game-owned geometry through `client.scene`.
The
[Virtual Monitors showcase](examples/virtual_monitors) combines these features
in a shared-state screen and spatial desktop. VR pointer support is not yet
verified.

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

## Installing

### The official Roblox Package (recommended if you work in Studio)

> **Not available yet — use [Git and Rojo](#git-and-rojo) or [the built model
> file](#the-built-model-file) below.** The Package asset has not been created,
> so there is nothing to install from this route today. It is documented first
> because it is the route this project intends you to use once the asset exists.

Facet is published as one Roblox Package: a model asset that remembers where its
copies live, so a new version reaches every place with one command instead of a
manual re-import.

When the asset exists, its id and creator are recorded in
`package/facet-package.json`, which is the one place to look. The id is
deliberately not part of Facet's Luau interface.

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

Clone the repository, materialize the pinned Compose dependency, and map `src/`
into your place with [Rojo](https://rojo.space/):

```sh
python3 tools/sync_compose.py
```

The repository stores Compose's commit and file hashes, not its source. The
sync command downloads that exact revision and verifies it. For an offline local
checkout, use `python3 tools/sync_compose.py --source ../compose`.

A project file needs two things:

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

After running the dependency sync above, copy the materialized `src/` into your own repository and map it the same way. Facet's internal
requires are relative, so the same source runs headless under Lune and mounted in
Roblox with no changes. Record `Facet.VERSION` somewhere you will see it, so you
know what you have.

### The built model file

`build/Facet.rbxm` is the whole library as one file whose root is the `Facet`
`ModuleScript`. In Studio, right-click `ReplicatedStorage` and choose **Insert from
File**. Maintainers regenerate it with `tools/build_model.sh`.
[Guide 8](docs/guide/08-without-rojo.md) covers this route, the one structural
rule it depends on, and what a no-Rojo workflow costs.

## Examples

- **[`examples/virtual_monitors/`](examples/virtual_monitors/)** — three floating
  desktop panels: game discovery, a 3D avatar editor and a simulated agent chat.
  Shared light/dark themes and Compose-driven motion. Build and try it locally
  in Studio using the example's README.

- **[`examples/consumer/`](examples/consumer/)** — the smallest complete project.
  One theme, one adaptive screen, one Compose cell, one teardown.
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
| [`CHANGELOG.md`](CHANGELOG.md) | What changed in each version. |
| [`AGENTS.md`](AGENTS.md) | The routing table for an automated coding agent working with Facet. |

## Development

```sh
rokit install                        # the pinned toolchain: Rojo, luau-lsp, Lune, StyLua
python3 tools/sync_compose.py         # the exact Compose revision
tools/verify.sh affected             # the smallest safe set for what you changed
tools/verify.sh fast                 # the inner-loop tier
tools/verify.sh full                 # every deterministic check, exactly once
tools/verify.sh release              # full, plus the build, package and evidence producers
```

The suite also runs directly, and a single spec file is the loop to work in:

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

## Versioning

`Facet.VERSION` reports the version defined in `src/init.luau`. Before 1.0, a minor
version may change public behavior. The [versioning policy](CONTRIBUTING.md#6-versioning-and-deprecation)
sets the rules for changes, and the [changelog](CHANGELOG.md) records them.

## Contributing, security, and license

- [`CONTRIBUTING.md`](CONTRIBUTING.md) — setup, where a change goes, the four
  verification tiers, and what a good change looks like.
- [`SECURITY.md`](SECURITY.md) — report a vulnerability privately, through
  GitHub's private vulnerability reporting on this repository.
- [`LICENSE`](LICENSE) — the MIT License.
  [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) lists everything in this
  repository that somebody else wrote, with the notice it carries.
