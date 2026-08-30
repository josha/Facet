--!strict
-- Wardrobe proof seed (RA-P5). Original clean-room catalog: 28 items, original
-- names/creators, original "Sparks" currency. Deterministic; no RNG at read
-- time. `price = nil` means free-to-wear. `rig` describes the worn piece as
-- plain part data (the runner materializes; the proof never touches Instances):
-- offsets are relative to the mannequin origin.

export type PartSpec = {
	shape: string,
	size: { number },
	color: { number },
	cframe: { pos: { number }, lookAt: { number }? },
	transparency: number?,
}

export type Item = {
	id: string,
	name: string,
	category: string,
	creator: string,
	verified: boolean,
	price: number?,
	thumbKey: string,
	rig: { PartSpec }?,
}

local CATEGORIES = { "all", "hats", "hair", "faces", "torso", "legs", "shoes", "accents", "backdrops" }

-- palette used by worn pieces (matte, toy-like; rgb 0..1)
local C = {
	moss = { 0.42, 0.55, 0.36 },
	rust = { 0.66, 0.4, 0.28 },
	slate = { 0.36, 0.42, 0.5 },
	cream = { 0.88, 0.84, 0.74 },
	coal = { 0.2, 0.2, 0.22 },
	sun = { 0.9, 0.75, 0.35 },
	tide = { 0.35, 0.6, 0.65 },
	plum = { 0.5, 0.36, 0.55 },
}

local function hat(color: { number }, h: number): { PartSpec }
	return {
		{ shape = "cylinder", size = { 0.3, 1.6, 1.6 }, color = color, cframe = { pos = { 0, 3.1 + h, 0 } } },
		{ shape = "cylinder", size = { 0.5, 1.1, 1.1 }, color = color, cframe = { pos = { 0, 3.3 + h, 0 } } },
	}
end
local function crown(color: { number }): { PartSpec }
	return {
		{ shape = "block", size = { 1.3, 0.35, 1.3 }, color = color, cframe = { pos = { 0, 3.15, 0 } } },
	}
end
local function torso(color: { number }): { PartSpec }
	return {
		{ shape = "block", size = { 2.15, 2.0, 1.15 }, color = color, cframe = { pos = { 0, 1.3, 0 } } },
	}
end
local function legs(color: { number }): { PartSpec }
	return {
		{ shape = "block", size = { 2.05, 1.1, 1.05 }, color = color, cframe = { pos = { 0, -0.4, 0 } } },
	}
end
local function shoes(color: { number }): { PartSpec }
	return {
		{ shape = "block", size = { 0.9, 0.45, 1.3 }, color = color, cframe = { pos = { -0.55, -1.75, 0.1 } } },
		{ shape = "block", size = { 0.9, 0.45, 1.3 }, color = color, cframe = { pos = { 0.55, -1.75, 0.1 } } },
	}
end
local function halo(color: { number }): { PartSpec }
	return {
		{
			shape = "cylinder",
			size = { 0.15, 1.9, 1.9 },
			color = color,
			cframe = { pos = { 0, 3.6, 0 } },
			transparency = 0.25,
		},
	}
end
local function cloak(color: { number }): { PartSpec }
	return {
		{ shape = "block", size = { 2.4, 2.3, 0.25 }, color = color, cframe = { pos = { 0, 1.2, 0.72 } } },
	}
end
local function face(color: { number }): { PartSpec }
	return {
		{ shape = "block", size = { 0.7, 0.18, 0.1 }, color = color, cframe = { pos = { 0, 2.55, -0.72 } } },
	}
end
local function hair(color: { number }): { PartSpec }
	return {
		{ shape = "block", size = { 1.5, 0.5, 1.5 }, color = color, cframe = { pos = { 0, 3.05, 0.1 } } },
	}
end
local function backdrop(color: { number }): { PartSpec }
	return {
		{ shape = "block", size = { 10, 7, 0.4 }, color = color, cframe = { pos = { 0, 1.5, 4.5 } } },
	}
end

local ITEMS: { Item } = {
	-- hats
	{
		id = "cinder-hood",
		name = "Cinder Hood",
		category = "hats",
		creator = "Foldline",
		verified = true,
		price = nil,
		thumbKey = "wd:cinder-hood",
		rig = hat(C.coal, 0),
	},
	{
		id = "puffin-beanie",
		name = "Puffin Beanie",
		category = "hats",
		creator = "Petal & Rust",
		verified = true,
		price = 35,
		thumbKey = "wd:puffin-beanie",
		rig = hat(C.tide, 0),
	},
	{
		id = "willow-crown",
		name = "Willow Crown",
		category = "hats",
		creator = "Gullwing",
		verified = false,
		price = 60,
		thumbKey = "wd:willow-crown",
		rig = crown(C.moss),
	},
	{
		id = "tin-visor",
		name = "Tin Visor",
		category = "hats",
		creator = "Kite Court",
		verified = false,
		price = 20,
		thumbKey = "wd:tin-visor",
		rig = hat(C.slate, -0.1),
	},
	-- hair
	{
		id = "brook-braid",
		name = "Brook Braid",
		category = "hair",
		creator = "Petal & Rust",
		verified = true,
		price = nil,
		thumbKey = "wd:brook-braid",
		rig = hair(C.rust),
	},
	{
		id = "gale-crop",
		name = "Gale Crop",
		category = "hair",
		creator = "Foldline",
		verified = true,
		price = 28,
		thumbKey = "wd:gale-crop",
		rig = hair(C.coal),
	},
	{
		id = "sunshower-curls",
		name = "Sunshower Curls",
		category = "hair",
		creator = "Gullwing",
		verified = false,
		price = 44,
		thumbKey = "wd:sunshower-curls",
		rig = hair(C.sun),
	},
	-- faces
	{
		id = "quiet-smile",
		name = "Quiet Smile",
		category = "faces",
		creator = "Foldline",
		verified = true,
		price = nil,
		thumbKey = "wd:quiet-smile",
		rig = face(C.coal),
	},
	{
		id = "star-wink",
		name = "Star Wink",
		category = "faces",
		creator = "Kite Court",
		verified = false,
		price = 18,
		thumbKey = "wd:star-wink",
		rig = face(C.plum),
	},
	{
		id = "grim-focus",
		name = "Grim Focus",
		category = "faces",
		creator = "Gullwing",
		verified = false,
		price = 22,
		thumbKey = "wd:grim-focus",
		rig = face(C.rust),
	},
	-- torso
	{
		id = "tidepool-tee",
		name = "Tidepool Tee",
		category = "torso",
		creator = "Petal & Rust",
		verified = true,
		price = nil,
		thumbKey = "wd:tidepool-tee",
		rig = torso(C.tide),
	},
	{
		id = "cobalt-slickers",
		name = "Cobalt Slickers",
		category = "torso",
		creator = "Foldline",
		verified = true,
		price = 52,
		thumbKey = "wd:cobalt-slickers",
		rig = torso(C.slate),
	},
	{
		id = "hearth-jacket",
		name = "Hearth Jacket",
		category = "torso",
		creator = "Kite Court",
		verified = false,
		price = 48,
		thumbKey = "wd:hearth-jacket",
		rig = torso(C.rust),
	},
	{
		id = "meadow-smock",
		name = "Meadow Smock",
		category = "torso",
		creator = "Gullwing",
		verified = false,
		price = 30,
		thumbKey = "wd:meadow-smock",
		rig = torso(C.moss),
	},
	-- legs
	{
		id = "fen-trousers",
		name = "Fen Trousers",
		category = "legs",
		creator = "Foldline",
		verified = true,
		price = nil,
		thumbKey = "wd:fen-trousers",
		rig = legs(C.coal),
	},
	{
		id = "dune-shorts",
		name = "Dune Shorts",
		category = "legs",
		creator = "Kite Court",
		verified = false,
		price = 24,
		thumbKey = "wd:dune-shorts",
		rig = legs(C.cream),
	},
	{
		id = "puddle-waders",
		name = "Puddle Waders",
		category = "legs",
		creator = "Petal & Rust",
		verified = true,
		price = 38,
		thumbKey = "wd:puddle-waders",
		rig = legs(C.tide),
	},
	-- shoes
	{
		id = "marsh-boots",
		name = "Marsh Boots",
		category = "shoes",
		creator = "Petal & Rust",
		verified = true,
		price = nil,
		thumbKey = "wd:marsh-boots",
		rig = shoes(C.moss),
	},
	{
		id = "ember-clogs",
		name = "Ember Clogs",
		category = "shoes",
		creator = "Gullwing",
		verified = false,
		price = 26,
		thumbKey = "wd:ember-clogs",
		rig = shoes(C.rust),
	},
	{
		id = "skiff-sneaks",
		name = "Skiff Sneaks",
		category = "shoes",
		creator = "Foldline",
		verified = true,
		price = 40,
		thumbKey = "wd:skiff-sneaks",
		rig = shoes(C.cream),
	},
	-- accents
	{
		id = "static-halo",
		name = "Static Halo",
		category = "accents",
		creator = "Foldline",
		verified = true,
		price = 450,
		thumbKey = "wd:static-halo",
		rig = halo(C.sun),
	},
	{
		id = "moth-cloak",
		name = "Moth Cloak",
		category = "accents",
		creator = "Gullwing",
		verified = false,
		price = 120,
		thumbKey = "wd:moth-cloak",
		rig = cloak(C.plum),
	},
	{
		id = "reed-satchel",
		name = "Reed Satchel",
		category = "accents",
		creator = "Kite Court",
		verified = false,
		price = 32,
		thumbKey = "wd:reed-satchel",
		rig = { { shape = "block", size = { 0.8, 1.0, 0.4 }, color = C.cream, cframe = { pos = { 1.3, 0.9, 0.3 } } } },
	},
	{
		id = "lantern-charm",
		name = "Lantern Charm",
		category = "accents",
		creator = "Petal & Rust",
		verified = true,
		price = nil,
		thumbKey = "wd:lantern-charm",
		rig = { { shape = "ball", size = { 0.5, 0.5, 0.5 }, color = C.sun, cframe = { pos = { -1.25, 1.9, -0.2 } } } },
	},
	-- backdrops
	{
		id = "fog-harbor",
		name = "Fog Harbor",
		category = "backdrops",
		creator = "Gullwing",
		verified = false,
		price = nil,
		thumbKey = "wd:fog-harbor",
		rig = backdrop(C.slate),
	},
	{
		id = "clover-field",
		name = "Clover Field",
		category = "backdrops",
		creator = "Petal & Rust",
		verified = true,
		price = 55,
		thumbKey = "wd:clover-field",
		rig = backdrop(C.moss),
	},
	{
		id = "dusk-plaza",
		name = "Dusk Plaza",
		category = "backdrops",
		creator = "Foldline",
		verified = true,
		price = 64,
		thumbKey = "wd:dusk-plaza",
		rig = backdrop(C.plum),
	},
	{
		id = "paper-sky",
		name = "Paper Sky",
		category = "backdrops",
		creator = "Kite Court",
		verified = false,
		price = 25,
		thumbKey = "wd:paper-sky",
		rig = backdrop(C.cream),
	},
}

-- seed ownership: every free item plus one bought-looking piece
local OWNED: { string } = {
	"cinder-hood",
	"brook-braid",
	"quiet-smile",
	"tidepool-tee",
	"fen-trousers",
	"marsh-boots",
	"lantern-charm",
	"fog-harbor",
	"gale-crop",
}

-- "Picked for you" inline header set (seed order)
local PICKED: { string } = { "puffin-beanie", "moth-cloak", "skiff-sneaks", "dusk-plaza" }

-- purchase fixtures: Static Halo always rejects (insufficient at seed balance);
-- Moth Cloak rejects ONCE with soldout, then confirms on retry
local FIXTURES: { [string]: string } = {
	["static-halo"] = "insufficient",
	["moth-cloak"] = "soldout-once",
}

local STAND_IN_ASSET = "rbxasset://textures/ui/GuiImagePlaceholder.png"
local FAILED_KEYS: { [string]: boolean } = { ["wd:grim-focus"] = true }

-- the base mannequin: a deliberately toy-like blocky figure (proof-owned)
local MANNEQUIN: { PartSpec } = {
	{ shape = "block", size = { 2, 2, 1 }, color = C.cream, cframe = { pos = { 0, 1.3, 0 } } }, -- torso core
	{ shape = "ball", size = { 1.4, 1.4, 1.4 }, color = C.cream, cframe = { pos = { 0, 2.7, 0 } } }, -- head
	{ shape = "block", size = { 0.6, 1.8, 0.6 }, color = C.cream, cframe = { pos = { -1.35, 1.2, 0 } } }, -- arms
	{ shape = "block", size = { 0.6, 1.8, 0.6 }, color = C.cream, cframe = { pos = { 1.35, 1.2, 0 } } },
	{ shape = "block", size = { 0.8, 1.6, 0.8 }, color = C.cream, cframe = { pos = { -0.5, -0.9, 0 } } }, -- legs
	{ shape = "block", size = { 0.8, 1.6, 0.8 }, color = C.cream, cframe = { pos = { 0.5, -0.9, 0 } } },
	{ shape = "cylinder", size = { 0.4, 3.2, 3.2 }, color = C.slate, cframe = { pos = { 0, -1.9, 0 } } }, -- stand
}

local seed = {}

seed.categories = CATEGORIES
seed.items = ITEMS
seed.owned = OWNED
seed.picked = PICKED
seed.fixtures = FIXTURES
seed.balance = 240
seed.mannequin = MANNEQUIN

function seed.itemById(id: string): Item?
	for _, item in ITEMS do
		if item.id == id then
			return item
		end
	end
	return nil
end

function seed.assetFor(key: string): (boolean, string?)
	if FAILED_KEYS[key] then
		return false, nil
	end
	return true, STAND_IN_ASSET
end

return seed
