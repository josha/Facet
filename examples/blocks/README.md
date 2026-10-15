# Facet blocks

Copy a block into your game and change the copy. Each module returns one
component function. Call it inside `app.mount` with `Facet`, `app.UI` and your
model. The game supplies Compose cells and request callbacks. The server
validates requests and updates game data. Request callbacks can yield.

The author kit blocks use the public Facet types. They need no repository
type aliases. In a repository source copy, replace only the `../../src`
require with this line. Keep one Compose instance for Facet and model cells.

```luau
local FacetTypes = require(game:GetService("ReplicatedStorage").Packages.Facet)
```

In a property function that reads two kinds of value, write
`function(use: Facet.Use)`. `Facet.Use` is `<T>(Facet.Readable<T>) -> T`.

## Starter blocks

| Block file | Player task | Controls used | Model fields |
|---|---|---|---|
| [hud_panel.luau](hud_panel.luau) | Open tasks from a safe HUD corner. | Screen, Composition, Region, Button, Sheet, VStack, Text | objective, trackObjective |
| [item_store.luau](item_store.luau) | Buy an item with Coins or Gems. | Screen, HStack, VStack, Text, VirtualGrid, Card, Alert, Toast | coins, gems, items, confirmationThreshold, purchase |
| [category_tabs.luau](category_tabs.luau) | Filter a collection by category. | Screen, Text, Picker, VirtualGrid | items |
| [settings_panel.luau](settings_panel.luau) | Change settings and restore defaults. | Screen, Text, Toggle, Slider, Picker, Button | music, volume, quality, reset |
| [code_redeem.luau](code_redeem.luau) | Redeem a code and read the result. | Screen, Text, TextInput, Button | redeem |
| [inventory_grid.luau](inventory_grid.luau) | Select an item and equip its slot. | Screen, Text, VirtualGrid, VStack, Button | items, equipped, equip |
| [scoreboard_table.luau](scoreboard_table.luau) | Compare scores and find your row. | Screen, Text, Table | players, localPlayerId |
| [round_hud.luau](round_hud.luau) | Follow the round clock and the currency counters. | Screen, Composition, Region, Timer, Text, `Facet.format` | phase, deadline, now, coins, gems |
| [dialogue_box.luau](dialogue_box.luau) | Read an NPC line and choose a reply. | Screen, Typewriter, Button, Text | line, choose |

## Model contracts

- `hud_panel`: `objective` is a string cell. `trackObjective()` requests task tracking.
- `item_store`: `coins` and `gems` are number cells. `items` is a cell of
  `{ id, name, description, image, price, currency, owned }` records. `currency`
  is `Coins` or `Gems`. `purchase(itemId)` returns `{ ok, reason? }`. Return
  `Not enough Coins` or `Not enough Gems` when the balance is too low. The
  server updates balances and ownership. Prices above `confirmationThreshold`
  require confirmation before the request.
- `category_tabs`: `items` is a cell of `{ id, name, category }` records.
  Categories are `tools` and `outfits`. Change the Picker options for your game.
- `settings_panel`: `music`, `volume` and `quality` are writable cells.
  Volume is 0 through 100. Quality is `low`, `medium` or `high`. `reset()`
  restores the game defaults through those cells.
- `code_redeem`: `redeem(code)` returns `{ ok, rewards?, reason? }`. Rewards
  are display strings from the server. A failed result supplies `reason`.
- `inventory_grid`: `items` is a cell of `{ id, name, description, slot }`
  records. `equipped` maps each slot to its equipped item id. `equip(itemId,
  slot)` requests a change. The server updates `equipped`.
- `round_hud`: `phase` is a string cell and `deadline` a number cell in the
  time of `now()`, for example `workspace:GetServerTimeNow`. `coins` and
  `gems` are number cells. The clock ticks once each second.
- `dialogue_box`: `line` is a cell of `{ speaker, text, replies }` or nil.
  Each reply is `{ id, label }`. `choose(replyId)` sends the choice. Skip
  shows the whole line. The replies show when the line is complete.
- `scoreboard_table`: `players` is a cell of `{ id, name, kills, deaths,
  score }` records. `localPlayerId` is the local player's id. Rows stay in
  descending score order.

`fill()` lets the grids, table and HUD composition use the remaining screen
height. Each collection owns its row selection and scrolling. Category tabs
use a segmented Picker to filter one collection.
