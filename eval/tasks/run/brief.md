# Build a complete kart racing game

You have one uninterrupted attempt. Build, play, inspect, and improve the game until it meets this whole brief. The author process can stop at any point without warning. The evaluator freezes the place's Edit data model at that point, so keep the Edit place in a working state. There are no follow-up prompts, extensions, or repairs after submission.

Start from the blank place open in your supplied Roblox Studio. Studio MCP is your only tool access. Create the world, driving, server logic, game data, and interface directly in the place. Deliver a game that can be played immediately in Studio. Make persistent changes in the Edit data model; Play-only changes are not submitted. Use Play, input, console output, and captures to test. Keep this Studio open; the evaluator handles saving and freezing the place. There is no filesystem project, shell, source sync, or build command for you to use. Use the interface technology specified in your instructions. Do not copy an existing game or inspect another submission or evaluator state.

Use strict Luau. Keep supplied libraries, skills, and reference documents unchanged. Do not add test modes, evaluation hooks, or background edits that continue after you stop. The server owns game state and validates requests. The place enables the native input action system and permits portrait and landscape orientation.

Make a beautiful sci-fi kart racing game with a neon identity. It should feel like one finished game, with clear hierarchy, readable text, deliberate composition, useful feedback, and consistent visual character. The world and interface should support each other. Give the player a reason to race, earn rewards, improve a kart, and race again. A static mockup, a set of disconnected panels, or buttons that only change their labels is not a working game.

## Drive, race, and return

Create a navigable hub and a real drivable circuit. Let the player enter a queue, leave it before the race begins, and join a race with opponents. Supply local opponents so a solo Studio session is playable. Steering, acceleration, braking, and a drift or boost mechanic must affect the kart in the world. Include an understandable countdown, laps, progress, and a finish condition based on actual racing. Give the player a useful camera and a way to recover a stuck kart.

While driving, show position, lap, and essential race information without covering the road or stealing steering input. Provide a live scoreboard with racers, position, lap, and finish state. Put the leaders first and make the local player easy to find. Make it quick to open and close with keyboard, touch, and controller. At the finish, show the actual order and earned rewards, then return to the hub with those rewards and the chosen loadout intact. Allow another race.

## Prepare a kart

- **Shop:** Browse parts by motors, boosts, wheels, cosmetics, or all items. Show prices, affordability, and ownership. Confirm expensive purchases with a clear price and Cancel. Cancellation and rejected purchases must not spend money. Successful purchases must update the shared wallet and inventory.
- **Garage:** Browse distinct karts with meaningful statistics, inspect details, try a kart, choose the next race's kart, and mark favorites. Search names without case sensitivity and combine search with category and rarity filters. Sort names A to Z, speed highest first, and rarity highest first; break ties by name. Show an empty result clearly. Clear removes search while preserving the chosen filters. Searching, sorting, and reopening must preserve selection and favorites.
- **Inventory and drivers:** Equip and unequip owned parts, inspect their effects, and choose a driver. Make equipped, selected, owned, and unavailable states distinct. Use the selected kart, parts, and driver in the next race.
- **Driver ownership and rental:** Browse driver groups and compare statistics. Buying or renting asks for confirmation with the driver and full price. Cancel spends nothing. A rental lasts ten minutes, shows its remaining time, permits equipment while active, and expires correctly. Permanent ownership remains available afterward.
- **Livery:** Preview body and accent colors using labeled Red, Amber, Green, Cyan, Blue, and Violet swatches. Support at least 50%, 75%, and 100% shade and six decals. Show the changing kart and mark unsaved edits. Save the design and find it again later. Revert and leaving with unsaved changes ask before discarding; Cancel keeps the draft and Discard restores the saved design. Clean Close returns immediately. Gamepad B follows the same rules and restores focus.
- **Upgrades:** Improve a chosen kart's speed, handling, and boost. Show current level, the next improvement, and its cost in both currencies. Confirm spending and support cancellation. Explain insufficient funds and maximum level. Keep each kart's upgrades separate, save accepted changes, and make upgrades affect that kart.

## Rewards and progression

Use one server-owned economy across the game. Keep balances, prices, purchases, equipment, and rewards consistent. Validate requests on the server, prevent duplicate rewards and overspending, and show confirmed results rather than treating a request as success.

- Open crates with prices, card counts, and rarity odds. Confirm before spending and allow cancellation. Reveal cards one at a time in the accepted order or reveal all. Keep collection counts, unknown cards, and collection progress. Consume a free crate before charging currency.
- Show a seven-day reward track with claimed, ready, and locked days, a claim action, and the next claim countdown. Prevent repeated claims. A new day enables the next reward; a missed day restarts the track with an explanation. Include a special final-day reward and a current ready indicator in the hub.
- Redeem codes with empty, invalid, expired, already-used, busy, and rate-limited states as well as success. Trim spaces and ignore case. Show a retry countdown when limited. Include a discoverable valid sample code so the feature can be tried. Allow codes to open from the shop and return to it without losing the shop state.
- Offer boosts, quests with visible progress and claimable rewards, and a timed offer with truthful eligibility and expiry.
- Add a mechanic NPC with a short conversation and a small completable job. Give the promised reward once.

Keep server-accepted progression across panel closure and the race-to-hub loop.
Show pending saves, confirmed saves, and failures honestly. Do not claim
cross-session storage if the game has not saved it. No external account setup
or published data store is supplied with the blank project.

Keep the shared HUD current when grants arrive while a panel is open. Show
both currencies, level and XP progress, race count, and relevant income and
zone progress. Stores show full prices even when HUD totals use short numbers.
The garage's preview drive has a clear exit back to the hub and preserves the
chosen next-race kart. Inventory updates without reopening and supports one
equipped item per slot, replacing an earlier item and showing empty slots.

Support Solo and Duo queue choices, joined and required player counts, a
readable countdown, and cancellation when someone leaves before start. Keep
OUT status and a short recent knockout feed truthful when that race mode is
used. Clear the feed for a new race and update XP, level, and race count once
when rewards are accepted. The mechanic must support asking, accepting,
declining, leaving, and ending dialogue when the player walks away.

## Social play and choices

- **Track voting:** Show track choices with descriptions, live vote counts, and a deadline. Mark the player's vote and allow it to change while voting is open. Include other participants' votes. At the deadline, show the winning track, stop accepting votes, and use the selected track for the next race.
- **Quick chat:** Open a readable wheel of eight preset messages using Q, gamepad Y, or a visible touch/controller-selectable button. Send the chosen message once, close the wheel, and show the message. Opening or canceling must send nothing. Enforce a five-second cooldown that survives closing and reopening the wheel. Keep driving controls clear and restore focus to its opener.
- **Party:** Show friends who are online, racing, or offline. Search and clear the list. Invite eligible friends, show pending replies and accepted or declined results, prevent duplicate and offline invitations, and retain accepted party members after filtering or reopening. Supply clearly identified demo participants for a solo session, with accepted and declined replies, so these interactions can be tried without other accounts.

## Settings and first use

Provide useful audio, display, and accessibility settings. Apply changes, show saving and saved states, retain accepted values, and report failures. Reset to defaults only after confirmation; Cancel changes nothing.

Include music and effects volume, damage numbers, camera shake, graphics
quality, and a readable controls reference. Sliders must work through touch
and gamepad steps. Follow changes accepted by the server while a panel or
purchase confirmation is open.

Give new players a short tutorial attached to the real garage, shop, and race queue actions. Include Next, Back, and Skip. Let the player use the highlighted action and return to the same step. Keep the pointer attached when the viewport changes or navigation scrolls. Remember completion or skipping and offer replayable help.

Show the current step and total. Disable Back at the first step; the last Next
completes help. Close or gamepad B goes back one step, or dismisses at the
first step. Restore focus to the help opener on dismissal. Do not place a
blocking layer over the highlighted action.

## Every device is part of the game

Support desktop mouse and keyboard, portrait and landscape phones, tablet touch, and a controller-only console interface. Adapt the layout while preserving the task. Use readable text, safe areas, useful touch targets, clear focus, and reliable Back and Close routes. Respect larger text and reduced motion. Keep controls and important text clear of Roblox's top bar, cutouts, and actual touch controls. Do not bind Roblox's reserved Escape or gamepad Start input.

Check the real game in the supplied Studio, including compact layouts and the route from hub to race and back. Fix the most important problems first. The final response should briefly state what works and what remains incomplete; it cannot substitute for the saved game.
