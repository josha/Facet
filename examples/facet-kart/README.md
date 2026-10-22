# Facet Kart

Facet Kart is the preserved playable racing game. It includes the hub, shop,
garage, inventory, settings, codes, daily rewards, mechanic dialogue, crates,
race HUD, results, server state, circuit, karts, and seeded opponents.

This project uses plain Luau and native Roblox Instances. The existing
interface and game behavior are preserved. It does not require a UI package.
`Packages` has no installed packages. Native InputContexts in
`input.project.json` own drift, modal Back, and selected settings-slider
actions. The game enables each context only while its task is active.

From this directory, install the pinned tools and build the place:

```sh
rokit install
rojo build default.project.json -o facet-kart.rbxlx
```

Open the place in Roblox Studio and press Play. Select Play in the hub, then
join Solo or Duo. Drive three laps or wait for the race time limit. Review
the results and return to the hub.

Use WASD or the arrow keys to drive on a keyboard. Use the left thumbstick
and triggers on a gamepad. Use the Roblox thumbstick on touch devices. Hold
Left Shift or gamepad X for at least 0.35 seconds while moving, then release
to boost. On touch, steer sharply to charge drift, then ease steering to
release the boost. The boost lasts 1.2 seconds.

The server owns the wallet, item ownership, loadout, crates, XP, race order,
and rewards. Opponents use seeded driving. The player kart uses native
VehicleSeat physics. The chase camera restores the hub camera after a race.
Off-track recovery returns the kart to its last checkpoint.

`Workspace.WorldTheme` selects `scifi` or `bright`. The project starts with
`scifi` and Future lighting. A missing attribute selects `bright`.

The interface Kit owns the existing styles and panel routes. The hub keeps
Play, Shop, Garage, and More in the top bar action row. More opens a menu
with scrolling, Close, and native selection navigation.

`tests/racing_track.verify.luau` checks deterministic opponent driving,
spacing, race rewards, lap knockout, circuit geometry, and world geometry.
These checks do not prove native contact response, replication, or live
input. Use Studio to check keyboard, gamepad, touch, camera recovery, seat
stability, and respawn.
