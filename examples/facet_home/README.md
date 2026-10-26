# Facet Home

Facet Home is a playable home inside a Roblox experience. Players choose
furniture, arrange a room, change its finish, and save or restore the result.
They can walk through the room or use the flat room plan. A short memory
activity gives the player a second task. The People page lists players in the
current server.

This first slice tests complete tasks. The Facet Lab remains the control catalog.
It does not replace Roblox discovery, accounts, chat, or moderation.

## Run

From the repository root:

```sh
lute run tools/facet build home
```

Open `build/Facet-Home.rbxl` in Studio and start Play. Each player gets a room.
Home keeps its interactive UI inside Roblox core and device safe areas.
Immersive mode uses the normal avatar camera, including while Home is open.
Flat mode uses a fixed room overview. Explore closes Home and enters immersive mode.
Cloud saves require a published experience with DataStore access. When loading
cloud data fails, Home keeps the room in memory and labels Save as session-only.
Save is explicit. Unsaved changes end when the player leaves.

## Design and code

The screens in `designs/` are Compose Design modules made with the Facet
library. Open one in Studio: select its ModuleScript and click **Design** in
the Compose toolbar. The editor stays linked to the module, so an edit in the
editor writes the source and an edit to the source updates the editor.

Use **Insert** to add a control from the library. Select a container layer
before inserting a child.

The Furnish design has a cell for each table column. The name cell contains
a title and a category. The count cell contains a badge. The finish cell
contains text. Edit a cell once to change every row. The table keeps the name
column at compact widths and adds the other columns when space permits.

A cell binds its text to fields of the `inventoryRows` input. The row actions
and the table's activation call the `onChooseFurniture` and
`onPlaceFurniture` outputs with the row. The inventory menu and swipe actions
choose a piece or place it in the selected room slot. Selecting a row also
chooses the piece. The search field keeps its text in the design's
`furnitureQuery` state.

Game code passes `inventoryRows`, `onChooseFurniture` and `onPlaceFurniture`
to the generated component. It owns filtering, server requests and durable
state.

`author.luau` builds the six designs with the Compose Design document API.
Run it only to regenerate all of them:

```sh
lute run examples/facet_home/author.luau
stylua examples/facet_home/designs
```

## State and engine ownership

`model.luau` validates furniture IDs, palettes, slots, rotations, and revisions.
The server owns the room layout and validates every request. DataStore
`UpdateAsync` rejects a save when another session has changed its revision.
The 2D activity state stays local to the client.

The place includes four textured furniture models from Roblox's Duvall Drive
pack. See [the asset receipt](ASSETS.md) for source and changes.

The implementation uses native Parts, ProximityPrompt, SurfaceGui, and
DataStore APIs. Compose owns reactive state, route mounts, and each furniture
rebuild. Native Table and RowActions own collection layout and input. Home adds
only room policy and player tasks.

## Development targets

| Dimension | Home task | Remaining evidence |
| --- | --- | --- |
| Reliability | Reject invalid edits; save and restore layouts | Cloud failures and concurrent published sessions |
| Adaptation | Compact inventory and wide columns; flat and immersive views | Physical phone, tablet, desktop, and console matrix |
| Access | Larger text, themes, native focus, complete flat actions | Localization, long strings, assistive input review |
| Developer experience | Edit column cells in Compose Design; bind live rows | More binding types and native source sync evidence |
| Performance | Replace furniture under disposable Compose owners | Long sessions, many players, low-end device budgets |
| Controls | Use controls in complete furnishing and play tasks | Map the remaining API to relevant future tasks |
| Ecosystem | Build a self-contained place with documented source | Reusable consumer recipes and maintained device evidence |

These are acceptance targets. The first slice does not establish all-API
coverage or completion of these seven dimensions.
