# Ticket: compare racers during a race

The racing team needs a scoreboard during the race. Start from the completed racing hub. Keep the same visual identity and all earlier behavior.

Add Scoreboard on the race HUD. It opens an overlay with the racer name, team, eliminations, and OUT state. Mark the local player as You. Sort by eliminations from highest to lowest, then name from A to Z. Read `context.round` and update while the overlay is open. Do not change the server or shared files.

Close returns to the race with the timer, position, loadout, and feed intact. On desktop, Tab toggles the overlay. Turn off the built-in player list so the game gets Tab. On console, B closes the overlay and selection returns to Scoreboard. Touch uses the visible buttons. The hub remains reachable through results.

| Element | Words |
| --- | --- |
| Action | Scoreboard |
| Columns | Racer, Team, Eliminations |
| State | You, OUT |
| Return | Close |

The entire racing hub must still work.
