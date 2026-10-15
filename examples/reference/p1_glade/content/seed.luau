--!strict

export type RGB = { number }
export type Glade = {
	id: string,
	favourite: boolean,
	nectar: string,
	phaseOffset: number,
	nectarAge: number,
	dewAge: number,
}
export type Wisp = {
	id: string,
	scale: number,
	phase: string,
	favourite: string,
	lumenOnly: boolean?,
	hero: boolean?,
	core: RGB,
	glow: RGB,
}
export type Nectar = { id: string, premium: boolean, priority: number?, art: RGB }
export type Pack = { id: string, nectar: string, quantity: number, price: number, hero: boolean?, art: RGB }
export type CharmTier = { id: string, rank: number, price: number }
export type Visit = { id: string, glade: string, wisp: string, start: number, finish: number, earlyStart: number? }
export type Flora = { id: string, art: RGB }
export type Drain = { empty: number, low: number }

local seed = {}

seed.WORLD = 20260808

local DRAIN: { [string]: Drain } = {
	nectar = { empty = 540, low = 450 },
	dew = { empty = 960, low = 780 },
}
seed.DRAIN = DRAIN

seed.DAY_SECONDS = 300
seed.PHASES = { "night", "dawn", "day", "dusk", "eve" }

seed.COMMAND_SECONDS = 0.75

seed.METRICS = {
	shellContentMin = 320,
	gladeCardMin = 236,
	nectarCardMin = 168,
	packCardMin = 176,
	detailPaneMin = 320,
	ringSmall = 34,
	ringLarge = 56,
	portrait = 48,
	heroPortrait = 96,
	sceneShort = 132,
	sceneMedium = 190,
	sceneTall = 244,
	wispSize = 26,
	offerActionsMax = 360,

	affordanceMin = 64,
	affordanceMax = 96,
}

local SKY: { [string]: { high: RGB, low: RGB, silhouette: RGB } } = {
	night = { high = { 0.04, 0.05, 0.13 }, low = { 0.10, 0.11, 0.22 }, silhouette = { 0.02, 0.03, 0.07 } },
	dawn = { high = { 0.28, 0.24, 0.42 }, low = { 0.86, 0.60, 0.44 }, silhouette = { 0.10, 0.09, 0.16 } },
	day = { high = { 0.36, 0.62, 0.86 }, low = { 0.74, 0.86, 0.92 }, silhouette = { 0.14, 0.22, 0.20 } },
	dusk = { high = { 0.20, 0.18, 0.36 }, low = { 0.90, 0.52, 0.34 }, silhouette = { 0.09, 0.08, 0.14 } },
	eve = { high = { 0.09, 0.10, 0.24 }, low = { 0.38, 0.24, 0.38 }, silhouette = { 0.05, 0.05, 0.11 } },
}
seed.SKY = SKY

seed.WHITE = { 1, 1, 1 }

seed.MOSS = { 0.20, 0.34, 0.20 }
seed.MOSS_DEEP = { 0.13, 0.24, 0.15 }
seed.FERN = { 0.17, 0.31, 0.19 }
seed.DEWSTONE = { 0.52, 0.56, 0.58 }
seed.DEWWATER = { 0.62, 0.82, 0.88 }

local GLADES: { Glade } = {

	{ id = "mossholm", favourite = true, nectar = "clover", phaseOffset = 180, nectarAge = 0, dewAge = 820 },
	{ id = "fernhollow", favourite = false, nectar = "meadow", phaseOffset = 0, nectarAge = 460, dewAge = 800 },
	{ id = "lanternDell", favourite = false, nectar = "fern", phaseOffset = 60, nectarAge = 600, dewAge = 300 },
	{ id = "brambleRest", favourite = false, nectar = "bramble", phaseOffset = 120, nectarAge = 200, dewAge = 1000 },
	{ id = "stillpond", favourite = false, nectar = "heather", phaseOffset = 240, nectarAge = 470, dewAge = 790 },
}
seed.GLADES = GLADES

local WISPS: { Wisp } = {
	{
		id = "emberwisp",
		scale = 0.83,
		phase = "eve",
		favourite = "bramble",
		core = { 1.00, 0.86, 0.62 },
		glow = { 0.96, 0.54, 0.24 },
	},
	{
		id = "palewisp",
		scale = 1.00,
		phase = "dawn",
		favourite = "clover",
		core = { 0.98, 0.98, 0.94 },
		glow = { 0.78, 0.82, 0.92 },
	},
	{
		id = "frostwisp",
		scale = 0.71,
		phase = "night",
		favourite = "moonpetal",
		lumenOnly = true,
		core = { 0.90, 0.98, 1.00 },
		glow = { 0.46, 0.74, 0.96 },
	},
	{
		id = "duskwisp",
		scale = 1.00,
		phase = "dusk",
		favourite = "moonpetal",
		core = { 0.92, 0.86, 1.00 },
		glow = { 0.52, 0.38, 0.82 },
	},
	{
		id = "sunwisp",
		scale = 1.00,
		phase = "day",
		favourite = "meadow",
		core = { 1.00, 0.96, 0.74 },
		glow = { 0.98, 0.80, 0.28 },
	},
	{
		id = "tidewisp",
		scale = 0.76,
		phase = "eve",
		favourite = "gilded",
		hero = true,
		core = { 0.86, 0.98, 0.96 },
		glow = { 0.24, 0.70, 0.72 },
	},
}
seed.WISPS = WISPS

local NECTARS: { Nectar } = {
	{ id = "clover", premium = false, art = { 0.72, 0.80, 0.46 } },
	{ id = "meadow", premium = false, art = { 0.84, 0.78, 0.38 } },
	{ id = "fern", premium = false, art = { 0.46, 0.68, 0.44 } },
	{ id = "thistle", premium = false, art = { 0.66, 0.52, 0.74 } },
	{ id = "bramble", premium = false, art = { 0.44, 0.24, 0.36 } },
	{ id = "heather", premium = false, art = { 0.80, 0.56, 0.70 } },
	{ id = "starlight", premium = true, priority = 3, art = { 0.80, 0.86, 1.00 } },
	{ id = "moonpetal", premium = true, priority = 2, art = { 0.68, 0.72, 0.94 } },
	{ id = "gilded", premium = true, priority = 1, art = { 0.92, 0.72, 0.30 } },
}
seed.NECTARS = NECTARS

local PACKS: { Pack } = {
	{ id = "starlightSingle", nectar = "starlight", quantity = 1, price = 79, art = { 0.80, 0.86, 1.00 } },
	{
		id = "starlightBundle",
		nectar = "starlight",
		quantity = 5,
		price = 299,
		hero = true,
		art = { 0.62, 0.72, 0.98 },
	},
	{ id = "moonpetalSingle", nectar = "moonpetal", quantity = 1, price = 69, art = { 0.68, 0.72, 0.94 } },
	{ id = "moonpetalBundle", nectar = "moonpetal", quantity = 5, price = 259, art = { 0.52, 0.58, 0.88 } },
	{ id = "gildedSingle", nectar = "gilded", quantity = 1, price = 59, art = { 0.92, 0.72, 0.30 } },
	{ id = "gildedBundle", nectar = "gilded", quantity = 5, price = 219, art = { 0.82, 0.58, 0.20 } },
}
seed.PACKS = PACKS

local SATCHEL: { [string]: number } = { starlight = 3 }
seed.SATCHEL = SATCHEL

local CHARM_TIERS: { CharmTier } = {
	{ id = "ember", rank = 1, price = 99 },
	{ id = "grove", rank = 2, price = 199 },
	{ id = "lumen", rank = 3, price = 349 },
}
seed.CHARM_TIERS = CHARM_TIERS
local CHARM_RANK: { [string]: number } = { none = 0, ember = 1, grove = 2, lumen = 3 }
seed.CHARM_RANK = CHARM_RANK

seed.KEEPER = { displayName = "Wren of the Low Fen", contact = "wren@glade", joined = "the third thaw" }

local VISITS: { Visit } = {
	{ id = "v1", glade = "mossholm", wisp = "emberwisp", start = -900, finish = -720 },
	{ id = "v2", glade = "mossholm", wisp = "emberwisp", start = -60, finish = 240 },
	{ id = "v3", glade = "mossholm", wisp = "tidewisp", start = 600, finish = 900 },
	{ id = "v4", glade = "fernhollow", wisp = "palewisp", start = -1500, finish = -1200 },
	{ id = "v5", glade = "fernhollow", wisp = "duskwisp", start = 300, finish = 600 },
	{ id = "v6", glade = "lanternDell", wisp = "sunwisp", start = -600, finish = -400 },
	{ id = "v7", glade = "lanternDell", wisp = "frostwisp", start = 480, finish = 760, earlyStart = 60 },
	{ id = "v8", glade = "stillpond", wisp = "duskwisp", start = -2000, finish = -1800 },
	{ id = "v9", glade = "stillpond", wisp = "tidewisp", start = -30, finish = 300 },
}
seed.VISITS = VISITS

local FLORA: { Flora } = {
	{ id = "mosscap", art = { 0.28, 0.44, 0.26 } },
	{ id = "lanternvine", art = { 0.74, 0.66, 0.32 } },
	{ id = "dewfern", art = { 0.34, 0.56, 0.42 } },
	{ id = "bramblewort", art = { 0.42, 0.26, 0.34 } },
	{ id = "stillreed", art = { 0.46, 0.62, 0.56 } },
}
seed.FLORA = FLORA

local OUTCOMES: { [string]: { string } } = {
	pack = { "confirmed", "declined", "confirmed", "offline" },
	charm = { "confirmed", "owned", "confirmed" },
	restore = { "confirmed", "offline" },
}
seed.OUTCOMES = OUTCOMES

seed.TASK = { glade = "mossholm", wisp = "emberwisp" }

local function index<T>(list: { T }, id: (T) -> string): { [string]: T }
	local out: { [string]: T } = {}
	for _, entry in list do
		out[id(entry)] = entry
	end
	return out
end

seed.GLADE_BY_ID = index(GLADES, function(entry: Glade): string
	return entry.id
end)
seed.WISP_BY_ID = index(WISPS, function(entry: Wisp): string
	return entry.id
end)
seed.NECTAR_BY_ID = index(NECTARS, function(entry: Nectar): string
	return entry.id
end)
seed.PACK_BY_ID = index(PACKS, function(entry: Pack): string
	return entry.id
end)
seed.CHARM_BY_ID = index(CHARM_TIERS, function(entry: CharmTier): string
	return entry.id
end)
seed.FLORA_BY_ID = index(FLORA, function(entry: Flora): string
	return entry.id
end)

seed.TASK_NECTAR = seed.WISP_BY_ID[seed.TASK.wisp].favourite

local PREMIUM: { Nectar } = {}
seed.PREMIUM = PREMIUM
for _, nectar in seed.NECTARS do
	if nectar.premium then
		table.insert(PREMIUM, nectar)
	end
end
table.sort(PREMIUM, function(a: Nectar, b: Nectar): boolean
	return (a.priority or 0) > (b.priority or 0)
end)

local STANDARD: { Nectar } = {}
seed.STANDARD = STANDARD
for _, nectar in seed.NECTARS do
	if not nectar.premium then
		table.insert(STANDARD, nectar)
	end
end

function seed.packsFor(nectarId: string): { Pack }
	local out: { Pack } = {}
	for _, pack in seed.PACKS do
		if pack.nectar == nectarId then
			table.insert(out, pack)
		end
	end
	table.sort(out, function(a: Pack, b: Pack): boolean
		return a.quantity < b.quantity
	end)
	return out
end

function seed.phaseAt(offset: number, now: number): string
	local span = seed.DAY_SECONDS / #seed.PHASES
	local t = (now + offset) % seed.DAY_SECONDS
	local bucket = math.floor(t / span) + 1
	if bucket > #seed.PHASES then
		bucket = #seed.PHASES
	end
	return seed.PHASES[bucket]
end

return seed
