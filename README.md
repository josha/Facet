# Facet

Facet is a UI library for Roblox. It has buttons, toggles, text fields,
pickers, menus, sheets, dialogs, tabs, lists, tables and more. Every control
works with pointer, touch, keyboard and gamepad, adapts to the screen it is on,
and takes its look from a theme you can replace without touching a screen.

Facet builds on the Roblox engine. Controls are ordinary Instances, and the
engine does layout, text, scrolling, selection and styling.

See all controls/layouts/options [live here](https://www.roblox.com/games/120259284556766/Facet-Lab) and this [showcase with examples in context](https://www.roblox.com/games/77767184583039/Facet-Showcase). 

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

app.mount(Counter)
script.Destroying:Connect(app.dispose)
```

A component is an ordinary function, and `count` is a cell of state: the label
updates when it changes. `Facet.app` sets up the controls and the theme, and
`app.mount` puts a component on the screen. `app.dispose` removes every screen
and releases what they own. `UI.environment()` supplies adaptive facts such as
the size class and the preferred input.

[Getting started](docs/guide/03-getting-started.md) explains this script.

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

[The verification scope](docs/guide/18-verification-scope.md) states what a run
covers. The current suite is the evidence. It does not claim to equal the tests
that existed before the native cutover.

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
`lune run tools/lune/build model`. [Installing without Rojo](docs/guide/08-without-rojo.md)
covers this route.

## Examples

- **[`examples/virtual_monitors/`](examples/virtual_monitors/)**: four apps for
  game discovery, a 3D avatar editor, an agent chat and Facet Flap. It uses every
  public Facet name, and a test checks this. Open the checked-in
  [Virtual Monitors](examples/places/Facet-VirtualMonitors.rbxl) place in Studio.
- **[`examples/facet_farm/`](examples/facet_farm/)**: a farming game with crops,
  tools and a seed market. Open the checked-in
  [Facet Farm](examples/places/Facet-Farm.rbxl) place in Studio. Rebuild the
  maintained places with `lune run tools/lune/build places`.
- **[`examples/consumer/`](examples/consumer/)**: the smallest complete project.
- **`examples/gallery/`**: every demo and every shipped theme. Build it with
  `rojo build examples/gallery.project.json -o build/Facet-Gallery.rbxl`.
- **`examples/gallery/examples/`**: the tutorial programs the guide teaches,
  smallest first.

## Documentation

| Document | What it is |
|---|---|
| [`docs/guide/README.md`](docs/guide/README.md) | **Start here.** The guide in reading order, with the capability catalog. |
| [`docs/guide/14-choosing-a-ui-library.md`](docs/guide/14-choosing-a-ui-library.md) | A comparison of Facet with other Roblox UI libraries. |
| [`tools/designer/README.md`](tools/designer/README.md) | Facet Design: visual editing, code sync, and human/agent design workflows. |
| [`docs/reference/api.md`](docs/reference/api.md) | Every property, default, callback and return value. |
| [`docs/reference/constitution.md`](docs/reference/constitution.md) | The rules anything added to this repository follows. |
| [`docs/MAINTAINERS.md`](docs/MAINTAINERS.md) | Where a change goes, and what proves it. |
| [`docs/extending/`](docs/extending/) | One playbook for each kind of addition. |
| [`CHANGELOG.md`](CHANGELOG.md) | What changed in each version. |
| [`AGENTS.md`](AGENTS.md) | The routing table for an automated coding agent. |

## Development

```sh
rokit install                        # the pinned toolchain: Rojo, luau-lsp, Lune, StyLua
lune run tools/lune/verify affected             # the smallest safe set for what you changed
lune run tools/lune/verify fast                 # the inner-loop tier
lune run tools/lune/verify full                 # every deterministic check, exactly once
lune run tools/lune/verify release              # full, plus the build, package and evidence producers
lune run tools/lune/verify spec <spec-name>     # one spec file
lune run tools/lune/bench                       # benchmarks
```

Builds and the distributable package:

```sh
lune run tools/lune/build model                 # build/Facet.rbxm, the library as one model file
lune run tools/lune/build themes                # build/themes/<Name>.rbxm, one per reference theme
python3 tools/package.py build               # the package artifact and its manifest
python3 tools/package.py status              # does the built artifact still match the source?
lune run tools/lune/build doctor                      # the toolchain and the library invariants
```

`python3 tools/package.py build` and `status` are offline. Publishing the asset needs a
credential that is never stored in this repository.

## State and Compose

Facet's state, animation and lifetimes come from
[Compose](https://github.com/voidmeld/compose), which Facet includes as
`Facet.Compose`. A game that already uses Compose can pass its own copy with
[`Facet.bind`](docs/reference/api.md#your-own-compose), so its state and Facet
share one reactive graph.

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
