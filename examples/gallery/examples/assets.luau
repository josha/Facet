--!strict
-- Art for the gallery examples.
--
-- LuauUI treats an image value as an opaque string: headless tests never fetch
-- anything, and on a real Roblox client the string is handed straight to the
-- engine as the Image property.
--
-- THESE ARE REAL, UPLOADED IDS — and they have to be (example-quality-pass,
-- 2026-08-06). The match-3 example previously used invented ids
-- ("rbxassetid://100000000n"), so on a real client every one of its thirty-six
-- tiles drew nothing and all five tile kinds were indistinguishable: the game was
-- unplayable in the only place it was supposed to be played. A placeholder id is
-- fine for a headless fixture and is a broken screen in a tutorial.
--
-- The five below are the framework's OWN shipped icons — five distinct SHAPES, so
-- the board reads without relying on colour (which is also what makes the game
-- playable for a colour-blind player). `tests/examples_games.spec.luau` pins each
-- id against `src/themes/standard_icons.luau`, so a re-upload that moves an id
-- fails a test instead of silently blanking the board.

local assets = {}

-- match-3 tile kinds -> the art a tile of that kind displays once its image has
-- finished loading. The keys ("a".."e") are the tile "kinds" the game logic
-- shuffles and matches.
--
-- `iconName` is the framework icon each id belongs to; the test cross-checks the
-- pair. `label` is the ASCII-safe fallback the game shows if art is unavailable,
-- so the board still has five DISTINCT symbols with no assets at all.
assets.match3Tiles = {
	a = { image = "rbxassetid://92798715826227", iconName = "chevron.up", label = "^" },
	b = { image = "rbxassetid://90343755930598", iconName = "chevron.down", label = "v" },
	c = { image = "rbxassetid://81739481512878", iconName = "chevron.leading", label = "<" },
	d = { image = "rbxassetid://121626475799702", iconName = "chevron.trailing", label = ">" },
	e = { image = "rbxassetid://108245103349446", iconName = "checkmark", label = "+" },
}

-- the semantic colour each kind carries, ON TOP of its distinct shape. A theme
-- role, never a literal — so a package swap recolours the board with it. Shape is
-- the primary cue; colour is the accelerator.
assets.match3Tints = {
	a = "accent",
	b = "content",
	c = "controlSelected",
	d = "danger",
	e = "contentSecondary",
}

-- shown while a tile image is still loading, or after one failed: an explicit,
-- visible placeholder rather than a blank tile.
assets.pending = "rbxassetid://1000000000"

return assets
