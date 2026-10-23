# Game flows

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md). Choose patterns by player
intent; these are not fixed screen templates.

## Set the pace and information need

Start with what the player must notice, decide and do while the world continues.
Use stable readouts for frequent checks and contextual detail for occasional decisions.
A planning task can support comparison that would distract during active play.
Keep deliberate game uncertainty separate from unclear commands or missing feedback.

Choose screen-space or world-space presentation by use. A world marker can explain
location, but distance, occlusion and camera movement affect its readability.
Keep essential commands and status accessible when the world cue cannot be read.
Use `WorldMarker.card` for target guidance and Host.SurfaceGui or Host.BillboardGui
for world UI. `DiegeticScreen.reference` moves an existing app between the screen
and a framed world surface. Test input and viewing distance in each presentation.

## During play

A HUD answers what matters now: resources and thresholds, the active objective,
the relevant target, and available commands. Keep readouts stable as values
change. Aggregate routine gains; give urgent state stronger emphasis.
Reserve room for changing numbers so targets do not shift as digits change.
Test simultaneous alerts; routine rewards must yield to immediate hazards.
ProgressView, Timer, ShortcutHint and WorldMarker supply their named behaviors.
Use `Tasks.hud` and `Tasks.safe-layout` for composition and movement clearance.

Use explicit verbs and game vocabulary for destinations. Keep one visible
entry per destination in each form. A reduced HUD must still expose required
tasks. End notices when their context ends.

## Choosing and preparing

Preserve object identity across browsing, preview, comparison and commitment.
Show owned, compatible, selected and equipped states separately. An empty slot
keeps its name. Show the actual candidate and meaningful differences before
Equip; the next play session must use the accepted choice.

Search helps known names; filters help unfamiliar content. Keep their combined
effect visible. Distinguish no matches, no items and load failure. Clear and
Reset are different actions. Preserve query, selection and favorites on return.

For purchases, crafting or trade, keep the complete terms beside commitment.
A change to price, quantity or reviewed terms invalidates an old confirmation.
Pending work cannot duplicate consequences. Preview, Buy, Claim and Equip
must have distinct meanings.
Use `Tasks.collection-detail` for browsing and `Tasks.purchase` for accepted transactions.

## Shared decisions

Lobbies show participants, rules, readiness and what prevents Start. Voting
shows identifiable choices, the local selection, shared counts and a truthful
deadline. Confirm acceptance before presenting local intent as shared state.
Do not let an arriving prompt consume an unrelated preceding press.

Keep cancellation available where valid. Explain host departure, rejected
invitations and rule changes; retain recoverable drafts and accepted membership.

## Results and progression

Lead with personal outcome and accepted gains or losses. Standings support
that result. Show progress toward a meaningful next goal and a clear Continue,
Retry, Spectate or Leave action with its consequences.

Reward reveals may be skipped without losing or duplicating the grant. Keep
the accepted result visible after a transient celebration. Do not claim a
successful race, quest or job from a timer alone.

## Learning and interruption

Teach one useful action in context. Anchor guidance to the currently visible
form; guide through a compact menu before targeting an item inside it.
Keep the action usable, offer Skip and replay, and detect actual completion.
Use the player's current binding in instructions. Reveal guidance when the action
becomes relevant, then let the player practice it and see the result.
Keep help available again without forcing experienced players through the lesson.

Settings should remain reachable before inaccessible interaction becomes
mandatory. State whether the world continues during a menu. Preserve interrupted
drafts and restore useful focus and gameplay input on exit.

## Names and messages

Localize complete messages, including plurals and value order, rather than
joining translated fragments. Escape player or server text with richText.escape
before inserting it into rich formatting. Keep player text outside AutoLocalize.
Test long names, large numbers and unbroken text. Truncation must leave a route
to the full identity. Reserve room for captions and chat without hiding controls.

Use concrete action labels and state the consequence before commitment.
Explain an unavailable action at its source; a dim button alone gives no route forward.
For failures, say what remains unchanged and what the player can do next.
