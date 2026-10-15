# Ticket: let the lobby choose a track

Start from `hub-livery-editor` in the same arm and seed. Keep all earlier behavior and the same visual identity. Add Track Vote in the hub. Show three track cards: Harbor Loop, Alpine Pass, and Desert Sprint. Each card needs a short track description, a live vote count, and a vote action. Show the remaining seconds. Highlight my current vote and label it Your vote. I can change it before time ends; subtract my old vote before adding the new vote.

When time ends, disable voting and show `Winner: TRACK`. Use the highest count and catalog order for a tie. Keep the final counts readable. Close or B returns to the hub and restores selection. Touch and console players must reach all three cards.

Use the existing `Extended.client()` contract. State has `tracks`, `votes`, `vote` (0 for none, otherwise a 1-based track index), `endsAt`, and `winner`. Call `request("vote", index)`. Use `now()` for the countdown and subscribe to changes while open. The game server starts ballots and sends other players' votes. Do not start or finish a ballot in interface code. Do not change server or shared files.
