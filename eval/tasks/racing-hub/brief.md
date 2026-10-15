# Ticket: racing hub

Build the interface for one racing game. Read `TEAM_NOTES.md` first. The player starts in the hub lobby. The server runs the game. Only the interface is in scope.

## Player story

I prepare my kart in the hub, get parts, choose a driver, and join a race. The mechanic gives me a crate for a test job. I open the crate and keep the cards in my collection. Race rewards increase my Coins, Gems, XP, level, and daily race count. I can see the same balance in every store and on the HUD.

## Design direction

Use one visual identity for the whole game. Use a dark slate base, warm amber for main actions, pale text, and a small set of status colors. Use one font family with a small set of sizes and weights. Use a spacing scale based on 4 pixels. Use the same panel heading, action style, and top-right Close or Back position across the game. You can use equivalent colors and a suitable readable font. Keep the world visible around the HUD.

Use one route through the game. Close or Back returns one level. Each panel has one clear visible way back. The root hub has no Back command. On a console, B returns one level and selection returns to the control that opened that level. Keep state when the player closes a panel. Each screen must have a route back to the hub without a server reset.

## Hub and rewards

- Show Coins, Gems, level, XP progress, daily race count, income, and zone progress. Use short large numbers on the HUD, such as `1.23M Coins`. Show full numbers in stores.
- The dock opens Shop, Garage, Inventory, Drivers, Crates, Daily Rewards, Codes, Settings, Boosts, Quests, and the timed Offer. Inventory is also available from Garage.
- Boosts sells `2x Coins for 30 seconds` for 10 Gems. Show the active time. Quests shows progress and Claim or Claimed. The timed Starter Offer sells 5K Coins for 99 Gems. Show its time on the dock and in the panel. A bought or expired offer cannot pay again.
- Daily Rewards shows all seven days, their rewards, the current day, earlier claimed days, and later locked days. Start on Day 3. Claim pays once. Show Claimed and `Next claim in H:MM:SS`. A new day enables the next claim. A missed day restarts the track and shows a clear message. Day 7 has the special crate reward. Keep the ready indicator on the dock current.
- Codes has a text field and Redeem. Handle empty, invalid, expired, repeated, limited, and busy requests. Trim spaces and ignore case. On success show the rewards, then Continue to the balance. The valid codes are WELCOME, SPEEDY, and LUCKY7. SUMMER24 is expired. Show the retry time when the server limits requests.

## Garage and stores

- Garage lists every kart with its name, level, category, and rarity. All, Sprint, Circuit, Coast, and Favorites filter the list. Filters opens a rarity choice with Apply and Cancel. Clear Filters removes the rarity filter. An empty result says `No vehicles match`.
- Select a kart to see Speed, Armor, and Firepower. These are the server's kart statistics. Favorite saves the favorite. Spawn chooses that kart and closes the garage. Show its driving hints and Leave Vehicle. Leave Vehicle returns to the hub. Do not open the garage while a kart is out. The chosen kart races next, even after the player leaves its preview.
- Inventory shows owned parts and cosmetics, their rarity, description, power, and slot. Select one to inspect it. Equip replaces the item in that slot. Unequip clears the slot. Show every equipped slot and Empty for an empty slot. New purchases and server grants appear without a reopen.
- Shop shows every part, its description, price, and currency. Start with 320 Coins and 40 Gems. Starter Motor is owned. Buy sends one request. Show Owned after success. A failure names the missing currency. Show other failures in short words. Codes can open over Shop. Close Codes returns to Shop, then Close Shop returns to the HUD.
- Drivers has Circuit and Rally groups. Each driver has rarity, Strength, Speed, and Durability. Select a driver to compare stats. Buy and Rent first check the visible funds, then ask for confirmation with the name and full price. Rent states the 10-minute term. Cancel spends nothing. A successful rent shows `Rented: M:SS left`. Equip is available for owned or active rented drivers. The equipped driver races next. The server removes an expired rent.
- Crates shows Starter Crate, Veteran Crate, and Legend Crate, their Gems prices, card counts, and rarity odds. Open first asks for confirmation. Cancel spends nothing. Confirm Open sends one request. Reveal shows one card at a time in server order. Reveal All shows the remaining cards. Done returns to the store. Collection shows each owned card with its count, unknown cards as `???`, and unique progress out of 11. Back returns to the store. A Starter Crate from the mechanic is free and is consumed before Gems.

## Mechanic and race

- The mechanic has a Talk to Mechanic control when nearby. Show the speaker and the full line, with reply choices. The player can ask what needs a test, accept the job, decline, or Leave. Accept pays 50 Coins and one Starter Crate once. Goodbye reaches the last line and Close ends the talk. Walking away ends the talk. Keep the HUD current.
- Play opens Solo (4 players) and Duo (6 players). Back returns to the hub. Joining shows `N/TOTAL` and `Need N more players`. Leave Queue cancels. A full queue shows `Match starts in N`. A player leaving stops the countdown. When it finishes, show Starting match, then the race HUD.
- The kart race uses the Round phase. Show its timer as `M:SS`, position, the chosen kart and driver, Red and Blue racers, `N alive`, OUT marks, and the local name with You. Show the last four `VICTIM knocked out: last on LAP` lines. Show `You are out` when the local racer is out. Clear the feed for a new race. Every racer can drive all three laps. The server owns standings and scenario lap knockouts. The world team owns driving and the race camera. Keep gamepad selection free during driving, keep interactive UI away from the default touch thumbstick, and leave the central road view clear. Follow the driving rules in `TEAM_NOTES.md`.
- Keep HUD text and controls clear of the Roblox top bar and device cutouts. A dialog or sheet dims the whole screen, including the area behind the top bar. Keep its text and controls inside the safe area. The queue countdown needs a readable backing over the world on every device.
- Results shows `TEAM wins` or Draw, `You earned N Coins`, `5 Gems`, and `120 XP`. Apply server rewards once. Update level and daily race count. Back to hub returns to the lobby. Every currency counter must show the new balance. Intermission hides the results.
- Settings has Music and Sound Effects sliders from 0 to 100, Damage Numbers and Camera Shake toggles, Low/Medium/High graphics, and the read-only keyboard and gamepad controls table. Start from saved server values. Save changes and follow server updates. Reopen with the saved values. Sliders work with touch and gamepad steps.

## Contract

`src/shared/Hub/init.luau` is the strict typed entry contract. The modules under it define each system's types and catalog. `Hub.context(player)` gives `mount(context)` these clients:

| Client | Reads and requests |
| --- | --- |
| `hub` | `getState`, `onStateChanged`, `serverNow`, `returnToHub`. State has `wallet`, total `xp`, `level`, `races`, free `crates`, selected `kart` and `driver`, race `raceKart` and `raceDriver`, and ordered `positions`. XP per level is 100. |
| `shop` | `catalog`, `categories`, `getState`, `purchase(itemId)`, `onStateChanged`. State is `{ wallet, owned }`. |
| `inventory` | `definitions`, `slots`, `getState`, `equip(itemId)`, `unequip(slot)`, `onChanged`. State is `{ owned, equipped }`. |
| `garage` | `vehicles`, `categories`, `rarities`, `getState`, `spawn(vehicleId)`, `exit`, `setFavorite(vehicleId, favorite)`, `onStateChanged`. |
| `drivers` | `drivers`, `rentSeconds`, `getState`, `buy`, `rent`, `equip`, `serverNow`, `onStateChanged`. IDs select the driver. |
| `crates` | `crates`, `cards`, `getState`, `open(crateId)`, `onStateChanged`. Open returns the ordered cards and the collection state. |
| `rewards` | `getState`, `claim`, `serverNow`, `onStateChanged`. State includes the full day track and next claim time. |
| `codes` | `getState`, `redeem(code)`, `onStateChanged`. Results include rewards, failure reason, and optional `retryIn`. |
| `dialogue` | `getState`, `talk`, `choose(choiceId)`, `leave`, `onStateChanged`. State has the nearby speaker and current node. |
| `settings` | `defaults`, `presets`, `keybinds`, `get`, `save(patch)`, `onChanged`. Save returns `{ ok, reason?, field?, values }`. |
| `economy` | `getState`, `buyBoost`, `claimQuest(questId)`, `buyOffer`, `serverNow`, `onStateChanged`. |
| `lobby` | `modes`, `getState`, `join(modeId)`, `leave`, `serverNow`, `onStateChanged`. |
| `round` | `localName`, `getState`, `serverNow`, `onStateChanged`, `onEvent`. State contains phase, timer end, racers, winner, and team rewards. |

The game model owns all state. Currency values in every client refer to one wallet. Results from requests carry the new system state. Subscribe to changes; rewards and grants can arrive while a panel is open. The server validates prices, funds, ownership, slots, code reuse, claims, proximity, rents, and queue state. Do not change `src/server`, `src/shared`, or the project contract.

## Copy

| Element | Words |
| --- | --- |
| Dock | Shop, Garage, Inventory, Drivers, Crates, Daily Rewards, Codes, Settings, Boosts, Quests, Offer, Play |
| Navigation | Close, Back, Back to hub |
| Shop | Buy, Owned, Not enough Coins, Not enough Gems |
| Garage | All, Sprint, Circuit, Coast, Favorites, Filters, Apply, Cancel, Clear Filters, Spawn, Favorite, Leave Vehicle |
| Inventory | Equip, Unequip, Equipped, Empty |
| Drivers | Circuit, Rally, Buy, Rent, Equip, Confirm, Cancel, Equipped, Rented: M:SS left |
| Crates | Open, Cancel, Reveal, Reveal All, Done, Collection, Back |
| Rewards | Day N, Claim, Claimed, Locked, Ready, Next claim in H:MM:SS |
| Codes | Redeem, Continue, Invalid code, Code expired, Already redeemed |
| Mechanic | Talk to Mechanic, I will help you., What needs a test?, Not today., Goodbye., Leave |
| Queue | Solo, Duo, Leave Queue, Need N more players, Match starts in N, Starting match |
| Race | Intermission, Round, Results, You, OUT, You are out, N alive, Position N |
| Settings | Music, Sound Effects, Damage Numbers, Camera Shake, Low, Medium, High, On, Off |

## Done when

One complete game loop works on desktop, both phone orientations, tablet, and console. All player actions work with that device's input. The interface has no dead ends. Purchases, equipped gear, driver choices, crate rewards, and race rewards flow through the game. The visual identity and navigation stay consistent across every screen.
