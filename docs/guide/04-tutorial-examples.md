# Maintained examples

All maintained examples use the same entry path:

- a Compose Roblox runtime,
- `Host = runtime.constructors`,
- `UI = Facet.controls(runtime)`.

Example components return native Instances. The caller mounts them. Read the
[working screen](03-getting-started.md) before you examine a larger application.

## Gallery

The showcase is a collection of five interactive demos: Garage, Sipworks,
Screen-anchored HUD, Playlist and Arcade. Arcade contains the
three existing games and the Outpost power puzzle. Each demo gives the player a small task with a visible
result. The Facet Lab is the control-by-control browser.

The showcase retains its theme, device, input and motion settings. Its larger
Sipworks and Arcade use adaptive sidebar or top-bar navigation. Sipworks
also preserves its recipe history between wide and compact
navigation stacks. See the [demo map](../../examples/README.md#showcase) for the source and
a short interaction to try in each one.

Examine the native tree together with the visual result. Parentage and sizes
are engine properties. They are not a dump from a Facet solver.

A scenario gets the runtime, controls and Host constructors from its caller. It
does not make an application facade. It does not require a private Facet
implementation. A nested native Frame or layout is ordinary composition. It is
not a different render target.

To build and start the gallery, run these commands from the repository root:

```sh
rojo build examples/showcase.project.json -o artifacts/gallery.rbxl
open -a RobloxStudio artifacts/gallery.rbxl
```

Press Play. The gallery settings select the theme, the palette, the motion
preference and the viewing-distance preview. The preview scales the controls.
Use the Studio emulators to check the actual viewport and input.

## Virtual monitors

The virtual monitors showcase uses the same composition path for its UI and
its embedded scenes.

- Discover exercises a catalog that you can filter and sort, and saved state.
- Avatar exercises controls and 3D content.
- Assistant exercises a streaming conversation and end-following.

Spatial mode and flat mode rearrange the native targets. The durable state
stays in the model.

The [Virtual Monitors README](../../examples/virtual_monitors/README.md) has
the build command and the application map. Use the actual showcase for
regression work. Verify these behaviors:

- filtering and sorting after scrolling,
- switching modes,
- continued scene rendering,
- streamed replies,
- keyboard and gamepad access,
- teardown.

## What to copy

Copy the state flow and the native composition of a component. Keep the keys
stable. Use current-item readables. Register external subscriptions with
Compose cleanup. Do not copy test drivers into the UI of a game.

A live visual check and a headless behavior check give different evidence. For
a visible change, do both.
