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

[Getting started](docs/guide/getting-started.md) explains this script.

## What it runs on

Facet draws client-side user interface on native Roblox targets. Mount into:

- **a screen**: a `ScreenGui` on the player's display. `Facet.app` makes one,
  and the getting-started example uses it;
- **a billboard**: a `BillboardGui` that follows an object in the world;
- **a world-fixed surface**: a flat `SurfaceGui` on a part, which a player walks
  up to and uses.

For a target that is not a `ScreenGui`, use the runtime directly, as the
[API reference](../docs/reference/nodes/Native-targets-and-boundaries.md) shows.
`UI.Stage` holds embedded 3D content, and `UI.worldAnchor` places a control
beside an object in the world. The
[Virtual Monitors showcase](examples/virtual_monitors) uses all of these.

The main library table is safe to require from server or shared code. The
controls create Instances only when a client mounts them.

## What the evidence covers

- **The headless suite.** Thousands of cases run under Lute with no Roblox
  process. They prove Facet's own decisions: control behavior, state, adaptation
  and teardown. They cannot see engine layout, paint or a real device.
- **Roblox Studio checks.** Play sessions with simulated devices prove the real
  Instances, engine layout, selection and input on the host that ran them. They
  cannot see a low-end processor, memory pressure, thermals or battery.

[The verification scope](docs/guide/verification-scope.md) states what a run
covers. The current suite is the evidence. A passing run proves only the selected cases.

## Performance

Facet uses [Compose](https://github.com/voidmeld/compose) for scene composition.
The [Compose framework comparison](https://github.com/voidmeld/compose/blob/main/docs/framework-comparison.md)
shows why: frame time and retained memory against the other Roblox UI frameworks.

Facet's target is less than 5% added cost against an equivalent screen that is
built directly with Compose and Roblox instances.

## Installing

### The official Roblox Package

The Package asset is not published yet. When it exists, its id and creator are
recorded in `package/facet-package.json`. Take new versions with **Get Latest
Package**, and leave `AutoUpdate` off for a production game.
[`package/README.md`](package/README.md) has the full policy.

### Git and Rojo

Clone the repository and map `src/` into your place with
[Rojo](https://rojo.space/) 7.7.0 or newer. The pinned Compose snapshot is part of
`src/vendor/compose`; `lute run tools/facet sync compose --check` confirms that it
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
are relative, so the same source runs headless under Lute and mounted in Roblox.
Record `Facet.VERSION` where you will see it.

### The built model file

`build/Facet.rbxm` is the whole library as one `ModuleScript`. In Studio,
right-click `ReplicatedStorage` and choose **Insert from File**. Build it with
`lute run tools/facet build model`. [Installing without Rojo](docs/guide/installation.md)
covers this route.

## Examples

- **[`examples/virtual_monitors/`](examples/virtual_monitors/)**: four apps for
  game discovery, a 3D avatar editor, an agent chat and Facet Flap. It uses every
  public Facet name, and a test checks this. Open the checked-in
  [Virtual Monitors](examples/places/Facet-VirtualMonitors.rbxl) place in Studio.
- **[`examples/facet_farm/`](examples/facet_farm/)**: a farming game with crops,
  tools and a seed market. Open the checked-in
  [Facet Farm](examples/places/Facet-Farm.rbxl) place in Studio. Rebuild the
  maintained places with `lute run tools/facet build places`.
- **[`examples/consumer/`](examples/consumer/)**: the smallest complete project.
- **`examples/gallery/`**: every demo and every shipped theme. Build it with
  `rojo build examples/gallery.project.json -o build/Facet-Gallery.rbxl`.
- **`examples/gallery/examples/`**: the tutorial programs the guide teaches,
  smallest first.

## Documentation

Agents building or reviewing UI must use the [use-facet skill](skills/use-facet/SKILL.md).
It starts with the design guide, then routes to the relevant controls and checks.

| Document | What it is |
|---|---|
| [Designing game interfaces with Facet](skills/use-facet/references/GAME_UI_DESIGN_GUIDE.md) | Design principles, game flows, control choices, adaptive interaction and review. |
| [`docs/guide/README.md`](docs/guide/README.md) | Task-based routes to installation, implementation and verification. |
| [`docs/guide/choosing-facet.md`](docs/guide/choosing-facet.md) | A comparison of Facet with other Roblox UI libraries. |
| [`tools/designer/README.md`](tools/designer/README.md) | Facet Design: visual editing, code sync, and human/agent design workflows. |
| [`docs/reference/api.md`](docs/reference/api.md) | Every property, default, callback and return value. |
| [`docs/reference/constitution.md`](docs/reference/constitution.md) | The rules anything added to this repository follows. |
| [`docs/MAINTAINERS.md`](docs/MAINTAINERS.md) | Where a change goes, and what proves it. |
| [`docs/extending/`](docs/extending/) | One playbook for each kind of addition. |
| [`CHANGELOG.md`](CHANGELOG.md) | Current package and verification references. |
| [`AGENTS.md`](AGENTS.md) | The routing table for an automated coding agent. |

## Development

```sh
rokit install                                   # the pinned toolchain: Rojo, luau-lsp, Lute, StyLua
lute run tools/facet gate affected             # the smallest safe set for what you changed
lute run tools/facet gate fast                 # the inner-loop tier
lute run tools/facet gate full                 # every deterministic check, exactly once
lute run tools/facet gate release              # full, plus the build, package and evidence producers
lute run tools/facet gate spec <spec-name>     # one spec file
lute run tools/facet bench                       # benchmarks
lute run tools/facet check --all                # every repository check
lute run tools/facet help                       # every maintainer command
```

Builds and the distributable package:

```sh
lute run tools/facet build model                # build/Facet.rbxm, the library as one model file
lute run tools/facet build themes               # build/themes/<Name>.rbxm, one per reference theme
lute run tools/facet package build              # the package artifact and its manifest
lute run tools/facet package status             # does the built artifact still match the source?
```

`lute run tools/facet package build` and `status` are offline. Publishing the asset needs a
credential that is never stored in this repository.

## State and Compose

Facet's state, animation and lifetimes come from
[Compose](https://github.com/voidmeld/compose), which Facet includes as
`Facet.Compose`. A game that already uses Compose can pass its own copy with
[`Facet.bind`](../docs/reference/nodes/Your-own-Compose.md#your-own-compose), so its state and Facet
share one reactive graph.

## Versioning

`Facet.VERSION` reports the version defined in `src/init.luau`. Before 1.0, a
minor version may change public behavior. The
[versioning policy](CONTRIBUTING.md#versioning) sets the rules,
and the [current package notes](CHANGELOG.md) link its contracts and verification scope.

## Contributing, security, and license

- [`CONTRIBUTING.md`](CONTRIBUTING.md): setup, where a change goes, the four
  verification tiers, and what a good change looks like.
- [`SECURITY.md`](SECURITY.md): report a vulnerability privately through
  GitHub's private vulnerability reporting.
- [`LICENSE`](LICENSE): the MIT License.
  [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) lists the code that
  somebody else wrote, with its notice.
