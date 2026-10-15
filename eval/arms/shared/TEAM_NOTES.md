# Team notes for interface work

These rules apply to every interface ticket in this project.

## Studio inspection

The evaluation requires the same scoped Studio MCP for both arms. If it is not
provisioned, report a setup failure. Do not continue with a blind build.
List the available Studio, then use its play/stop, screen capture,
execute_luau, input and console output tools. The tools show only your run's
Studio and refuse other ids. Build and inspect after coherent edits. Use Edit
execution to update the provisioned place, then play it. Inspect captures and
console output, exercise the interface, and fix the problems you find.
Input runs native VirtualInput code on Client. Computer and browser use are
disabled. All MCP calls and results count in the same token budget as shell
tools. The Facet arm also has its product CLI.

## Project layout

- `src/server` holds the game model. It owns all game state and validates every request.
- `src/shared` holds the network contract and the shared data. The client and the server both use it.
- `src/client/Interface` is where the interface goes. `src/client/init.client.luau` calls `Interface.mount(context)` once when the player joins.
- The world team owns the plaza, circuit, karts, driving, and race camera. `src/client/Driving.client.luau` is also out of scope. Keep its project mapping. Both interface arms use the same world and server.
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
- Keep HUD text and controls clear of the Roblox top bar and device cutouts. When a dialog or sheet opens, dim the whole screen, including the area behind the top bar.
- Make touch targets at least 44 x 44 points.
- Text must be readable: good contrast and no clipped or cut text.
- A player with only a gamepad must reach and use every control with the D-pad (or left stick) and the A button. When a screen or a dialog opens and the player uses a gamepad, put the selection on a sensible control.
- Roblox reserves the Escape key and the gamepad Start button for its own menu. Do not use them.

## Driving and the race HUD

The player walks in the hub. A race seats the player in a kart on the grid. The server returns the player to the plaza at the end of the race. The race camera follows the kart and restores the default camera in the hub.

- Keyboard: WASD or arrow keys drive. Hold Left Shift during a turn, then release for a short boost.
- Gamepad: the left thumbstick steers and the triggers drive. Hold X during a turn, then release for a short boost.
- Touch: use the default Roblox thumbstick. Hold a sharp turn for at least 0.35 seconds, then ease the stick toward the center for a short boost. The same steering charge works on all devices.
- Do not bind movement keys or gamepad driving inputs in the passive race HUD. Do not set `GuiService.SelectedObject` during driving. A panel that the player opens can use selection; closing it must release selection back to driving.
- Keep interactive UI and HUD text clear of the actual default touch controls in the hub and races. Read the visible rectangles in PlayerGui.TouchGui.TouchControlFrame, including ThumbstickFrame or DynamicThumbstickFrame and JumpButton. Read bound action buttons through ContextActionService:GetAllBoundActionInfo() and GetButton(). Recheck on resize and rotation. Keep the central road view clear. Use edge readouts for race information.
- The server owns standings, finish order, lap knockouts, and rewards. Every racer can drive all three laps in normal play. Scenario hooks can set OUT states for interface checks. An event's `by` value names the lap, such as `lap 1`. Show `VICTIM knocked out: last on LAP`. The existing `eliminations` numeric field now reports completed laps. Use it for the scoreboard's Laps column. Use the existing clients and remotes. Do not add a driving system, camera, world, or extra vehicle GUI.

## Words in the interface

The short player prompts allow clear labels in your own words. A detailed spec
ticket can also supply exact copy. Keep its copy for that diagnostic variant.

## Quality bar

QA plays every ticket on all five devices. They check that the task works, that the server state is correct, and that the screens look finished. A screen that works on desktop but not on a phone or with a gamepad is not done.
