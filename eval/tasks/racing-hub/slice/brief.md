# Ticket: racing hub HUD and shop

Build the first part of the interface for one racing game: the hub HUD with its dock, and the Shop. Read `TEAM_NOTES.md` first. The player starts in the hub lobby. The server runs the game. Only the interface is in scope, and only the HUD, the dock panels below and the Shop. Leave the other dock entries out.

## Design direction

Use one visual identity. Use a dark slate base, warm amber for main actions, pale text, and a small set of status colors. Use one font family with a small set of sizes and weights. Use a spacing scale based on 4 pixels. Use the same panel heading, action style, and top-right Close position on every panel. You can use equivalent colors and a suitable readable font. Keep the world visible around the HUD.

Close returns to the hub. Each panel has one clear visible way back. The root hub has no Back command. On a console, B closes the panel and selection returns to the control that opened it. Keep state when the player closes a panel.

## Hub

- Show Coins, Gems, level, XP progress, daily race count, income, and zone progress. Use short large numbers on the HUD, such as `1.23M Coins`. Show full numbers in the Shop.
- The dock opens Shop, Boosts, Quests, and the timed Offer.
- Boosts sells `2x Coins for 30 seconds` for 10 Gems. Show the active time. Quests shows progress and Claim or Claimed. The timed Starter Offer sells 5K Coins for 99 Gems. Show its time on the dock and in the panel. A bought or expired offer cannot pay again.

## Shop

- Shop shows every part, its description, price, and currency. Start with 320 Coins and 40 Gems. Starter Motor is owned. Buy sends one request. Show Owned after success. A failure names the missing currency. Show other failures in short words. Close Shop returns to the HUD.

## Contract

`src/shared/Hub/init.luau` is the strict typed entry contract. `Hub.context(player)` gives `mount(context)` its clients. This ticket uses these:

| Client | Reads and requests |
| --- | --- |
| `hub` | `getState`, `onStateChanged`, `serverNow`, `returnToHub`. State has `wallet`, total `xp`, `level`, `races` and the other hub values. XP per level is 100. |
| `shop` | `catalog`, `categories`, `getState`, `purchase(itemId)`, `onStateChanged`. State is `{ wallet, owned }`. |
| `economy` | `getState`, `buyBoost`, `claimQuest(questId)`, `buyOffer`, `serverNow`, `onStateChanged`. |

The game model owns all state. Currency values in every client refer to one wallet. Results from requests carry the new system state. Subscribe to changes; rewards can arrive while a panel is open. The server validates prices, funds, ownership and claims. Do not change `src/server`, `src/shared`, or the project contract.

## Copy

| Element | Words |
| --- | --- |
| Dock | Shop, Boosts, Quests, Offer |
| Navigation | Close |
| Shop | Buy, Owned, Not enough Coins, Not enough Gems |

## Done when

The HUD, the dock panels and the Shop work on desktop, both phone orientations, tablet, and console. All player actions work with that device's input. Every panel has a way back. Purchases and rewards update every balance.
