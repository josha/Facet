# Maintained examples

All maintained examples use the same entry path:

- a Compose Roblox runtime,
- `Host = runtime.constructors`,
- `UI = Facet.controls(runtime)`.

Example components return native Instances. The caller mounts them. Read the
[working screen](03-getting-started.md) before you examine a larger application.

## Gallery

The gallery is the browser for controls and composition. It has examples of
input, selection, menus, navigation, modal content, collections, themes, media
and ownership. Start with the action and text controls. Then examine the
collection behavior. Then examine the presented and retained content.

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

## Reference applications

- **Glade:** care for a glade, select and consume nectar, watch the supply and
  visitor state, browse wisps and flora, buy provisions, edit the keeper
  profile and reset the world.
- **Cartwheel:** examine and complete brews, keep potion drafts, review
  popularity and history, unlock expanded history and chatter, examine market
  conditions and join the guild.
- **Sipworks:** search blends and botanicals, save favorites, order with
  pending and rejection states, earn and redeem stamps, examine measured
  recipes and unlock the Blend Book.
- **Foyer:** search and refresh world catalogs, examine details, keep the visit
  history, browse friends and notifications, and show unavailable destinations
  honestly.

These applications keep their original content and deterministic domain
services. Native controls own the UI mechanisms. The scripted services model
successful and rejected operations. They are examples. They are not production
payment or authority services.

## What to copy

Copy the state flow and the native composition of a component. Keep the keys
stable. Use current-item readables. Register external subscriptions with
Compose cleanup. Do not copy test drivers into the UI of a game.

A live visual check and a headless behavior check give different evidence. For
a visible change, do both.
