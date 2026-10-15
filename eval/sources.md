# Real-world interface sources

The FacetBench tasks copy player tasks and interactions from the interfaces of
real Roblox games. They do not copy art, names or text. The sources were found
in public Roblox game videos in October 2026. The repository holds no video,
frame or image from them.

## Source 1: a vehicle inventory in a tycoon game

- A modal window with a vertical rail of category tabs (favorites and vehicle
  types), a 3 x 3 grid of vehicle cards with name, level and rarity color, a
  search field and a filter button in the header, and a pager ("Page 1 / 28")
  with next and previous arrows. A close button.
- A detail panel at the side shows the selected vehicle with a favorite mark,
  level, stat bars (damage, health, speed), an upgrade button and a Spawn
  button.
- The filter button opens a filter panel over the grid: a sort choice, rarity
  chips, sub-class chips, and Cancel and Confirm buttons. The filtered grid has
  fewer pages.
- After Spawn, the window closes and the vehicle HUD shows key hints, a
  minimap and a weapon bar.

## Source 2: settings in a gardening game

- A Settings panel with a close button. Rows with a label and a horizontal
  slider for each volume. The list scrolls.
- Further down: a low-detail toggle and a codes row with a text field and a
  submit arrow.
- The components are a slider setting, a dropdown, a toggle and a codes
  setting.

## Source 3: pack opening in a sports game

- A title card for the game mode.
- Four pack tiers side by side, each with its own color. The selected pack
  shakes and opens with a light effect.

## Source 4: a simulator HUD with rebirth, settings and codes

- A 2 x 2 group of square menu buttons (Rebirth, Shop, Settings, Codes) and a
  Daily Reward button.
- A Rebirth modal shows the current currency and the value after rebirth
  (2.35K, then 0), the current and next multipliers, a progress bar
  ("2,350/5,750") and a Rebirth button.
- A Settings modal with a search field, a General section with a music toggle
  and a Gameplay section with effect and sound toggles.
- A Codes modal with a text field and a Redeem button.

## Source 5: a daily rewards track

- A full-width banner "Daily Rewards". A horizontal row of day cards, each
  with a reward icon and a quantity. The current day is larger and marked, with
  an arrow above it. A line under the row says how many days unlock a special
  reward. A close button.

## Source 6: a racing game HUD, shop, codes and reward reveal

- A progress track at the top with milestone icons, currency counters
  (17, 540, 93.2K), side buttons and a bottom dock of menu buttons.
- A shop window with tabs at the bottom (featured, currency, passes, potions,
  codes) and a Redeem Code button. A codes dialog opens over the shop with a
  text field and an Enter button.
- A "You got" reveal shows three rewards with icons and amounts (12,000 coins,
  an item x4, a potion x1) and a Continue button.

## Source 7: an inventory in an action game

- Category tabs at the side, a search field, a filter menu and a sort choice
  in the header. The item grid uses rarity colors. A detail panel shows the
  name, the rarity, tags, a preview and Equip, Favorite and Delete buttons.
- A full grid with a count ("55 / 100 Items"). The detail panel says when no
  preview is available.
- In play, the HUD shows the player name, health and energy bars and an
  ability list.

## Source 8: a character shop

- A title and a subtitle, a two-way switch and a vertical list of characters
  with rarity colors. The selected row grows and shows Rent and Purchase
  buttons. A stats panel shows three stat bars. A Close button. A 3D preview
  of the character.

## Source 9: an NPC quest cutscene

- A cutscene with letterbox bars. A subtitle line at the bottom names the
  speaker and types out the line, one line after the other.

## Source 10: NPC dialogue with a reward

- A "Talk" prompt above the NPC. A dialogue box at the bottom with the speaker
  portrait, the speaker name and text that types out.
- The money value in the player list changes, and a narrator line describes
  the payment.

## Source 11: a match lobby

- A status banner at the top says how many more players the match needs. The
  HUD has a currency balance, a large Shop button, inventory, trading and
  reward buttons with a badge, a free gift timer, an XP bar and quick slots.
- An inventory window with tabs, a grid of items with counts, a search field
  and a count.
- The round starts and the HUD hides.

## Source 12: a team round HUD

- Two team rosters at the top with player avatars. Eliminated players are
  marked. A round timer between the rosters (1:17) counts down.
- A currency counter (387,153), category buttons, a battle pass button with an
  alert badge, a feed of earnings and a timed starter pack offer (25:51).

## From sources to tasks

The extended turns use these generic interface patterns. These descriptions are design inputs. They are not measurements from a named game.

| Source | Pattern | Extended task |
| --- | --- | --- |
| 13 | A vehicle paint workshop with two color palettes, shade choices, a decal grid, a live preview, and a discard question. | `hub-livery-editor` |
| 14 | A lobby ballot with three track cards, changing counts, a timer, a marked personal choice, and a locked winner. | `hub-track-vote` |
| 15 | A wheel of eight preset social messages with a keyboard, touch, and gamepad entry path and a send cooldown. | `hub-quick-chat` |
| 16 | A vehicle workshop with per-vehicle rating bars, levels, two-currency prices, and a purchase question. | `hub-upgrades` |
| 17 | A social panel with friend presence, search, invite replies, and a party member strip. | `hub-party-invite` |
| 18 | A new-player guide with coach marks beside live hub actions, step navigation, and resize tracking. | `hub-first-time-tutorial` |

The extended turns use these generic interface patterns. These descriptions are design inputs. They are not measurements from a named game.

| Source | Pattern | Extended task |
| --- | --- | --- |
| 13 | A vehicle paint workshop with two color palettes, shade choices, a decal grid, a live preview, and a discard question. | `hub-livery-editor` |
| 14 | A lobby ballot with three track cards, changing counts, a timer, a marked personal choice, and a locked winner. | `hub-track-vote` |
| 15 | A wheel of eight preset social messages with a keyboard, touch, and gamepad entry path and a send cooldown. | `hub-quick-chat` |
| 16 | A vehicle workshop with per-vehicle rating bars, levels, two-currency prices, and a purchase question. | `hub-upgrades` |
| 17 | A social panel with friend presence, search, invite replies, and a party member strip. | `hub-party-invite` |
| 18 | A new-player guide with coach marks beside live hub actions, step navigation, and resize tracking. | `hub-first-time-tutorial` |

| Task | Sources | Player task taken from the source |
| --- | --- | --- |
| `shop` | 6, 8 | Browse priced items in two currencies, buy, see why a purchase fails. |
| `inventory` | 1, 7 | Browse owned items, read details, equip and unequip by slot. |
| `settings` | 2, 4 | Change volumes, toggles and quality, and keep them saved. |
| `daily-rewards` | 5 | See the day track, claim today, see claimed and locked days and the time to the next claim. |
| `codes` | 2, 4, 6 | Type a code, redeem it, see the rewards or the reason it failed. |
| `npc-dialogue` | 9, 10 | Talk to an NPC, read lines, choose a reply and get the result. |
| `pack-opening` | 3, 6 | Choose a pack, confirm the cost, reveal the cards and see the collection grow. |
| `vehicle-garage` | 1 | Filter vehicles, open the details, spawn one and use the vehicle HUD. |
| `character-shop` | 8 | Compare characters, rent or buy one after a confirmation and equip it. |
| `round-hud` | 12 | Follow the intermission, the round timer, positions, laps, standings and results. |
| `lobby-queue` | 11 | Join a queue, see how many more players the match needs, leave the queue, see the countdown. |
| `hud-dock` | 4, 6, 12 | Read currencies and progress while they change, open panels from a dock and claim a timed offer. |
| `shop-categories` | 6 | Change request: category tabs and a confirmation for large purchases. |
| `inventory-sort` | 1, 7 | Change request: search and sort in the inventory. |
| `settings-reset` | 2, 4 | Change request: reset to defaults with a confirmation, and a saved indicator. |
| `round-scoreboard` | 12 | Change request: a scoreboard that opens over the round HUD. |
