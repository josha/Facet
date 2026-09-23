# Maintained examples

Every maintained example uses the same entry path: a Compose Roblox runtime, `Host = runtime.constructors`, and `UI = Facet.controls(runtime)`. Example components return native Instances; their caller mounts them. Read the [working screen](03-getting-started.md) before exploring a larger application.

## Gallery

The gallery is the control and composition browser. It includes input, selection, menus, navigation, modal content, collections, themes, media and ownership examples. Start with action and text controls, then collection behavior, then presented and retained content. Inspect the native tree alongside the visual result: parentage and sizes are engine properties, not a solved Facet dump.

A scenario obtains the caller's runtime, controls and Host constructors. It does not create an application facade or require a private Facet implementation. A nested native Frame or layout is ordinary composition, not another render target.

## Virtual monitors

The virtual monitors showcase uses the same composition path for its UI and embedded scenes. Discover exercises a filterable/sortable catalog and saved state; Avatar exercises controls and 3D content; Assistant exercises streaming conversation and end-following. Spatial and flat modes rearrange native targets while durable state remains in the model.

Use the actual showcase for regression work. Verify filtering and sorting after scrolling, switching modes, continued scene rendering, streamed replies, keyboard/gamepad access and teardown.

## Reference applications

- **Glade:** care for a glade, select and consume nectar, watch supply/visitor state, browse wisps and flora, purchase provisions, edit the keeper profile and reset the world.
- **Cartwheel:** inspect and complete brews, retain potion drafts, review popularity/history, unlock expanded history and chatter, inspect market conditions and join the guild.
- **Sipworks:** search blends and botanicals, save favorites, order with pending/rejection states, earn and redeem stamps, inspect measured recipes and unlock the Blend Book.
- **Foyer:** search and refresh world catalogs, inspect details, retain visit history, browse friends and notifications, and expose unavailable destinations honestly.

These applications retain their original content and deterministic domain services. Native controls own their UI mechanisms. The scripted services model successful and rejected operations; they are examples, not production payment or authority services.

## What to copy

Copy a component's state flow and native composition. Keep keys stable, use current-item readables, and register external subscriptions with Compose cleanup. Do not copy test drivers into a game's UI. A live visual check and a headless behavior check provide different evidence; run both for a visible change.
