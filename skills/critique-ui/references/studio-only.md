# Critique with Studio tools only

Use this route when you have Studio MCP tools but no shell or filesystem.
For an early [design target](../SKILL.md#review-a-design-target), use its rendered
prototype images and brief in place of the runtime capture and rule report.
Label the stage and leave input behavior unverified until implementation.

## Collect the evidence

1. Start Play. Open the screen to review through real input.
2. Run the design rules in the **Client** data model:

   ```luau
   local Facet = require(game.ReplicatedStorage.Packages.Facet)
   return Facet.review.screen().text
   ```

   The report lists rule findings, their fixes and the six most prominent
   texts. Pass `{ root = someGuiObject }` to review one surface.
3. Capture the states needed to judge the task at each supported size the host
   can show. For choices, include selection and focus together. For feedback,
   include before and after the action. Each capture stays in context.
4. Write a short brief: the game, the player's task on this screen and its
   decision.

For a new visual direction, include the original request and the inspected
reference images or links. The reviewer must see their pixels to compare them.

For a focused change, use the quick pass in the [skill](../SKILL.md#quick-review)
instead of the full judgment below.

## Compare with a target

With a target image and no shell, build the same evidence by hand.

1. State the kind of the target: `specification`, `concept` or
   `inspiration`; the [skill](../SKILL.md#fidelity-to-a-target) has the table.
2. Set the device preview to the aspect ratio of the target, or to the
   nearest that the host has, and capture the screen. Record a different
   ratio as missing evidence: the pair then compares parts, not the
   composition.
3. View the target and the capture one after the other at the same width.
   Then picture both at a quarter size: what leads in each?
4. Read the `measures` lines at the end of `Facet.review.screen().text`:
   the largest numeral as a share of the screen height and against the
   most common text size, the plates and a typical control, and the
   strongest control with its place and size.
5. Write three comparisons, each with the target's value, the runtime's
   value and kept or lost: the leading numeral and type scale; the shapes
   of the panels and controls; the place and the emphasis of the main
   action. Take the target's values from the image and from the measured
   card. When the target has a main action and the strongest control of
   the runtime is another one, the emphasis is lost. A target with no
   single main action, such as a HUD during play, has nothing to lose
   here.
6. List what you could not see: a state, a size, the card.

Give fidelity its own verdict, apart from the scores below.

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
capture with the old one. Follow the [main loop's stopping rule](../SKILL.md#the-loop):
at most three fresh scoring rounds, followed by any remaining known `must`
repairs and focused recapture. Report unresolved blockers; do not describe
them as finished or claim a pass that no review gave.
