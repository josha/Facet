--!strict
-- Placeholder art for the gallery examples.
--
-- These are stand-in asset ids, not real uploads. LuauUI treats an image value
-- as an opaque string: headless tests never fetch anything, and on a real
-- Roblox client the string is handed straight to the engine as the Image
-- property. Swap these for your own uploaded "rbxassetid://..." ids when you
-- wire the examples into a live place.
--
-- The match-3 example acquires each tile image through a resource provider
-- (see 07_match3.luau), which models the ready / pending states an engine
-- texture load really has, so nothing on screen assumes an image is available
-- the instant a tile appears.

local assets = {}

-- match-3 tile kinds -> their placeholder image id. The keys ("a".."e") are the
-- tile "kinds" the game logic shuffles and matches; the values are what a tile
-- of that kind would display once its image finishes loading.
assets.match3Tiles = {
	a = "rbxassetid://1000000001",
	b = "rbxassetid://1000000002",
	c = "rbxassetid://1000000003",
	d = "rbxassetid://1000000004",
	e = "rbxassetid://1000000005",
}

-- shown while a tile image is still loading (or failed): an explicit, visible
-- placeholder rather than a blank tile.
assets.pending = "rbxassetid://1000000000"

return assets
