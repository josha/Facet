--!strict
-- Foyer proof seed data (RA-P4). Original clean-room content universe —
-- worlds, creators and friends invented for this proof; nothing references a
-- real experience, creator, or platform identity. Deterministic: the seed page
-- selects a rotation, never an RNG at read time.

export type Tile = {
	id: string,
	title: string,
	creator: string,
	thumbKey: string,
	approval: number,
	sponsored: boolean,
	blurb: string,
}

local WORLDS: { Tile } = {
	{
		id = "moss-kingdom",
		title = "Moss Kingdom",
		creator = "Latchkey Labs",
		thumbKey = "thumb:moss-kingdom",
		approval = 94,
		sponsored = false,
		blurb = "Grow a tiny realm one stone at a time.",
	},
	{
		id = "rooftop-dash",
		title = "Rooftop Dash",
		creator = "Nine Kites",
		thumbKey = "thumb:rooftop-dash",
		approval = 88,
		sponsored = false,
		blurb = "Chase the sunset across the shingles.",
	},
	{
		id = "bumper-barge",
		title = "Bumper Barge",
		creator = "Bramble & Co",
		thumbKey = "thumb:bumper-barge",
		approval = 81,
		sponsored = true,
		blurb = "River bumper chaos, four to a barge.",
	},
	{
		id = "signal-lost",
		title = "Signal Lost",
		creator = "Latchkey Labs",
		thumbKey = "thumb:signal-lost",
		approval = 91,
		sponsored = false,
		blurb = "Find the beacon before the fog does.",
	},
	{
		id = "pancake-tycoon",
		title = "Pancake Tycoon",
		creator = "Griddle House",
		thumbKey = "thumb:pancake-tycoon",
		approval = 76,
		sponsored = false,
		blurb = "Flip your way to a breakfast empire.",
	},
	{
		id = "gloamwood",
		title = "Gloamwood",
		creator = "Nine Kites",
		thumbKey = "thumb:gloamwood",
		approval = 96,
		sponsored = false,
		blurb = "A quiet forest that remembers you.",
	},
	{
		id = "crater-golf",
		title = "Crater Golf",
		creator = "Bramble & Co",
		thumbKey = "thumb:crater-golf",
		approval = 84,
		sponsored = false,
		blurb = "Eighteen holes, zero gravity manners.",
	},
	{
		id = "harbor-watch",
		title = "Harbor Watch",
		creator = "Salt & Twine",
		thumbKey = "thumb:harbor-watch",
		approval = 79,
		sponsored = true,
		blurb = "Keep the lighthouse fed and lit.",
	},
	{
		id = "paper-armada",
		title = "Paper Armada",
		creator = "Fold Foundry",
		thumbKey = "thumb:paper-armada",
		approval = 90,
		sponsored = false,
		blurb = "Fold, float, and out-sail the bathtub.",
	},
	{
		id = "static-garden",
		title = "Static Garden",
		creator = "Latchkey Labs",
		thumbKey = "thumb:static-garden",
		approval = 87,
		sponsored = false,
		blurb = "Plant antennas. Harvest songs.",
	},
	{
		id = "waffle-run",
		title = "Waffle Run",
		creator = "Griddle House",
		thumbKey = "thumb:waffle-run",
		approval = 72,
		sponsored = false,
		blurb = "Syrup is lava. Obviously.",
	},
	{
		id = "ferry-tales",
		title = "Ferry Tales",
		creator = "Salt & Twine",
		thumbKey = "thumb:ferry-tales",
		approval = 89,
		sponsored = false,
		blurb = "Every crossing tells a story.",
	},
	{
		id = "clockmakers",
		title = "The Clockmakers",
		creator = "Fold Foundry",
		thumbKey = "thumb:clockmakers",
		approval = 93,
		sponsored = false,
		blurb = "Wind the town. Mind the mainspring.",
	},
	{
		id = "burrow-bay",
		title = "Burrow Bay",
		creator = "Bramble & Co",
		thumbKey = "thumb:burrow-bay",
		approval = 83,
		sponsored = false,
		blurb = "Dig in. The tide keeps score.",
	},
	{
		id = "kite-court",
		title = "Kite Court",
		creator = "Nine Kites",
		thumbKey = "thumb:kite-court",
		approval = 86,
		sponsored = false,
		blurb = "String duels above the plaza.",
	},
	{
		id = "lantern-line",
		title = "Lantern Line",
		creator = "Salt & Twine",
		thumbKey = "thumb:lantern-line",
		approval = 92,
		sponsored = false,
		blurb = "Run the night railway on time.",
	},
}

export type Friend = { id: string, handle: string, portraitKey: string, presence: string }

local FRIENDS: { Friend } = {
	{ id = "marrow", handle = "Marrow", portraitKey = "face:marrow", presence = "here" },
	{ id = "tibbs", handle = "Tibbs", portraitKey = "face:tibbs", presence = "away" },
	{ id = "juno", handle = "Juno", portraitKey = "face:juno", presence = "here" },
	{ id = "pell", handle = "Pell", portraitKey = "face:pell", presence = "away" },
	{ id = "okra", handle = "Okra", portraitKey = "face:okra", presence = "here" },
	{ id = "vess", handle = "Vess", portraitKey = "face:vess", presence = "away" },
	{ id = "halloway", handle = "Halloway", portraitKey = "face:halloway", presence = "away" },
	{ id = "brindle", handle = "Brindle", portraitKey = "face:brindle", presence = "here" },
	{ id = "sorrel", handle = "Sorrel", portraitKey = "face:sorrel", presence = "away" },
}

export type Notice = { id: string, bodyKeyless: string, timeKey: string, timeParam: string? }

-- Notice bodies are seeded English-independent proof copy (they are DATA the
-- fake service returns, like world titles — not UI chrome), while the relative
-- time caption is an i18n key so the locale swap visibly reaches the modal.
local NOTICES: { Notice } = {
	{ id = "n1", bodyKeyless = "Tibbs sent you a spark", timeKey = "time.now" },
	{ id = "n2", bodyKeyless = "Moss Kingdom added new stones", timeKey = "time.h", timeParam = "2" },
	{ id = "n3", bodyKeyless = "Juno beat your Kite Court volley", timeKey = "time.h", timeParam = "5" },
	{ id = "n4", bodyKeyless = "Gloamwood remembered you", timeKey = "time.d", timeParam = "1" },
	{ id = "n5", bodyKeyless = "Ferry Tales left the dock without you", timeKey = "time.d", timeParam = "3" },
}

-- Two thumbKeys that the transport SCRIPTS as failures (spec §3): visible in
-- the first seed page so the failed-image placeholder behavior is in every run.
local FAILED_KEYS: { [string]: boolean } = {
	["thumb:signal-lost"] = true,
	["face:vess"] = true,
}

-- The engine-shipped generic placeholder texture: a deterministic, unbranded
-- stand-in so async-ready images render offline. Original art is an art-pass
-- follow-up recorded in the stage report; behavior (pending/ready/failed) is
-- what this proof exercises.
local STAND_IN_ASSET = "rbxasset://textures/ui/GuiImagePlaceholder.png"

local seed = {}

seed.worlds = WORLDS
seed.friends = FRIENDS
seed.notices = NOTICES
seed.inviteCount = 2

function seed.assetFor(key: string): (boolean, string?)
	if FAILED_KEYS[key] then
		return false, nil
	end
	return true, STAND_IN_ASSET
end

-- Deterministic section builder for a seed page: rotates the world list by the
-- page index so refresh() visibly reorders with zero randomness.
function seed.sections(page: number): { { id: string, titleKey: string, layout: string, tiles: { Tile } } }
	local n = #WORLDS
	local function pick(offset: number, count: number): { Tile }
		local out: { Tile } = {}
		for i = 0, count - 1 do
			out[#out + 1] = WORLDS[((offset + i + page * 3) % n) + 1]
		end
		return out
	end
	return {
		{ id = "picked", titleKey = "section.picked", layout = "grid", tiles = pick(0, 8) },
		{ id = "continue", titleKey = "section.continue", layout = "shelf", tiles = pick(8, 6) },
		{ id = "new", titleKey = "section.new", layout = "grid", tiles = pick(5, 8) },
		{ id = "friends", titleKey = "section.friends", layout = "grid", tiles = pick(11, 4) },
	}
end

-- The Charts tab: the same tiles ranked by approval, descending — real content
-- through the same Section blueprint, not a stub.
function seed.charted(): { { id: string, titleKey: string, layout: string, tiles: { Tile } } }
	local ranked = table.clone(WORLDS)
	table.sort(ranked, function(a, b)
		if a.approval ~= b.approval then
			return a.approval > b.approval
		end
		return a.id < b.id
	end)
	local top: { Tile } = {}
	for i = 1, 8 do
		top[i] = ranked[i]
	end
	return { { id = "charts", titleKey = "tab.charts", layout = "grid", tiles = top } }
end

return seed
