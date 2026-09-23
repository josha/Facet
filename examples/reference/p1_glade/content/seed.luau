--!strict

local seed = {}

seed.WORLD = 20260808

seed.DRAIN = {
	nectar = { empty = 540, low = 450 },
	dew = { empty = 960, low = 780 },
}

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

seed.SKY = {
	night = { high = { 0.04, 0.05, 0.13 }, low = { 0.10, 0.11, 0.22 }, silhouette = { 0.02, 0.03, 0.07 } },
	dawn = { high = { 0.28, 0.24, 0.42 }, low = { 0.86, 0.60, 0.44 }, silhouette = { 0.10, 0.09, 0.16 } },
	day = { high = { 0.36, 0.62, 0.86 }, low = { 0.74, 0.86, 0.92 }, silhouette = { 0.14, 0.22, 0.20 } },
	dusk = { high = { 0.20, 0.18, 0.36 }, low = { 0.90, 0.52, 0.34 }, silhouette = { 0.09, 0.08, 0.14 } },
	eve = { high = { 0.09, 0.10, 0.24 }, low = { 0.38, 0.24, 0.38 }, silhouette = { 0.05, 0.05, 0.11 } },
}

seed.WHITE = { 1, 1, 1 }

seed.MOSS = { 0.20, 0.34, 0.20 }
seed.MOSS_DEEP = { 0.13, 0.24, 0.15 }
seed.FERN = { 0.17, 0.31, 0.19 }
seed.DEWSTONE = { 0.52, 0.56, 0.58 }
seed.DEWWATER = { 0.62, 0.82, 0.88 }

seed.GLADES = {

	{ id = "mossholm", favourite = true, nectar = "clover", phaseOffset = 180, nectarAge = 0, dewAge = 820 },
	{ id = "fernhollow", favourite = false, nectar = "meadow", phaseOffset = 0, nectarAge = 460, dewAge = 800 },
	{ id = "lanternDell", favourite = false, nectar = "fern", phaseOffset = 60, nectarAge = 600, dewAge = 300 },
	{ id = "brambleRest", favourite = false, nectar = "bramble", phaseOffset = 120, nectarAge = 200, dewAge = 1000 },
	{ id = "stillpond", favourite = false, nectar = "heather", phaseOffset = 240, nectarAge = 470, dewAge = 790 },
}

seed.WISPS = {
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

seed.NECTARS = {
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

seed.PACKS = {
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

seed.SATCHEL = { starlight = 3 }

seed.CHARM_TIERS = {
	{ id = "ember", rank = 1, price = 99 },
	{ id = "grove", rank = 2, price = 199 },
	{ id = "lumen", rank = 3, price = 349 },
}
seed.CHARM_RANK = { none = 0, ember = 1, grove = 2, lumen = 3 }

seed.KEEPER = { displayName = "Wren of the Low Fen", contact = "wren@glade", joined = "the third thaw" }

seed.VISITS = {
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

seed.FLORA = {
	{ id = "mosscap", art = { 0.28, 0.44, 0.26 } },
	{ id = "lanternvine", art = { 0.74, 0.66, 0.32 } },
	{ id = "dewfern", art = { 0.34, 0.56, 0.42 } },
	{ id = "bramblewort", art = { 0.42, 0.26, 0.34 } },
	{ id = "stillreed", art = { 0.46, 0.62, 0.56 } },
}

seed.OUTCOMES = {
	pack = { "confirmed", "declined", "confirmed", "offline" },
	charm = { "confirmed", "owned", "confirmed" },
	restore = { "confirmed", "offline" },
}

seed.TASK = { glade = "mossholm", wisp = "emberwisp" }

local function index(list: { any }): { [string]: any }
	local out: { [string]: any } = {}
	for _, entry in list do
		out[entry.id] = entry
	end
	return out
end

seed.GLADE_BY_ID = index(seed.GLADES)
seed.WISP_BY_ID = index(seed.WISPS)
seed.NECTAR_BY_ID = index(seed.NECTARS)
seed.PACK_BY_ID = index(seed.PACKS)
seed.CHARM_BY_ID = index(seed.CHARM_TIERS)
seed.FLORA_BY_ID = index(seed.FLORA)

seed.TASK_NECTAR = seed.WISP_BY_ID[seed.TASK.wisp].favourite

seed.PREMIUM = {}
for _, nectar in seed.NECTARS do
	if nectar.premium then
		table.insert(seed.PREMIUM, nectar)
	end
end
table.sort(seed.PREMIUM, function(a: any, b: any)
	return a.priority > b.priority
end)

seed.STANDARD = {}
for _, nectar in seed.NECTARS do
	if not nectar.premium then
		table.insert(seed.STANDARD, nectar)
	end
end

function seed.packsFor(nectarId: string): { any }
	local out: { any } = {}
	for _, pack in seed.PACKS do
		if pack.nectar == nectarId then
			table.insert(out, pack)
		end
	end
	table.sort(out, function(a: any, b: any)
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
