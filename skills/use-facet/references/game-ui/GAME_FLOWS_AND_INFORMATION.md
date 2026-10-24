# Moments of play

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

A game moves the player through moments with different paces: playing, preparing, deciding with others, seeing results, learning and pausing.  Each moment asks for a different amount of attention.  Choose its patterns from what the player must notice, decide and do while the world continues.  These are patterns, not screen templates.

Keep the uncertainty the game intends separate from uncertainty the UI causes.  Hidden enemy positions can be part of the challenge.  A hidden cooldown or an unclear command never is.

## Playing

During play, the UI answers one question: what matters now?  That is usually the resources near a threshold, the active objective, the relevant target and the commands that apply.  A racer needs position, lap and the boost meter in a glance; the wallet can wait for the pit.

- **Stable readouts.**  Values change in place.  Reserve room for changing digits so neighbors do not move.
- **Proportional emphasis.**  Combine routine gains into one quiet update.  Give urgent state stronger emphasis, and let an immediate hazard outrank every reward when alerts compete.
- **Commands that fit the moment.**  Show a command while it applies and remove it when its context ends.  The same goes for notices about queues, votes and offers.
- **Destinations in the game's words.**  Label HUD entries with explicit verbs and the game's vocabulary.  Keep one visible entry per destination in each HUD form.  A reduced HUD still exposes every required task.

Choose world or screen presentation by readability.  A marker in the world explains location, but distance, occlusion and camera motion change how well it reads.  Keep essential status and commands on the screen when the world cue cannot be read.

Facet: Composition and Region arrange HUD groups by rank and swap in smaller forms (`Tasks.hud`, `HUD-actions`).  `Tasks.safe-layout` covers movement clearance.  ProgressView, Timer, ShortcutHint and `WorldMarker.card` supply their named behaviors.  Use Host.SurfaceGui or Host.BillboardGui for UI in the world.  `DiegeticScreen.reference` moves an existing app between the screen and a framed surface in the world.

## Preparing

Preparation is where players compare and choose: a garage, an inventory, a shop or a loadout.  Preserve the object's identity from browsing through preview and comparison to commitment.

- **Show what changes.**  Show the actual candidate and the meaningful differences before Equip.  An upgrade shows the current value, the next value and the cost together.
- **Keep ownership states apart.**  Owned, compatible, selected and equipped look different from each other.  An empty slot keeps its name.
- **Find, then narrow.**  Search helps when players know a name; filters help them explore unfamiliar content.  Keep the combined effect of search and filters visible.  Give each clearing action one meaning: for example, Clear removes the search and Reset restores every filter.  Return to the same query, selection and favorites.
- **Complete terms at commitment.**  Purchases, crafting and trades keep the full terms beside the commit action.  A change to the price, quantity or terms invalidates an earlier confirmation.  Pending work never duplicates a consequence.  Preview, Buy, Claim and Equip each have one distinct meaning.
- **A route when it is out of reach.**  When the player cannot afford or unlock something, show the shortfall and how to close it.
- **Real money through Roblox.**  Purchases for Robux use Roblox's native purchase prompt.  Show the Robux price before the prompt, and grant the item only after the server confirms the purchase.

The next play session uses the accepted choice, not the last thing the player looked at.

Facet: `Tasks.collection-detail` browses objects beside their detail, and `Tasks.purchase` separates pending from accepted transactions.  The [collections chapter](COLLECTIONS_AND_ACTIONS.md) covers selection and commands.

## Deciding with others

Shared decisions belong to the server.  Show what everyone sees and what the local player chose, and keep the two distinct.

- A lobby shows the participants, the rules, who is ready and what prevents the start.
- A vote shows identifiable choices, the local selection, the shared counts and a truthful deadline.
- Present local intent as shared state only after the server accepts it.
- An arriving prompt never consumes a press the player made for something else.

Keep cancellation available while it is valid.  Explain a host who left, a refused invitation or a rule change, and keep recoverable drafts and accepted membership.

## Results and progression

Lead with the personal outcome and the accepted gains or losses.  Standings support that outcome.  Show progress toward a meaningful next goal, and offer a clear next action, such as Continue, Retry, Spectate or Leave, with its consequence.

A reward reveal can build anticipation, but the player can skip it without losing or duplicating the grant.  The accepted result stays visible after the celebration ends.  A race, quest or job never succeeds because a timer ran out or an animation finished.

Facet: Travel moves an earned object to where it is stored, and `UI.sequence` orders a reveal that Skip and reduced motion can finish at once.  See the [motion chapter](MOTION_AND_FEEDBACK.md).

## Learning

Teach one useful action when it becomes relevant, in the place where the player uses it.  Name the player's current binding, let them do the action and show the result.

- Anchor guidance to what is visible now.  Guide the player into a compact menu before you point at an item inside it.
- Keep the taught action usable.  Detect that the player completed it; do not advance on a timer.
- Offer Skip, keep help available to replay, and never force experienced players through the lesson again.

Facet: Callout attaches guidance to the control it teaches.  Read `Callout.card` for its anchor and dismissal.

## Pausing and settings

Players open menus in the middle of play.  Say whether the world continues.  Keep interrupted drafts, and restore useful focus and gameplay input on exit.  Make settings reachable before a task requires an interaction that some players cannot perform.

Facet: `Tasks.settings` shows local settings in a panel, and `Tasks.pages` registers the game's input suspension so gameplay input returns on exit.

## Waiting and transitions

Loading, matchmaking and teleports are moments too.  Show what is happening, how long it takes when that is known, and what the player can do meanwhile.  Keep the coming structure stable while content arrives.  Never show a frozen screen, and never claim progress the game cannot measure.

Facet: Skeleton reserves known structure, and ProgressView shows a measured or unknown wait.

## Words

- **Concrete labels.**  Name the action and its object, such as "Buy Flux motor".  State the consequence before commitment.
- **Reasons at the source.**  Explain an unavailable action where the player sees it.  A dim button alone gives no route forward.
- **Useful failures.**  Say what stayed unchanged and what the player can do next.
- **Whole messages.**  Localize complete messages, including plurals and the order of values, instead of joining translated fragments.
- **Safe player text.**  Escape player and server text with `richText.escape` before you insert it into rich text.  Keep player text out of AutoLocalize.
- **Room for extremes.**  Test long names, large numbers and unbroken text.  Truncation keeps a route to the full name.  Reserve room for captions and chat without covering controls.

## Check

Play through each moment in order: play, open a task, prepare, commit, return, finish and see the result.  Trigger simultaneous alerts, a refused request and a change made by another player while a surface is open.  Confirm that the HUD, the panels and the results show the same accepted values.
