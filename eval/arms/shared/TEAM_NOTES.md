# Team notes for interface work

These rules apply to every interface ticket in this project.

## Project layout

- `src/server` holds the game model. It owns all game state and validates every request.
- `src/shared` holds the network contract and the shared data. The client and the server both use it.
- `src/client/Interface` is where the interface goes. `src/client/init.client.luau` calls `Interface.mount(context)` once when the player joins.
- `Packages` maps to `ReplicatedStorage.Packages`. Put third-party Luau packages there.
- Do not change `src/server` or `src/shared`. The server team owns them. If the contract does not give you something, work with what it gives you.
- Build the place with `rojo build default.project.json -o game.rbxlx`. The build must succeed.
- Keep `rokit.toml`. It pins the tools that build and test the place.
- The server creates `ServerStorage.AdminCommands` for the live-ops team. Do not use it in the interface.
- Use strict Luau (`--!strict`) in every interface file. The interface must pass the strict type check `lute run tools/typecheck/check.luau`. Run it while you work and fix each error. The review runs the same check.

## Devices

Players use these devices. Every screen must work and read well on all of them:

| Device | Screen | Input |
| --- | --- | --- |
| Phone, portrait | about 390 x 844 points, with a notch | Touch |
| Phone, landscape | about 844 x 390 points, with a notch | Touch |
| Tablet | about 1180 x 820 points | Touch |
| Desktop | 1920 x 1080 | Mouse and keyboard |
| Console on a TV | 1920 x 1080, seen from a sofa | Gamepad only |

- The game allows both phone orientations: `StarterGui.ScreenOrientation` is `Sensor` in `default.project.json`. Keep it.
- Keep important content and controls inside the safe area.
- Make touch targets at least 44 x 44 points.
- Text must be readable: good contrast and no clipped or cut text.
- A player with only a gamepad must reach and use every control with the D-pad (or left stick) and the A button. When a screen or a dialog opens and the player uses a gamepad, put the selection on a sensible control.
- Roblox reserves the Escape key and the gamepad Start button for its own menu. Do not use them.

## Words in the interface

Each ticket has a "Copy" section. Use those words for the visible labels. Capital letters do not matter. You can add more words, icons or numbers around them.

## Quality bar

QA plays every ticket on all five devices. They check that the task works, that the server state is correct, and that the screens look finished. A screen that works on desktop but not on a phone or with a gamepad is not done.
