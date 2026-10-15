# Ticket: find a kart in the hub garage

The racing team needs a faster way to choose a kart. Start from the completed racing hub. Keep the same visual identity and all earlier behavior.

Add a search field to Garage. Search kart names without case sensitivity. Combine search with the category and rarity filters. Show `No vehicles match` for an empty result. Clear empties the search and restores the full current category and rarity result.

Add Name, Speed, and Rarity sort choices. Name uses A to Z. Speed uses the highest value first. Rarity uses Legendary, Epic, Rare, then Common. Use name order to break ties. Preserve the selected kart, favorites, and all server state when search or sort changes. Use the current garage catalog. Do not change the server or shared files.

| Element | Words |
| --- | --- |
| Search | Search karts |
| Clear | Clear |
| Sort | Name, Speed, Rarity |
| Empty result | No vehicles match |

Search, sorting, details, Spawn, Close, and B must work on all devices. The entire racing hub must still work.
