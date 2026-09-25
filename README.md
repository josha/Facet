# Facet

Facet is a library of Roblox UI controls. It uses Compose and the Roblox engine.

- Compose creates and owns the native Instances, bindings, collections and motion.
- Roblox does layout, text editing, scrolling, selection and styling.
- Facet adds control behavior and adaptive presentation.

UI and embedded 3D content use one composition path. Create a Compose Roblox
runtime, get the Facet controls for that runtime, and mount into a native
target. Each control root is an Instance. You can use native property names and
Compose structural operations directly.

## A working screen

1. Set `Workspace.PlayerScriptsUseInputActionSystem` to true in the place.
2. Put Facet in ReplicatedStorage.
3. Put this LocalScript in StarterPlayerScripts.

```luau
local Facet = require(game.ReplicatedStorage:WaitForChild("Facet"))
local Compose = Facet.Compose
local app = Facet.app({ name = "Counter" })
local UI = app.UI

local function Counter()
    local count = Compose.cell(0)
    return UI.Screen {
        gap = "s",
        UI.Label {
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

app.mount(Counter)
script.Destroying:Connect(app.dispose)
```

Compose tracks `use(count)` and updates the label when the cell changes. A
component is an ordinary function. `Facet.app` makes the runtime, the controls
and the theme StyleSheet, and `app.mount` puts a component on the screen.
`app.dispose` removes every screen and releases what they own. The button works
with pointer, touch, keyboard and gamepad. `UI.environment()` supplies adaptive
facts such as the size class and the preferred input.

[Getting started](docs/guide/03-getting-started.md) explains this script.

## Already using Compose

Give Facet your own Compose copy, so your state and Facet share one reactive
graph:

```luau
local Compose = require(game.ReplicatedStorage.Packages.Compose.core)
local ComposeRoblox = require(game.ReplicatedStorage.Packages.Compose.roblox)
local Facet = require(game.ReplicatedStorage.Packages.Facet).bind(Compose, ComposeRoblox)
local UI = Facet.controls(ComposeRoblox.createRuntime())
```

Your cells drive Facet controls directly, and control disposal belongs to your
Compose owners. A runtime or readable from a different Compose copy stops with
an error that names the control. See
[`Facet.bind`](docs/reference/api.md) for the details.

## What it runs on

Facet draws client-side user interface on native Roblox targets. Mount into:

- **a screen**: a `ScreenGui` on the player's display. `Facet.app` makes one,
  and every guide chapter assumes it;
- **a billboard**: a `BillboardGui` that follows an object in the world;
- **a world-fixed surface**: a flat `SurfaceGui` on a part, which a player walks
  up to and uses.

For a target that is not a `ScreenGui`, use the runtime directly, as the
[API reference](docs/reference/api.md#native-targets-and-boundaries) shows.
`UI.Stage` holds embedded 3D content, and `UI.worldAnchor` places a control
beside an object in the world. The
[Virtual Monitors showcase](examples/virtual_monitors) uses all of these.

The main library table is safe to require from server or shared code. The
controls create Instances only when a client mounts them.

## What the evidence covers

- **The headless suite.** Thousands of cases run under Lune with no Roblox
  process. They prove Facet's own decisions: control behavior, state, adaptation
  and teardown. They cannot see engine layout, paint or a real device.
- **Roblox Studio checks.** Play sessions with simulated devices prove the real
  Instances, engine layout, selection and input on the host that ran them. They
  cannot see a low-end processor, memory pressure, thermals or battery.

[Verification parity](docs/guide/20-verification-parity.md) maps every test case
of the previous architecture to its replacement, and
[the verification scope](docs/guide/18-verification-scope.md) says what a run
does not cover.

## Installing

### The official Roblox Package

The Package asset is not published yet. When it exists, its id and creator are
recorded in `package/facet-package.json`. Take new versions with **Get Latest
Package**, and leave `AutoUpdate` off for a production game.
[`package/README.md`](package/README.md) has the full policy.

### Git and Rojo

Clone the repository and map `src/` into your place with
[Rojo](https://rojo.space/) 7.7.0 or newer. The pinned Compose snapshot is part of
`src/vendor/compose`; `python3 tools/sync_compose.py --check` confirms that it
matches its lock. A project file needs two things:

```json
{
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": { "Facet": { "$path": "path/to/Facet/src" } },
    "Workspace": { "$properties": { "PlayerScriptsUseInputActionSystem": "Enabled" } }
  }
}
```

`examples/consumer/default.project.json` is a complete, runnable version.

### A source copy

Copy `src/` into your own repository and map it the same way. Facet's requires
are relative, so the same source runs headless under Lune and mounted in Roblox.
Record `Facet.VERSION` where you will see it.

### The built model file

`build/Facet.rbxm` is the whole library as one `ModuleScript`. In Studio,
right-click `ReplicatedStorage` and choose **Insert from File**. Build it with
`tools/build_model.sh`. [Installing without Rojo](docs/guide/08-without-rojo.md)
covers this route.

## Examples

- **[`examples/virtual_monitors/`](examples/virtual_monitors/)**: three desktop
  panels for game discovery, a 3D avatar editor and an agent chat. It uses every
  public Facet name, and a test checks this.
- **[`examples/consumer/`](examples/consumer/)**: the smallest complete project.
- **`examples/gallery/`**: every demo and every shipped theme. Build it with
  `rojo build examples/gallery.project.json -o build/Facet-Gallery.rbxl`.
- **`examples/gallery/examples/`**: the tutorial programs the guide teaches,
  smallest first.
- **`examples/reference/`**: complete reference applications built from the
  public surface only.

## Documentation

| Document | What it is |
|---|---|
| [`docs/guide/README.md`](docs/guide/README.md) | **Start here.** The guide in reading order, with the capability catalog. |
| [`docs/guide/14-choosing-a-ui-library.md`](docs/guide/14-choosing-a-ui-library.md) | A comparison of Facet with other Roblox UI libraries. |
| [`docs/reference/api.md`](docs/reference/api.md) | Every property, default, callback and return value. |
| [`docs/reference/constitution.md`](docs/reference/constitution.md) | The rules anything added to this repository follows. |
| [`docs/MAINTAINERS.md`](docs/MAINTAINERS.md) | Where a change goes, and what proves it. |
| [`docs/extending/`](docs/extending/) | One playbook for each kind of addition. |
| [`CHANGELOG.md`](CHANGELOG.md) | What changed in each version. |
| [`AGENTS.md`](AGENTS.md) | The routing table for an automated coding agent. |

## Development

```sh
rokit install                        # the pinned toolchain: Rojo, luau-lsp, Lune, StyLua
tools/verify.sh affected             # the smallest safe set for what you changed
tools/verify.sh fast                 # the inner-loop tier
tools/verify.sh full                 # every deterministic check, exactly once
tools/verify.sh release              # full, plus the build, package and evidence producers
lune run tests/run_one <spec-name>   # one spec file
tools/bench.sh                       # benchmarks
```

Builds and the distributable package:

```sh
tools/build_model.sh                 # build/Facet.rbxm, the library as one model file
tools/build_themes.sh                # build/themes/<Name>.rbxm, one per reference theme
tools/package.sh build               # the package artifact and its manifest
tools/package.sh status              # does the built artifact still match the source?
tools/doctor.sh                      # the toolchain and the library invariants
```

`tools/package.sh build` and `status` are offline. Publishing the asset needs a
credential that is never stored in this repository.

## Versioning

`Facet.VERSION` reports the version defined in `src/init.luau`. Before 1.0, a
minor version may change public behavior. The
[versioning policy](CONTRIBUTING.md#versioning) sets the rules,
and the [changelog](CHANGELOG.md) records each change.

## Contributing, security, and license

- [`CONTRIBUTING.md`](CONTRIBUTING.md): setup, where a change goes, the four
  verification tiers, and what a good change looks like.
- [`SECURITY.md`](SECURITY.md): report a vulnerability privately through
  GitHub's private vulnerability reporting.
- [`LICENSE`](LICENSE): the MIT License.
  [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) lists the code that
  somebody else wrote, with its notice.
