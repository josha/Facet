# Facet Home assets

`furniture.rbxm` contains four static models selected from Roblox's
[House Furniture Pack — Duvall Drive](https://create.roblox.com/store/asset/10847897579):

| Home piece | Source model |
| --- | --- |
| Sofa | Couch_Double |
| Table | Furniture_CoffeeTable |
| Lamp | Furniture_FloorLamp_Off |
| Shelf | Furniture_Bookshelf_A |

Source creator: Roblox. Source asset ID: `10847897579`.
The Creator Store listed this asset as free when it was retrieved on 2026-10-02.
The source pack describes these models as reusable furniture with PBR surfaces.

The checked-in subset keeps geometry and surface maps. It removes scripts,
click detectors, joints, constraints, package links, and click trigger parts.
All parts are anchored. Home scales each clone to fit its room slot. Compose
owns each clone through a cleanup function. Models load from the place; Home
does not fetch or execute marketplace code at runtime.

The room shell, plant, rug, and garden are local geometry. Their source is
`world.luau`.
