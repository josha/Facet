# Critique with Studio tools only

Use this route when you have Studio MCP tools but no shell or filesystem.

## Collect the evidence

1. Start Play. Open the screen to review through real input.
2. Run the design rules in the **Client** data model:

   ```luau
   local Facet = require(game.ReplicatedStorage.Packages.Facet)
   return Facet.review.screen().text
   ```

   The report lists rule findings, their fixes and the six most prominent
   texts. Pass `{ root = someGuiObject }` to review one surface.
3. Capture the screen with the host's screenshot tool, once per screen and
   device size the host can show. Each capture stays in context.
4. Write a short brief: the game, the player's task on this screen and its
   decision.

For a focused change, use the quick pass in the [skill](../SKILL.md#quick-review)
instead of the full judgment below.

## Get the judgment

If you can start a separate agent, give it the [critic brief](critic-brief.md),
the captures, the review text and the brief. Ask for verdict.json content in
its reply.

If you cannot, do a separate review pass yourself:

1. Stop editing. Do not read your code during the pass.
2. Look at each capture as a stranger. Squint, or picture it at a quarter size:
   what leads?
3. Answer the [rubric](rubric.md) for each screen. Write the scores and fixes
   down before you change anything.
4. Take the scores as given. Do not raise a score because you know why a
   choice was made.

## Act on it

Apply the top one to three `must` fixes, capture again and compare the new
capture with the old one. Repeat at most three rounds. Report the remaining
fixes; do not claim a pass that no review gave.
